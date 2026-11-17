#!/usr/bin/env python3
"""Only words shown to be right: a render's placed words with the ones it
drew as the OCR read them (-1: not tied to the text) kept only where
  - the line is the text's: it has words tied to the text, or it is a
    comment carried over the page break, matched to the neighbour's text
    (score 50 or more), and
  - the word is read alike by the OCR and the line reader (verify.py),
  - and it lies within its column: among the words tied to its text on
    its line and the lines around it.
Whole lines drawn as read and tied to no text are left out: a note, a
margin's line, a reading too poor to match. The running head is kept as it is; the
other words of no column only where read alike or the text's own.

    strict.py PLACE_DIR VERIFY_DIR OUT_DIR --lines DIR [DIR ...]

(--lines: the renders' lines/, to find whether a line was carried: the
base render's first, then the one merged into it.)
"""

import argparse
import json
from collections import Counter
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

CACHE = Path(__file__).resolve().parents[2] / 'build/daf/cache'


def lines_of(placed):
    out = []
    for i, w in enumerate(placed):
        if out and placed[out[-1][-1]][0] == w[0] and abs(placed[out[-1][-1]][5] - w[5]) < 0.3 * w[7]:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def carried(ws, maps):
    """The line of the render a placed line is, if it is a comment carried
    from the amud before or after, matched to its text (else None)."""
    b = sum(w[5] for w in ws) / len(ws)
    x0, x1 = min(w[4] for w in ws), max(w[4] for w in ws)
    for L in maps:
        for l in L:
            s = l.get('stream') or ''
            if (('_prev' in s or '_next' in s) and (l.get('score') or 0) >= 50 and abs(l['base'] - b) < 0.5 * l['h']
                    and l['x0'] - 5 <= x0 and x1 <= l['x1'] + 5):
                return l
    return None


def norm(w):
    import re
    return re.sub(r'[^\u05D0-\u05EA\'"]', '', w)


def _ends(w, fonts):
    import svg
    return w[4], w[4] + fonts.width(svg.RASHI if w[2] else svg.SQUARE, 1, w[3]) * w[6]


def off_column(ix, placed, fonts):
    """The words of a line that lie off its column: a run of them set off
    from the rest of the line by a gap a gutter's width (a row the reading
    ran on from the Gemara into Rashi beside it, drawn all as one: Taanit
    8b), beyond the words tied to its text on its line and the lines around
    it. (Not a row wider than the rows under it, as Rashi's first rows are,
    read on without such a gap: Menachot 37a.)"""
    c = placed[ix[0]][0]
    h = max(placed[i][7] for i in ix)
    ends = {i: _ends(placed[i], fonts) for i in ix}
    runs, run = [], []
    for i in sorted(ix, key=lambda i: ends[i][0]):
        if run and ends[i][0] - max(ends[j][1] for j in run) > 1.0 * h:
            runs.append(run)
            run = []
        run.append(i)
    runs.append(run)
    if len(runs) < 2:
        return set()
    w = placed[ix[0]]
    near = [_ends(v, fonts) for v in placed if v[0] == c and v[1] >= 0 and abs(v[5] - w[5]) < 3 * h]
    if not near:
        return set()
    lo, hi = min(e[0] for e in near) - 0.5 * h, max(e[1] for e in near) + 0.5 * h
    out = set()
    for r in runs:
        a, b = min(ends[i][0] for i in r), max(ends[i][1] for i in r)
        if (a + b) / 2 < lo or (a + b) / 2 > hi or all(placed[i][1] < 0 for i in r) and (a < lo or b > hi):
            out.update(i for i in r if placed[i][1] < 0)
    return out


def strict(place, verdicts, maps, extra=None, fonts=None, streams=None):
    placed = place['placed']
    drop, why = set(), Counter()
    # Words of no column under the running head (a comment's opening words
    # set big, a chapter's end line): kept where the reader read them alike,
    # or where the word is one of the amud's texts' own, letter for letter.
    top = min((w[5] for w in placed), default=0)
    known = {norm(x) for ws in (streams or {}).values() for x in ws}
    for i, w in enumerate(placed):
        if w[0] == '' and w[1] < 0 and w[5] >= top + 40:
            if verdicts.get(str(i)) == 'same':
                why[('-', 'free_kept')] += 1
            elif norm(w[3]) in known:
                why[('-', 'free_text')] += 1
            else:
                drop.add(i)
                why[('-', 'free_unread')] += 1
    for ix in lines_of(placed):
        c = placed[ix[0]][0]
        if c not in ('m', 'i', 'o'):
            continue
        loose = [i for i in ix if placed[i][1] < 0]
        if not loose:
            continue
        mixed = len(loose) < len(ix)
        src = None if mixed else carried([placed[i] for i in ix], maps)
        if not mixed and src is None:
            drop.update(loose)
            why[(c, 'line_untied')] += len(loose)
            continue
        kind = 'mixed' if mixed else 'carried'
        # (A carried line is drawn with the neighbour's words, but for one
        # the reading put in where they differ.)
        theirs = set()
        if src is not None and extra and src.get('range'):
            a, b = src['range']
            theirs = {norm(w) for w in (extra.get(src['stream']) or [])[a:b]}
        off = off_column(ix, placed, fonts) if fonts is not None else set()
        for i in loose:
            if i in off:
                drop.add(i)
                why[(c, f'{kind}_off_column')] += 1
            elif norm(placed[i][3]) in theirs:
                why[(c, 'carried_text')] += 1
            elif verdicts.get(str(i)) == 'same':
                why[(c, f'{kind}_kept')] += 1
            else:
                drop.add(i)
                why[(c, f'{kind}_unread')] += 1
    return dict(place, placed=[w for i, w in enumerate(placed) if i not in drop]), why


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('place', type=Path)
    p.add_argument('verify', type=Path)
    p.add_argument('out', type=Path)
    p.add_argument('--lines', type=Path, nargs='+', required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    import svg
    fonts = svg.Fonts()
    tot = Counter()
    for f in sorted(a.place.glob('*.json')):
        place = json.loads(f.read_text())
        vf = a.verify / f.name
        verdicts = json.loads(vf.read_text()) if vf.exists() else {}
        maps = [json.loads((d / f.name).read_text()) for d in a.lines if (d / f.name).exists()]
        book, amud = f.stem.rsplit('_', 1)
        try:
            streams, extra = linemap.texts(CACHE, book.replace('_', ' '), amud)
        except SystemExit:
            streams, extra = {}, {}
        out, why = strict(place, verdicts, maps, extra, fonts, streams)
        tot.update(why)
        (a.out / f.name).write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')))
    for k, v in sorted(tot.items()):
        print(*k, v)


if __name__ == '__main__':
    main()
