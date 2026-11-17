#!/usr/bin/env python3
"""A render's placed words (place/<name>.json, what the app draws) over
the scan: the scan grey, the words red, both dark red. Optionally only the
words of one column ('' for the siyum and words drawn as read) and the
part of the page they cover.

    placeview.py PLACE.json [...] [--col ''] [--out DIR] [--scale 1.5]
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import json  # noqa: E402

import linemap  # noqa: E402
import svg as S  # noqa: E402
from inkmatch import render  # noqa: E402


def page_svg(place, keep):
    f = S.Fonts()
    body = []
    for w in place['placed']:
        if not keep(w):
            continue
        font = S.RASHI if w[2] else S.SQUARE
        x, uses = f.width(font, 1, w[3]), []
        for c in w[3]:
            key, adv = f._glyph(font, c)
            x -= adv
            if key:
                uses.append(f'<use xlink:href="#{key}" x="{x * 1000:.0f}"/>')
        body.append(f'<g transform="matrix({w[6] / 1000:.5f},0,0,{-w[7] / 1000:.5f},{w[4]:.1f},{w[5]:.1f})">' + ''.join(uses) + '</g>')
    W, H = place['size']
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<rect width="{W}" height="{H}" fill="white"/>{f.svg_defs()}' + ''.join(body) + '</svg>')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('places', nargs='+', type=Path)
    p.add_argument('--col', help="only this column's words ('' for the siyum and words drawn as read)")
    p.add_argument('--out', type=Path, default=Path('build/daf/look/placeview'))
    p.add_argument('--scale', type=float, default=1.0)
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--rows', type=Path, help="siyum.py's rows report: crop to each page's siyum")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    for f in a.places:
        place = json.loads(f.read_text())
        keep = (lambda w: True) if a.col is None else (lambda w: w[0] == a.col)
        ws = [w for w in place['placed'] if keep(w)]
        if not ws:
            continue
        book, amud = f.stem.rsplit('_', 1)
        img, _ = linemap.ocr(Path(a.cache), book.replace('_', ' '), amud)
        scan = np.asarray(linemap.page_image(img).convert('L')) < 128
        H, W = scan.shape
        sv = a.out / f'{f.stem}.svg'
        sv.write_text(page_svg(place, keep))
        drawn = np.asarray(render(str(sv), W, H)) < 128
        out = np.full((H, W, 3), 255, np.uint8)
        out[scan] = (190, 190, 190)
        out[drawn] = (230, 30, 30)
        out[drawn & scan] = (120, 0, 0)
        im = Image.fromarray(out)
        rows = [r for r in json.loads(a.rows.read_text()) if r['page'] == f.stem] if a.rows else []
        if rows:
            im = im.crop((0, max(0, min(r['at'][2] - 3 * r['at'][3] for r in rows)), W,
                          min(H, max(r['at'][2] + r['at'][3] for r in rows))))
        elif a.col is not None:
            y0 = max(0, int(min(w[5] - 2.2 * w[7] for w in ws)))
            y1 = min(H, int(max(w[5] + 0.6 * w[7] for w in ws)))
            im = im.crop((0, y0, W, y1))
        if a.scale != 1:
            im = im.resize((int(im.width * a.scale), int(im.height * a.scale)))
        dest = a.out / f'{f.stem}.png'
        im.save(dest)
        print(dest)


if __name__ == '__main__':
    main()
