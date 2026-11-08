"""The print's periods, found in a line's image.

The Vilna page sets its period mid-line, a small round dot standing on its
own between words; heb_vilna learned every other mark but drops this one
(trained on it more often, it still did). This finds the dots by their
shape and puts them back into a reading, after the word they follow.
"""

import numpy as np
from scipy import ndimage


def _otsu(grey):
    """The grey level that best splits ink from paper (scans differ in how
    dark their paper is)."""
    hist = np.bincount(grey.ravel(), minlength=256).astype(float)
    p = hist / hist.sum()
    w = np.cumsum(p)
    mu = np.cumsum(p * np.arange(256))
    between = (mu[-1] * w - mu) ** 2 / np.maximum(w * (1 - w), 1e-9)
    return int(np.argmax(between))


def _components(img):
    """Ink of a grey line image, labelled, and each component's
    (x0, y0, x1, y1, area, label)."""
    grey = np.asarray(img.convert('L'))
    ink = grey < _otsu(grey)
    lab, n = ndimage.label(ink, structure=np.ones((3, 3)))
    out = []
    for k, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        out.append((xs.start, ys.start, xs.stop, ys.stop, int((lab[sl] == k).sum()), k))
    return lab, out


def periods(img):
    """x centers of the periods in a line image: small solid round dots,
    clear of other ink, at any height from mid-line to the baseline, and
    alone (not a colon's dot, with another above or below it)."""
    lab, comps = _components(img)
    big = [c for c in comps if c[3] - c[1] > 8 and c[2] - c[0] > 4]
    if len(big) < 3:
        return []
    h = float(np.median([c[3] - c[1] for c in big]))
    top = float(np.median([c[1] for c in big]))
    base = float(np.median([c[3] for c in big]))
    m = max(2, int(0.06 * h))
    found = []
    for c in comps:
        x0, y0, x1, y1, area, k = c
        w, hh = x1 - x0, y1 - y0
        if not (0.12 * h <= w <= 0.45 * h and 0.12 * h <= hh <= 0.45 * h and 0.6 <= w / hh <= 1.7):
            continue
        if area < 0.55 * w * hh:
            continue  # a dot is solid
        cy = (y0 + y1) / 2
        if not (top + 0.1 * (base - top) <= cy <= base):
            continue  # a geresh or gershayim sits high
        around = lab[max(0, y0 - m):y1 + m, max(0, x0 - m):x1 + m]
        if ((around != 0) & (around != k)).any():
            continue  # touching other ink: part of a letter
        # A space on either side at its height, as between words: a piece
        # of a broken letter has the rest of the letter beside it.
        g, v = int(0.2 * h), int(0.15 * h)
        rows = lab[max(0, y0 - v):y1 + v]
        sides = np.concatenate([rows[:, max(0, x0 - g):x0], rows[:, x1:x1 + g]], axis=1)
        if ((sides != 0) & (sides != k)).any():
            continue
        # A colon: another dot just above or below it, within the line.
        if any(d is not c and min(d[2], x1) - max(d[0], x0) > 0.5 * w and 0.5 * area < d[4] < 2 * area
               and 0.3 * (base - top) < abs((d[1] + d[3]) / 2 - cy) < base - top
               and top - 0.15 * h < (d[1] + d[3]) / 2 < base + 0.15 * h
               for d in comps):
            continue
        found.append((x0 + x1) / 2)
    return found


def place(words, xs):
    """`words` ((text, x0, x1, …) in reading order) with a period after the
    word each dot follows: right to left, the nearest word reaching past it
    to the right (Tesseract's box for that word often takes the dot in)."""
    words = [list(w) for w in words]
    for x in xs:
        after = [w for w in words if w[2] > x + 2]
        if not after:
            continue
        w = min(after, key=lambda w: w[2])
        if not w[0].endswith(('.', ':')):
            w[0] += '.'
    return [tuple(w) for w in words]
