#!/usr/bin/env python3
"""The SVG page over its scan, to see where they differ: the scan in light
grey, the SVG's letters in red on top, where both have ink dark red.

    overlay.py build/daf/svg/Berakhot_40b.core.svg [...]

writes …/Berakhot_40b.core.overlay.png beside each SVG."""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from inkmatch import render  # noqa: E402


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('svgs', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    a = p.parse_args()
    for svg in a.svgs:
        name = Path(svg).name.split('.')[0]
        book, amud = name.rsplit('_', 1)
        img_path, _ = linemap.ocr(Path(a.cache), book.replace('_', ' '), amud)
        scan = np.asarray(linemap.page_image(img_path).convert('L')) < 128
        h, w = scan.shape
        page = np.asarray(render(svg, w, h)) < 128
        out = np.full((h, w, 3), 255, np.uint8)
        out[scan] = (190, 190, 190)
        out[page] = (230, 30, 30)
        out[page & scan] = (120, 0, 0)
        dest = Path(svg).with_suffix('.overlay.png')
        Image.fromarray(out).save(dest)
        print(dest)


if __name__ == '__main__':
    sys.exit(main())
