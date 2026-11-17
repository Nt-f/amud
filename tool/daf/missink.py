#!/usr/bin/env python3
"""Printed ink no drawn word covers, in a region of the page: the
reverse of wordfit.py. Each uncovered blob the size of a letter or more
(not a rule or an ornament: those are long and flat) is listed, and the
lot drawn in red over the scan's grey for a look.

    missink.py PLACE.json --rows SIYUM_ROWS.json [--out DIR]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
import svg as S  # noqa: E402


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('places', nargs='+', type=Path)
    p.add_argument('--rows', type=Path, required=True)
    p.add_argument('--out', type=Path, default=Path('build/daf/look/missink'))
    p.add_argument('--cache', default='build/daf/cache')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    F = S.Fonts()
    rows = json.loads(a.rows.read_text())
    for f in a.places:
        rs = [r for r in rows if r['page'] == f.stem]
        if not rs:
            continue
        place = json.loads(f.read_text())
        book, amud = f.stem.rsplit('_', 1)
        img, _ = linemap.ocr(Path(a.cache), book.replace('_', ' '), amud)
        scan = np.asarray(linemap.page_image(img).convert('L')) < 128
        H, W = scan.shape
        Y0 = max(0, min(r['at'][2] - 2 * r['at'][3] for r in rs))
        Y1 = min(H, max(r['at'][2] + r['at'][3] for r in rs))
        X0 = max(0, min(r['at'][0] for r in rs) - 20)
        X1 = min(W, max(r['at'][1] for r in rs) + 20)
        cover = np.zeros_like(scan)
        for w in place['placed']:
            font = S.RASHI if w[2] else S.SQUARE
            wid = F.width(font, w[6], w[3])
            x0, x1 = int(w[4]) - 3, int(w[4] + wid) + 3
            y0, y1 = int(w[5] - 1.25 * w[7]), int(w[5] + 0.45 * w[7])
            cover[max(0, y0):max(0, y1), max(0, x0):max(0, x1)] = True
        miss = scan & ~cover
        miss[:Y0] = False
        miss[Y1:] = False
        miss[:, :X0] = False
        miss[:, X1:] = False
        lab, n = ndimage.label(ndimage.binary_dilation(miss, iterations=2))
        hm = np.median([r['at'][3] for r in rs])
        blobs = []
        for i, o in enumerate(ndimage.find_objects(lab)):
            hh, ww = o[0].stop - o[0].start, o[1].stop - o[1].start
            px = (miss[o] & (lab[o] == i + 1)).sum()
            if px < 0.15 * hm * hm or hh < 0.3 * hm:
                continue
            if ww > 6 * hh:
                continue
            blobs.append((o[1].start, o[0].start, ww, hh, int(px)))
        out = np.full((H, W, 3), 255, np.uint8)
        out[scan] = (200, 200, 200)
        out[miss] = (230, 30, 30)
        Image.fromarray(out[Y0:Y1, X0:X1]).save(a.out / f'{f.stem}.png')
        print(f.stem, len(blobs), 'blobs', blobs[:12])


if __name__ == '__main__':
    main()
