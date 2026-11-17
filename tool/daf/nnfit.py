#!/usr/bin/env python3
"""The words of a gap, put on the lines between with the line reader: for
each text of an amud, the words missing between two of its drawn lines
(svg.py draws lines matched with a score of 50 or more), and the lines on
the scan between those two that nothing drew (read too poorly to match,
put aside by a layout rule, or matched to the wrong words). The reader
(ctcalign.py) scores each run of the gap's words on each such line, and a
best path through them in order (a line may be a note, and a word may be
one the print hasn't) gives each line its words. Its lines are written as
corrections linemap reads (NNFIT_DIR), with their own score.

Runs in kraken's venv:

    build/daf/kraken-venv/bin/python tool/daf/nnfit.py MODEL RENDER_DIR --pages FILE [--out build/daf/nnfit]

RENDER_DIR is a render's output with its lines/ (shas.py render).
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from ctcalign import Reader  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
OWN = ('main', 'inner', 'outer')
# Per letter, in nats: a line whose best run costs more is no line of the
# gap's (a note, a heading); a word left on no line costs this a letter.
LINE_T = float(__import__('os').environ.get('NNFIT_LINE_T', 1.0))
WORD_T = float(__import__('os').environ.get('NNFIT_WORD_T', 2.5))
BEAM = 48
EDGES = __import__('os').environ.get('NNFIT_EDGES', '1') != '0'


def _drawn(l):
    return l.get('range') and (l.get('score') or 0) >= 50


def _xover(a, b):
    return min(a['x1'], b['x1']) - max(a['x0'], b['x0'])


def _after(g, lines, claimed, down=True):
    """The lines under g in its column (over g if not down), to the next
    drawn line of any text there."""
    col = [l for l in lines if l is not g and _xover(l, g) > 0.5 * min(l['x1'] - l['x0'], g['x1'] - g['x0'])
           and (l['base'] > g['base'] + 0.5 * g['h'] if down else l['base'] < g['base'] - 0.5 * g['h'])]
    col.sort(key=lambda l: l['base'] if down else -l['base'])
    out = []
    for l in col:
        if id(l) in claimed:
            break
        out.append(l)
    return out if down else out[::-1]


def _split(l, ink):
    """A wide line read across two columns side by side (the OCR runs on
    over a narrow gutter: Bava Metzia 46a's Rashi and Tosafot under the
    Gemara) as its two pieces, at the widest blank run of the scan's
    columns in its middle half; the line itself if there's none."""
    if ink is None or l['x1'] - l['x0'] < 20 * l['h']:
        return [l]
    x0, x1, h = int(l['x0']), int(l['x1']), l['h']
    strip = ink[max(0, int(l['base'] - 0.9 * h)):int(l['base'] + 0.25 * h), x0:x1]
    # (A column's gutter runs on over and under the line, but for a note
    # set in it; a wide space between two words of one line has the rows
    # over and under it inked across.)
    tall = ink[max(0, int(l['base'] - 2.2 * h)):int(l['base'] + 1.4 * h), x0:x1]
    if strip.size == 0 or tall.size == 0:
        return [l]
    full = strip.any(0)
    clear = tall.sum(0) <= 2
    lo, hi = int(0.25 * len(full)), int(0.75 * len(full))
    best, run = None, None
    for c in range(lo, hi + 1):
        if c < hi and not full[c]:
            run = c if run is None else run
        elif run is not None:
            if c - run >= 0.4 * h and clear[run:c].sum() >= 0.25 * h and (best is None or c - run > best[1] - best[0]):
                best = (run, c)
            run = None
    if not best:
        return [l]
    # (Right first: the order the print is read in.)
    return [dict(l, x0=x0 + best[1], piece=True), dict(l, x1=x0 + best[0], piece=True)]


def gaps(lines, words, sid, ink=None):
    """(a, b, candidate lines in reading order) per run of words words[a:b]
    no drawn line of the text has, between two that do."""
    mine = sorted([l for l in lines if l.get('stream') == sid and _drawn(l)], key=lambda l: l['range'][0])
    claimed = {id(l) for l in lines if l.get('stream') in linemap.BODY + tuple(f'{s}_{d}' for s in OWN for d in ('prev', 'next'))
               and _drawn(l)}
    out = []
    for g1, g2 in zip(mine, mine[1:]):
        a, b = g1['range'][1], g2['range'][0]
        if b - a < 2:
            continue
        cand = _after(g1, lines, claimed)
        for l in _after(g2, lines, claimed, down=False):
            if all(l is not m for m in cand):
                cand.append(l)
        cand = [p for l in cand for p in _split(l, ink) if p['x1'] - p['x0'] > 3 * p['h']]
        if cand and len(cand) <= 40 and b - a <= 600:
            out.append((a, b, cand))
    # The text's start and end on this amud: words before its first drawn
    # line, on the lines over it in its column, and after its last, on the
    # lines under it. (Many are a comment carried over the page break and
    # printed on the neighbour: the fit may leave them all out.)
    if mine and EDGES:
        first, last = mine[0], mine[-1]
        a = first['range'][0]
        cand = [l for l in _after(first, lines, claimed, down=False) if l['x1'] - l['x0'] > 3 * l['h']]
        if a > 0 and cand and len(cand) <= 40:
            out.append((max(0, a - 300), a, cand))
        z = last['range'][1]
        cand = [l for l in _after(last, lines, claimed) if l['x1'] - l['x0'] > 3 * l['h']]
        if z < len(words) and cand and len(cand) <= 40:
            out.append((z, min(len(words), z + 300), cand))
    return out


def fit(reader, em, cand, words, a, b, cpp):
    """The best path of the gap's words over its lines: per line, its words
    (a run) or None."""
    nlet = [len(linemap._flat(w, linemap.FOLD_SQUARE)) for w in words]
    rest = np.concatenate([np.cumsum(nlet[::-1])[::-1], [0]])  # letters from word k on

    def rank(kv):
        # (A state's cost if the rest were left out: states that have placed
        # different amounts compare fairly.)
        return kv[1][0] + WORD_T * (rest[kv[0]] - rest[b])
    states = {a: (0.0, [])}  # next word → (cost, per line: run or None)
    for i, l in enumerate(cand):
        e = em[i]
        est = (l['x1'] - l['x0']) * cpp
        # Words left out before this line, any number: the print may lack
        # them, or set them where the gap's lines aren't (a comment in
        # another order than Sefaria's). Each costs WORD_T a letter.
        for j in sorted(states):
            cost, path = states[j]
            n = 0
            for k in range(j, b):
                n += nlet[k]
                if k + 1 not in states or cost + WORD_T * n < states[k + 1][0]:
                    states[k + 1] = (cost + WORD_T * n, path)
        states = dict(sorted(states.items(), key=rank)[:4 * BEAM])
        nxt = {}

        def put(j, cost, path):
            if j not in nxt or cost < nxt[j][0]:
                nxt[j] = (cost, path)
        jobs = []
        for j, (cost, path) in states.items():
            put(j, cost + LINE_T * est, path + [None])  # a note: no words of the gap
            n = 0
            for k in range(j, b):
                n += nlet[k]
                if n > 1.6 * est:
                    break
                if n >= 0.5 * est:
                    jobs.append((j, k + 1, cost, path))
        if jobs and e is not None:
            texts = [' '.join(words[j:k]) for j, k, _, _ in jobs]
            losses = _batch_loss(reader, e, texts)
            for (j, k, cost, path), loss, t in zip(jobs, losses, texts):
                if np.isfinite(loss):
                    # (Words skipped before the run cost as words on no line.)
                    put(k, cost + loss, path + [(j, k, loss / max(1, len(t)))])
        states = dict(sorted(nxt.items(), key=rank)[:BEAM])
    end = min(states.items(), key=rank)
    return end[1][1]


def _batch_loss(reader, e, texts):
    ys = [reader.labels(t) for t in texts]
    ok = [i for i, y in enumerate(ys) if y and 2 * len(y) <= e.shape[0]]
    out = [float('inf')] * len(texts)
    if not ok:
        return out
    T = e.shape[0]
    lp = e.unsqueeze(1).expand(T, len(ok), e.shape[1])
    tgt = torch.tensor([v for i in ok for v in ys[i]])
    loss = F.ctc_loss(lp, tgt, torch.full((len(ok),), T, dtype=torch.long), torch.tensor([len(ys[i]) for i in ok]),
                      blank=0, reduction='none', zero_infinity=False)
    for i, v in zip(ok, loss.tolist()):
        out[i] = v
    return out


def page(reader, render, book, amud):
    from PIL import Image
    name = f'{book.replace(" ", "_")}_{amud}'
    lines = json.loads((render / 'lines' / f'{name}.json').read_text())
    streams, _ = linemap.texts(CACHE, book, amud)
    img, _ = linemap.ocr(CACHE, book, amud)
    im = Image.open(img)
    ink = np.asarray(im.convert('L')) < 128
    fixes, used = [], {}
    for sid in OWN:
        words = streams[sid]
        if not words:
            continue
        good = [l for l in lines if l.get('stream') == sid and _drawn(l)]
        if not good:
            continue
        # Letters per pixel in this text's print here.
        cpp = sum(len(linemap._flat(' '.join(words[l['range'][0]:l['range'][1]]), linemap.FOLD_SQUARE)) for l in good) \
            / max(1, sum(l['x1'] - l['x0'] for l in good))
        for a, b, cand in gaps(lines, words, sid, ink):
            em = reader.emissions(im, cand)
            for l, run in zip(cand, fit(reader, em, cand, words, a, b, cpp)):
                if run is None:
                    continue
                j, k, per = run
                if per > LINE_T:
                    continue
                key = (round(l['x0']), round(l['base']))
                if key in used and used[key][0] <= per:
                    continue
                used[key] = (per, sid)
                fixes = [f for f in fixes if (round(f['x0']), round(f['base'])) != key]
                fixes.append(dict(stream=sid, base=l['base'], x0=l['x0'], x1=l['x1'], h=l['h'], words=[j, k],
                                  first=words[j], last=words[k - 1], score=60, loss=round(per, 3), was=l.get('stream'),
                                  **({'split': True} if l.get('piece') else {})))
    return fixes


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('model')
    p.add_argument('render', type=Path)
    p.add_argument('--pages', type=Path, required=True)
    p.add_argument('--out', type=Path, default=ROOT / 'build/daf/nnfit')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    reader = Reader(a.model)
    for s in a.pages.read_text().split('\n'):
        if not s.strip():
            continue
        book, amud = s.rsplit(' ', 1)
        try:
            fixes = page(reader, a.render, book, amud)
        except Exception as e:  # noqa: BLE001
            print(s, 'error', repr(e)[:200], flush=True)
            continue
        name = f'{book.replace(" ", "_")}_{amud}'
        (a.out / f'{name}.json').write_text(json.dumps(dict(lines=fixes), ensure_ascii=False, default=float))
        print(s, len(fixes), 'lines', sum(f['words'][1] - f['words'][0] for f in fixes), 'words', flush=True)


if __name__ == '__main__':
    main()
