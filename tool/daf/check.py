#!/usr/bin/env python3
"""How well the line map puts the Gemara's, Rashi's and Tosafot's words on
their printed lines: each line is read again, by a model the map didn't
use (heb_vilna, all scripts; OCR_CHECK to change it), from a crop of its
own, and compared with the words it was given.

    check.py Berakhot 2a-10b [--cache build/daf/cache] [-v]

Per line it reports trouble of these kinds:

  shift   the line reads better with a word more or fewer at either end:
          a line break in the wrong place
  low     the words and the reading differ a lot (a line run into
          another, a wrong column, text Sefaria lacks)
  missed  a line of the body with no words at all
  split   two lines of one text on one baseline in one column: a printed
          line in pieces
  skip    a column's lines farther apart than its spacing, with a line's
          ink between them: a printed line the map skipped or ran into
          the one beside it

and per stream the words no line got (a line put right in
tool/daf/corrections is taken to be right). split and skip look at the scan and
the lines' places only, not their text. Reads are cached in CACHE/check/,
keyed by the line's crop and model.
"""

import argparse
import hashlib
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image
from rapidfuzz import fuzz

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from lineread import words as read_words  # noqa: E402

import segment  # noqa: E402

# Not the models the line map reads with (heb_vilna_square, _rashi).
MODEL = os.environ.get('OCR_CHECK', 'heb_vilna')


def _f(s):
    # Sefaria's verse references are in the margin in print, not the line.
    s = re.sub(r'\([^()\s]*(?:\s+[^()\s]+){0,3}?\s*\)|\([^()\s]*(?:\s+[^()\s]+){0,1}|^[^()]*\)', ' ', linemap.print_text(s))
    return linemap.fold(s, linemap.FOLD_SQUARE)


def _cached_read(cache, im, l, model):
    """A line read from its own crop: straightened along its slope (none for
    a line of the first pass), a little roomier than segment's."""
    ch = l['h'] / 1.3
    x0, x1 = l.get('ink') or (l['x0'], l['x1'])
    xm = (l['x0'] + l['x1']) / 2
    box = dict(x0=int(x0), x1=int(x1) + 1, top=l['base'] - ch, bottom=l['base'], xc=xm, k=l.get('k', 0.0))
    key = hashlib.sha1(json.dumps([str(cache), box, model, 'v2']).encode()).hexdigest()[:16]
    path = cache / 'check' / f'{key}.json'
    if path.exists():
        return json.loads(path.read_text())
    img, _ = segment.crop(im, box, ch=1.1 * ch)
    ws = read_words(img, model)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(ws, ensure_ascii=False))
    return ws


LABELS = ("מתני'", "גמ'")


def score(read, words):
    # (Sefaria's מתני' and גמ' where the print has a big opening word.)
    words = [w for w in words if w not in LABELS or _f(w) in _f(read)]
    a, b = _f(read), _f(" ".join(words))
    return max(fuzz.ratio(a, b), fuzz.token_sort_ratio(a, b))


def _geometry(body, im):
    """split and skip (see above), from where the lines are and the ink."""
    import numpy as np
    grey = np.asarray(im.convert('L'))
    out = []

    def column(l, m):
        return min(l['x1'], m['x1']) - max(l['x0'], m['x0']) > 0.5 * min(l['x1'] - l['x0'], m['x1'] - m['x0'])
    for sid in {l['stream'] for l in body}:
        ls = sorted([l for l in body if l['stream'] == sid], key=lambda l: l['base'])
        if len(ls) < 3:
            continue
        h = float(np.median([l['h'] for l in ls]))
        steps = []
        for l in ls:
            below = [m['base'] - l['base'] for m in ls if 0.5 * h < m['base'] - l['base'] < 3 * h and column(l, m)]
            if below:
                steps.append(min(below))
        if not steps:
            continue
        pitch = float(np.median(steps))
        for i, l in enumerate(ls):
            for m in ls[i + 1:]:
                if m['base'] - l['base'] >= 0.5 * pitch:
                    break
                gap = max(l['x0'], m['x0']) - min(l['x1'], m['x1'])
                right, left = (l, m) if l['x1'] > m['x1'] else (m, l)
                # (One line's pieces: its words run on from the right one
                # into the left. The top band's halves don't.)
                if gap < 3 * h and right['range'][1] == left['range'][0]:
                    out.append(('split', l, f"with {m['x0']:.0f}-{m['x1']:.0f}"))
            below = [m for m in ls if m['base'] - l['base'] >= 0.5 * pitch and column(l, m)]
            if not below:
                continue
            m = min(below, key=lambda m: m['base'])
            if m['base'] - l['base'] > 1.7 * pitch:
                # A line's ink between them?
                x0, x1 = int(max(l['x0'], m['x0'])), int(min(l['x1'], m['x1']))
                ch = h / 1.3
                y0, y1 = int(l['base'] + 0.3 * ch), int(m['base'] - 1.2 * ch)
                if y1 - y0 < 0.5 * ch or x1 - x0 < 20:
                    continue
                p = (grey[y0:y1, x0:x1] < 128).sum(1)
                line = (grey[int(l['base'] - ch):int(l['base']), x0:x1] < 128).sum(1).mean()
                thick = [e - s for s, e in segment._runs(p > 0.3 * line)]
                if thick and max(thick) >= 0.5 * ch:
                    out.append(('skip', l, f"to {m['base']:.0f}"))
    return out


def check_amud(cache, book, amud, verbose=False):
    lines = []
    linemap.amud_map(cache, book, amud, lines_out=lines)
    streams, extra = linemap.texts(cache, book, amud)
    texts = {**extra, **streams}
    img_path, _ = linemap.ocr(cache, book, amud)
    im = Image.open(img_path)
    im.load()
    body = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]

    def one(l):
        l['check_read'] = ' '.join(w[0] for w in _cached_read(cache, im, l, MODEL))
    with ThreadPoolExecutor(os.cpu_count()) as ex:
        list(ex.map(one, body))

    problems = []
    for l in body:
        ws = texts[l['stream']]
        a, b = l['range']
        s = score(l['check_read'], ws[a:b] + [w for c, d in l.get('more', []) for w in ws[c:d]])
        l['check'] = s
        if l.get('reviewed'):
            continue  # put right by hand (tool/daf/corrections)
        best = (s, 0, 0)
        for da in (-2, -1, 1, 2):
            for db in (-2, -1, 0, 1, 2):
                if 0 <= a + da < b + db <= len(ws):
                    t = score(l['check_read'], ws[a + da:b + db])
                    if t > best[0] + 4:
                        best = (t, da, db)
        for db in (-2, -1, 1, 2):
            if a < b + db <= len(ws):
                t = score(l['check_read'], ws[a:b + db])
                if t > best[0] + 4:
                    best = (t, 0, db)
        if best[1] or best[2]:
            problems.append(('shift', l, f'{best[1]:+d} {best[2]:+d} → {best[0]}'))
        elif s < 60:
            problems.append(('low', l, ''))
    # Lines inside the body's columns with no words: body lines just above
    # and below them, over them.
    def over(m, l):
        return min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.5 * (l['x1'] - l['x0'])
    for l in lines:
        if 'range' in l or l.get('reviewed') or l.get('letters', 0) < 6 or l.get('outside') or linemap._heading(l['text']):
            continue
        above = any(0 < l['base'] - m['base'] < 60 and over(m, l) for m in body)
        below = any(0 < m['base'] - l['base'] < 60 and over(m, l) for m in body)
        if above and below:
            problems.append(('missed', l, l.get('stream') or '-'))
    problems += _geometry(body, im)
    # Words no line got.
    gaps = {}
    for sid in ('main', 'inner', 'outer'):
        got = sorted(r for l in body if l['stream'] == sid for r in [l['range']] + l.get('more', []))
        if not got or not texts.get(sid):
            continue
        holes, end = [], 0
        for a, b in got:
            if a > end:
                holes.append((end, a))
            end = max(end, b)
        if end < len(texts[sid]):
            holes.append((end, len(texts[sid])))
        if holes:
            gaps[sid] = holes
    if verbose:
        for kind, l, note in sorted(problems, key=lambda p: (p[1].get('stream') or '', p[1]['base'])):
            a, b = l.get('range', (0, 0))
            print(f"  {kind:6} {l.get('stream') or '-':8} x{l['x0']:5.0f}-{l['x1']:<5.0f} y{l['base']:5.0f} {note}")
            if 'range' in l:
                print('         set :', linemap.print_text(' '.join(texts[l['stream']][a:b])))
            print('         read:', l.get('check_read') or l['text'])
        for sid, holes in gaps.items():
            for a, b in holes:
                print(f'  gap    {sid:8} {a}-{b}:', linemap.print_text(' '.join(texts[sid][a:b]))[:120])
    return dict(lines=len(body), problems=problems, gaps=gaps)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('-v', '--verbose', action='store_true')
    a = p.parse_args()
    total = dict(lines=0, shift=0, low=0, missed=0, split=0, skip=0, gap=0)
    for amud in linemap.amudim(a.amudim):
        try:
            r = check_amud(Path(a.cache), a.book, amud, a.verbose)
        except SystemExit as e:
            print(amud, 'failed:', e)
            continue
        kinds = [k for k, _, _ in r['problems']]
        n = {k: kinds.count(k) for k in ('shift', 'low', 'missed', 'split', 'skip')}
        g = sum(len(h) for h in r['gaps'].values())
        total['lines'] += r['lines']
        for k in n:
            total[k] += n[k]
        total['gap'] += g
        print(f"{amud}: {r['lines']} lines, {n['shift']} shift, {n['low']} low, {n['missed']} missed, "
              f"{n['split']} split, {n['skip']} skip, {g} gaps", flush=True)
    print('total', total)


if __name__ == '__main__':
    sys.exit(main())
