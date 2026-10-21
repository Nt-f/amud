#!/usr/bin/env python3
"""Draws an amud from its line map as the app sets it (layoutPrinted in
lib/features/gemara/daf_layout.dart), beside the scan, to check a map by
eye.

    render.py OUT/Berakhot_3a.json [--cache build/daf_cache] [-o page.png]
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
FONTS = {'main': ROOT / 'assets/fonts/FrankRuehlCLM-Medium.otf', 'side': ROOT / 'assets/fonts/NotoRashiHebrew-Regular.ttf'}


def printed_size(lines, column):
    steps = sorted(b[2] - a[2] for a, b in zip(lines, lines[1:]) if 0 < b[2] - a[2] < 2.5 * b[3])
    pitch = steps[len(steps) // 2] if steps else lines[0][3] * 1.4
    return pitch * (0.76 if column == 'main' else 0.72)


def render(m, words, scan, scale=1.0):
    x0, top, x1, bottom = m['frame']
    s = scale
    im = Image.new('RGB', (int((x1 - x0) * s), int((bottom - top) * s)), 'white')
    d = ImageDraw.Draw(im)
    fonts = {}

    def font(kind, size):
        key = (kind, round(size * 4))
        if key not in fonts:
            fonts[key] = ImageFont.truetype(str(FONTS[kind]), max(4, round(size)))
        return fonts[key]
    for col, lines in m['columns'].items():
        if not lines:
            continue
        kind = 'main' if col == 'main' else 'side'
        size = printed_size(lines, col) * s
        for lx0, lx1, base, h, a, b in lines:
            ws = words[col][a:b]
            if not ws:
                continue
            f = font(kind, size)
            widths = [d.textlength(w, font=f) for w in ws]
            space = size * 0.25
            natural = sum(widths) + space * (len(ws) - 1)
            box = (lx1 - lx0) * s
            fit = box / natural if natural > box else 1.0
            f = font(kind, size * fit)
            widths = [d.textlength(w, font=f) for w in ws]
            used = sum(widths)
            gap = (box - used) / (len(ws) - 1) if len(ws) > 1 else 0
            x = (lx1 - x0) * s
            y = (base - top) * s
            for w, wd in zip(ws, widths):
                x -= wd
                d.text((x, y), w, font=f, fill='black', anchor='ls', direction='rtl')
                x -= gap
    page = scan.crop((int(x0), int(top), int(x1), int(bottom)))
    if s != 1:
        page = page.resize(im.size)
    out = Image.new('RGB', (im.width * 2 + 20, im.height), 'white')
    out.paste(page, (0, 0))
    out.paste(im, (im.width + 20, 0))
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('map', type=Path)
    p.add_argument('--cache', type=Path, default=Path('build/daf_cache'))
    p.add_argument('-o', '--out', type=Path)
    a = p.parse_args()
    if not features.check('raqm'):
        sys.exit('Pillow needs libraqm to set Hebrew right to left')
    m = json.loads(a.map.read_text())
    streams, _ = linemap.texts(a.cache, m['book'], m['amud'])
    scan = Image.open(a.cache / 'scan' / f'{m["book"].replace(" ", "_")}_{m["amud"]}.jpg').convert('RGB')
    render(m, streams, scan).save(a.out or a.map.with_suffix('.png'))


if __name__ == '__main__':
    main()
