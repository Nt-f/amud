#!/usr/bin/env python3
"""Print words an SVG page leaves out: in each body line, stretches of the
scan's ink at least a word wide with none of the SVG's ink near them.

    bare.py build/daf/sample/*.core.svg [--list N]"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from rapidfuzz import fuzz

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from inkmatch import render  # noqa: E402


def gaps(cache, svg, lines=None):
    """(`lines`: the amud's line map, if made already.)"""
    name = Path(svg).name.split('.')[0]
    book, amud = name.rsplit('_', 1)
    book = book.replace('_', ' ')
    img_path, _ = linemap.ocr(cache, book, amud)
    scan = np.asarray(linemap.page_image(img_path).convert('L')) < 128
    h, w = scan.shape
    page = np.asarray(render(svg, w, h)) < 128
    near = np.asarray(Image.fromarray((page * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))) > 0
    if lines is None:
        lines = []
        linemap.amud_map(cache, book, amud, lines_out=lines)
    out = []
    for l in lines:
        if l.get('stream') not in linemap.BODY or 'range' not in l:
            continue
        core = l['h'] / 1.3
        y0, y1 = int(l['base'] - core), int(l['base'])
        x0, x1 = int(l['x0']), int(l['x1'])
        s = scan[y0:y1, x0:x1].any(0)
        n = near[y0:y1, x0:x1].any(0)
        bare = s & ~n
        # Runs of columns with bare ink, joined across small gaps.
        cols = np.flatnonzero(bare)
        if not len(cols):
            continue
        runs = np.split(cols, np.flatnonzero(np.diff(cols) > 0.5 * core) + 1)
        for r in runs:
            # (Not the Torah Or column's heading, read into the line from the
            # gutter beside it.)
            read = ' '.join(w['text'] for w in l.get('words') or [] if w['x1'] > x0 + r[0] and w['x0'] < x0 + r[-1])
            if read and (fuzz.partial_ratio(read, 'תורה אור') >= 75 or linemap._heading(read)):
                continue
            if r[-1] - r[0] >= 1.5 * core:
                out.append(dict(page=name, stream=l['stream'], base=round(l['base']), x0=x0 + int(r[0]), x1=x0 + int(r[-1]),
                                text=l['text'][:40]))
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('svgs', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--list', type=int, default=0)
    a = p.parse_args()
    rows, n = [], 0
    for svg in a.svgs:
        g = gaps(Path(a.cache), svg)
        rows += g
        print(Path(svg).name.split('.')[0], len(g), flush=True)
    print('TOTAL', len(rows))
    for r in rows[:a.list]:
        print('  ', r['page'], r['stream'], r['base'], r['x0'], r['x1'], r['text'])


if __name__ == '__main__':
    sys.exit(main())
