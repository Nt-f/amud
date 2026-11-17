#!/usr/bin/env python3
"""Why a page draws less of a text with one OCR than with another: renders
the amud with OCR_LANG A and B (both cached) and, for each of B's lines of
the text that A has no such line at, A's line there and its tag.

    whylost.py "Yoma 60b" [--a heb_vilna --b heb]
"""
import argparse, os, subprocess, sys, json
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def dump(page, lang):
    code = f'''
import sys, json; sys.path.insert(0, {str(ROOT / 'tool/daf')!r})
from pathlib import Path
import svg
b, a = {page!r}.rsplit(' ', 1)
L = []
svg.amud_svg(Path({str(ROOT / 'build/daf/cache')!r}), b, a, core=True, lines_out=L)
print(json.dumps([dict(x0=l['x0'], x1=l['x1'], base=l['base'], h=l['h'], stream=l.get('stream'), range=l.get('range'),
    score=l.get('score'), why=l.get('why') or ('catchword' if l.get('catchword') else '')) for l in L], default=float))
'''
    r = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True, env={**os.environ, 'OCR_LANG': lang})
    if r.returncode: sys.exit(r.stderr[-800:])
    return json.loads(r.stdout.strip().splitlines()[-1])

def main():
    p = argparse.ArgumentParser()
    p.add_argument('pages', nargs='+')
    p.add_argument('--a', default='heb_vilna')
    p.add_argument('--b', default='heb')
    p.add_argument('-v', action='store_true')
    o = p.parse_args()
    for page in o.pages:
        A, B = dump(page, o.a), dump(page, o.b)
        why = Counter()
        rows = []
        for l in B:
            s = l['stream']
            if s not in ('main', 'inner', 'outer') or not l['range'] or (l['score'] or 0) < 50:
                continue
            near = [m for m in A if abs(m['base'] - l['base']) < 0.5 * l['h'] and min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.3 * (l['x1'] - l['x0'])]
            if any(m['stream'] == s and m['range'] and (m['score'] or 0) >= 50 for m in near):
                continue
            m = max(near, key=lambda m: min(m['x1'], l['x1']) - max(m['x0'], l['x0'])) if near else None
            tag = 'none' if not m else f"{m['stream']}:{m['why'] or ('score' + str(round(m['score'] or 0)) if m['stream'] == s else '')}"
            why[s, tag] += 1
            rows.append((round(l['base']), round(l['x0']), round(l['x1']), s, tag))
        print(page, dict(why.most_common(6)))
        if o.v:
            for r in rows: print('   ', *r)

main()
