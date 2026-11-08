#!/usr/bin/env python3
"""Draw segment.py's regions and lines on a scan: build/daf/look/<page>.regions.png."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).parent))
import linemap, segment  # noqa: E402

book, amud = ' '.join(sys.argv[1:-1]), sys.argv[-1]
cache = Path('build/daf/cache')
img_path, rows = linemap.ocr(cache, book, amud)
streams, extra = linemap.texts(cache, book, amud)
im = Image.open(img_path)
lines = linemap.lines_of(rows, im)
info = linemap.classify(lines, streams, extra)
fx0, top, fx1, bottom = info['frame']
grey = np.asarray(im.convert('L'))
k = linemap.OCR_SCALE
words = [dict(x0=int(r['left']) / k, y0=int(r['top']) / k, x1=(int(r['left']) + int(r['width'])) / k, y1=(int(r['top']) + int(r['height'])) / k) for r in rows]
gs, rs = segment.regions(grey, top - 10, bottom + 10, fx0, fx1, lines, linemap._index({**streams, **extra}))
print('frame', [round(v) for v in info['frame']], 'gutters', gs)
out = im.convert('RGB')
d = ImageDraw.Draw(out)
for r in rs:
    d.rectangle(r, outline=(200, 0, 0), width=2)
    ls = segment.lines_in(grey, r)
    print(r, len(ls), [l['bottom'] - l['top'] for l in ls], 'k', sorted({round(l['k'], 4) for l in ls}))
    for l in ls:
        yb = lambda x: l['bottom'] + l['k'] * (x - l['xc'])
        d.line([l['x0'], yb(l['x0']), l['x1'], yb(l['x1'])], fill=(0, 170, 0), width=1)
out.save(f'build/daf/look/{book.replace(" ", "_")}_{amud}.regions.png')
