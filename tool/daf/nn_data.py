#!/usr/bin/env python3
"""Training data for the two networks, from two full renders of Shas (the
Vilna OCR model's and stock heb's, each with its lines, shas.py render):
per amud a PAGE XML file beside a link to its scan, every line of it typed
(main, inner, outer: the Gemara, Rashi, Tosafot; note: anything else), and
the lines matched well to their text carrying that text, for a line reader.

    nn_data.py VILNA_DIR HEB_DIR MERGED_PLACE_DIR [--out build/daf/nn] [-j 12]
    nn_data.py VILNA_DIR - - --text-only --out build/daf/nn_text

A line is a text's where either render matched it to that text (score ≥ 50;
a comment carried over the page break is its text's too); a line of the
Vilna render's that neither matched is a note. Only amudim whose texts the
merged render draws nearly whole (each text ≥ 97% of the words between its
first and last drawn one) are written: their labels are the ones to learn.
pages.tsv lists them with the share drawn, for choosing a held-out set.
"""

import argparse
import json
import os
import sys
from multiprocessing import Pool
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

sys.path.insert(0, str(Path(__file__).parent))
os.environ.setdefault('OCR_LANG', 'heb_vilna')

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
OWN = ('main', 'inner', 'outer')
COL = {'m': 'main', 'i': 'inner', 'o': 'outer'}


def _base(s):
    """main_prev → main; other streams are no text's (None)."""
    s = (s or '').split('_')[0]
    return s if s in OWN else None


def _good(l):
    return _base(l.get('stream')) and l.get('range') and (l.get('score') or 0) >= 50


def _near(l, m):
    return (abs(l['base'] - m['base']) < 0.5 * max(l['h'], m['h'])
            and min(l['x1'], m['x1']) - max(l['x0'], m['x0']) > 0.5 * min(l['x1'] - l['x0'], m['x1'] - m['x0']))


def coverage(place):
    """Per text, the share of the words between its first and last drawn
    word that are drawn."""
    out = {}
    for c, sid in COL.items():
        got = {w[1] for w in place['placed'] if w[0] == c and w[1] >= 0}
        if len(got) >= 5:
            out[sid] = len(got) / (max(got) - min(got) + 1)
    return out


def labelled(A, B):
    """The page's lines, each with its kind and, matched well, its text's
    stream and word range."""
    out = []
    for l in A:
        if l['x1'] - l['x0'] <= 4:
            continue
        if _good(l):
            out.append(dict(l, kind=_base(l['stream']), src='a'))
            continue
        m = next((m for m in B if _good(m) and _near(l, m)), None)
        if m:
            out.append(dict(m, kind=_base(m['stream']), src='b'))
        elif l.get('letters', 0) >= 3 or l.get('catchword'):
            out.append(dict(l, kind='note', src='a'))
    # (A piece of a text's line read on its own is no note.)
    body = [l for l in out if l['kind'] != 'note']
    out = [l for l in out if l['kind'] != 'note' or not any(
        abs(l['base'] - m['base']) < 0.5 * max(l['h'], m['h'])
        and min(l['x1'], m['x1']) - max(l['x0'], m['x0']) > 0.3 * (l['x1'] - l['x0']) for m in body)]
    # Lines only the other render found (Menachot 87b's Rashi column).
    for m in B:
        if _good(m) and not any(_near(l, m) for l in out):
            out.append(dict(m, kind=_base(m['stream']), src='b'))
    return out


def _join_notes(ls):
    """Notes come in pieces of a word or two: one line where pieces stand
    on one baseline close together (as kraken_gt.py)."""
    joined = []
    for l in sorted(ls, key=lambda l: -l['x1']):
        for j in joined:
            if abs(j['base'] - l['base']) < 0.4 * max(j['h'], l['h']) and -0.5 * l['h'] < j['x0'] - l['x1'] < 1.5 * max(j['h'], l['h']):
                j.update(x0=min(j['x0'], l['x0']), h=max(j['h'], l['h']))
                break
        else:
            joined.append(dict(x0=l['x0'], x1=l['x1'], base=l['base'], h=l['h'], kind='note'))
    return joined


def page_xml(lines, words, size, img_name):
    from shapely.geometry import box
    from shapely.ops import unary_union
    w, h = size
    kinds = {}
    for l in lines:
        kinds.setdefault(l['kind'], []).append(l)
    if 'note' in kinds:
        kinds['note'] = _join_notes(kinds['note'])
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<PcGts xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2019-07-15">',
           f'<Page imageFilename={quoteattr(img_name)} imageWidth="{w}" imageHeight="{h}">']
    n_text = 0
    for n, (k, ls) in enumerate(sorted(kinds.items())):
        shape = unary_union([box(l['x0'] - 2, l['base'] - 1.6 * l['h'], l['x1'] + 2, l['base'] + 0.6 * l['h']) for l in ls])
        polys = [shape] if shape.geom_type == 'Polygon' else list(shape.geoms)
        for j, poly in enumerate(polys):
            poly = poly.simplify(1.5)
            inside = [l for l in ls if poly.buffer(1).contains(box(l['x0'], l['base'] - l['h'], l['x1'], l['base']))]
            if not inside:
                continue
            pts = ' '.join(f'{x:.0f},{y:.0f}' for x, y in poly.exterior.coords[:-1])
            out.append(f'<TextRegion id="r{n}_{j}" custom="structure {{type:{k};}}"><Coords points="{pts}"/>')
            for i, l in enumerate(sorted(inside, key=lambda l: (l['base'], -l['x1']))):
                x0, x1, b, lh = l['x0'], l['x1'], l['base'], l['h']
                text = ''
                # (Its own text's words, for the line reader: well matched,
                # on this amud, not cut by a rule of the gap-fill.)
                if k in OWN and l.get('stream') == k and (l.get('score') or 0) >= 90 and not l.get('tail'):
                    a, z = l['range']
                    text = ' '.join(words[k][a:z])
                te = f'<TextEquiv><Unicode>{escape(text)}</Unicode></TextEquiv>' if text else ''
                n_text += bool(text)
                out.append(f'<TextLine id="r{n}_{j}_l{i}" custom="structure {{type:{k};}}">'
                           f'<Coords points="{x0:.0f},{b - lh:.0f} {x1:.0f},{b - lh:.0f} {x1:.0f},{b + 0.35 * lh:.0f} {x0:.0f},{b + 0.35 * lh:.0f}"/>'
                           f'<Baseline points="{x0:.0f},{b:.0f} {x1:.0f},{b:.0f}"/>{te}</TextLine>')
            out.append('</TextRegion>')
    out += ['</Page>', '</PcGts>']
    return '\n'.join(out), n_text


def one(job):
    import linemap
    from PIL import Image
    name, A, B, M, out, text_only = job
    try:
        if text_only:
            cov = {}
        else:
            cov = coverage(json.loads((M / f'{name}.json').read_text()))
            if not cov or min(cov.values()) < 0.97:
                return name, None, cov
        book, amud = name.rsplit('_', 1)
        book = book.replace('_', ' ')
        streams, _ = linemap.texts(CACHE, book, amud)
        img, _ = linemap.ocr(CACHE, book, amud)
        lines = labelled(json.loads((A / f'{name}.json').read_text()), [] if text_only else json.loads((B / f'{name}.json').read_text()))
        if text_only:
            lines = [l for l in lines if l['kind'] != 'note']
        size = Image.open(img).size
        xml, n_text = page_xml(lines, streams, size, f'{name}.jpg')
        link = out / f'{name}.jpg'
        if not link.exists():
            link.symlink_to(Path(img).resolve())
        (out / f'{name}.xml').write_text(xml)
        return name, n_text, cov
    except Exception as e:  # noqa: BLE001
        return name, f'error {e}', {}


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('vilna', type=Path)
    p.add_argument('heb', type=Path)
    p.add_argument('merged', type=Path)
    p.add_argument('--out', type=Path, default=ROOT / 'build/daf/nn')
    p.add_argument('-j', type=int, default=12)
    p.add_argument('--text-only', action='store_true', help="the first render's lines only, for the line reader (HEB_DIR and MERGED aren't read)")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    names = sorted(f.stem for f in (a.vilna / 'lines').glob('*.json') if a.text_only or (a.heb / 'lines' / f.name).exists())
    jobs = [(n, a.vilna / 'lines', a.heb / 'lines', a.merged, a.out, a.text_only) for n in names]
    rows, kept, lines = [], 0, 0
    with Pool(a.j) as pool:
        for name, n, cov in pool.imap_unordered(one, jobs, chunksize=8):
            if isinstance(n, str):
                print(name, n)
                continue
            rows.append(f"{name}\t{'' if n is None else n}\t" + '\t'.join(f'{s}={cov.get(s, 0):.3f}' for s in OWN))
            if n is not None:
                kept += 1
                lines += n
    (a.out / 'pages.tsv').write_text('\n'.join(sorted(rows)) + '\n')
    print(f'{kept} of {len(names)} amudim written, {lines} lines with text')


if __name__ == '__main__':
    main()
