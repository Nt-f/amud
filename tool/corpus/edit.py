#!/usr/bin/env python3
"""Token-cheap editing of Amud's siddur text (corpus/siddur).

The expensive part of editing Hebrew with a language model is writing the
Hebrew back out to say where an edit goes. This tool never asks for it:
text is addressed by segment, part and *word number*, and edits are a line
language that names tags, not words.

    python3 tool/corpus/edit.py -n ashkenaz "outline Ashrei" "show Minchah/Ashrei he:1"
    python3 tool/corpus/edit.py -n ashkenaz --apply -f ops.txt

Every positional argument (or line of -f/stdin) is one command. Without
--apply nothing is written (a dry run). `edit.py help` lists the commands.
See corpus/SCHEMA.md for what the tags mean.
"""
import argparse
import copy
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import source  # noqa: E402

HELP = """\
Addresses: he:3 (a segment, by ref)  he:3.2 (its 2nd part)  en:2
Words: w4 (word 4, from 0)  w4..9 (inclusive)  w4..  ..9   ~phrase (a phrase, matched without niqqud; ~phrase#2 the 2nd match)
Leaf: `@ Minchah/Ashrei` sets the leaf (path, suffix or unique part); `@@ sefard` the siddur.

Read:   outline [filter]            leaves, with ids of their text
        show [LEAF] [ADDR] [full] [pointed] [words=4..20]
        find ~phrase [in=PREFIX] [en]      where a phrase is (addresses and word numbers)
        lint [in=PREFIX]            formatting problems found without reading the prayer (run this first)
        verses [in=PREFIX]          numerals in the text, and which continue a verse sequence
        vars [filter] | nodes [filter] | labels [filter]
Write (all by address, no Hebrew needed):
        set ADDR k=v ...            tags on a segment (all its parts) or a part; k= removes
        tag ADDR RANGE k=v ...      tags just those words (splits the part around them)
        tagall ~phrase k=v [whole] [in=PREFIX|*]   tags every occurrence (or the whole part with `whole`)
        split ADDR w12 [w30 ...]    cut a part before those words
        merge ADDR                  part with the next part; a segment: all its parts
        flat ADDR                   a segment with one part becomes a plain segment
        del ADDR | dup ADDR [as REF] | ref ADDR NEWREF | mv ADDR after|before ADDR2
        tr en:2 he:3,4              which Hebrew an English segment translates
        ins ADDR before|after k=v ... text="..."    new part next to a part
        new he:REF after|before|start|end [ADDR] k=v ... text="..."   new segment
        text ADDR "..." | sub ADDR ~phrase "new" | strip ADDR niqqud|tags
        verse ADDR wK [glued] n=N | verse ADDR wK insert n=N | unverse ADDR | tidy ADDR | balance ADDR   verse numbers are <sup class="verse">, made by the harness
        lset k=v ...                leaf fields (when, node, service, title, comment)
Review: edit.py proposals | approve ID | reject ID | undo   (--propose saves a diff for the editor; the default asks y/N)
Fields: kind when alt node role voice align amidah minyan gestures repeat forgot en he gloss cite comment
"""

STRUCT = ['kind', 'when', 'alt', 'node', 'role', 'voice', 'align', 'amidah', 'minyan', 'gestures', 'repeat']
LISTS = {'gestures'}
INTS = {'repeat'}
BOOLS = {'minyan', 'forgot'}
LEAF_KEYS = {'when', 'node', 'service', 'title', 'comment'}
VOID = {'br', 'img', 'hr', 'wbr'}

MARKS = re.compile('[֑-ׇֽֿׁׂׅׄ]')
TAGRE = re.compile(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*?(/?)>')
SCAN = re.compile(r'(<[^>]*>)|(&(?:nbsp|thinsp|#160|#8201);)|(\s)|(.)', re.S)


class EditError(Exception):
    pass


# ---------------------------------------------------------------- words

def words(html):
    """Word spans of an HTML text: [(start, end)] offsets into it. A word is
    a run of visible characters; tags don't break it, `<br>` and spaces do."""
    out, cur = [], None
    for m in SCAN.finditer(html):
        if m.group(1):
            if m.group(1).lower().startswith('<br') and cur:
                out.append(tuple(cur)); cur = None
        elif m.group(2) or m.group(3):
            if cur:
                out.append(tuple(cur)); cur = None
        else:
            if cur is None:
                cur = [m.start(), m.end()]
            else:
                cur[1] = m.end()
    if cur:
        out.append(tuple(cur))
    return out


def visible(s):
    return re.sub(r'<[^>]*>', '', s)


def norm_word(w):
    """A word as it is searched: no tags, niqqud or punctuation."""
    w = MARKS.sub('', visible(w)).replace('־', ' ')
    return re.sub(r'[^\w\s\'"]|_', '', w).strip().lower()


def tokens_of(html, spans):
    """[(normalized token, word index)]: a maqaf-joined word is several."""
    out = []
    for i, (a, b) in enumerate(spans):
        for t in norm_word(html[a:b]).split():
            out.append((t, i))
    return out


def phrase_matches(html, phrase):
    """Word ranges [(first, last)] where the phrase occurs."""
    spans = words(html)
    toks = tokens_of(html, spans)
    want = norm_word(phrase).split()
    if not want:
        raise EditError('empty phrase')
    hits, i = [], 0
    while i + len(want) <= len(toks):
        if [t for t, _ in toks[i:i + len(want)]] == want:
            hits.append((toks[i][1], toks[i + len(want) - 1][1]))
            i += len(want)
        else:
            i += 1
    return hits


def open_stack(html, pos):
    st = []
    for m in TAGRE.finditer(html[:pos]):
        name = m.group(2).lower()
        if name in VOID or m.group(3):
            continue
        if not m.group(1):
            st.append((name, m.group(0)))
        else:
            for k in range(len(st) - 1, -1, -1):
                if st[k][0] == name:
                    del st[k:]
                    break
    return st


def cut_before(html, spans, k):
    """Where to cut so word k starts the next piece (None for the ends):
    just after word k-1, taking any closing tags with it."""
    if k <= 0 or k >= len(spans):
        return None
    pos = spans[k - 1][1]
    while html.startswith('</', pos):
        m = re.match(r'</[^>]*>', html[pos:])
        pos += m.end()
    return pos


def pieces(html, cuts):
    """The text cut at offsets, each piece's tags balanced."""
    out, prev = [], 0
    for c in sorted(set(cuts)) + [len(html)]:
        head = ''.join(t for _, t in open_stack(html, prev)) if prev else ''
        tail = ''.join(f'</{n}>' for n, _ in reversed(open_stack(html, c))) if c < len(html) else ''
        out.append(head + html[prev:c] + tail)
        prev = c
    return out


# ---------------------------------------------------------------- docs

class Session:
    def __init__(self, nusach, root=None, work=None):
        self.root = root or source.SIDDUR
        self.work = work or os.path.join(source.CORPUS, 'work', 'edit-backups')
        self.nusach = nusach
        self.docs = {}        # nusach -> {file: doc}
        self.orig = {}        # (nusach, file) -> original text
        self.touched = set()
        self.leaf = None      # (nusach, file, leaf)
        self.scope = None     # only leaves whose path contains this may be read or edited
        self.log = []

    # loading
    def files(self, n):
        return sorted(p for p in glob.glob(os.path.join(self.root, n, '*.json')) if os.path.basename(p) != 'book.json')

    def load(self, n):
        if n not in self.docs:
            if n not in {os.path.basename(d) for d in glob.glob(os.path.join(self.root, '*'))}:
                raise EditError(f'no siddur {n!r}')
            self.docs[n] = {}
            for p in self.files(n):
                with open(p, encoding='utf-8') as fh:
                    text = fh.read()
                self.orig[(n, os.path.basename(p))] = text
                self.docs[n][os.path.basename(p)] = json.loads(text)
        return self.docs[n]

    def leaves(self, n=None):
        n = n or self.nusach
        for f, d in self.load(n).items():
            for lf in d['leaves']:
                if self.scope and not (lf['path'] == self.scope[1:] if self.scope.startswith('=') else self.scope.lower() in lf['path'].lower()):
                    continue
                yield n, f, lf

    def find_leaf(self, q):
        q = q.strip()
        allv = list(self.leaves())
        for test in (lambda p: p == q, lambda p: p.endswith('/' + q), lambda p: q.lower() in p.lower()):
            hit = [x for x in allv if test(x[2]['path'])]
            if len(hit) == 1:
                return hit[0]
            if len(hit) > 1:
                names = ', '.join(x[2]['path'] for x in hit[:5])
                raise EditError(f'{q!r} matches {len(hit)} leaves ({names}{", …" if len(hit) > 5 else ""})')
        raise EditError(f'no leaf matches {q!r}')

    def mark(self, n, f):
        self.touched.add((n, f))

    # snapshot for block atomicity
    def snapshot(self):
        return copy.deepcopy((self.docs, self.touched, self.leaf and (self.leaf[0], self.leaf[1], self.leaf[2]['path'])))

    def restore(self, snap):
        self.docs, self.touched, lp = snap
        self.leaf = None
        if lp:
            self.leaf = self.find_leaf(lp[2]) if True else None


# ---------------------------------------------------------------- addressing

ADDR = re.compile(r'^(he|en):([^\s.:]+)(?:\.(\d+))?$')
RANGE = re.compile(r'^w(\d*)(?:\.\.(\d*))?$|^\.\.(\d+)$')


def parse_addr(tok):
    m = ADDR.match(tok)
    if not m:
        return None
    return m.group(1), m.group(2), (int(m.group(3)) - 1 if m.group(3) else None)


def get_seg(lf, lang, ref):
    segs = (lf.get(lang) or {}).get('segs')
    if segs is None:
        raise EditError(f'the leaf has no {lang} text')
    for i, s in enumerate(segs):
        if s['ref'] == ref:
            return segs, i, s
    refs = ', '.join(s['ref'] for s in segs[:12])
    raise EditError(f'no {lang}:{ref} (refs: {refs}{", …" if len(segs) > 12 else ""})')


def seg_parts(seg):
    return seg['parts'] if 'parts' in seg else [seg]


def ensure_parts(seg):
    if 'parts' not in seg:
        rest = {k: v for k, v in seg.items() if k not in ('ref', 'translates')}
        for k in rest:
            del seg[k]
        seg['parts'] = [rest]
    return seg['parts']


def get_part(seg, pi, who):
    parts = seg_parts(seg)
    if pi is None:
        if len(parts) != 1:
            raise EditError(f'{who} has {len(parts)} parts: say which (e.g. {who}.1)')
        return parts[0]
    if pi >= len(parts):
        raise EditError(f'{who} has {len(parts)} part(s), no part {pi + 1}')
    return parts[pi]


def parse_range(tok, n, html=None):
    """(first, last) word numbers from `w4..9`, `~phrase` ..."""
    if tok.startswith('~'):
        raise EditError('internal: phrase handled by caller')
    m = RANGE.match(tok)
    if not m:
        raise EditError(f'not a word range: {tok!r}')
    if tok.startswith('..'):
        a, b = 0, int(m.group(3))
    else:
        a = int(m.group(1)) if m.group(1) else None
        if a is None:
            raise EditError(f'not a word range: {tok!r}')
        if '..' not in tok:
            b = a
        else:
            b = int(m.group(2)) if m.group(2) else n - 1
    if not (0 <= a <= b < n):
        raise EditError(f'words {a}..{b} are outside 0..{n - 1}')
    return a, b


def resolve_ranges(html, tokens):
    """Ranges from word tokens (w4..9) and phrase tokens (~phrase[#n])."""
    n = len(words(html))
    out = []
    for t in tokens:
        if t.startswith('~'):
            ph, _, occ = t[1:].partition('#')
            hits = phrase_matches(html, ph)
            if not hits:
                raise EditError(f'phrase {ph!r} not found in the part')
            if occ:
                if not occ.isdigit() or not (1 <= int(occ) <= len(hits)):
                    raise EditError(f'phrase {ph!r} has {len(hits)} match(es), not #{occ}')
                out.append(hits[int(occ) - 1])
            elif len(hits) > 1:
                raise EditError(f'phrase {ph!r} matches {len(hits)} times in the part: add #1..#{len(hits)} (or use tagall)')
            else:
                out.append(hits[0])
        else:
            out.append(parse_range(t, n))
    return sorted(out)


# ---------------------------------------------------------------- fields

def coerce(k, v):
    if k not in source.PART_FIELDS or k in ('text', 'ref'):
        raise EditError(f'unknown field {k!r} (fields: {" ".join(f for f in source.PART_FIELDS if f != "text")})')
    if v == '':
        return None
    if k in LISTS:
        return [x for x in v.split(',') if x]
    if k in INTS:
        if not v.isdigit():
            raise EditError(f'{k} must be a whole number')
        return int(v)
    if k in BOOLS:
        if v not in ('true', 'false'):
            raise EditError(f'{k} must be true or false')
        return True if v == 'true' else None
    enums = {'kind': source.KINDS, 'role': source.ROLES, 'voice': source.VOICES, 'align': source.ALIGNS, 'amidah': source.AMIDAH}
    if k in enums and v not in enums[k]:
        raise EditError(f'{k}={v!r}: one of {", ".join(sorted(enums[k]))}')
    if k == 'gestures':
        pass
    return v


def apply_fields(part, fields):
    for k, v in fields.items():
        if v is None:
            part.pop(k, None)
        else:
            part[k] = v


def parse_fields(toks):
    fields, rest = {}, []
    for t in toks:
        m = re.match(r'^([a-z]+)=(.*)$', t, re.S)
        if m and m.group(1) in source.PART_FIELDS:
            k, v = m.group(1), m.group(2)
            if k == 'text':
                fields['text'] = v
            else:
                fields[k] = coerce(k, v)
                if k == 'gestures':
                    for g in fields[k] or []:
                        if g not in source.GESTURES:
                            raise EditError(f'gesture {g!r}: one of {", ".join(sorted(source.GESTURES))}')
        else:
            rest.append(t)
    return fields, rest


def retag(seg, pi, ranges, fields):
    """Tags the word ranges of one part, splitting it around them."""
    parts = ensure_parts(seg) if not (pi is None and 'parts' not in seg) else None
    plain = parts is None
    part = seg if plain else parts[pi]
    html = part['text']
    spans = words(html)
    if not spans:
        raise EditError('the part has no words')
    whole = len(ranges) == 1 and ranges[0] == (0, len(spans) - 1)
    if whole:
        apply_fields(part, fields)
        return 1
    cuts = []
    for a, b in ranges:
        for k in (a, b + 1):
            c = cut_before(html, spans, k)
            if c is not None:
                cuts.append(c)
    texts = pieces(html, cuts)
    bounds = sorted(set(k for a, b in ranges for k in (a, b + 1) if 0 < k < len(spans)))
    starts = [0] + bounds
    tagged = {a for a, _ in ranges}
    if plain:
        parts = ensure_parts(seg)
        part = parts[0]
    base = {k: v for k, v in part.items() if k != 'text'}
    new = []
    for i, (w0, t) in enumerate(zip(starts, texts)):
        p = {k: copy.deepcopy(v) for k, v in base.items() if i == 0 or k in STRUCT}
        p['text'] = t
        if w0 in tagged:
            apply_fields(p, fields)
        new.append(p)
    idx = parts.index(part)
    parts[idx:idx + 1] = new
    return len(new)


# ---------------------------------------------------------------- reading

def plain_words(html, pointed=False):
    return [html[a:b] if pointed else MARKS.sub('', visible(html[a:b])) if True else '' for a, b in words(html)]


def fmt_words(html, pointed, full, window=None, head=7, tail=3):
    spans = words(html)
    ws = [(MARKS.sub('', visible(html[a:b])) if not pointed else visible(html[a:b])) for a, b in spans]
    n = len(ws)
    if window:
        a, b = window
        return ' '.join(f'w{i}:{ws[i]}' for i in range(max(0, a), min(n - 1, b) + 1))
    if full or n <= head + tail + 2:
        return ' '.join(f'w{i}:{w}' for i, w in enumerate(ws))
    return ' '.join(f'w{i}:{ws[i]}' for i in range(head)) + f' … ({n - head - tail} more) … ' + ' '.join(f'w{i}:{ws[i]}' for i in range(n - tail, n))


def tags_of(p):
    out = []
    for k in STRUCT + ['forgot', 'en', 'he', 'gloss', 'cite']:
        if k in p and k != 'kind':
            v = p[k]
            v = ','.join(v) if isinstance(v, list) else ('true' if v is True else v)
            out.append(f'{k}={json.dumps(v, ensure_ascii=False) if " " in str(v) else v}')
    return ' '.join(out)


def cmd_show(s, toks):
    fields, rest = parse_fields(toks)
    flags = {t for t in rest if t in ('full', 'pointed')}
    window = None
    addr = None
    for t in rest:
        if t in flags:
            continue
        if t.startswith('words='):
            m = re.match(r'words=(\d+)\.\.(\d+)', t)
            window = (int(m.group(1)), int(m.group(2)))
        elif parse_addr(t):
            addr = parse_addr(t)
        else:
            s.leaf = s.find_leaf(t)
    if not s.leaf:
        raise EditError('which leaf? (`@ path` or `show path`)')
    n, f, lf = s.leaf
    lines = [f'{lf["path"]}  [{f}]  node={lf.get("node")}' + (f' when={lf["when"]}' if 'when' in lf else '') + (f' service={lf["service"]}' if 'service' in lf else '')]
    for lang in ('he', 'en'):
        segs = (lf.get(lang) or {}).get('segs')
        if not segs:
            continue
        for seg in segs:
            if addr and (addr[0] != lang or addr[1] != seg['ref']):
                continue
            for i, p in enumerate(seg_parts(seg)):
                if addr and addr[2] is not None and addr[2] != i:
                    continue
                label = f'{lang}:{seg["ref"]}' + (f'.{i + 1}' if 'parts' in seg else '')
                extra = (f' →{",".join(seg.get("translates", []))}' if lang == 'en' and 'parts' not in seg or (lang == 'en' and i == 0) else '')
                nw = len(words(p.get('text', '')))
                body = fmt_words(p.get('text', ''), 'pointed' in flags, 'full' in flags or bool(addr), window)
                lines.append(f'{label}{extra} {p.get("kind", "")} {nw}w {tags_of(p)} | {body}'.replace('  ', ' '))
    return '\n'.join(lines)


def cmd_outline(s, toks):
    q = ' '.join(toks).lower()
    lines = []
    for n, f, lf in s.leaves():
        if q and q not in lf['path'].lower():
            continue
        he = len(((lf.get('he') or {}).get('segs')) or [])
        en = len(((lf.get('en') or {}).get('segs')) or [])
        lines.append(f'{lf["path"]}  he{he} en{en}' + (f' when={lf["when"]}' if 'when' in lf else ''))
    if len(lines) > 120:
        lines = lines[:120] + [f'… {len(lines) - 120} more: narrow the filter']
    return '\n'.join(lines) or 'no leaves match'


def cmd_find(s, toks):
    fields, rest = parse_fields(toks)
    scope, lang, phrase = None, 'he', None
    for t in rest:
        if t.startswith('in='):
            scope = t[3:]
        elif t == 'en':
            lang = 'en'
        elif t.startswith('~'):
            phrase = t[1:]
    if not phrase:
        raise EditError('find ~phrase')
    out = []
    for n, f, lf in s.leaves():
        if scope and scope != '*' and scope.lower() not in lf['path'].lower():
            continue
        if not scope and s.leaf and lf is not s.leaf[2]:
            continue
        for seg in ((lf.get(lang) or {}).get('segs')) or []:
            for i, p in enumerate(seg_parts(seg)):
                html = p.get('text', '')
                spans = words(html)
                for a, b in phrase_matches(html, phrase):
                    ctx = ' '.join(MARKS.sub('', visible(html[x:y])) for x, y in spans[max(0, a - 2):b + 3])
                    out.append(f'{lf["path"]} {lang}:{seg["ref"]}' + (f'.{i + 1}' if 'parts' in seg else '') + f' w{a}..{b}  {ctx}')
    if len(out) > 40:
        out = out[:40] + [f'… {len(out) - 40} more']
    return '\n'.join(out) or 'not found'


def ref_list(path, filt):
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh)
    q = ' '.join(filt).lower()
    return d, q


def cmd_vars(s, toks):
    d, q = ref_list(os.path.join(source.CORPUS, 'variables.json'), toks)
    return '\n'.join(f'{k}: {v["doc"]}' for k, v in d.items() if not q or q in k.lower() or q in v['doc'].lower()) or 'none'


def cmd_nodes(s, toks):
    d, q = ref_list(os.path.join(source.CORPUS, 'nodes.json'), toks)
    return '\n'.join(f'{k}: {v["en"]}' for k, v in d.items() if not q or q in k.lower() or q in v['en'].lower())[:3000] or 'none'


def cmd_labels(s, toks):
    d, q = ref_list(os.path.join(source.CORPUS, 'labels.json'), toks)
    return '\n'.join(f'{k}: {v}' for k, v in d.items() if not q or q in k.lower() or q in v.lower()) or 'none'


# ---------------------------------------------------------------- writing

def need_leaf(s):
    if not s.leaf:
        raise EditError('which leaf? start with `@ path`')
    return s.leaf


def seg_of(s, tok):
    a = parse_addr(tok)
    if not a:
        raise EditError(f'expected an address like he:3 or he:3.2, got {tok!r}')
    n, f, lf = need_leaf(s)
    segs, i, seg = get_seg(lf, a[0], a[1])
    return n, f, lf, a, segs, i, seg


def op_set(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    fields, rest = parse_fields(toks[1:])
    if rest:
        raise EditError(f'unexpected {rest[0]!r}')
    if 'text' in fields:
        raise EditError('use `text` to replace text')
    targets = seg_parts(seg) if a[2] is None else [get_part(seg, a[2], toks[0])]
    for p in targets:
        apply_fields(p, fields)
    s.mark(n, f)
    return f'set {toks[0]} ({len(targets)} part(s))'


def op_tag(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    fields, rest = parse_fields(toks[1:])
    if not rest:
        raise EditError('tag ADDR RANGE k=v: which words?')
    part = get_part(seg, a[2], toks[0])
    ranges = resolve_ranges(part['text'], rest)
    k = retag(seg, a[2], ranges, fields)
    s.mark(n, f)
    return f'tag {toks[0]} → {k} part(s)'


def op_tagall(s, toks):
    fields, rest = parse_fields(toks)
    phrase = next((t for t in rest if t.startswith('~')), None)
    if not phrase:
        raise EditError('tagall ~phrase k=v')
    whole = 'whole' in rest
    scope = next((t[3:] for t in rest if t.startswith('in=')), None)
    lang = 'en' if 'en' in rest else 'he'
    count = 0
    for n, f, lf in s.leaves():
        if scope:
            if scope != '*' and scope.lower() not in lf['path'].lower():
                continue
        elif s.leaf and lf is not s.leaf[2]:
            continue
        for seg in ((lf.get(lang) or {}).get('segs')) or []:
            for pi in range(len(seg_parts(seg))):
                p = seg_parts(seg)[pi]
                hits = phrase_matches(p.get('text', ''), phrase[1:])
                if not hits:
                    continue
                if whole:
                    apply_fields(p, fields)
                else:
                    retag(seg, pi if 'parts' in seg else None, hits, fields)
                count += len(hits)
                s.mark(n, f)
                break_ = True  # parts changed: stop scanning this segment
                break
    return f'tagall: {count} place(s)'


def op_split(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    part = get_part(seg, a[2], toks[0])
    html = part['text']
    spans = words(html)
    cuts_w = []
    for t in toks[1:]:
        if t.startswith('~'):
            r = resolve_ranges(html, [t])[0]
            cuts_w.append(r[0])
        else:
            m = re.match(r'^w(\d+)$', t)
            if not m:
                raise EditError(f'split at w12 or ~phrase, got {t!r}')
            cuts_w.append(int(m.group(1)))
    cuts = []
    for k in cuts_w:
        c = cut_before(html, spans, k)
        if c is None:
            raise EditError(f'cannot cut before word {k} (the part has {len(spans)} words)')
        cuts.append(c)
    parts = ensure_parts(seg)
    pi = a[2] if a[2] is not None else 0
    part = parts[pi]
    texts = pieces(html, cuts)
    base = {k: v for k, v in part.items() if k != 'text'}
    new = []
    for j, t in enumerate(texts):
        p = {k: copy.deepcopy(v) for k, v in base.items() if j == 0 or k in STRUCT}
        p['text'] = t
        new.append(p)
    parts[pi:pi + 1] = new
    s.mark(n, f)
    return f'split {toks[0]} → {len(new)} parts'


def op_merge(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    parts = ensure_parts(seg)
    if a[2] is None:
        first = parts[0]
        for p in parts[1:]:
            if any(p.get(k) != first.get(k) for k in STRUCT):
                raise EditError(f'{toks[0]}: parts differ in tags; merge {toks[0]}.1 to join just two')
        first['text'] = ''.join(p['text'] for p in parts)
        del parts[1:]
    else:
        if a[2] + 1 >= len(parts):
            raise EditError('no next part to merge with')
        parts[a[2]]['text'] += parts[a[2] + 1]['text']
        del parts[a[2] + 1]
    s.mark(n, f)
    return f'merge {toks[0]}'


def op_flat(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if 'parts' not in seg:
        return f'{toks[0]} is already plain'
    if len(seg['parts']) != 1:
        raise EditError(f'{toks[0]} has {len(seg["parts"])} parts')
    p = seg['parts'][0]
    del seg['parts']
    seg.update(p)
    s.mark(n, f)
    return f'flat {toks[0]}'


def op_del(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if a[2] is not None:
        parts = ensure_parts(seg)
        if len(parts) == 1:
            raise EditError('cannot delete the only part: delete the segment')
        del parts[get_part(seg, a[2], toks[0]) and a[2]]
    else:
        del segs[i]
        if a[0] == 'he':
            for e in ((lf.get('en') or {}).get('segs')) or []:
                if 'translates' in e:
                    e['translates'] = [r for r in e['translates'] if r != a[1]]
    s.mark(n, f)
    return f'del {toks[0]}'


def next_ref(segs):
    used = {x['ref'] for x in segs}
    nums = [int(x['ref']) for x in segs if x['ref'].isdigit()]
    k = (max(nums) if nums else 0) + 1
    while str(k) in used:
        k += 1
    return str(k)


def op_dup(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    new = copy.deepcopy(seg)
    new['ref'] = toks[2] if len(toks) >= 3 and toks[1] == 'as' else next_ref(segs)
    if any(x['ref'] == new['ref'] for x in segs):
        raise EditError(f'ref {new["ref"]} is taken')
    segs.insert(i + 1, new)
    s.mark(n, f)
    return f'dup {toks[0]} → {a[0]}:{new["ref"]}'


def op_ref(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    new = toks[1]
    if any(x['ref'] == new for x in segs):
        raise EditError(f'ref {new} is taken')
    if a[0] == 'he':
        for e in ((lf.get('en') or {}).get('segs')) or []:
            if 'translates' in e:
                e['translates'] = [new if r == a[1] else r for r in e['translates']]
    seg['ref'] = new
    s.mark(n, f)
    return f'ref {toks[0]} → {new}'


def op_mv(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if len(toks) != 3 or toks[1] not in ('after', 'before'):
        raise EditError('mv ADDR after|before ADDR2')
    b = parse_addr(toks[2])
    if not b or b[0] != a[0]:
        raise EditError('mv within one language')
    _, j, _ = get_seg(lf, b[0], b[1])
    if j == i:
        raise EditError('cannot move a segment next to itself')
    del segs[i]
    j = [x['ref'] for x in segs].index(b[1])
    segs.insert(j + (1 if toks[1] == 'after' else 0), seg)
    s.mark(n, f)
    return f'mv {toks[0]} {toks[1]} {toks[2]}'


def op_tr(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if a[0] != 'en':
        raise EditError('tr is for English segments')
    refs = [r for r in (toks[1].split(',') if len(toks) > 1 else []) if r]
    he = {x['ref'] for x in ((lf.get('he') or {}).get('segs')) or []}
    for r in refs:
        r = r[3:] if r.startswith('he:') else r
        if r not in he:
            raise EditError(f'no Hebrew ref {r}')
    seg['translates'] = [r[3:] if r.startswith('he:') else r for r in refs]
    s.mark(n, f)
    return f'tr {toks[0]} → {seg["translates"]}'


def op_ins(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    where = toks[1] if len(toks) > 1 else ''
    if where not in ('before', 'after'):
        raise EditError('ins ADDR before|after k=v text=...')
    fields, rest = parse_fields(toks[2:])
    if not fields.get('text'):
        raise EditError('ins needs text="..."')
    parts = ensure_parts(seg)
    pi = a[2] if a[2] is not None else 0
    p = {k: v for k, v in fields.items() if v is not None}
    if a[0] == 'he':
        p.setdefault('kind', 'prayer')
    parts.insert(pi + (1 if where == 'after' else 0), p)
    s.mark(n, f)
    return f'ins {where} {toks[0]}'


def op_new(s, toks):
    m = re.match(r'^(he|en):(\S+)$', toks[0])
    if not m:
        raise EditError('new he:REF after|before|start|end [ADDR] k=v text=...')
    lang, ref = m.groups()
    n, f, lf = need_leaf(s)
    fields, rest = parse_fields(toks[1:])
    if not fields.get('text'):
        raise EditError('new needs text="..."')
    where = rest[0] if rest else 'end'
    segs = (lf.get(lang) or {}).get('segs')
    if segs is None:
        raise EditError(f'the leaf has no {lang} text')
    if any(x['ref'] == ref for x in segs):
        raise EditError(f'ref {ref} is taken')
    seg = {'ref': ref}
    if lang == 'en':
        seg['translates'] = []
    seg.update({k: v for k, v in fields.items() if v is not None})
    if lang == 'he':
        seg.setdefault('kind', 'prayer')
    if where in ('after', 'before'):
        b = parse_addr(rest[1]) if len(rest) > 1 else None
        if not b:
            raise EditError('new ... after ADDR')
        _, j, _ = get_seg(lf, b[0], b[1])
        segs.insert(j + (1 if where == 'after' else 0), seg)
    elif where == 'start':
        segs.insert(0, seg)
    else:
        segs.append(seg)
    s.mark(n, f)
    return f'new {lang}:{ref}'


def op_text(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if len(toks) != 2:
        raise EditError('text ADDR "new text"')
    get_part(seg, a[2], toks[0])['text'] = toks[1]
    s.mark(n, f)
    return f'text {toks[0]}'


def op_sub(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if len(toks) != 3 or not toks[1].startswith('~'):
        raise EditError('sub ADDR ~old "new"')
    part = get_part(seg, a[2], toks[0])
    html = part['text']
    r = resolve_ranges(html, [toks[1]])[0]
    spans = words(html)
    part['text'] = html[:spans[r[0]][0]] + toks[2] + html[spans[r[1]][1]:]
    s.mark(n, f)
    return f'sub {toks[0]} w{r[0]}..{r[1]}'


def op_strip(s, toks):
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    what = toks[1] if len(toks) > 1 else ''
    if what not in ('niqqud', 'tags'):
        raise EditError('strip ADDR niqqud|tags')
    targets = seg_parts(seg) if a[2] is None else [get_part(seg, a[2], toks[0])]
    for p in targets:
        p['text'] = MARKS.sub('', p['text']) if what == 'niqqud' else visible(p['text'])
    s.mark(n, f)
    return f'strip {what} {toks[0]}'


def op_lset(s, toks):
    n, f, lf = need_leaf(s)
    for t in toks:
        m = re.match(r'^([a-z]+)=(.*)$', t, re.S)
        if not m or m.group(1) not in LEAF_KEYS:
            raise EditError(f'lset takes {", ".join(sorted(LEAF_KEYS))} as k=v')
        k, v = m.groups()
        if v == '':
            lf.pop(k, None)
        else:
            lf[k] = v
    s.mark(n, f)
    return 'lset ' + ' '.join(toks)





# ---------------------------------------------------------------- verse numbers

SUP = re.compile(r'<sup class="verse">([^<]*)</sup>')
VERSE_SPACED = re.compile(r'(^|[.:׃]\s+|<br>\s*)([א-ת]{1,3})\s+(?=[א-ת][^\s<]*[֑-ׇ])')
VERSE_GLUED = re.compile(r'(^|[.:׃]\s+|<br>\s*)((?:[קרשת]?[יכלמנסעפצ]?[א-ט]|[קרשת]?[יכלמנסעפצ]|[קרשת]|ט[וז]))(?=[א-ת][֑-ׇ])')
NUMERALS = [(400, 'ת'), (300, 'ש'), (200, 'ר'), (100, 'ק'), (90, 'צ'), (80, 'פ'), (70, 'ע'), (60, 'ס'), (50, 'נ'), (40, 'מ'),
            (30, 'ל'), (20, 'כ'), (10, 'י'), (9, 'ט'), (8, 'ח'), (7, 'ז'), (6, 'ו'), (5, 'ה'), (4, 'ד'), (3, 'ג'), (2, 'ב'), (1, 'א')]
NUMVAL = {c: v for v, c in NUMERALS}


def numeral_value(s):
    """The value of Hebrew numeral letters (טו is 15), or None."""
    if not s or any(c not in NUMVAL for c in s):
        return None
    return sum(NUMVAL[c] for c in s)


def to_numeral(n):
    """15 -> טו, 16 -> טז, 12 -> יב."""
    if not 1 <= n <= 899:
        raise EditError(f'cannot write {n} as a verse number')
    out = ''
    for v, c in NUMERALS[:4]:
        while n >= v:
            out += c
            n -= v
    if n in (15, 16):
        return out + ('טו' if n == 15 else 'טז')
    for v, c in NUMERALS[4:]:
        while n >= v:
            out += c
            n -= v
    return out


def word_at(spans, off):
    for i, (a, b) in enumerate(spans):
        if a <= off < b:
            return i
    return None


def part_verse_items(html):
    """Numerals in a part: [(word, kind, numeral, value)], kind spaced|glued|baked, in text order."""
    spans = words(html)
    items = []
    for m in SUP.finditer(html):
        w = word_at(spans, m.start(1))
        if w is not None:
            items.append((m.start(1), w, 'baked', m.group(1)))
    for kind, rx in (('spaced', VERSE_SPACED), ('glued', VERSE_GLUED)):
        for m in rx.finditer(html):
            if html.rfind('<sup class="verse">', 0, m.start(2)) > html.rfind('</sup>', 0, m.start(2)):
                continue  # inside a baked sup
            w = word_at(spans, m.start(2))
            if w is not None:
                items.append((m.start(2), w, kind, m.group(2)))
    items.sort(key=lambda x: x[0])
    out, seen = [], set()
    for pos, w, kind, num in items:
        if (w, kind) in seen:
            continue
        if kind == 'glued' and any(k != 'glued' and ww == w for _, ww, k, _ in items):
            continue
        seen.add((w, kind))
        out.append((w, kind, num, numeral_value(num)))
    return out


def leaf_verse_status(lf, lang='he'):
    """Per numeral of a leaf, in order, with whether it continues the verse
    sequence: [(segref, part index or None, word, kind, numeral, value, status)],
    status ok | baked | out-of-sequence | skip.

    A chain starts only from a standalone (spaced) numeral: א, or two
    consecutive spaced numerals. A glued numeral only continues a chain. That
    keeps Ashrei's acrostic letters (ט י כ ל…, consecutive and glued to their
    words) from ever being taken for verse numbers."""
    items = []
    for seg in ((lf.get(lang) or {}).get('segs')) or []:
        for i, p in enumerate(seg_parts(seg)):
            if p.get('kind', 'prayer') != 'prayer':
                continue
            for w, kind, num, val in part_verse_items(p.get('text', '')):
                if val is not None:
                    items.append((seg['ref'], i if 'parts' in seg else None, w, kind, num, val))
    out, prev = [], None
    for k, (ref, pi, w, kind, num, val) in enumerate(items):
        nxt = items[k + 1] if k + 1 < len(items) else None
        if kind == 'baked':
            st = 'baked' if prev is None or val == prev + 1 else 'out-of-sequence'
        elif prev is not None and val == prev + 1:
            st = 'ok'
        elif kind == 'spaced' and (val == 1 or (nxt and nxt[3] == 'spaced' and nxt[5] == val + 1)):
            st = 'ok'
        else:
            st = 'skip'
        if st in ('ok', 'baked'):
            prev = val
        out.append((ref, pi, w, kind, num, val, st))
    return out


def cmd_verses(s, toks):
    fields, rest = parse_fields(toks)
    scope = next((t[3:] for t in rest if t.startswith('in=')), None)
    out = []
    for n, f, lf in s.leaves():
        if scope and scope != '*' and scope.lower() not in lf['path'].lower():
            continue
        if not scope and s.leaf and lf is not s.leaf[2]:
            continue
        for ref, pi, w, kind, num, val, st in leaf_verse_status(lf):
            if st == 'skip':
                continue
            addr = f'he:{ref}' + (f'.{pi + 1}' if pi is not None else '')
            how = '' if kind == 'baked' else f'verse {addr} w{w}' + (f' glued n={val}' if kind == 'glued' else '')
            out.append(f'{lf["path"]} {addr} w{w} {kind} {num}={val} {st}' + (f'  → {how}' if how and st == 'ok' else ''))
    return '\n'.join(out[:60]) or 'no verse numbers'


def op_verse(s, toks):
    """verse ADDR wK [glued] [insert] [n=N]: makes a verse number (a baked <sup class="verse">)."""
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    part = get_part(seg, a[2], toks[0])
    html = part['text']
    spans = words(html)
    flags = {t for t in toks[1:] if t in ('glued', 'insert')}
    want = None
    k = None
    for t in toks[1:]:
        if re.match(r'^w\d+$', t):
            k = int(t[1:])
        elif t.startswith('n='):
            want = int(t[2:]) if t[2:].isdigit() else None
    if k is None or not 0 <= k < len(spans):
        raise EditError(f'verse ADDR wK: word number 0..{len(spans) - 1}')
    a0, b0 = spans[k]
    word = html[a0:b0]
    plain = visible(word)
    if 'insert' in flags:
        if want is None:
            raise EditError('insert needs n=N')
        part['text'] = html[:a0] + f'<sup class="verse">{to_numeral(want)}</sup> ' + html[a0:]
        s.mark(n, f)
        return f'verse {toks[0]} insert {to_numeral(want)} before w{k}'
    if 'glued' in flags:
        m = re.match(r'^([א-ת]{1,3})(?=[א-ת][\u0591-\u05C7])', plain)
        best = None
        if m:
            for ln in range(len(m.group(1)), 0, -1):
                v = numeral_value(m.group(1)[:ln])
                if v is not None and (want is None or v == want):
                    best = m.group(1)[:ln]
                    break
        if not best or want is None or numeral_value(best) != want:
            raise EditError(f'w{k} ({MARKS.sub("", plain)}) does not start with the numeral n={want}: not a glued verse number')
        a1 = html.index(best, a0)
        part['text'] = html[:a1] + f'<sup class="verse">{best}</sup> ' + html[a1 + len(best):]
        s.mark(n, f)
        return f'verse {toks[0]} glued {best}'
    if MARKS.search(plain) or numeral_value(plain) is None:
        raise EditError(f'w{k} ({plain}) is not an unpointed numeral; use glued or insert')
    if want is not None and numeral_value(plain) != want:
        raise EditError(f'w{k} is {plain}={numeral_value(plain)}, not n={want}')
    part['text'] = html[:a0] + html[a0:b0].replace(plain, f'<sup class="verse">{plain}</sup>', 1) + html[b0:]
    s.mark(n, f)
    return f'verse {toks[0]} {plain}'


def op_unverse(s, toks):
    """unverse ADDR: removes the baked verse numbers of a part (keeps nothing of them)."""
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    targets = seg_parts(seg) if a[2] is None else [get_part(seg, a[2], toks[0])]
    for p in targets:
        p['text'] = re.sub(r'<sup class="verse">[^<]*</sup>\s*', '', p['text'])
    s.mark(n, f)
    return f'unverse {toks[0]}'


def balance_html(html):
    """Closes tags left open at the end and drops closing tags that close nothing."""
    out, st, pos = [], [], 0
    for m in TAGRE.finditer(html):
        name = m.group(2).lower()
        out.append(html[pos:m.start()])
        pos = m.end()
        if name in VOID or m.group(3):
            out.append(m.group(0))
        elif not m.group(1):
            st.append(name)
            out.append(m.group(0))
        elif name in st:
            while st and st[-1] != name:
                out.append(f'</{st.pop()}>')
            st.pop()
            out.append(m.group(0))
        # else: a stray closing tag, dropped
    out.append(html[pos:])
    return ''.join(out) + ''.join(f'</{n}>' for n in reversed(st))


def op_balance(s, toks):
    """balance ADDR: closes unclosed tags and drops stray closing tags in the text."""
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    if 'parts' in seg:
        raise EditError('balance is for a plain segment: a tag may be meant to span its parts')
    targets = [seg]
    for p in targets:
        p['text'] = balance_html(p['text'])
    s.mark(n, f)
    return f'balance {toks[0]}'


def op_tidy(s, toks):
    """tidy ADDR: collapses runs of whitespace in the text to one space."""
    n, f, lf, a, segs, i, seg = seg_of(s, toks[0])
    targets = seg_parts(seg) if a[2] is None else [get_part(seg, a[2], toks[0])]
    for p in targets:
        p['text'] = re.sub(r'[ \t\r\n\u00a0]{2,}', ' ', p['text'])
    s.mark(n, f)
    return f'tidy {toks[0]}'


def cmd_lint(s, toks):
    """Formatting problems the harness can see without understanding the prayer."""
    fields, rest = parse_fields(toks)
    scope = next((t[3:] for t in rest if t.startswith('in=')), None)
    out = []
    for n, f, lf in s.leaves():
        if scope and scope != '*' and scope.lower() not in lf['path'].lower():
            continue
        if not scope and s.leaf and lf is not s.leaf[2]:
            continue
        for lang in ('he', 'en'):
            for seg in ((lf.get(lang) or {}).get('segs')) or []:
                for i, p in enumerate(seg_parts(seg)):
                    addr = f'{lang}:{seg["ref"]}' + (f'.{i + 1}' if 'parts' in seg else '')
                    html = p.get('text', '')
                    if 'parts' not in seg:
                        bad = source.unbalanced_tags(html)
                        if bad:
                            out.append(f'{lf["path"]} {addr} unbalanced {bad}  → balance {addr}')
                    elif i == 0:        # a tag may legitimately open in one part and close in the next
                        bad = source.unbalanced_tags(''.join(q.get('text', '') for q in seg['parts']))
                        if bad:
                            out.append(f'{lf["path"]} {lang}:{seg["ref"]} unbalanced {bad} across its parts: leave it for a person')
                    if re.search(r'\S[ \t\u00a0]{2,}\S', html):
                        out.append(f'{lf["path"]} {addr} double-space  → tidy {addr}')
                    if lang == 'he' and p.get('kind') in ('instruction', 'note', 'heading', 'speaker') and not p.get('en'):
                        out.append(f'{lf["path"]} {addr} {p["kind"]} has no en=')
        for ref, pi, w, kind, num, val, st in leaf_verse_status(lf):
            addr = f'he:{ref}' + (f'.{pi + 1}' if pi is not None else '')
            if st == 'ok' and kind != 'baked':
                out.append(f'{lf["path"]} {addr} w{w} verse {num}={val}  → verse {addr} w{w}' + (f' glued n={val}' if kind == 'glued' else ''))
            elif st == 'out-of-sequence':
                out.append(f'{lf["path"]} {addr} w{w} baked verse {num}={val} is out of sequence')
    return '\n'.join(out[:80]) or 'clean'


OPS = {'set': op_set, 'tag': op_tag, 'tagall': op_tagall, 'split': op_split, 'merge': op_merge, 'flat': op_flat, 'del': op_del,
       'dup': op_dup, 'ref': op_ref, 'mv': op_mv, 'tr': op_tr, 'ins': op_ins, 'new': op_new, 'text': op_text, 'sub': op_sub,
       'strip': op_strip, 'lset': op_lset, 'verse': op_verse, 'unverse': op_unverse, 'tidy': op_tidy, 'balance': op_balance}
READS = {'lint': cmd_lint, 'verses': cmd_verses, 'outline': cmd_outline, 'show': cmd_show, 'find': cmd_find, 'vars': cmd_vars, 'nodes': cmd_nodes, 'labels': cmd_labels}


# ---------------------------------------------------------------- running

def run_line(s, line):
    line = line.strip()
    if not line or line.startswith('#'):
        return None, False
    head, _, tail = line.partition(' ')
    if head in ('@', '@@', 'outline'):
        toks = [head] + ([tail.strip()] if tail.strip() else [])   # leaf names may hold apostrophes (Ma'ariv)
    else:
        try:
            toks = shlex.split(line, comments=True)
        except ValueError:
            # an apostrophe inside a name: only double quotes group
            toks = [w[1:-1] if len(w) > 1 and w[0] == w[-1] == '"' else w for w in re.findall(r'"[^"]*"|\S+', line)]
    if not toks:
        return None, False
    op, args = toks[0], toks[1:]
    if op == '@':
        s.leaf = s.find_leaf(' '.join(args))
        return f'@ {s.leaf[2]["path"]}', False
    if op == '@@':
        if not args:
            raise EditError('@@ nusach')
        s.load(args[0])
        s.nusach, s.leaf = args[0], None
        return f'@@ {args[0]}', False
    if op in READS:
        return READS[op](s, args), False
    if op in OPS:
        return OPS[op](s, args), True
    if op == 'help':
        return HELP, False
    raise EditError(f'unknown command {op!r} (try `help`)')


def run_block(s, lines, stop_on_error=True):
    """Runs lines atomically: on an error nothing of the block stays.
    Returns (output lines, error or None, wrote-anything)."""
    snap = s.snapshot()
    out, changed = [], False
    for k, line in enumerate(lines, 1):
        try:
            res, wrote = run_line(s, line)
        except EditError as e:
            s.docs, s.touched, lp = snap
            s.leaf = s.find_leaf(lp[2]) if lp else None
            return out, f'line {k} `{line.strip()[:80]}`: {e}  (the block was not applied)', False
        if res is not None:
            out.append(res)
        changed = changed or wrote
    return out, None, changed


def validate_touched(s):
    """New problems the edits caused, per touched file."""
    known = source.VARIABLES | set(source.labels())
    new_errs, new_warns = [], []
    for n, f in sorted(s.touched):
        docs = s.docs[n]
        seen = {lf['path']: ff for ff, d in docs.items() if ff != f for lf in d['leaves'] if 'path' in lf}
        path = os.path.join(s.root, n, f)
        after = source.check_file(path, docs[f], known, dict(seen))
        before = source.check_file(path, json.loads(s.orig[(n, f)]), known, dict(seen))
        new_errs += [f'{f}: {m}' for m in after[0] if m not in before[0]]
        new_warns += [f'{f}: {m}' for m in after[1] if m not in before[1]]
    return new_errs, new_warns


def commit(s, write):
    """Validates, backs up and writes the touched files."""
    if not s.touched:
        return 'nothing changed'
    errs, warns = validate_touched(s)
    if errs:
        return 'NOT applied: ' + str(len(errs)) + ' new problem(s):\n' + '\n'.join(errs[:12])
    changed = [(n, f) for n, f in sorted(s.touched) if source.dumps(s.docs[n][f]) != s.orig[(n, f)]]
    msg = f'{"applied" if write else "dry run: would change"} {len(changed)} file(s)'
    if warns:
        msg += f', {len(warns)} new warning(s):\n' + '\n'.join(warns[:6])
    if not write:
        return msg
    stamp = time.strftime('%Y%m%d-%H%M%S')
    for n, f in changed:
        dst = os.path.join(s.work, stamp, n)
        os.makedirs(dst, exist_ok=True)
        open(os.path.join(dst, f), 'w', encoding='utf-8').write(s.orig[(n, f)])
        open(os.path.join(s.root, n, f), 'w', encoding='utf-8').write(source.dumps(s.docs[n][f]))
        s.orig[(n, f)] = source.dumps(s.docs[n][f])
    s.touched.clear()
    return msg + f'  (backup: {os.path.relpath(os.path.join(s.work, stamp), source.ROOT)})'


# ---------------------------------------------------------------- review

def _line(p, pointed=True, width=110):
    tags = tags_of(p)
    text = SUP.sub(lambda m: '⟦' + m.group(1) + '⟧', p.get('text', ''))      # a verse number shows as ⟦א⟧
    text = re.sub(r'<(/?)([a-zA-Z]+)[^>]*>', lambda m: f'‹{m.group(1)}{m.group(2)}›', text)  # other tags stay visible
    if not pointed:
        text = MARKS.sub('', text)
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) > width:
        text = text[:width - 30] + ' … ' + text[-24:]
    return f'[{p.get("kind", "")}{" " + tags if tags else ""}] {text}'


def _seg_lines(seg, lang):
    ps = seg_parts(seg)
    out = []
    for i, p in enumerate(ps):
        label = f'{lang}:{seg["ref"]}' + (f'.{i + 1}' if 'parts' in seg else '')
        extra = f' →{",".join(seg["translates"])}' if lang == 'en' and i == 0 and seg.get('translates') else ''
        out.append(f'{label}{extra} {_line(p)}')
    return out


def _marked(p):
    text = SUP.sub(lambda m: '⟦' + m.group(1) + '⟧', p.get('text', ''))
    return re.sub(r'<(/?)([a-zA-Z]+)[^>]*>', lambda m: f'‹{m.group(1)}{m.group(2)}›', text)


def _text_changes(x, y, lang, ctx=3, limit=8):
    """A segment whose only change is its text: each changed word, with a few words around it."""
    import difflib
    aw, bw = _marked(seg_parts(x)[0]).split(' '), _marked(seg_parts(y)[0]).split(' ')
    ops = [o for o in difflib.SequenceMatcher(None, aw, bw, autojunk=False).get_opcodes() if o[0] != 'equal']
    ref = f'{lang}:{x["ref"]}'
    out = []
    for tag, i1, i2, j1, j2 in ops[:limit]:
        pre, post = ' '.join(aw[max(0, i1 - ctx):i1]), ' '.join(aw[i2:i2 + ctx])
        vis = lambda ws: ' '.join(w if w else '␣' for w in ws) if ws else '∅'     # ␣ an extra space, ∅ nothing
        out.append(('- ', f'{ref} …{pre} [{vis(aw[i1:i2])}] {post}…'))
        out.append(('+ ', f'{ref} …{pre} [{vis(bw[j1:j2])}] {post}…'))
    if len(ops) > limit:
        out.append(('  ', f'{ref} … and {len(ops) - limit} more change(s)'))
    return out


def diff_text(s, color=False):
    """What the edits changed, by leaf and segment: - before, + after."""
    red, green, dim, off = ('\033[31m', '\033[32m', '\033[2m', '\033[0m') if color else ('', '', '', '')
    out = []
    for n, f in sorted(s.touched):
        old = {lf['path']: lf for lf in json.loads(s.orig[(n, f)])['leaves']}
        new = {lf['path']: lf for lf in s.docs[n][f]['leaves']}
        for path in list(old) + [p for p in new if p not in old]:
            a, b = old.get(path), new.get(path)
            if a == b:
                continue
            out.append(f'{dim}{n}  {path}{off}')
            if a is None or b is None:
                out.append(f'  {green if b else red}{"+ new leaf" if b else "- leaf removed"}{off}')
                continue
            for k in sorted(set(a) | set(b)):
                if k not in ('he', 'en') and a.get(k) != b.get(k):
                    out.append(f'  {red}- {k}={a.get(k)}{off}' if k in a else '')
                    out.append(f'  {green}+ {k}={b.get(k)}{off}' if k in b else '')
            for lang in ('he', 'en'):
                sa = {x['ref']: x for x in ((a.get(lang) or {}).get('segs')) or []}
                sb = {x['ref']: x for x in ((b.get(lang) or {}).get('segs')) or []}
                order = [x['ref'] for x in ((b.get(lang) or {}).get('segs')) or []]
                moved = [r for r in sa if r in sb] != [r for r in order if r in sa]
                for ref in list(sa) + [r for r in sb if r not in sa]:
                    x, y = sa.get(ref), sb.get(ref)
                    if x == y:
                        continue
                    if x and y and len(seg_parts(x)) == 1 and len(seg_parts(y)) == 1 and \
                            {k: v for k, v in seg_parts(x)[0].items() if k != 'text'} == {k: v for k, v in seg_parts(y)[0].items() if k != 'text'}:
                        out += [f'  {c}{l}{off}' for c, l in _text_changes(x, y, lang)]
                        continue
                    for l in (_seg_lines(x, lang) if x else []):
                        out.append(f'  {red}- {l}{off}')
                    for l in (_seg_lines(y, lang) if y else []):
                        out.append(f'  {green}+ {l}{off}')
                if moved:
                    out.append(f'  {dim}{lang}: segments reordered{off}')
    return '\n'.join(l for l in out if l) or 'no changes'


PROPOSALS = os.path.join(source.CORPUS, 'work', 'proposals')


def _read_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def _write_json(path, d):
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def make_proposal(s, task='', ops=None, name=None):
    """Saves the pending edits for review (nothing is written to the corpus).
    The editor shows the diff and applies it on approval."""
    errs, warns = validate_touched(s)
    changed = [(n, f) for n, f in sorted(s.touched) if source.dumps(s.docs[n][f]) != s.orig[(n, f)]]
    if not changed:
        return None
    pid = name or time.strftime('%Y%m%d-%H%M%S')
    prop = {'id': pid, 'created': time.time(), 'task': task, 'nusach': s.nusach, 'ops': ops or [],
            'diff': diff_text(s), 'errors': errs, 'warnings': warns, 'status': 'pending',
            'files': {f'{n}/{f}': {'base': sha(s.orig[(n, f)]), 'text': source.dumps(s.docs[n][f])} for n, f in changed}}
    os.makedirs(PROPOSALS, exist_ok=True)
    _write_json(os.path.join(PROPOSALS, pid + '.json'), prop)
    return prop


def list_proposals(status='pending'):
    out = []
    for p in sorted(glob.glob(os.path.join(PROPOSALS, '*.json')), reverse=True):
        d = _read_json(p)
        if status in (None, d.get('status')):
            out.append(d)
    return out


def apply_proposal(pid, root=None, work=None, reject=False):
    """Writes an approved proposal (after checking the files are as it left them)."""
    root, work = root or source.SIDDUR, work or os.path.join(source.CORPUS, 'work', 'edit-backups')
    path = os.path.join(PROPOSALS, pid + '.json')
    if not os.path.isfile(path):
        raise EditError(f'no proposal {pid}')
    d = _read_json(path)
    if d['status'] != 'pending':
        raise EditError(f'proposal {pid} is already {d["status"]}')
    if reject:
        d['status'] = 'rejected'
        _write_json(path, d)
        return 'rejected'
    if d.get('errors'):
        raise EditError('the proposal has validation errors; it cannot be applied')
    for rel, info in d['files'].items():
        with open(os.path.join(root, rel), encoding='utf-8') as fh:
            cur = fh.read()
        if sha(cur) != info['base']:
            raise EditError(f'{rel} changed on disk since the proposal was made; ask for it again')
    stamp = time.strftime('%Y%m%d-%H%M%S')
    for rel, info in d['files'].items():
        nus, f = rel.split('/', 1)
        dst = os.path.join(work, stamp, nus)
        os.makedirs(dst, exist_ok=True)
        shutil.copy(os.path.join(root, rel), os.path.join(dst, f))
        open(os.path.join(root, rel), 'w', encoding='utf-8').write(info['text'])
    d['status'] = 'applied'
    _write_json(path, d)
    return f'applied {len(d["files"])} file(s)'


def undo(root=None, work=None):
    work = work or os.path.join(source.CORPUS, 'work', 'edit-backups')
    root = root or source.SIDDUR
    if not os.path.isdir(work) or not os.listdir(work):
        return 'no backups'
    last = sorted(os.listdir(work))[-1]
    n = 0
    for nus in os.listdir(os.path.join(work, last)):
        for f in os.listdir(os.path.join(work, last, nus)):
            shutil.copy(os.path.join(work, last, nus, f), os.path.join(root, nus, f))
            n += 1
    shutil.rmtree(os.path.join(work, last))
    return f'restored {n} file(s) from {last}'


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('lines', nargs='*', help='one command per argument')
    ap.add_argument('-n', '--nusach', default='ashkenaz')
    ap.add_argument('-f', '--file', help='commands, one per line (- for stdin)')
    ap.add_argument('--apply', action='store_true', help='write without asking')
    ap.add_argument('--propose', action='store_true', help='save the changes as a proposal for review in the editor')
    a = ap.parse_args(argv)
    if a.lines == ['undo']:
        print(undo())
        return 0
    if len(a.lines) == 2 and a.lines[0] in ('approve', 'reject'):
        print(apply_proposal(a.lines[1], reject=a.lines[0] == 'reject'))
        return 0
    if a.lines == ['proposals']:
        for d in list_proposals():
            print(d['id'], d['task'][:70], len(d['files']), 'file(s)')
        return 0
    if a.lines == ['help']:
        print(HELP)
        return 0
    lines = list(a.lines)
    if a.file:
        lines += (sys.stdin if a.file == '-' else open(a.file, encoding='utf-8')).read().splitlines()
    s = Session(a.nusach)
    s.load(a.nusach)
    out, err, _ = run_block(s, [l for l in lines if l.strip() != 'apply'])
    print('\n'.join(out))
    if err:
        print('ERROR', err)
        return 1
    if not s.touched:
        print('nothing changed')
        return 0
    errs, _ = validate_touched(s)
    print(diff_text(s, color=sys.stdout.isatty()))
    if errs:
        print('NOT applied: ' + str(len(errs)) + ' new problem(s):\n' + '\n'.join(errs[:12]))
        return 1
    if a.propose:
        prop = make_proposal(s, ops=lines)
        print(f'proposal {prop["id"]} saved: review it in the editor (Agent tab) or `edit.py approve {prop["id"]}`' if prop else 'nothing changed')
        return 0
    if not a.apply:
        if not sys.stdin.isatty():
            print('(dry run: pass --apply to write, or --propose to review in the editor)')
            return 0
        if input('Apply these changes? [y/N] ').strip().lower() != 'y':
            print('discarded')
            return 0
    print(commit(s, True))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
