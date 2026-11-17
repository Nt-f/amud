#!/usr/bin/env python3
"""Cleaned copies of archive.org's scans (toned, unevenly yellowed paper),
for the scan/ of another cache:

  flat    grey, divided by a wide blur of itself (the paper's tone, sigma
          40 px at full size), so the paper is flat white, then stretched:
          ink at its darkest percentile to 0, paper to 255. Greys kept.
  sauvola grey, thresholded locally (Sauvola, a window of ~2.5 Rashi letter
          heights), black and white.

    iaclean.py flat|sauvola SRC_SCAN_DIR DEST_SCAN_DIR [--pages FILE] [--crop]

--crop writes, beside DEST, crops at full scale of a Rashi passage to
compare by eye instead of whole pages."""

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np


def flat(grey):
    g = grey.astype(np.float32)
    bg = cv2.GaussianBlur(g, (0, 0), 40)
    f = np.clip(g / np.maximum(bg, 1) * 255, 0, 255)
    lo = np.percentile(f, 0.5)
    return np.clip((f - lo) / max(1.0, 250 - lo) * 255, 0, 255).astype(np.uint8)


def sauvola(grey):
    from skimage.filters import threshold_sauvola
    t = threshold_sauvola(grey, window_size=61, k=0.2)
    return np.where(grey > t, 255, 0).astype(np.uint8)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('how', choices=('flat', 'sauvola'))
    p.add_argument('src', type=Path)
    p.add_argument('dest', type=Path)
    p.add_argument('--pages', type=Path)
    a = p.parse_args()
    names = ([s.strip().replace(' ', '_') + '.jpg' for s in a.pages.read_text().splitlines() if s.strip()]
             if a.pages else [f.name for f in sorted(a.src.glob('*.jpg'))])
    a.dest.mkdir(parents=True, exist_ok=True)
    f = flat if a.how == 'flat' else sauvola
    for n in names:
        src, dst = a.src / n, a.dest / n
        if not src.exists() or dst.exists():
            continue
        grey = cv2.imread(str(src), cv2.IMREAD_GRAYSCALE)
        cv2.imwrite(str(dst), f(grey), [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f'{len(names)} pages', file=sys.stderr)


if __name__ == '__main__':
    main()
