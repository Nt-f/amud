#!/usr/bin/env python3
"""Validates corpus/tagged annotation files against their raw chunk
(see corpus/SCHEMA.md). Prints OK, or the problems found.

    python3 tool/corpus/validate.py corpus/tagged/ashkenaz/04_….json [more…]
    python3 tool/corpus/validate.py --all
"""
import glob
import html
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPUS = os.path.join(ROOT, 'corpus')

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
PART_FIELDS = {'text', 'kind', 'when', 'alt', 'node', 'role', 'voice', 'amidah', 'minyan', 'gestures', 'repeat',
               'clean', 'en', 'he', 'cite', 'gloss', 'forgot'}
EN_FIELDS = PART_FIELDS | {'he', 'parts'}
ISSUE_TYPES = {'missing_text', 'misplaced', 'duplicate', 'wrong_vowel', 'ambiguous', 'new_variable', 'new_minhag',
               'alignment', 'engine_bug_risk'}

VARIABLES = set(json.load(open(os.path.join(CORPUS, 'variables.json'))))
NODES = set(json.load(open(os.path.join(CORPUS, 'nodes.json'))))


def comparable(s):
    """Letters, niqqud and punctuation only: no tags, entities, whitespace
    or formatting characters."""
    s = re.sub(r'<[^>]*>', '', s)
    s = html.unescape(s)
    s = unicodedata.normalize('NFC', s)
    return ''.join(c for c in s if not c.isspace() and unicodedata.category(c) != 'Cf')


_TOKEN = re.compile(r'\s*(?:(\|\||&&|==|!=|<=|>=|[!<>()\[\],])|([A-Za-z_]\w*)|(\d+(?:\.\d+)?))')


def check_condition(expr):
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
            if t[1] not in ('true', 'false', 'in') and t[1] not in VARIABLES and not t[1].startswith('x_'):
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
        return f'unknown variable(s) {", ".join(sorted(set(unknown)))} (use one from variables.json or x_…)'
    return None


def check_part(p, where, errs, is_part):
    for k in p:
        if k not in (EN_FIELDS if where.startswith('en:') else PART_FIELDS) and k != 'parts':
            errs.append(f'{where}: unknown field {k!r}')
    kind = p.get('kind')
    if kind is not None and kind not in KINDS:
        errs.append(f'{where}: bad kind {kind!r}')
    if is_part and 'text' not in p:
        errs.append(f'{where}: part without text')
    if 'when' in p:
        if not isinstance(p['when'], str):
            errs.append(f'{where}: when must be a string')
        else:
            e = check_condition(p['when'])
            if e:
                errs.append(f'{where}: when {p["when"]!r}: {e}')
    for f, allowed in (('role', ROLES), ('voice', VOICES), ('amidah', AMIDAH)):
        if f in p and p[f] not in allowed:
            errs.append(f'{where}: bad {f} {p[f]!r}')
    for g in p.get('gestures', []):
        if g not in GESTURES:
            errs.append(f'{where}: bad gesture {g!r}')
    if 'node' in p and p['node'] not in NODES and not str(p['node']).startswith('x.'):
        errs.append(f'{where}: unknown node {p["node"]!r} (use nodes.json or x.…)')
    if 'repeat' in p and not (isinstance(p['repeat'], int) and p['repeat'] > 1):
        errs.append(f'{where}: repeat must be an int > 1')
    if 'minyan' in p and p['minyan'] is not True:
        errs.append(f'{where}: minyan must be true or omitted')


def check_segment(seg_id, original, ann, errs, he_ids=None):
    if not isinstance(ann, dict):
        errs.append(f'{seg_id}: entry must be an object')
        return
    if seg_id.startswith('en:') and 'he' in ann and he_ids is not None and isinstance(ann['he'], list):
        for h in ann['he']:
            if h not in he_ids:
                errs.append(f'{seg_id}: aligned to unknown Hebrew id {h!r}')
    parts = ann.get('parts')
    if parts is not None:
        if not isinstance(parts, list) or len(parts) < 2:
            errs.append(f'{seg_id}: parts must be a list of 2 or more')
            return
        for j, p in enumerate(parts):
            check_part(p, f'{seg_id} part {j + 1}', errs, True)
            if 'kind' not in p:
                errs.append(f'{seg_id} part {j + 1}: missing kind')
        joined = comparable(''.join(p.get('text', '') for p in parts))
        want = comparable(original)
        if joined != want:
            k = next((n for n in range(min(len(joined), len(want))) if joined[n] != want[n]), min(len(joined), len(want)))
            errs.append(f'{seg_id}: parts differ from the original at char {k}: '
                        f'original …{want[max(0, k - 15):k + 15]!r}… parts …{joined[max(0, k - 15):k + 15]!r}…')
    else:
        check_part(ann, seg_id, errs, False)
        if not seg_id.startswith('en:') and 'kind' not in ann:
            errs.append(f'{seg_id}: missing kind')


def validate(path):
    errs = []
    try:
        with open(path) as handle:
            tagged = json.load(handle)
    except json.JSONDecodeError as e:
        return [f'not valid JSON: {e}']
    rel = os.path.relpath(path, os.path.join(CORPUS, 'tagged'))
    raw_path = os.path.join(CORPUS, 'raw', rel)
    if not os.path.exists(raw_path):
        return [f'no raw chunk at {raw_path}']
    with open(raw_path) as handle:
        raw = json.load(handle)
    if tagged.get('chunk') != raw['chunk']:
        errs.append(f'chunk should be {raw["chunk"]!r}')

    leaves = tagged.get('leaves', {})
    for leaf in raw['leaves']:
        l = leaves.get(leaf['path'])
        if l is None:
            errs.append(f'leaf {leaf["path"]!r} missing from "leaves"')
            continue
        if 'node' not in l:
            errs.append(f'leaf {leaf["path"]!r}: missing node')
        for k in l:
            if k not in ('node', 'when', 'service'):
                errs.append(f'leaf {leaf["path"]!r}: unknown field {k!r}')
        if 'node' in l and l['node'] not in NODES and not str(l['node']).startswith('x.'):
            errs.append(f'leaf {leaf["path"]!r}: unknown node {l["node"]!r}')
        if 'when' in l:
            e = check_condition(l['when'])
            if e:
                errs.append(f'leaf {leaf["path"]!r}: when: {e}')
        if 'service' in l and l['service'] not in SERVICES:
            errs.append(f'leaf {leaf["path"]!r}: bad service {l["service"]!r}')
    extra = set(leaves) - {l['path'] for l in raw['leaves']}
    if extra:
        errs.append(f'unknown leaves: {sorted(extra)[:5]}')

    he_ids = set()
    for lang in ('he', 'en'):
        originals = {}
        for leaf in raw['leaves']:
            for s in leaf.get(lang, {}).get('segments', []):
                originals[s['id']] = s['html']
        if lang == 'he':
            he_ids = set(originals)
        anns = tagged.get(lang, {})
        missing = [i for i in originals if i not in anns]
        if missing:
            errs.append(f'{len(missing)} {lang} segment(s) not annotated, first: {missing[:3]}')
        unknown = [i for i in anns if i not in originals]
        if unknown:
            errs.append(f'{len(unknown)} unknown {lang} id(s), first: {unknown[:3]}')
        for seg_id, ann in anns.items():
            if seg_id in originals:
                check_segment(seg_id, originals[seg_id], ann, errs, he_ids if lang == 'en' else None)

    for j, iss in enumerate(tagged.get('issues', [])):
        if not isinstance(iss, dict) or iss.get('type') not in ISSUE_TYPES:
            errs.append(f'issue {j + 1}: type must be one of {sorted(ISSUE_TYPES)}')
    return errs


def main(argv):
    paths = sorted(glob.glob(os.path.join(CORPUS, 'tagged', '*', '*.json'))) if argv == ['--all'] else argv
    if not paths:
        print(__doc__)
        return 2
    bad = 0
    for p in paths:
        errs = validate(p)
        if errs:
            bad += 1
            print(f'{p}: {len(errs)} problem(s)')
            for e in errs[:40]:
                print('  ' + e)
            if len(errs) > 40:
                print(f'  … and {len(errs) - 40} more')
        elif len(paths) == 1:
            print('OK')
    if len(paths) > 1:
        print(f'{len(paths) - bad}/{len(paths)} OK')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
