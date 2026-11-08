#!/usr/bin/env python3
"""How well an SVG page's ink lies on the scan's: the SVG rendered at the
scan's size (headless Chrome), both made black and white, and compared
with a little give (the fonts aren't the print's).

    inkmatch.py build/daf/svg/Berakhot_40b.core.svg [...] [--lines N]

prints per page: recall (the scan's ink in the body's lines that the SVG
covers), precision (the SVG's ink that lies on the scan's), and with
--lines the N body lines that match worst. Only the Gemara, Rashi and
Tosafot lines and the running head count (what --core draws)."""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

GIVE = 3  # pixels


def render(svg, w, h):
    with tempfile.TemporaryDirectory() as d:
        png = Path(d) / 'page.png'
        subprocess.run(['google-chrome', '--headless', '--disable-gpu', '--hide-scrollbars', f'--window-size={w},{h}',
                        f'--screenshot={png}', f'file://{Path(svg).resolve()}'], capture_output=True, check=True)
        return Image.open(png).convert('L')


def grow(mask):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * GIVE + 1))
    return np.asarray(im) > 0


def score(cache, svg, n_lines=0):
    name = Path(svg).name.split('.')[0]
    book, amud = name.rsplit('_', 1)
    book = book.replace('_', ' ')
    img_path, _ = linemap.ocr(cache, book, amud)
    scan = np.asarray(linemap.page_image(img_path).convert('L')) < 128
    h, w = scan.shape
    page = np.asarray(render(svg, w, h)) < 128
    lines = []
    linemap.amud_map(cache, book, amud, lines_out=lines)
    body = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]
    region = np.zeros_like(scan)
    for l in body:
        y0, y1 = int(l['base'] - 1.3 * l['h']), int(l['base'] + 0.4 * l['h'])
        region[max(0, y0):y1, max(0, int(l['x0'])):int(l['x1']) + 1] = True
    gs, gp = grow(scan), grow(page)
    want = scan & region
    recall = (want & gp).sum() / max(1, want.sum())
    near = grow(region)
    drawn = page & near
    precision = (drawn & gs).sum() / max(1, drawn.sum())
    # Ink drawn where the page is blank, anywhere: overflow, words over
    # others, a line in the wrong place.
    stray = (page & ~gs).sum() / max(1, page.sum())
    out = dict(page=name, recall=round(float(recall), 3), precision=round(float(precision), 3), stray=round(float(stray), 3))
    if n_lines:
        rows = []
        for l in body:
            y0, y1 = max(0, int(l['base'] - 1.3 * l['h'])), int(l['base'] + 0.4 * l['h'])
            x0, x1 = max(0, int(l['x0'])), int(l['x1']) + 1
            s, p = want[y0:y1, x0:x1], page[y0:y1, x0:x1]
            r = (s & gp[y0:y1, x0:x1]).sum() / max(1, s.sum())
            q = (p & gs[y0:y1, x0:x1]).sum() / max(1, p.sum())
            rows.append((min(r, q), round(float(r), 2), round(float(q), 2), l['stream'], round(l['base']), x0, x1, l['text'][:40]))
        out['worst'] = sorted(rows)[:n_lines]
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('svgs', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--lines', type=int, default=0)
    a = p.parse_args()
    tot = []
    for svg in a.svgs:
        r = score(Path(a.cache), svg, a.lines)
        tot.append(r)
        print(r['page'], 'recall', r['recall'], 'precision', r['precision'], 'stray', r['stray'], flush=True)
        for row in r.get('worst', []):
            print('   ', *row[1:])
    if len(tot) > 1:
        print('MEAN recall', round(float(np.mean([r['recall'] for r in tot])), 3),
              'precision', round(float(np.mean([r['precision'] for r in tot])), 3),
              'stray', round(float(np.mean([r['stray'] for r in tot])), 3))


if __name__ == '__main__':
    sys.exit(main())
