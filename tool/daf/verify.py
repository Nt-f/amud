#!/usr/bin/env python3
"""Two readers for the words drawn as read: a word a render draws as the
OCR read it (not tied to the text: -1 in its placed words) is checked by
the line reader trained on these pages (ctcalign.Reader), which reads the
word's line on its own. A word both read alike, letter for letter, is kept;
one they read differently is put aside (for review, or left out).

Runs in kraken's venv:

    build/daf/kraken-venv/bin/python tool/daf/verify.py MODEL PLACE_DIR --pages FILE [--out build/daf/verify]

Writes per amud OUT/<name>.json: for each placed word drawn as read, by its
index in `placed`, its verdict ('same', or what the reader read), with the
reader's reading of the whole line.
"""

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from ctcalign import Reader  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
# Letters and the marks of an abbreviation; the rest (punctuation, brackets,
# the asterisk of a note) doesn't decide a word.
_KEEP = re.compile(r'[^א-ת\'"׳״]')


def norm(w):
    w = w.replace('׳', "'").replace('״', '"')
    return _KEEP.sub('', w).strip('\'"') if len(_KEEP.sub('', w)) > 1 else _KEEP.sub('', w)


def geometry(ws, maps, fonts, svg):
    """A placed line's box on the scan: the render's own line under it
    (its height is the print's; the placed words' size is the font's),
    else one made from the words."""
    b = sum(w[5] for w in ws) / len(ws)
    x0 = min(w[4] for w in ws)
    x1 = max(w[4] + fonts.width(svg.RASHI if w[2] else svg.SQUARE, 1, w[3]) * w[6] for w in ws)
    best = None
    for L in maps:
        for l in L:
            o = min(l['x1'], x1) - max(l['x0'], x0)
            if abs(l['base'] - b) < 0.5 * l['h'] and o > 0.5 * (x1 - x0) and (best is None or o > best[0]):
                best = (o, l)
    if best:
        # (Its baseline and height; its ends the words', where the line
        # the reading made runs on into the next column.)
        l = best[1]
        return dict(x0=max(l['x0'], x0 - 0.5 * l['h']), x1=min(l['x1'], x1 + 0.5 * l['h']), base=l['base'], h=l['h'])
    h = max(w[7] for w in ws)
    return dict(x0=x0 - 0.3 * h, x1=x1 + 0.3 * h, base=b, h=h)


def lines_of(placed):
    """The placed words as lines: runs of one column on one baseline."""
    out = []
    for i, w in enumerate(placed):
        if out and placed[out[-1][-1]][0] == w[0] and abs(placed[out[-1][-1]][5] - w[5]) < 0.3 * w[7]:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def page(reader, fonts, svg, place, im, maps=()):
    placed = place['placed']
    todo = [ix for ix in lines_of(placed) if any(placed[i][1] < 0 for i in ix)]
    if not todo:
        return {}, 0
    boxes = [geometry([placed[i] for i in ix], maps, fonts, svg) for ix in todo]
    ems = reader.emissions(im, boxes)
    out = {}
    for ix, em in zip(todo, ems):
        if em is None:
            continue
        read = reader.read(em).split()
        # (The placed words run right to left in the print's order: the
        # reading's order.)
        ocr = [norm(placed[i][3]) for i in ix]
        got = [norm(w) for w in read]
        sm = difflib.SequenceMatcher(None, ocr, got, autojunk=False)
        same = set()
        for a, b, n in sm.get_matching_blocks():
            same.update(range(a, a + n))
        # What the reader read where the OCR's word is: its words in the
        # same stretch of the alignment.
        alt = {}
        for tag, a0, a1, b0, b1 in sm.get_opcodes():
            if tag != 'equal':
                for a in range(a0, a1):
                    alt[a] = ' '.join(read[b0:b1])
        for j, i in enumerate(ix):
            if placed[i][1] >= 0:
                continue
            out[i] = 'same' if j in same and ocr[j] else alt.get(j, '')
    return out, len(todo)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('model')
    p.add_argument('place', type=Path)
    p.add_argument('--pages', type=Path, required=True)
    p.add_argument('--out', type=Path, default=ROOT / 'build/daf/verify')
    p.add_argument('--lines', type=Path, nargs='*', default=[], help="the renders' lines/ (for each line's box)")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    import svg
    from PIL import Image
    fonts = svg.Fonts()
    reader = Reader(a.model)
    tot = {'same': 0, 'other': 0}
    for s in a.pages.read_text().split('\n'):
        if not s.strip():
            continue
        book, amud = s.rsplit(' ', 1)
        name = f'{book.replace(" ", "_")}_{amud}'
        try:
            place = json.loads((a.place / f'{name}.json').read_text())
            img, _ = linemap.ocr(CACHE, book, amud)
            maps = [json.loads((d / f'{name}.json').read_text()) for d in a.lines if (d / f'{name}.json').exists()]
            got, n = page(reader, fonts, svg, place, Image.open(img), maps)
        except Exception as e:  # noqa: BLE001
            print(s, 'error', repr(e)[:200], flush=True)
            continue
        (a.out / f'{name}.json').write_text(json.dumps(got, ensure_ascii=False))
        k = sum(v == 'same' for v in got.values())
        tot['same'] += k
        tot['other'] += len(got) - k
        print(s, n, 'lines', k, 'same', len(got) - k, 'other', flush=True)
    print('total', tot)


if __name__ == '__main__':
    main()
