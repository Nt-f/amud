#!/usr/bin/env python3
"""Where each word of a matched line is on the scan, by the line reader:
for each drawn line of an amud that has words the render couldn't tie to
the text ("unlinked": drawn as the OCR read them), the line's own words
are aligned to its ink letter by letter (ctcalign.Reader.align). svg.py
reads the result (NNALIGN_DIR) as the line's reading, so each of its words
is the text's word, over its own ink.

Runs in kraken's venv:

    build/daf/kraken-venv/bin/python tool/daf/nnalign.py MODEL RENDER_DIR --pages FILE [--out build/daf/nnalign] [--all]

RENDER_DIR is a render's output (its lines/ and place/).

Before that, where a line's word range is a word or two off at an end
(the commonest reason a word goes unlinked), the breaks between a run of
consecutive drawn lines of a text are put right: each may move up to
SHIFT words, and the set of breaks the reader fits best over all the
run's lines is taken. Moved breaks are written as corrections (--fixes
DIR, read by linemap through NNFIT_DIR) beside the word places.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from ctcalign import Reader  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
OWN = {'main': 'm', 'inner': 'i', 'outer': 'o'}
# Per letter: above this the line's text and its ink disagree (a line
# matched to the wrong words, a reading of another text): left as read.
MAX_LOSS = 0.8
SHIFT = 3
# A line the reader can't read as its own words even roughly (a box over
# two lines, a line matched to the wrong place) breaks a run.
BREAK_LOSS = 3.0
# Per letter: a low-scored line whose words fit its ink this well is drawn
# (a line's own text: median 0.03, 95% under 0.52).
LOW_OK = 0.5


def _lines_with_unlinked(lines, place):
    out = []
    for l in lines:
        sid = l.get('stream')
        if sid not in OWN or not l.get('range') or (l.get('score') or 0) < 50 or l.get('more'):
            continue
        c = OWN[sid]
        if any(w[0] == c and w[1] < 0 and abs(w[5] - l['base']) < 0.6 * l['h'] and l['x0'] - 4 <= w[4] <= l['x1'] + 4
               for w in place['placed']):
            out.append(l)
    return out


def _runs(lines, sid):
    """Runs of drawn lines of a text, each starting where the last ended."""
    ls = sorted([l for l in lines if l.get('stream') == sid and l.get('range') and (l.get('score') or 0) >= 50
                 and not l.get('more')], key=lambda l: l['range'][0])
    runs = []
    for l in ls:
        if runs and runs[-1][-1]['range'][1] == l['range'][0]:
            runs[-1].append(l)
        else:
            runs.append([l])
    return runs


def _losses(reader, em, texts):
    import torch.nn.functional as F
    import torch
    ys = [reader.labels(t) for t in texts]
    out = [float('inf')] * len(texts)
    ok = [i for i, y in enumerate(ys) if y and em is not None and 2 * len(y) <= em.shape[0]]
    if not ok:
        return out
    T = em.shape[0]
    loss = F.ctc_loss(em.unsqueeze(1).expand(T, len(ok), em.shape[1]), torch.tensor([v for i in ok for v in ys[i]]),
                      torch.full((len(ok),), T, dtype=torch.long), torch.tensor([len(ys[i]) for i in ok]),
                      blank=0, reduction='none', zero_infinity=False)
    for i, v in zip(ok, loss.tolist()):
        out[i] = v
    return out


def _rebreak(reader, run, ems, words):
    """New (a, b) per line of a run: the breaks the reader fits best."""
    n = len(run)
    lo, hi = run[0]['range'][0], run[-1]['range'][1]
    # The breaks' choices: c_0 = lo and c_n = hi fixed, c_i near b_i.
    choices = [[lo]] + [list(range(max(lo + 1, l['range'][1] - SHIFT), min(hi, l['range'][1] + SHIFT + 1))) for l in run[:-1]] + [[hi]]
    best = {lo: (0.0, [])}
    for i in range(n):
        pairs = [(c0, c1) for c0 in best for c1 in choices[i + 1] if c1 > c0]
        losses = _losses(reader, ems[i], [' '.join(words[c0:c1]) for c0, c1 in pairs])
        nxt = {}
        for (c0, c1), v in zip(pairs, losses):
            if v == float('inf'):
                continue
            tot = best[c0][0] + v
            if c1 not in nxt or tot < nxt[c1][0]:
                nxt[c1] = (tot, best[c0][1] + [(c0, c1)])
        if not nxt:
            return [tuple(l['range']) for l in run]
        best = nxt
    return best[hi][1] if hi in best else [tuple(l['range']) for l in run]


def _snap(ink, l, xs, frame):
    """The reader's word edges are a frame or so out (a frame is several
    pixels): each break between two words moved onto the widest blank
    run of the scan's columns near it, and each word cut to its own ink."""
    import numpy as np
    X0 = int(l['x0']) - 8
    strip = ink[max(0, int(l['base'] - 0.9 * l['h'])):int(l['base'] + 0.25 * l['h']), max(0, X0):int(l['x1']) + 8]
    if strip.size == 0:
        return xs
    X0 = max(0, X0)
    full = strip.any(0)
    xs = [list(x) for x in xs]
    f = max(2, int(round(frame)))
    # (Text order runs right to left: word i+1 is left of word i.)
    for i in range(len(xs) - 1):
        lo = int(min(xs[i + 1][1], xs[i][0])) - f - X0
        hi = int(max(xs[i + 1][1], xs[i][0])) + f - X0
        lo, hi = max(0, lo), min(len(full), hi)
        best, run = None, None
        for c in range(lo, hi + 1):
            if c < hi and not full[c]:
                run = c if run is None else run
            elif run is not None:
                mid = (lo + hi) / 2
                if best is None or (c - run, -abs((run + c) / 2 - mid)) > (best[1] - best[0], -abs(sum(best) / 2 - mid)):
                    best = (run, c)
                run = None
        if best:
            xs[i + 1][1], xs[i][0] = best[0] + X0, best[1] + X0
    out = []
    for i, (a, b) in enumerate(xs):
        # The outer edges may reach a frame further, to the line's own ink.
        a_ = a - (f if i == len(xs) - 1 else 0)
        b_ = b + (f if i == 0 else 0)
        cols = np.nonzero(full[max(0, int(a_) - X0):max(0, int(b_) - X0)])[0]
        out.append((cols[0] + max(0, int(a_) - X0) + X0, cols[-1] + 1 + max(0, int(a_) - X0) + X0) if len(cols) else (a, b))
    return out


def page(reader, render, book, amud, every=False):
    from PIL import Image
    name = f'{book.replace(" ", "_")}_{amud}'
    lines = json.loads((render / 'lines' / f'{name}.json').read_text())
    place = json.loads((render / 'place' / f'{name}.json').read_text())
    want = {id(l) for l in (lines if every else _lines_with_unlinked(lines, place))}
    if not want and not any(l.get('stream') in OWN and l.get('range') and (l.get('score') or 0) < 50 for l in lines):
        return [], []
    streams, _ = linemap.texts(CACHE, book, amud)
    img, _ = linemap.ocr(CACHE, book, amud)
    im = Image.open(img)
    import numpy as np
    ink = np.asarray(im.convert('L')) < 128
    out, fixes = [], []
    for sid in OWN:
        words = streams[sid]
        for run in _runs(lines, sid):
            if not any(id(l) in want for l in run):
                continue
            ems = reader.emissions(im, run)
            geos = list(reader.geometry)
            # Lines the reader can't read as theirs break the run.
            own = [_losses(reader, e, [' '.join(words[l['range'][0]:l['range'][1]])])[0]
                   / max(1, len(' '.join(words[l['range'][0]:l['range'][1]]))) for l, e in zip(run, ems)]
            parts, cur = [], []
            for l, e, g, v in zip(run, ems, geos, own):
                if v > BREAK_LOSS:
                    if cur:
                        parts.append(cur)
                    cur = []
                    continue
                cur.append((l, e, g))
            if cur:
                parts.append(cur)
            for part in parts:
                ls = [x[0] for x in part]
                spans = _rebreak(reader, ls, [x[1] for x in part], words) if len(ls) > 1 else [tuple(ls[0]['range'])]
                for (l, e, g), (a, b) in zip(part, spans):
                    xs, loss = reader.align(e, g, words[a:b])
                    if xs is None or loss > MAX_LOSS:
                        continue
                    xs = _snap(ink, l, xs, g[1] * g[2])
                    if (a, b) != tuple(l['range']):
                        fixes.append(dict(stream=sid, base=l['base'], x0=l['x0'], x1=l['x1'], h=l['h'], words=[a, b],
                                          first=words[a], last=words[b - 1], score=max(60, round(l.get('score') or 0)),
                                          loss=round(loss, 3), was=list(l['range'])))
                    if id(l) in want or (a, b) != tuple(l['range']):
                        out.append(dict(stream=sid, base=l['base'], x0=l['x0'], x1=l['x1'], range=[a, b], loss=round(loss, 3),
                                        words=[[round(x0, 1), round(x1, 1)] for x0, x1 in xs]))
    # Lines matched to their words with too low a score to draw (a poor
    # reading): the reader checks the words on the ink, and where they fit
    # as a line's own text does, the line is drawn.
    for sid in OWN:
        words = streams[sid]
        low = [l for l in lines if l.get('stream') == sid and l.get('range') and 0 <= (l.get('score') or 0) < 50
               and not l.get('more') and l['range'][1] > l['range'][0] and l['x1'] - l['x0'] > 3 * l['h']]
        if not low:
            continue
        for l, e, g in zip(low, reader.emissions(im, low), list(reader.geometry)):
            a, b = l['range']
            if e is None:
                continue
            xs, loss = reader.align(e, g, words[a:b])
            if xs is None or loss > LOW_OK:
                continue
            fixes.append(dict(stream=sid, base=l['base'], x0=l['x0'], x1=l['x1'], h=l['h'], words=[a, b],
                              first=words[a], last=words[b - 1], score=60, loss=round(loss, 3), was=list(l['range']), low=True))
            out.append(dict(stream=sid, base=l['base'], x0=l['x0'], x1=l['x1'], range=[a, b], loss=round(loss, 3),
                            words=[[round(x0, 1), round(x1, 1)] for x0, x1 in _snap(ink, l, xs, g[1] * g[2])]))
    return out, fixes


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('model')
    p.add_argument('render', type=Path)
    p.add_argument('--pages', type=Path, required=True)
    p.add_argument('--out', type=Path, default=ROOT / 'build/daf/nnalign')
    p.add_argument('--all', action='store_true', help='every drawn line, not only those with unlinked words')
    p.add_argument('--fixes', type=Path, help='write moved line breaks here as corrections (merged with any there)')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    reader = Reader(a.model)
    for s in a.pages.read_text().split('\n'):
        if not s.strip():
            continue
        book, amud = s.rsplit(' ', 1)
        try:
            got, fixes = page(reader, a.render, book, amud, a.all)
        except Exception as e:  # noqa: BLE001
            print(s, 'error', repr(e)[:200], flush=True)
            continue
        name = f'{book.replace(" ", "_")}_{amud}'
        (a.out / f'{name}.json').write_text(json.dumps(dict(lines=got), ensure_ascii=False, default=float))
        if a.fixes and fixes:
            a.fixes.mkdir(parents=True, exist_ok=True)
            fp = a.fixes / f'{name}.json'
            old = json.loads(fp.read_text())['lines'] if fp.exists() else []
            # (A line the gap fit placed keeps that; these are for the rest.)
            keep = [f for f in old if not any(abs(f['base'] - g['base']) < 5 and abs(f['x0'] - g['x0']) < 5 and f['stream'] == g['stream'] for g in fixes)]
            fp.write_text(json.dumps(dict(lines=keep + fixes), ensure_ascii=False, default=float))
        print(s, len(got), 'lines', len(fixes), 'moved', flush=True)


if __name__ == '__main__':
    main()
