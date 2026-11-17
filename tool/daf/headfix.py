#!/usr/bin/env python3
"""The running head from another render where it sits on the print
better: a page's head row (the unlinked row just above its body) is
replaced by the other render's when both read the same words and the
other's words cover more of the scan's ink (the share of each word's
columns with ink, averaged). Some renders set the head's words packed
together from its right end, over the gaps the print leaves between its
parts (Bava Kamma 66a: "פרק שביעי בבא קמא" drawn beside "מרובה").

    headfix.py BASE_DIR OTHER_DIR OUT_DIR   (directories of place/*.json)
"""
import argparse
import json
import shutil
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
import svg as S  # noqa: E402

BETTER = 0.1


def head(placed):
    """Indices of the head row: unlinked words above the body, on the
    baseline nearest it."""
    body = [w for w in placed if w[0]]
    if not body:
        return []
    top = min(w[5] for w in body)
    hs = [i for i, w in enumerate(placed) if w[0] == '' and w[5] < top]
    if not hs:
        return []
    hb = max(placed[i][5] for i in hs)
    return [i for i in hs if abs(placed[i][5] - hb) < 0.5 * placed[i][7]]


def fit(fonts, ink, ws):
    out = []
    for w in ws:
        wid = fonts.width(S.RASHI if w[2] else S.SQUARE, w[6], w[3])
        x0, x1 = max(0, int(w[4]) + 1), int(w[4] + wid) - 1
        y0, y1 = max(0, int(w[5] - 0.8 * w[7])), int(w[5])
        b = ink[y0:y1, x0:x1]
        out.append(b.any(axis=0).mean() if b.size else 0.0)
    return float(np.mean(out)) if out else 0.0


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('base', type=Path)
    p.add_argument('other', type=Path)
    p.add_argument('out', type=Path)
    p.add_argument('--cache', default='build/daf/cache')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    fonts = S.Fonts()
    tot = Counter()
    for f in sorted(a.base.glob('*.json')):
        o = a.other / f.name
        if not o.exists():
            shutil.copy(f, a.out / f.name)
            continue
        place, other = json.loads(f.read_text()), json.loads(o.read_text())
        hb, ho = head(place['placed']), head(other['placed'])
        wb = [place['placed'][i] for i in hb]
        wo = [other['placed'][i] for i in ho]
        if not wb or not wo or [w[3] for w in wb] == [w[3] for w in wo] and all(
                abs(x[4] - y[4]) < 3 for x, y in zip(wb, wo)):
            shutil.copy(f, a.out / f.name)
            continue
        tot['differ'] += 1
        if sorted(w[3] for w in wb) != sorted(w[3] for w in wo):
            tot['other words'] += 1
            shutil.copy(f, a.out / f.name)
            continue
        book, amud = f.stem.rsplit('_', 1)
        img, _ = linemap.ocr(Path(a.cache), book.replace('_', ' '), amud)
        ink = np.asarray(linemap.page_image(img).convert('L')) < 128
        sb, so = fit(fonts, ink, wb), fit(fonts, ink, wo)
        if so <= sb + BETTER:
            tot['kept'] += 1
            shutil.copy(f, a.out / f.name)
            continue
        tot['taken'] += 1
        print(f.stem, f'{sb:.2f} -> {so:.2f}', ' '.join(w[3] for w in wo), flush=True)
        gone = set(hb)
        placed = [w for i, w in enumerate(place['placed']) if i not in gone]
        at = min(hb)
        placed[at:at] = [list(w) for w in wo]
        x0, y0, x1, y1 = place['frame']
        for w in wo:
            x0 = min(x0, w[4])
            x1 = max(x1, w[4] + fonts.width(S.RASHI if w[2] else S.SQUARE, 1, w[3]) * w[6])
            y0 = min(y0, w[5] - 1.1 * w[7])
            y1 = max(y1, w[5] + 0.35 * w[7])
        place = dict(place, placed=placed, frame=[round(x0), round(y0), round(x1), round(y1)])
        (a.out / f.name).write_text(json.dumps(place, ensure_ascii=False, separators=(',', ':')))
    print('total', dict(tot))


if __name__ == '__main__':
    main()
