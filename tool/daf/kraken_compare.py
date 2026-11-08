#!/usr/bin/env python3
"""How kraken's lines (build/daf/kraken/<page>.json) and the line map's
body lines agree:

    kraken_compare.py Book amud... [--dir build/daf/kraken] [-v]

Per line of the map: the kraken line on its baseline (within 0.4 of its
height) that overlaps it most, and whether their ends agree (within one
letter height). Prints counts: same, kraken longer (the map's line is a
piece of kraken's), kraken shorter, none on that baseline; and kraken's
lines inside the body that no map line is on."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402


DIR = Path('build/daf/kraken')
TOTAL = dict(same=0, longer=0, shorter=0, none=0, extra=0)


def kraken_lines(page):
    k = json.loads((DIR / f'{page.replace(" ", "_")}.json').read_text())
    out = []
    for l in k['lines']:
        xs = [p[0] for p in l['baseline']]
        ys = [p[1] for p in l['baseline']]
        out.append(dict(x0=min(xs), x1=max(xs), base=sum(ys) / len(ys)))
    return out


def compare(book, amud, verbose=False):
    cache = Path('build/daf/cache')
    lines = []
    linemap.amud_map(cache, book, amud, lines_out=lines)
    body = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]
    ks = kraken_lines(f'{book}_{amud}')
    n = dict(same=0, longer=0, shorter=0, none=0)
    used = set()
    for l in body:
        h = l['h']
        near = [(i, k) for i, k in enumerate(ks) if abs(k['base'] - l['base']) < 0.4 * h and min(k['x1'], l['x1']) - max(k['x0'], l['x0']) > 0]
        if not near:
            n['none'] += 1
            if verbose:
                print('  none   ', l['stream'], int(l['base']), int(l['x0']), int(l['x1']))
            continue
        i, k = max(near, key=lambda t: min(t[1]['x1'], l['x1']) - max(t[1]['x0'], l['x0']))
        used.add(i)
        d0, d1 = k['x0'] - l['x0'], k['x1'] - l['x1']
        if abs(d0) <= h and abs(d1) <= h:
            n['same'] += 1
        elif d0 < -h or d1 > h:
            n['longer'] += 1
            if verbose:
                print('  longer ', l['stream'], int(l['base']), f"map {int(l['x0'])}-{int(l['x1'])} kraken {int(k['x0'])}-{int(k['x1'])}")
        else:
            n['shorter'] += 1
            if verbose:
                print('  shorter', l['stream'], int(l['base']), f"map {int(l['x0'])}-{int(l['x1'])} kraken {int(k['x0'])}-{int(k['x1'])}")
    x0 = min(l['x0'] for l in body)
    x1 = max(l['x1'] for l in body)
    y0 = min(l['base'] for l in body)
    y1 = max(l['base'] for l in body)
    extra = [k for i, k in enumerate(ks) if i not in used and x0 <= (k['x0'] + k['x1']) / 2 <= x1 and y0 <= k['base'] <= y1
             and not any(abs(k['base'] - l['base']) < 0.4 * l['h'] and min(k['x1'], l['x1']) - max(k['x0'], l['x0']) > 0 for l in body)]
    for key, v in n.items():
        TOTAL[key] += v
    TOTAL['extra'] += len(extra)
    print(f"{book} {amud}: {len(body)} map lines: {n}; kraken lines in the body on no map line: {len(extra)}")
    if verbose:
        for k in extra:
            print('  kraken only', int(k['base']), int(k['x0']), int(k['x1']))


if __name__ == '__main__':
    v = '-v' in sys.argv
    args = [a for a in sys.argv[1:] if a != '-v']
    if '--dir' in args:
        i = args.index('--dir')
        DIR = Path(args[i + 1])
        del args[i:i + 2]
    for amud in linemap.amudim(args[1:]):
        compare(args[0], amud, v)
    print('total', TOTAL)
