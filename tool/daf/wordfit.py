#!/usr/bin/env python3
"""Each placed word against the scan: the share of its drawn ink that
lands on the scan's ink (dilated a little), to find words drawn where
nothing like them is printed. Lists the worst.

    wordfit.py PLACE.json [...] [--col ''] [--below 0.5]

With --unlinked, only words that stand for no word of the texts (as
read off the scan); with --drop DIR, each page is also written to DIR
without its words under --drop-below that have no print near them either
(drawn on blank paper: OCR of the paper's grain, e.g. an archive.org
scan's margin; not a misplaced word, which has print beside it or a
line above or below), its frame re-measured.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
import svg as S  # noqa: E402
from inkmatch import render  # noqa: E402
from placeview import page_svg  # noqa: E402


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('places', nargs='+', type=Path)
    p.add_argument('--col')
    p.add_argument('--below', type=float, default=0.5)
    p.add_argument('--out', type=Path, default=Path('build/daf/look/wordfit'))
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--unlinked', action='store_true')
    p.add_argument('--drop', type=Path)
    p.add_argument('--drop-below', type=float, default=0.02)
    a = p.parse_args()
    if a.drop:
        a.drop.mkdir(parents=True, exist_ok=True)
    a.out.mkdir(parents=True, exist_ok=True)
    f_ = S.Fonts()
    tot, bad = 0, 0
    for f in a.places:
        place = json.loads(f.read_text())
        book, amud = f.stem.rsplit('_', 1)
        img, _ = linemap.ocr(Path(a.cache), book.replace('_', ' '), amud)
        scan = np.asarray(linemap.page_image(img).convert('L')) < 128
        scan_raw = scan
        scan = ndimage.binary_dilation(scan, iterations=2)
        H, W = scan.shape
        keep = (lambda w: (a.col is None or w[0] == a.col) and (not a.unlinked or w[1] < 0))
        gone = set()
        sv = a.out / f'{f.stem}.svg'
        sv.write_text(page_svg(place, keep))
        drawn = np.asarray(render(str(sv), W, H)) < 128
        for i, w in enumerate(place['placed']):
            if not keep(w):
                continue
            font = S.RASHI if w[2] else S.SQUARE
            wid = f_.width(font, w[6], w[3])
            x0, x1 = max(0, int(w[4]) + 1), min(W, int(w[4] + wid) - 1)
            y0, y1 = max(0, int(w[5] - 1.6 * w[7])), min(H, int(w[5] + 0.6 * w[7]))
            if x1 <= x0 or y1 <= y0:
                continue
            d = drawn[y0:y1, x0:x1]
            n = d.sum()
            if not n:
                continue
            fit = (d & scan[y0:y1, x0:x1]).sum() / n
            tot += 1
            if a.drop and fit < a.drop_below:
                # (Print within a line and a half above or below: a real
                # word drawn off its place, Sanhedrin 40a's head, is kept.)
                g = int(2 * w[7])
                v0, v1 = max(0, int(y0 - 1.5 * w[7])), int(y1 + 1.5 * w[7])
                if scan_raw[v0:v1, max(0, x0 - g):x1 + g].mean() < 0.005:
                    gone.add(i)
            if fit < a.below:
                bad += 1
                print(f.stem, i, w[3], round(float(w[4])), round(float(w[5])), round(float(fit), 2))
        if a.drop and gone:
            ws = [w for i, w in enumerate(place['placed']) if i not in gone]
            xs = [v for w in ws for v in (w[4], w[4] + f_.width(S.RASHI if w[2] else S.SQUARE, 1, w[3]) * w[6])]
            ys = [v for w in ws for v in (w[5] - 1.1 * w[7], w[5] + 0.35 * w[7])]
            place = dict(place, placed=ws, frame=[round(min(xs)), round(min(ys)), round(max(xs)), round(max(ys))])
            (a.drop / f.name).write_text(json.dumps(place, ensure_ascii=False, separators=(',', ':')))
            print(f.stem, 'dropped', len(gone), flush=True)
    print('words', tot, 'below', a.below, bad)


if __name__ == '__main__':
    main()
