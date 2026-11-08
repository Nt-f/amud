#!/usr/bin/env python3
"""Training data for kraken's line finder from the line maps: per page a
PAGE XML file beside a copy of its scan, every line the map found as a
baseline and a box, typed by what it is (the Gemara, a commentary in Rashi
script, a note), and each kind's lines together as one region of that type.

    kraken_gt.py Book amud... [--out build/daf/kraken/gt]

The map's word ranges can be off; where its lines are is what kraken
learns, and that is right far more often (check.py's split, skip and
missed flags are the ones about it)."""

import argparse
import shutil
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

from shapely.geometry import box
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

KIND = {'main': 'gemara', 'inner': 'commentary', 'outer': 'commentary'}


def kind_of(l):
    sid = l.get('stream')
    if sid in linemap.BODY and 'range' in l:
        return KIND.get(sid, 'commentary')
    if l.get('catchword') or sid == 'other' and l.get('letters', 0) >= 3:
        return 'note'
    return None


def page_xml(cache, book, amud, img_name):
    lines = []
    m, _ = linemap.amud_map(cache, book, amud, lines_out=lines)
    w, h = m['page']
    kinds = {}
    for l in lines:
        k = kind_of(l)
        if k and l['x1'] - l['x0'] > 4:
            kinds.setdefault(k, []).append(l)
    # The notes' lines come in pieces (a word or two each): one line where
    # they stand on one baseline close together.
    notes = sorted(kinds.get('note', []), key=lambda l: -l['x1'])
    joined = []
    for l in notes:
        for j in joined:
            if abs(j['base'] - l['base']) < 0.4 * max(j['h'], l['h']) and -0.5 * l['h'] < j['x0'] - l['x1'] < 1.5 * max(j['h'], l['h']):
                j.update(x0=min(j['x0'], l['x0']), h=max(j['h'], l['h']))
                break
        else:
            joined.append(dict(x0=l['x0'], x1=l['x1'], base=l['base'], h=l['h']))
    if joined:
        kinds['note'] = joined
    regions = []
    for n, (k, ls) in enumerate(sorted(kinds.items())):
        # A kind's region: its lines' boxes, grown to meet the lines above
        # and below.
        shape = unary_union([box(l['x0'] - 2, l['base'] - 1.6 * l['h'], l['x1'] + 2, l['base'] + 0.6 * l['h']) for l in ls])
        polys = [shape] if shape.geom_type == 'Polygon' else list(shape.geoms)
        for j, poly in enumerate(polys):
            poly = poly.simplify(1.5)
            inside = [l for l in ls if poly.buffer(1).contains(box(l['x0'], l['base'] - l['h'], l['x1'], l['base']))]
            if not inside:
                continue
            regions.append((f'r{n}_{j}', k, poly, inside))
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<PcGts xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2019-07-15">',
           f'<Page imageFilename={quoteattr(img_name)} imageWidth="{w}" imageHeight="{h}">']
    for rid, k, poly, ls in regions:
        pts = ' '.join(f'{x:.0f},{y:.0f}' for x, y in poly.exterior.coords[:-1])
        out.append(f'<TextRegion id="{rid}" custom="structure {{type:{k};}}"><Coords points="{pts}"/>')
        for i, l in enumerate(sorted(ls, key=lambda l: (l['base'], -l['x1']))):
            x0, x1, b, lh = l['x0'], l['x1'], l['base'], l['h']
            out.append(f'<TextLine id="{rid}_l{i}" custom="structure {{type:{k};}}">'
                       f'<Coords points="{x0:.0f},{b - lh:.0f} {x1:.0f},{b - lh:.0f} {x1:.0f},{b + 0.35 * lh:.0f} {x0:.0f},{b + 0.35 * lh:.0f}"/>'
                       f'<Baseline points="{x0:.0f},{b:.0f} {x1:.0f},{b:.0f}"/></TextLine>')
        out.append('</TextRegion>')
    out += ['</Page>', '</PcGts>']
    return '\n'.join(out), sum(len(ls) for *_, ls in regions)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--out', default='build/daf/kraken/gt')
    a = p.parse_args()
    cache, out = Path(a.cache), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for amud in linemap.amudim(a.amudim):
        name = f'{a.book.replace(" ", "_")}_{amud}'
        img, _ = linemap.ocr(cache, a.book, amud)
        shutil.copy(img, out / f'{name}.jpg')
        xml, n = page_xml(cache, a.book, amud, f'{name}.jpg')
        (out / f'{name}.xml').write_text(xml)
        print(f'{name}: {n} lines')


if __name__ == '__main__':
    sys.exit(main())
