"""Amud's siddur text: corpus/siddur/<nusach>/<chunk>.json, edited by hand
(see corpus/SCHEMA.md). Loading, checking and the canonical formatting
shared by build_assets.py, validate.py and fmt.py.
"""
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPUS = os.path.join(ROOT, 'corpus')
SIDDUR = os.path.join(CORPUS, 'siddur')

KINDS = {'prayer', 'instruction', 'speaker', 'note', 'heading', 'commentary'}
ROLES = {'individual', 'chazzan', 'congregation', 'congregation_then_chazzan', 'chazzan_then_congregation',
         'together', 'responsive', 'kohanim', 'mourner', 'oleh', 'head_of_household'}
VOICES = {'silent', 'undertone', 'aloud'}
AMIDAH = {'silent', 'repetition'}
SERVICES = {'shacharit', 'mincha', 'maariv', 'musaf', 'none'}
GESTURES = {'stand', 'sit', 'bow', 'bow_full', 'knees_bend', 'rise_on_toes', 'feet_together', 'three_steps_back',
            'three_steps_forward', 'cover_eyes', 'kiss_tzitzit', 'gather_tzitzit', 'touch_tefillin', 'head_down',
            'face_ark', 'ark_open', 'ark_close', 'hold_torah', 'shake_lulav', 'hold_cup', 'look_at_candles',
            'look_at_fingernails', 'strike_chest', 'look_at_moon', 'raise_hands', 'turn_west',
            'bow_left_right_center'}

# Field order in the files: what a line is and when it is said first, the
# text last. `comment` is for editors and never reaches the app.
PART_FIELDS = ['kind', 'when', 'alt', 'node', 'role', 'voice', 'amidah', 'minyan', 'gestures', 'repeat',
               'forgot', 'en', 'he', 'gloss', 'cite', 'clean', 'comment', 'text']
SEG_FIELDS = ['ref', 'translates', 'parts'] + PART_FIELDS
LEAF_FIELDS = ['path', 'title', 'comment', 'node', 'when', 'service', 'he', 'en']
TEXT_FIELDS = ['version', 'segs']

VARIABLES = set(json.load(open(os.path.join(CORPUS, 'variables.json'))))
NODES = set(json.load(open(os.path.join(CORPUS, 'nodes.json'))))


def labels():
    """What each personal circumstance (`if_…`) means: "If: For a man"."""
    return json.load(open(os.path.join(CORPUS, 'labels.json')))


def nusachim():
    return sorted(os.path.basename(d) for d in glob.glob(os.path.join(SIDDUR, '*')) if os.path.isdir(d))


def files(nusach):
    """A siddur's chunk files, in book order (by file name)."""
    return sorted(p for p in glob.glob(os.path.join(SIDDUR, nusach, '*.json')) if os.path.basename(p) != 'book.json')


def parts(seg):
    """A segment's parts: its `parts`, or the segment itself as one part."""
    if 'parts' in seg:
        return seg['parts']
    return [{k: v for k, v in seg.items() if k not in ('ref', 'translates')}]


# Formatting: one line per segment, or per part of a split segment, so a
# diff shows exactly which line changed.

def _j(v):
    return json.dumps(v, ensure_ascii=False)


def _obj(d, order):
    keys = [k for k in order if k in d] + [k for k in d if k not in order]
    return '{' + ', '.join(f'{_j(k)}: {_j(d[k])}' for k in keys) + '}'


def _seg(s, ind):
    if 'parts' not in s:
        return ind + _obj(s, SEG_FIELDS)
    head = {k: v for k, v in s.items() if k != 'parts'}
    lines = [ind + _obj(head, SEG_FIELDS)[:-1] + ', "parts": [']
    lines += [',\n'.join(ind + '  ' + _obj(p, PART_FIELDS) for p in s['parts'])]
    return '\n'.join(lines) + '\n' + ind + ']}'


def _text(t, ind):
    segs = ',\n'.join(_seg(s, ind + '    ') for s in t['segs'])
    return (f'{{\n{ind}  "version": {_j(t["version"])},\n{ind}  "segs": [\n{segs}\n{ind}  ]\n{ind}}}')


def dumps(doc):
    out = ['{', f'  "book": {_j(doc["book"])},', f'  "chunk": {_j(doc["chunk"])},', '  "leaves": [']
    leaves = []
    for leaf in doc['leaves']:
        keys = [k for k in LEAF_FIELDS if k in leaf] + [k for k in leaf if k not in LEAF_FIELDS]
        body = []
        for k in keys:
            v = _text(leaf[k], '      ') if k in ('he', 'en') and isinstance(leaf[k], dict) else _j(leaf[k])
            body.append(f'      {_j(k)}: {v}')
        leaves.append('    {\n' + ',\n'.join(body) + '\n    }')
    out.append(',\n'.join(leaves))
    out += ['  ]', '}']
    return '\n'.join(out) + '\n'


# Checking.

_TOKEN = re.compile(r'\s*(?:(\|\||&&|==|!=|<=|>=|[!<>()\[\],])|([A-Za-z_]\w*)|(\d+(?:\.\d+)?))')


def check_condition(expr, known):
    """Parses the condition grammar of packages/siddur_engine condition.dart.
    Returns an error string or None."""
    toks, pos = [], 0
    expr = expr.strip()
    while pos < len(expr):
        m = _TOKEN.match(expr, pos)
        if not m or m.end() == pos:
            return f'bad character at {pos}: {expr[pos:pos + 10]!r}'
        pos = m.end()
        if m.group(1):
            toks.append(('op', m.group(1)))
        elif m.group(2):
            toks.append(('id', m.group(2)))
        elif m.group(3):
            toks.append(('num', m.group(3)))
    i = 0
    unknown = []

    def peek():
        return toks[i] if i < len(toks) else (None, None)

    def take(v=None):
        nonlocal i
        t = peek()
        if v is not None and t[1] != v:
            raise ValueError(f'expected {v!r}, got {t[1]!r}')
        i += 1
        return t

    def primary():
        t = take()
        if t[0] == 'id':
            if t[1] not in ('true', 'false', 'in') and t[1] not in known:
                unknown.append(t[1])
        elif t[0] == 'num':
            pass
        elif t[1] == '(':
            orx()
            take(')')
        else:
            raise ValueError(f'unexpected {t[1]!r}')

    def cmp():
        primary()
        t = peek()
        if t[1] in ('==', '!=', '<', '<=', '>', '>='):
            take()
            primary()
        elif t == ('id', 'in'):
            take()
            take('[')
            if peek()[1] != ']':
                primary()
                while peek()[1] == ',':
                    take()
                    primary()
            take(']')

    def unary():
        if peek()[1] == '!':
            take()
            unary()
        else:
            cmp()

    def andx():
        unary()
        while peek()[1] == '&&':
            take()
            unary()

    def orx():
        andx()
        while peek()[1] == '||':
            take()
            andx()

    try:
        orx()
        if i != len(toks):
            return f'trailing {toks[i][1]!r}'
    except (ValueError, IndexError) as e:
        return str(e)
    if unknown:
        return f'unknown variable(s) {", ".join(sorted(set(unknown)))} (variables.json, or an if_ in labels.json)'
    return None


_VOID = {'br', 'img', 'hr', 'wbr'}


def unbalanced_tags(html):
    """The first tag that isn't closed in order, or None."""
    stack = []
    for m in re.finditer(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*?(/?)>', html):
        tag = m.group(2).lower()
        if tag in _VOID or m.group(3):
            continue
        if not m.group(1):
            stack.append(tag)
        elif not stack or stack[-1] != tag:
            return f'</{tag}>'
        else:
            stack.pop()
    return f'<{stack[-1]}>' if stack else None


def _check_part(p, where, errs, known, english):
    for k in p:
        if k not in PART_FIELDS:
            errs.append(f'{where}: unknown field {k!r}')
    if not isinstance(p.get('text'), str) or not p['text']:
        errs.append(f'{where}: missing text')
    if 'kind' in p and p['kind'] not in KINDS:
        errs.append(f'{where}: bad kind {p["kind"]!r} ({", ".join(sorted(KINDS))})')
    if not english and 'kind' not in p:
        errs.append(f'{where}: missing kind')
    if 'when' in p:
        e = check_condition(p['when'], known) if isinstance(p['when'], str) else 'must be a string'
        if e:
            errs.append(f'{where}: when {p["when"]!r}: {e}')
    for f, allowed in (('role', ROLES), ('voice', VOICES), ('amidah', AMIDAH)):
        if f in p and p[f] not in allowed:
            errs.append(f'{where}: bad {f} {p[f]!r}')
    for g in p.get('gestures', []):
        if g not in GESTURES:
            errs.append(f'{where}: bad gesture {g!r}')
    if 'node' in p and p['node'] not in NODES and not str(p['node']).startswith('x.'):
        errs.append(f'{where}: unknown node {p["node"]!r} (nodes.json, or x.…)')
    if 'repeat' in p and not (isinstance(p['repeat'], int) and p['repeat'] > 1):
        errs.append(f'{where}: repeat must be a whole number above 1')
    for f in ('minyan', 'forgot'):
        if f in p and p[f] is not True:
            errs.append(f'{where}: {f} must be true or left out')


def check_file(path, doc, known, seen_paths):
    """Problems (errors) and warnings in one chunk file."""
    errs, warns = [], []
    for k in ('book', 'chunk', 'leaves'):
        if k not in doc:
            errs.append(f'missing {k!r}')
    for leaf in doc.get('leaves', []):
        lp = leaf.get('path')
        w = f'leaf {lp!r}'
        if not lp:
            errs.append('a leaf without a path')
            continue
        if lp in seen_paths:
            errs.append(f'{w}: also in {os.path.basename(seen_paths[lp])}')
        seen_paths[lp] = path
        for k in leaf:
            if k not in LEAF_FIELDS:
                errs.append(f'{w}: unknown field {k!r}')
        if leaf.get('node') not in NODES and not str(leaf.get('node')).startswith('x.'):
            errs.append(f'{w}: unknown node {leaf.get("node")!r}')
        if 'when' in leaf:
            e = check_condition(leaf['when'], known)
            if e:
                errs.append(f'{w}: when: {e}')
        if 'service' in leaf and leaf['service'] not in SERVICES:
            errs.append(f'{w}: bad service {leaf["service"]!r}')
        he_refs = set()
        for lang in ('he', 'en'):
            t = leaf.get(lang)
            if t is None:
                continue
            if not isinstance(t, dict) or not isinstance(t.get('version'), str) or not isinstance(t.get('segs'), list):
                errs.append(f'{w} {lang}: needs "version" and "segs"')
                continue
            refs = set()
            for s in t['segs']:
                ref = s.get('ref')
                where = f'{lp} {lang}:{ref}'
                if not isinstance(ref, str) or not ref:
                    errs.append(f'{w} {lang}: a segment without a ref')
                    continue
                if ref in refs:
                    errs.append(f'{where}: ref used twice')
                refs.add(ref)
                if lang == 'en':
                    for h in s.get('translates', []):
                        if h not in he_refs:
                            errs.append(f'{where}: translates unknown Hebrew ref {h!r}')
                elif 'translates' in s:
                    errs.append(f'{where}: "translates" is for English segments')
                if 'parts' in s:
                    extra = set(s) - {'ref', 'translates', 'parts'}
                    if extra:
                        errs.append(f'{where}: fields {sorted(extra)} go on the parts')
                    if not isinstance(s['parts'], list) or not s['parts']:
                        errs.append(f'{where}: parts must be a non-empty list')
                        continue
                for j, p in enumerate(parts(s)):
                    _check_part(p, where + (f' part {j + 1}' if 'parts' in s else ''), errs, known, lang == 'en')
                tag = unbalanced_tags(''.join(p.get('text', '') for p in parts(s)))
                if tag:
                    warns.append(f'{where}: unbalanced {tag}')
            if lang == 'he':
                he_refs = refs
    return errs, warns


LICENSES = ['public domain', 'cc0', 'cc-by', 'cc-by-sa', 'cc-by-nc', 'cc-by-nc-sa']


def combined_license(licenses):
    """The license of text drawn from several sources: the most restrictive,
    or 'unknown' if one of them isn't an open license."""
    ranks = [LICENSES.index(l.lower()) if l.lower() in LICENSES else None for l in licenses]
    if not ranks or None in ranks:
        return 'unknown'
    worst = LICENSES[max(ranks)]
    return {'public domain': 'Public Domain', 'cc0': 'CC0'}.get(worst, worst.upper())


def check_book(book, chunks):
    """Problems and warnings in book.json, against the chunks."""
    errs, warns = [], []
    for k in ('title', 'heTitle', 'sources', 'sections'):
        if k not in book:
            errs.append(f'book.json: missing {k!r}')
    paths = [l['path'] for _, d in chunks for l in d.get('leaves', []) if 'path' in l]
    sections = {'/'.join(p.split('/')[:i]) for p in paths for i in range(1, p.count('/') + 1)}
    for _, d in chunks:
        if d.get('book') != book.get('title'):
            errs.append(f'book.json: title {book.get("title")!r}, but a chunk says {d.get("book")!r}')
            break
    for sp in book.get('sections', {}):
        if sp not in sections:
            warns.append(f'book.json: section {sp!r} has no leaves')
    for sp in sorted(sections - set(book.get('sections', {}))):
        warns.append(f'book.json: section {sp!r} has no Hebrew title')
    for lang in ('he', 'en'):
        listed = book.get('sources', {}).get(lang, {})
        for _, d in chunks:
            for leaf in d.get('leaves', []):
                v = (leaf.get(lang) or {}).get('version')
                if v is not None and v not in listed:
                    errs.append(f'leaf {leaf.get("path")!r}: {lang} version {v!r} is not in book.json sources')
    return errs, warns


def load_book(nusach):
    return json.load(open(os.path.join(SIDDUR, nusach, 'book.json')))


def load(nusach):
    """A siddur, checked: book.json, [(path, doc)] in order, errors, warnings."""
    known = VARIABLES | set(labels())
    out, errs, warns, seen = [], [], [], {}
    for path in files(nusach):
        rel = os.path.relpath(path, ROOT)
        try:
            doc = json.load(open(path))
        except json.JSONDecodeError as e:
            errs.append(f'{rel}: not valid JSON: {e}')
            continue
        e, w = check_file(path, doc, known, seen)
        errs += [f'{rel}: {x}' for x in e]
        warns += [f'{rel}: {x}' for x in w]
        out.append((path, doc))
    try:
        book = load_book(nusach)
    except (OSError, json.JSONDecodeError) as e:
        return None, out, errs + [f'{nusach}/book.json: {e}'], warns
    e, w = check_book(book, out)
    return book, out, errs + [f'{nusach}/{x}' for x in e], warns + [f'{nusach}/{x}' for x in w]
