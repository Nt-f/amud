#!/usr/bin/env python3
"""How far each body line of an SVG page sits from its print: per line the
shift (dx, dy) that best lays the SVG's ink on the scan's, and how much of
the scan's ink the SVG leaves bare there.

    drift.py build/daf/sample/*.core.svg [--worst N]"""

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from inkmatch import render  # noqa: E402


def shifts(cache, svg):
    name = Path(svg).name.split('.')[0]
    book, amud = name.rsplit('_', 1)
    book = book.replace('_', ' ')
    img_path, _ = linemap.ocr(cache, book, amud)
    scan = np.asarray(linemap.page_image(img_path).convert('L')) < 128
    h, w = scan.shape
    page = np.asarray(render(svg, w, h)) < 128
    lines = []
    linemap.amud_map(cache, book, amud, lines_out=lines)
    out = []
    R = 12
    for l in lines:
        if l.get('stream') not in linemap.BODY or 'range' not in l:
            continue
        y0, y1 = int(l['base'] - 1.3 * l['h']), int(l['base'] + 0.4 * l['h'])
        x0, x1 = int(l['x0']), int(l['x1'])
        if y0 - R < 0 or y1 + R > h or x0 - R < 0 or x1 + R > w:
            continue
        s = scan[y0:y1, x0:x1]
        if s.sum() < 50:
            continue
        best = (-1, 0, 0)
        for dy in range(-R, R + 1, 1):
            for dx in range(-R, R + 1, 2):
                p = page[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
                v = (p & s).sum()
                if v > best[0]:
                    best = (v, dx, dy)
        p0 = page[y0:y1, x0:x1]
        bare = 1 - (p0 & s).sum() / s.sum()
        drawn = p0.sum() / max(1, s.sum())
        # (dx, dy: where the SVG's ink is, from the scan's; + is right/down)
        out.append(dict(page=name, stream=l['stream'], base=round(l['base']), x0=x0, x1=x1,
                        dx=-best[1], dy=-best[2], drawn=round(float(drawn), 2), text=l['text'][:40]))
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('svgs', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--worst', type=int, default=0)
    a = p.parse_args()
    rows = []
    for svg in a.svgs:
        rows += shifts(Path(a.cache), svg)
    if not rows:
        return
    for sid in ('main', 'inner', 'outer'):
        r = [x for x in rows if x['stream'].startswith(sid)]
        if not r:
            continue
        dx, dy, dr = (np.array([x[k] for x in r]) for k in ('dx', 'dy', 'drawn'))
        print(f'{sid:6} lines {len(r):4}  dy median {np.median(dy):+.1f}  |dy|>3 {np.mean(abs(dy) > 3):.0%}  '
              f'dx median {np.median(dx):+.1f}  |dx|>4 {np.mean(abs(dx) > 4):.0%}  '
              f'drawn/print ink median {np.median(dr):.2f}  <0.6 {np.mean(dr < 0.6):.0%}')
    for x in sorted(rows, key=lambda x: -(abs(x['dy']) + abs(x['dx']) / 2))[:a.worst]:
        print('  ', x['page'], x['stream'], x['base'], x['x0'], 'dx', x['dx'], 'dy', x['dy'], 'drawn', x['drawn'], x['text'])


if __name__ == '__main__':
    sys.exit(main())
