#!/usr/bin/env python3
"""kraken's lines (build/daf/kraken/<page>.json, from `kraken segment -bl`)
drawn on the scan beside the line map's, to compare the two:

    kraken_look.py Book amud [--crop x0,y0,x1,y1] [--dir build/daf/kraken]

writes build/daf/look/<page>.kraken.png: kraken's baselines and line
outlines in blue, the line map's baselines in red."""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument('book')
p.add_argument('amud')
p.add_argument('--crop')
p.add_argument('--dir', default='build/daf/kraken')
a = p.parse_args()
page = f'{a.book}_{a.amud}'
cache = Path('build/daf/cache')
k = json.loads((Path(a.dir) / f'{page.replace(" ", "_")}.json').read_text())
im = Image.open(cache / 'scan' / f'{page}.jpg').convert('RGB')
d = ImageDraw.Draw(im)
for l in k['lines']:
    d.line([tuple(pt) for pt in l['boundary']], fill=(80, 120, 255), width=1)
    d.line([tuple(pt) for pt in l['baseline']], fill=(0, 0, 255), width=2)
lines = []
linemap.amud_map(cache, a.book, a.amud, lines_out=lines)
for l in lines:
    if l.get('stream') in linemap.BODY and 'range' in l:
        d.line([(l['x0'], l['base'] + 2), (l['x1'], l['base'] + 2)], fill=(230, 0, 0), width=2)
if a.crop:
    im = im.crop(tuple(int(v) for v in a.crop.split(',')))
out = Path('build/daf/look') / f'{page.replace(" ", "_")}.kraken.png'
im.save(out)
print(out)
