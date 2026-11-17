#!/usr/bin/env python3
"""A text's line the render drew only as read, found in the text by the
line reader: each line of a body column a render drew wholly as the OCR
read it (tied to no word of the text) is read by the reader, its reading
looked for in the amud's texts, and the best stretch, if the reader's loss
for it on the line's ink is as low as for a line's own words, is written
as a correction (NNFIT_DIR) tying the line to it.

Runs in kraken's venv:

    build/daf/kraken-venv/bin/python tool/daf/nnfind.py MODEL PLACE_DIR --pages FILE --out DIR [--fixes DIR]

With --fixes, the corrections already there (nnfit's) are kept beside the
new ones, unless one is on the same line.
"""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from ctcalign import Reader  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
SIDS = {'m': 'main', 'i': 'inner', 'o': 'outer'}
# Per letter, on the line's ink: as a line's own words (median 0.03, 95%
# under 0.52).
MAX_LOSS = 0.4
MIN_RATIO = 85


def _letters(s):
    return re.sub(r'[^א-ת]', '', s)


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
    out = []
    for i, w in enumerate(placed):
        if out and placed[out[-1][-1]][0] == w[0] and abs(placed[out[-1][-1]][5] - w[5]) < 0.3 * w[7]:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def find(read, words, n_hint):
    """The stretch of `words` most like the reading: (a, b, ratio)."""
    from rapidfuzz import fuzz
    # (Sefaria's verse references, in parentheses, are in the print's
    # margin, not its line; what the reader read in brackets, nothing.)
    target = _letters(re.sub(r'\([^)]*\)', '', read))
    if len(target) < 8:
        return None
    flat, depth = [], 0
    for w in words:
        depth += w.count('(')
        flat.append('' if depth else _letters(w))
        depth = max(0, depth - w.count(')'))
    # (Windows of n words that are on the line: a reference's words in
    # them don't count.)
    real = [i for i, f in enumerate(flat) if f]
    best = None
    for n in range(max(1, n_hint - 3), n_hint + 4):
        for j in range(0, len(real) - n + 1):
            a, z = real[j], real[j + n - 1] + 1
            r = fuzz.ratio(target, ''.join(flat[a:z]))
            if best is None or r > best[2]:
                best = (a, z, r)
    return best


def _candidates(placed, maps, fonts, svg, ks=()):
    """The lines to look for: each a body column drew wholly as read, and
    each line of the renders' maps nothing drew (a text's line put aside
    as a quote, or taken for the wrong text and matched to no words), one
    per place on the page; with the OCR's reading."""
    out = []
    for ix in lines_of(placed):
        if placed[ix[0]][0] in SIDS and all(placed[i][1] < 0 for i in ix):
            box = geometry([placed[i] for i in ix], maps, fonts, svg)
            gem = any(k['kind'] == 'gemara' and abs(k['base'] - box['base']) < 0.5 * box['h']
                      and min(k['x1'], box['x1']) - max(k['x0'], box['x0']) > 0.7 * (box['x1'] - box['x0']) for k in ks)
            # (Where kraken takes it for the Gemara's, any text of its size.)
            out.append(dict(box, text=' '.join(placed[i][3] for i in ix), col=None if gem else SIDS[placed[ix[0]][0]]))
    # A commentary's line kraken takes for the Gemara's (its square
    # letters): the Gemara's words a commentary quotes, matched to the
    # commentary (Shabbat 88b): looked for in the Gemara.
    for ix in lines_of(placed):
        if placed[ix[0]][0] not in ('i', 'o') or not any(placed[i][1] >= 0 for i in ix):
            continue
        box = geometry([placed[i] for i in ix], maps, fonts, svg)
        if any(k['kind'] == 'gemara' and abs(k['base'] - box['base']) < 0.5 * box['h']
               and min(k['x1'], box['x1']) - max(k['x0'], box['x0']) > 0.7 * (box['x1'] - box['x0']) for k in ks):
            out.append(dict(box, text=' '.join(placed[i][3] for i in ix), col='main', retake=True))
    linked = [w for w in placed if w[0] in SIDS and w[1] >= 0]
    for L in maps:
        for l in L:
            if (l.get('stream') in SIDS.values() and (l.get('score') or 0) >= 50) or l['x1'] - l['x0'] < 3 * l['h'] \
                    or len(_letters(l.get('text', ''))) < 8:
                continue
            # (Not where a word of a text is drawn tied to it already.)
            if any(abs(w[5] - l['base']) < 0.5 * l['h'] and l['x0'] - 2 <= w[4] <= l['x1'] + 2 for w in linked):
                continue
            if any(abs(c['base'] - l['base']) < 0.5 * l['h'] and min(c['x1'], l['x1']) - max(c['x0'], l['x0']) > 0.5 * (l['x1'] - l['x0'])
                   for c in out):
                continue
            out.append(dict(x0=l['x0'], x1=l['x1'], base=l['base'], h=l['h'], text=l.get('text', ''), col=None))
    return out


def fit(f, lines):
    """A found line as a correction the render can apply to its own lines
    (`lines`, the base render's): where the reading made one line of it and
    more (a row read on across a gutter), the correction cuts its piece out
    (split); where that wider line is the same text's, drawn already, none
    (the correction would give the whole row the piece's words: Shabbat 42b)."""
    w = f['x1'] - f['x0']
    wide = [l for l in lines if abs(l['base'] - f['base']) < 0.5 * l['h'] and l['x1'] - l['x0'] > 1.5 * w
            and min(l['x1'], f['x1']) - max(l['x0'], f['x0']) > 0.5 * w]
    if any(l.get('stream') == f['stream'] for l in wide):
        return None
    return dict(f, split=True) if wide else f


def page(reader, fonts, svg, place, im, streams, maps=(), why=None, ks=()):
    from collections import Counter
    from rapidfuzz import fuzz
    import statistics
    why = why if why is not None else Counter()
    placed = place['placed']
    todo = _candidates(placed, maps, fonts, svg, ks)
    if not todo:
        return []
    ems = reader.emissions(im, todo)
    out = []
    drawn = {sid: {w[1] for w in placed if w[0] == c and w[1] >= 0} for c, sid in SIDS.items()}
    size = {sid: statistics.median([l['h'] for L in maps for l in L if l.get('stream') == sid and (l.get('score') or 0) >= 90])
            for sid in SIDS.values() if any(l.get('stream') == sid and (l.get('score') or 0) >= 90 for L in maps for l in L)}
    for box, em in zip(todo, ems):
        if em is None:
            continue
        read = reader.read(em)
        # (Each text whose lines here are this line's size: a line taken
        # for the wrong text is looked for in the others.)
        sids = [box['col']] if box['col'] else [s for s in SIDS.values() if size.get(s) and 0.75 * size[s] <= box['h'] <= 1.3 * size[s]]
        hits = [(find(read, streams.get(s) or [], len(read.split())), s) for s in sids]
        hits = [(h, s) for h, s in hits if h]
        if not hits:
            why['no_match'] += 1
            continue
        hit, sid = max(hits, key=lambda x: x[0][2])
        # (The Gemara's square letters or a commentary's, as kraken sees
        # them: a commentary quoting the Gemara is no Gemara line.)
        gem = any(k['kind'] == 'gemara' and abs(k['base'] - box['base']) < 0.5 * box['h']
                  and min(k['x1'], box['x1']) - max(k['x0'], box['x0']) > 0.5 * (box['x1'] - box['x0']) for k in ks)
        if ks and (sid == 'main') != gem:
            why['script'] += 1
            continue
        words = streams[sid]
        if hit[2] < MIN_RATIO:
            why['no_match'] += 1
            continue
        a, b, ratio = hit
        # (Not words drawn already: a note quoting the text, read off its
        # own line; and a line of the text's own size.)
        if any(k in drawn[sid] for k in range(a, b)):
            why['drawn'] += 1
            continue
        if size.get(sid) and not 0.75 * size[sid] <= box['h'] <= 1.3 * size[sid]:
            why['size'] += 1
            continue
        loss = reader.score(em, re.sub(r'\([^)]*\)', '', ' '.join(words[a:b])))
        # (Or both readings near the text: a mark in the line, a reference's
        # sign, costs the reader's loss but not the words.)
        text = _letters(re.sub(r'\([^)]*\)', '', ' '.join(words[a:b])))
        both = ratio >= 95 and fuzz.ratio(_letters(box['text']), text) >= 90
        if loss > MAX_LOSS and not both:
            why['loss'] += 1
            continue
        f = fit(dict(stream=sid, base=box['base'], x0=box['x0'], x1=box['x1'], h=box['h'], words=[a, b],
                     first=words[a], last=words[b - 1], score=60, loss=round(loss, 3), ratio=round(ratio, 1),
                     found=True), maps[0] if maps else [])
        if f is None:
            why['part_drawn'] += 1
            continue
        drawn[sid].update(range(a, b))
        out.append(f)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('model')
    p.add_argument('place', type=Path)
    p.add_argument('--pages', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--fixes', type=Path)
    p.add_argument('--lines', type=Path, nargs='*', default=[], help="the renders' lines/ (for each line's box)")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    import svg
    from PIL import Image
    fonts = svg.Fonts()
    reader = Reader(a.model)
    n_lines = 0
    from collections import Counter
    why = Counter()
    for s in a.pages.read_text().split('\n'):
        if not s.strip():
            continue
        book, amud = s.rsplit(' ', 1)
        name = f'{book.replace(" ", "_")}_{amud}'
        try:
            place = json.loads((a.place / f'{name}.json').read_text())
            streams, _ = linemap.texts(CACHE, book, amud)
            img, _ = linemap.ocr(CACHE, book, amud)
            maps = [json.loads((d / f'{name}.json').read_text()) for d in a.lines if (d / f'{name}.json').exists()]
            ks = linemap.kraken_lines(CACHE, book, amud, img)
            got = page(reader, fonts, svg, place, Image.open(img), streams, maps, why, ks)
        except Exception as e:  # noqa: BLE001
            print(s, 'error', repr(e)[:200], flush=True)
            continue
        old = []
        if a.fixes and (a.fixes / f'{name}.json').exists():
            old = [f for f in json.loads((a.fixes / f'{name}.json').read_text())['lines']
                   if not any(abs(f['base'] - g['base']) < 0.5 * g['h'] and min(f['x1'], g['x1']) - max(f['x0'], g['x0']) > 0 for g in got)]
        if got or old:
            (a.out / f'{name}.json').write_text(json.dumps(dict(lines=old + got), ensure_ascii=False, default=float))
        n_lines += len(got)
        print(s, len(got), 'found', sum(g['words'][1] - g['words'][0] for g in got), 'words', flush=True)
    print('total', n_lines, dict(why))


if __name__ == '__main__':
    main()
