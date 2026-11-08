#!/usr/bin/env python3
"""The scan and svg.py's page side by side, as a PNG to compare them:

    side.py build/daf/svg/Berakhot_5a.svg [--scale 0.5]

writes …/Berakhot_5a.side.png beside the SVG. Renders with headless Chrome
(google-chrome) at the scan's size."""
import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

p = argparse.ArgumentParser()
p.add_argument('svg')
p.add_argument('--cache', default='build/daf/cache')
p.add_argument('--scale', type=float, default=0.5)
a = p.parse_args()
svg = Path(a.svg).resolve()
name = svg.name.split('.')[0]
book, amud = name.rsplit('_', 1)
scan = Image.open(Path(a.cache) / 'scan' / f'{book.replace("_", " ")}_{amud}.jpg').convert('RGB')
w, h = scan.size
with tempfile.TemporaryDirectory() as d:
    png = Path(d) / 'page.png'
    subprocess.run(['google-chrome', '--headless', '--disable-gpu', '--hide-scrollbars', f'--window-size={w},{h}',
                    f'--screenshot={png}', f'file://{svg}'], capture_output=True, check=True)
    page = Image.open(png).convert('RGB')
out = Image.new('RGB', (2 * w, h), 'white')
out.paste(scan, (0, 0))
out.paste(page, (w, 0))
out = out.resize((int(2 * w * a.scale), int(h * a.scale)), Image.LANCZOS)
dest = svg.with_suffix('.side.png')
out.save(dest)
print(dest)
