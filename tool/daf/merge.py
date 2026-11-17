#!/usr/bin/env python3
"""One amud's placed words from two renders of the same scan, made with two
OCR models: the base render's words, and each line of the other's where the
base drew nothing. The Vilna model reads most of a page better; stock `heb`
reads some columns the Vilna one loses (Nedarim's Tosafot in its narrow
side column, a misread that ends the body at a false heading). A line comes
over only onto blank page: no word of the base's is where it is.

    merge.py BASE_DIR OTHER_DIR OUT_DIR   (directories of place/*.json)

A word the base already draws elsewhere comes over unlinked (-1), as read.
"""

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

COLS = ('m', 'i', 'o')


def _boxes(placed, fonts):
    import svg
    out = []
    for w in placed:
        c, k, font, word, left, base, sx, sy = w[:8]
        x1 = left + fonts.width(svg.RASHI if font else svg.SQUARE, 1, word) * sx
        out.append((left, base - 0.8 * sy, x1, base + 0.2 * sy))
    return out


def _lines(placed):
    """The entries of a render as its lines: runs of one column on one
    baseline, in its order."""
    out = []
    for i, w in enumerate(placed):
        if out and placed[out[-1][-1]][0] == w[0] and abs(placed[out[-1][-1]][5] - w[5]) < 0.3 * w[7]:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def _on_matched(w, lines):
    """Is a base word on a line its render matched to a text (score 50 or
    more: its own, or a comment carried over the page break)?"""
    x, base = w[4], w[5]
    for l in lines:
        if (l.get('range') and (l.get('score') or 0) >= 50 and abs(l['base'] - base) < 0.6 * l['h']
                and l['x0'] - 2 <= x <= l['x1'] + 2):
            return True
    return False


def merge(a, b, fonts, a_lines=None):
    """a, b: two place dicts of one amud. The merged dict and the words it
    gained, per column. With the base's lines (its render's lines/), a line
    of b's also replaces base words that are all unlinked and on no line the
    base matched (a line it drew as the scan reads it: Beitzah 40b's
    Gemara, matched by stock heb and not by the Vilna model)."""
    pa, pb = a['placed'], b['placed']
    ba, bb = _boxes(pa, fonts), _boxes(pb, fonts)
    have = {c: {w[1] for w in pa if w[0] == c and w[1] >= 0} for c in COLS}
    gained = Counter()
    add = []
    gone = set()
    replace = gone
    for line in _lines(pb):
        c = pb[line[0]][0]
        if c not in COLS:
            continue
        x0 = min(bb[i][0] for i in line)
        y0 = min(bb[i][1] for i in line)
        x1 = max(bb[i][2] for i in line)
        y1 = max(bb[i][3] for i in line)
        hits = [j for j, (u0, v0, u1, v1) in enumerate(ba)
                if j not in gone and min(x1, u1) - max(x0, u0) > 2 and min(y1, v1) - max(y0, v0) > 0.3 * (y1 - y0)]
        ks = [pb[i][1] for i in line if pb[i][1] >= 0]
        if hits:
            if a_lines is None or len(ks) < 0.6 * len(line):
                continue
            # (Words the base drew linked under it are given up only to a
            # line that has them all, in its own column: the base's piece of
            # a row it read in pieces (Bava Metzia 24b's Tosafot).)
            linked = [j for j in hits if pa[j][1] >= 0]
            if any(pa[j][0] != c or pa[j][1] not in ks for j in linked):
                continue
            took = {pa[j][1] for j in linked}
            if linked and len([k for k in ks if k not in took and k not in have[c]]) < max(3, len(took)):
                continue
            if any(pa[j][1] < 0 and _on_matched(pa[j], a_lines) for j in hits) and not linked:
                continue
            replace.update(hits)
            for j in linked:
                have[c].discard(pa[j][1])
        new = [k for k in ks if k not in have[c]]
        # (Most of its words drawn already: the base has them elsewhere,
        # and one of the two is wrong.)
        if ks and len(new) < 0.5 * len(ks):
            continue
        words = []
        for i in line:
            w = list(pb[i])
            if w[1] >= 0 and w[1] in have[c]:
                w[1] = -1
            elif w[1] >= 0:
                have[c].add(w[1])
                gained[c] += 1
            words.append(w)
        add.append((c, min(new) if new else None, words))
    placed = [w for j, w in enumerate(pa) if j not in gone]
    for c, k, words in add:
        # After the base's word of its column just before it in the text,
        # or, unlinked, the base's last word of its column above it.
        at = None
        for j, w in enumerate(placed):
            if w[0] != c:
                continue
            if k is not None and 0 <= w[1] < k:
                at = j
            elif k is None and w[5] < words[0][5]:
                at = j
        at = len(placed) if at is None else at + 1
        placed[at:at] = words
    out = dict(a, placed=placed)
    if add:
        # (The ink's extent as svg.placement measures it.)
        bx = _boxes(placed, fonts)
        out['frame'] = [round(min(x[0] for x in bx)), round(min(w[5] - 1.1 * w[7] for w in placed)),
                        round(max(x[2] for x in bx)), round(max(w[5] + 0.35 * w[7] for w in placed))]
    return out, gained


def main():
    import svg
    A, B, O = (Path(p) for p in sys.argv[1:4])
    O.mkdir(parents=True, exist_ok=True)
    fonts = svg.Fonts()
    tot = Counter()
    pages = []
    for f in sorted(A.glob('*.json')):
        a = json.loads(f.read_text())
        g = B / f.name
        if g.exists():
            b = json.loads(g.read_text())
            if b.get('words') == a.get('words'):
                lp = A.parent / 'lines' / f.name
                a, gained = merge(a, b, fonts, json.loads(lp.read_text()) if lp.exists() else None)
                tot.update(gained)
                if sum(gained.values()):
                    pages.append((sum(gained.values()), f.stem, dict(gained)))
        (O / f.name).write_text(json.dumps(a, ensure_ascii=False, separators=(',', ':')))
    pages.sort(reverse=True)
    print('gained', dict(tot), 'on', len(pages), 'amudim')
    for p in pages[:30]:
        print(*p)


if __name__ == '__main__':
    main()
