"""The page body's printed lines from the scan's ink, not from Tesseract's
page layout (which runs two of Rashi's dense lines into one, or cuts one
into pieces it then files under different texts).

1. Gutters: the white strips between the page's columns run straight down
   the page, so they are found as x ranges that stay free of ink, between
   text, over a stretch of it.
2. Down the page, each gutter is there or not (the Gemara widens over it
   where a commentary ends); a note set in a gutter breaks it only briefly.
3. Between the gutters there at each height: regions, each one column of
   one text.
4. In a region, the rows of ink cut into lines where they thin out,
   taken along the region's slope (the scans are a little askew).

Each line is then read on its own, straightened, with the model for its
script, and placed in its text by its own anchors (linemap's). What the
first pass found most of a region's letters to be says whether it is the
Gemara or a margin; a column with a margin's heading, one outside the
Gemara's band, and two lines claiming one stretch of a text (a commentary
quoting the Gemara) are sorted out on the way. linemap.amud_map calls
reline().
"""

import json
import os
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

import linemap
from lineread import words as read_words

INK = 128
SQUARE = os.environ.get('OCR_SQUARE', 'heb_vilna_square')
RASHI = os.environ.get('OCR_RASHI', 'heb_vilna_rashi')


def _runs(on):
    """[start, end) of each run of True."""
    on = np.r_[False, np.asarray(on, bool), False]
    d = np.flatnonzero(np.diff(on.astype(np.int8)))
    return list(zip(d[::2], d[1::2]))


def _free(ink, y0, y1):
    """Per x, whether rows y0..y1 have no ink there, with ink on both
    sides near it (a gutter, not the space around the page)."""
    W = ink.shape[1]
    col = ink[y0:y1].any(0)
    cs = np.cumsum(np.r_[0, col])
    x = np.arange(W)
    left = cs[x] - cs[np.clip(x - 60, 0, W)]
    right = cs[np.clip(x + 61, 0, W)] - cs[np.clip(x + 1, 0, W)]
    return (~col) & (left > 25) & (right > 25), col.sum()


def gutters(ink, top, bottom):
    """The page's gutters as (x0, x1, cut): strips free of ink across most
    of some stretch of the body (a few lines' bands, in windows of the
    page), and where between its columns to cut."""
    W = ink.shape[1]
    B, S, WIN = 75, 5, 300
    bands = []
    for y in range(int(top), max(int(top) + 1, int(bottom) - B), S):
        f, n = _free(ink, y, y + B)
        if n >= 200:
            bands.append((y, f))
    score = np.zeros(W)
    # Over a long stretch, most of it free; over a short one (the top
    # band's halves), nearly all.
    for win, share in ((WIN, 0.6), (100, 0.95)):
        n = win // S
        for k in range(0, len(bands), max(1, n // 2)):
            part = [f for y, f in bands[k:k + n]]
            if len(part) >= n // 2:
                score = np.maximum(score, np.mean(part, axis=0) / share)
    runs = [(a, b) for a, b in _runs(score >= 1) if b - a >= 3]
    groups = []
    for a, b in runs:
        if groups and a - groups[-1][-1][1] < 30:
            groups[-1].append((a, b))  # a strip broken by a note set in it
        else:
            groups.append([(a, b)])
    out = []
    for g in groups:
        a, b = g[0][0], g[-1][1]
        if b - a < 8:
            continue
        # The cut: in the strip that is the gutter most of the way down
        # (what joined it can be the white of a column's short lines).
        best = max(g, key=lambda r: (round(float(score[r[0]:r[1]].mean()), 1), r[1] - r[0]))
        out.append((int(a), int(b), int((best[0] + best[1]) // 2)))
    return out


def _joined(lines, g, index):
    """Rows (top, bottom) where a line of the first pass runs on across
    gutter g: one text from its right to its left, the left piece starting
    where the right one ends in it. There it is a river of word spaces, not
    a gutter. A line Tesseract ran across the gutter is cut there and each
    side placed in its text by its own anchors."""
    a, b = g[:2]
    mid = (a + b) / 2
    pieces = []
    for l in lines:
        if not l.get('stream'):
            continue
        if l['x0'] < a - 4 and l['x1'] > b + 4:
            for side in ([w for w in l['words'] if w['x0'] >= mid], [w for w in l['words'] if w['x1'] <= mid]):
                if side:
                    p = linemap._line(side)
                    p['letters'] = len(linemap._flat(p['text'], linemap.FOLD_RASHI))
                    c = linemap._anchor(p, index)
                    if c:
                        k = max(c, key=lambda k: c[k][1])
                        p['stream'], (p['pos'], p['hits']) = k, c[k]
                        pieces.append(p)
        elif l.get('pos') is not None and l.get('hits', 0) >= 2:
            # (Placed by its own anchors: a place taken from the line beside
            # it would prove itself.)
            pieces.append(l)
    out = []
    for r in pieces:
        if not (a - 10 <= r['x0'] <= b + 60):
            continue
        for l in pieces:
            if (l is not r and l['stream'] == r['stream'] and a - 60 <= l['x1'] <= b + 10 and l['x1'] < r['x0'] + 5
                    and abs(l['base'] - r['base']) < 0.5 * max(l['h'], r['h'])
                    and abs(l['pos'] - (r['pos'] + r['letters'])) <= max(8, 0.3 * min(l['letters'], r['letters']))):
                out.append((min(l['y0'], r['y0']), max(l['y1'], r['y1'])))
    return out


def presence(ink, g, top, bottom, step=2, tall=70, line=12, lines=(), index=None):
    """Per row from top to bottom (every `step`), whether gutter g is there:
    an x of it free of ink over the line on that row and the two above it,
    or the two below it (word spaces don't line up over three lines; a
    column's last line has its gutter above it), with text on both sides.
    Unknown rows (no text beside the gutter) and short breaks (a note set
    in it) take their surroundings' value."""
    a, b = g[:2]
    ys = list(range(int(top), int(bottom), step))
    joined = _joined(lines, g, index) if index else []
    val = []
    veto = np.array([any(j0 + 2 <= y <= j1 - 2 for j0, j1 in joined) for y in ys], bool)
    for y, no in zip(ys, veto):
        if no:
            val.append(False)
            continue
        v = None
        for y0, y1 in ((y - tall, y + line), (y - line, y + tall)):
            y0 = max(0, y0)
            left = ink[y0:y1, max(0, a - 150):a].any(0).sum()
            right = ink[y0:y1, b:b + 150].any(0).sum()
            if left < 8 or right < 8:
                continue
            free = _runs(~ink[y0:y1, a:b].any(0))
            v = bool(v) or max((e - s for s, e in free), default=0) >= 6
        val.append(v)
    v = np.array([np.nan if x is None else float(x) for x in val])
    # Unknowns: the value on either side, if they agree; else absent.
    known = np.flatnonzero(~np.isnan(v))
    if not len(known):
        return ys, np.zeros(len(ys), bool)
    for s, e in _runs(np.isnan(v)):
        before = v[s - 1] if s > 0 else v[e] if e < len(v) else 0
        after = v[e] if e < len(v) else before
        v[s:e] = before if before == after else 0
    on = v > 0.5
    # The widest strip free of ink on each row's line (unknown between
    # lines).
    width = np.zeros(len(ys))
    for i, y in enumerate(ys):
        rows = ink[max(0, y - 8):y + 8, a:b]
        beside = ink[max(0, y - 8):y + 8, max(0, a - 150):b + 150].any()
        width[i] = max((e - s for s, e in _runs(~rows.any(0))), default=0) if beside else np.nan
    # Short breaks in a present gutter: notes set in it (a line or several).
    # Longer ones too where the lines either side of it are out of step
    # (Rashi's pitch beside the Gemara's): one line running across would
    # have its ink on the same rows both sides.
    gap = 130 // step
    for s, e in _runs(~on):
        if s > 0 and e < len(on) and (e - s < gap or e - s < 400 // step and _out_of_step(ink, a, b, ys[s], ys[e - 1] + step)):
            on[s:e] = True
    on &= ~veto  # a line runs across: never bridged over
    # A gutter is wider than a word space: where a commentary's column ends
    # and the Gemara widens over it, its first wide line can have a space
    # just there. A stretch of gutter ends where it narrows to that.
    for s, e in _runs(on):
        w = width[s:e]
        if np.all(np.isnan(w)):
            continue
        typ = float(np.nanmedian(w))
        lo, hi = s, e
        while lo < hi and (np.isnan(width[lo]) or width[lo] < 0.6 * typ):
            lo += 1
        while hi > lo and (np.isnan(width[hi - 1]) or width[hi - 1] < 0.6 * typ):
            hi -= 1
        on[s:lo] = False
        on[hi:e] = False
    # Short presences: a column of chance gaps.
    for s, e in _runs(on):
        if e - s < 40 // step:
            on[s:e] = False
    return ys, on


def _out_of_step(ink, a, b, y0, y1):
    """Whether the rows of ink left of a gutter (x a) and right of it (x b)
    between y0 and y1 are two columns' lines, not one's."""
    left = ink[y0:y1, max(0, a - 150):a].sum(1).astype(float)
    right = ink[y0:y1, b:b + 150].sum(1).astype(float)
    if len(left) < 30 or left.std() == 0 or right.std() == 0:
        return False
    return float(np.corrcoef(left, right)[0, 1]) < 0.3


def regions(grey, top, bottom, x0, x1, lines=(), index=None):
    """The body cut into regions [x0, y0, x1, y1] between the gutters that
    are there at each height; `lines` are the first pass's, classified."""
    ink = grey < INK
    gs = gutters(ink, top, bottom)
    gs = [g for g in gs if x0 - 40 <= g[2] <= x1 + 40]
    pres = [presence(ink, g, top, bottom, lines=lines, index=index) for g in gs]
    ys = pres[0][0] if pres else list(range(int(top), int(bottom), 2))
    out, cur = [], {}
    for k, y in enumerate(ys):
        on = sorted((gs[i][2], gs[i][1] - gs[i][0]) for i in range(len(gs)) if pres[i][1][k])
        # No column is narrower than 100 (a river of word spaces down a
        # column's first words): of two cuts that close, the narrower
        # gutter goes.
        changed = True
        while changed:
            changed = False
            edges = [(int(x0) - 1, 1e9)] + on + [(int(x1) + 1, 1e9)]
            for (a, wa), (b, wb) in zip(edges, edges[1:]):
                if b - a < 100 and min(wa, wb) < 1e9:
                    on.remove((a, wa) if wa < wb else (b, wb))
                    changed = True
                    break
        cuts = sorted({int(x0) - 1, int(x1) + 1} | {c for c, _ in on})
        spans = {(cuts[i], cuts[i + 1]) for i in range(len(cuts) - 1)}
        for s in list(cur):
            if s not in spans:
                out.append([s[0], cur.pop(s), s[1], y])
        for s in spans:
            cur.setdefault(s, y)
    for s, y in cur.items():
        out.append([s[0], y, s[1], int(bottom)])
    out = [r for r in out if r[3] - r[1] >= 10 and r[2] - r[0] >= 30]
    # The top band's halves (and those under the Gemara where it ends
    # first) are too few lines for the gutter between them to be found
    # above: a wide region with a strip free of ink all the way down near
    # its middle is two, unless a line of one text runs on across it.
    split = []
    for r in out:
        if r[2] - r[0] < 0.6 * (x1 - x0):
            split.append(r)
            continue
        m0, m1 = int(r[0] + (r[2] - r[0]) / 3), int(r[2] - (r[2] - r[0]) / 3)
        col = ink[r[1]:r[3], m0:m1].any(0)
        free = [(m0 + a, m0 + b) for a, b in _runs(~col) if b - a >= 8]
        if not free:
            # A narrower one (notes set close to it) where the lines either
            # side are two commentaries.
            free = [(m0 + a, m0 + b) for a, b in _runs(~col) if b - a >= 4 and _two_texts(lines, r, m0 + a, m0 + b)]
        if free and r[3] - r[1] >= 20:
            a, b = max(free, key=lambda f: f[1] - f[0])
            g = (a - 2, b + 2, (a + b) // 2)
            if not any(j0 < r[3] and j1 > r[1] for j0, j1 in (_joined(lines, g, index) if index else [])):
                gs.append(g)
                split += [[r[0], r[1], g[2], r[3]], [g[2], r[1], r[2], r[3]]]
                continue
        split.append(r)
    return gs, split


def _two_texts(lines, r, a, b):
    """Whether the first pass's anchored lines in region r left of x a are
    mostly one margin's text and those right of x b another's."""
    def main_text(side):
        n = {}
        for l in lines:
            if l.get('stream') in ('inner', 'outer') and l.get('hits') and r[1] <= l['base'] <= r[3] + 5 and side(l):
                n[l['stream']] = n.get(l['stream'], 0) + l['letters']
        best = max(n, key=n.get) if n else None
        return best if best and n[best] >= 30 and n[best] >= 0.8 * sum(n.values()) else None
    left = main_text(lambda l: r[0] - 5 <= l['x0'] and l['x1'] <= a + 3)
    right = main_text(lambda l: b - 3 <= l['x0'] and l['x1'] <= r[2] + 5)
    return left is not None and right is not None and left != right


def _sheared(a, k):
    """Ink rows taken along lines of slope k (dy/dx) through the middle
    column: row y of the result is the row through (middle, y)."""
    H, W = a.shape
    sh = np.round(k * (np.arange(W) - W / 2)).astype(int)
    ys = np.arange(H)[:, None] + sh[None, :]
    ok = (ys >= 0) & (ys < H)
    return a[ys.clip(0, H - 1), np.arange(W)[None, :]] & ok


def _slope(a):
    """The slope of a stretch of lines (the scan is a little askew, more so
    toward the foot of the page): how far the left half's rows of ink are
    from the right half's, over the distance between them."""
    H, W = a.shape
    if W < 200:
        return 0.0
    pl, pr = a[:, :W // 2].sum(1).astype(float), a[:, W // 2:].sum(1).astype(float)
    pl, pr = pl - pl.mean(), pr - pr.mean()
    best, d0 = None, 0
    for d in range(-20, 21):
        if d >= 0:
            c = float((pr[:H - d] * pl[d:]).sum())
        else:
            c = float((pr[-d:] * pl[:H + d]).sum())
        if best is None or c > best:
            best, d0 = c, d
    return -d0 / (W / 2)


def _extent(cols, zones):
    """The first and last x of a line's ink, leaving out what stands apart
    from the rest inside a gutter (a note set there)."""
    if not len(cols):
        return None
    parts, start = [], cols[0]
    for p, q in zip(cols, cols[1:]):
        if q - p > 5:
            parts.append((start, p + 1))
            start = q
    parts.append((start, cols[-1] + 1))
    keep = [(a, b) for a, b in parts if not any(z0 - 2 <= a and b <= z1 + 2 for z0, z1 in zones)]
    keep = keep or parts
    return keep[0][0], keep[-1][1]


def lines_in(grey, r, pad=16, chunk=240, zones=()):
    """A region's printed lines: dicts of x0, x1 and the top and bottom of
    the line's letters (their bodies: no ascenders or descenders) where it
    crosses the middle x xc, with its slope k. Lines are where the rows of
    ink, taken along the slope, run thick. Rows a little past the region's
    top and bottom are looked at too, so a line its edge cuts is whole; it
    is the region's if its middle is."""
    rx0, ry0, rx1, ry1 = r
    xc = (rx0 + rx1) / 2
    out = []
    for c0 in range(ry0, ry1, chunk):
        c1 = min(ry1, c0 + chunk)
        if ry1 - c1 < chunk // 3:
            c1 = ry1  # no thin last chunk
        y0 = max(0, c0 - pad)
        a = grey[y0:c1 + pad, rx0:rx1] < INK
        if not a.size:
            continue
        k = _slope(a)
        a = _sheared(a, k)
        p = a.sum(1).astype(float)
        if p.max() == 0:
            continue
        t = 0.12 * np.percentile(p[p > 0], 90)
        runs = _runs(p > t)
        # A line of a word or two (a catchword, a paragraph's last word)
        # has less ink than that: where nothing else is, a lower bar.
        # (Its ink can top the bar in a row or two: those are no line.)
        runs, low = [(s, e) for s, e in runs if e - s >= 4], set()
        taken = np.zeros(len(p), bool)
        for s, e in runs:
            taken[max(0, s - 3):e + 3] = True
        for s, e in _runs((p > 0.3 * t) & ~taken):
            # (Its letters' whole height: so little ink runs thin at the top.)
            while s > 0 and p[s - 1] > 0.1 * t and not taken[s - 1]:
                s -= 1
            while e < len(p) and p[e] > 0.1 * t and not taken[e]:
                e += 1
            if e - s >= 8:
                low.add((s, e))
        for s, e in sorted(runs + list(low)):
            if e - s < 4 or not c0 <= y0 + (s + e) / 2 < c1:
                continue
            ext = _extent(np.flatnonzero(a[s:e].any(0)) + rx0, zones)
            out.append(dict(x0=int(ext[0]), x1=int(ext[1]), top=y0 + int(s), bottom=y0 + int(e), xc=xc, k=k, low=(s, e) in low))
        if c1 == ry1:
            break
    return out


# ------------------------------------------------------------------ reline

def crop(im, l, k3=3, ch=None):
    """A line's image, straightened along its slope, grey at k3×: its
    letters with room above and below for what rises and hangs, and the
    page x its left edge is at. `ch` is the height of its column's letters
    (a big opening word makes a line's own taller)."""
    ch = ch or l['bottom'] - l['top']
    l = dict(l, top=l['bottom'] - ch)
    left = l['x0'] - 5
    # Not into the letters of the lines above and below.
    top = max(l['top'] - 0.75 * ch, l.get('above', -1e9) + 2)
    bottom = min(l['bottom'] + 0.55 * ch, l.get('below', 1e9) - 2)
    if bottom - top < 0.8 * ch:
        # (Lines found close together: its letters, at least.)
        top, bottom = min(top, l['top'] - 1), max(bottom, l['bottom'] + 1)
    w, hgt = l['x1'] + 5 - left, int(round(bottom - top))
    k = l['k']
    out = im.convert('L').transform((int(w), hgt), Image.AFFINE, (1, 0, left, k, 1, top + k * (left - l['xc'])),
                                    resample=Image.BILINEAR, fillcolor=255)
    return out.resize((max(1, round(out.width * k3)), max(1, round(out.height * k3))), Image.LANCZOS), left


def _free_strip(grey, g, y0, y1):
    """The part of gutter g free of ink over rows y0..y1 (but for 2% of
    them) around its cut, and a note between two such strips."""
    a = grey[int(y0):int(y1), g[0]:g[1]] < INK
    if not a.size:
        return None
    free = [(g[0] + s, g[0] + e) for s, e in _runs(a.mean(0) <= 0.02) if e - s >= 3]
    if not free:
        return None
    k = min(range(len(free)), key=lambda i: 0 if free[i][0] <= g[2] < free[i][1] else min(abs(free[i][0] - g[2]), abs(free[i][1] - g[2])))
    lo = hi = k
    while lo > 0 and free[lo][0] - free[lo - 1][1] < 20:
        lo -= 1
    while hi + 1 < len(free) and free[hi + 1][0] - free[hi][1] < 20:
        hi += 1
    return free[lo][0], free[hi][1]


def _kind_of(stream):
    if stream == 'main':
        return 'main'
    return 'margin' if stream in linemap.BODY else 'other'


def _region_kind(r, lines):
    """What the first pass found in a region: the text most of its letters
    are, by kind (the Gemara, a margin, or neither)."""
    votes = {'main': 0, 'margin': 0, 'other': 0}
    for l in lines:
        cx, cy = (l['x0'] + l['x1']) / 2, l['base'] - 0.4 * l['h']
        # (Not a line none of the texts were found in, nor one put aside as
        # none of them: on a poor first reading, most of a region's can be.)
        if r[0] <= cx < r[2] and r[1] <= cy < r[3] and (l.get('stream') not in (None, 'other') or l.get('hits', 0) >= 3):
            votes[_kind_of(l.get('stream'))] += l.get('letters', 0) * (2 if l.get('hits', 0) >= 3 else 1)
    return max(votes, key=votes.get), votes


def _dedupe(lines):
    """One line read twice (two regions that overlap) is one: the reading
    with more letters."""
    seg = sorted([l for l in lines if l.get('seg')], key=lambda l: -l.get('letters', 0))
    gone = set()
    for i, l in enumerate(seg):
        for m in seg[i + 1:]:
            if id(m) not in gone and id(l) not in gone and abs(l['base'] - m['base']) < 0.3 * l['h'] \
                    and min(l['x1'], m['x1']) - max(l['x0'], m['x0']) > 0.8 * min(l['x1'] - l['x0'], m['x1'] - m['x0']):
                gone.add(id(m))
    # Nor a first-pass piece of a line read again whole (a region's edge
    # left it beside its own line).
    for m in lines:
        if m.get('seg') or m.get('stream') not in linemap.BODY:
            continue
        for l in seg:
            if id(l) not in gone and abs(l['base'] - m['base']) < 0.3 * l['h'] \
                    and min(l['x1'], m['x1']) - max(l['x0'], m['x0']) > 0.8 * (m['x1'] - m['x0']):
                gone.add(id(m))
                break
    return [l for l in lines if id(l) not in gone]


def reline(lines, im, streams, extra, frame, cache_path):
    """The body's lines again, from segment's regions (see above): the first
    pass's lines in each region of the Gemara or a margin are replaced by
    the region's own, read again. Returns the new list of lines."""
    # Everything here is measured for a scan 1100 to 1600 wide, as most are:
    # a few are 4100, looked at at 1530 and their lines scaled back.
    f = 1530 / im.width
    if f > 0.75:
        f = 1.0
    if f != 1.0:
        lines = [_scaled(l, f) for l in lines]
        frame = [v * f for v in frame]
        small = im.convert('L').resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
    else:
        small = im
    out = _dedupe(_reline(lines, small, im, f, streams, extra, frame, cache_path))
    if f == 1.0:
        return out
    back = []
    for l in out:
        if l.get('seg'):
            b = _scaled(l, 1 / f)
            b.pop('_orig')
            b['ink'] = (l['ink'][0] / f, l['ink'][1] / f)
        else:
            b = l['_orig']
            b.update(stream=l.get('stream'), pos=l.get('pos'), hits=l.get('hits', 0))
        back.append(b)
    return back


def _scaled(l, f):
    """A line of the first pass at f× its size, its words too."""
    m = dict(l)
    for k in ('x0', 'x1', 'y0', 'y1', 'base', 'h'):
        if k in m:
            m[k] = l[k] * f
    m['words'] = [dict(w, x0=w['x0'] * f, x1=w['x1'] * f, y0=w['y0'] * f, y1=w['y1'] * f) for w in l['words']]
    if m.get('gutters') is not None:
        g = np.asarray(l['gutters'])
        m['gutters'] = g[np.clip((np.arange(int(len(g) * f) + 1) / f).astype(int), 0, len(g) - 1)]
    m['_orig'] = l
    return m


def _reline(lines, im, full, f, streams, extra, frame, cache_path):
    """reline on `im`, the page at f× (`full` is the scan itself, to read
    the lines from)."""
    grey = np.asarray(im.convert('L'))
    fx0, top, fx1, bottom = frame
    # The body ends at a heading under the Gemara across the middle of the
    # page (רבינו גרשום, הגהות הב"ח: the foot's own commentaries). The
    # Gemara ends with its longest run of lines: a commentary at the foot
    # quotes it too.
    ends = sorted(l['y1'] for l in lines if l.get('stream') == 'main' and l.get('hits', 0) >= 3)
    runs = []
    for y in ends:
        if runs and y - runs[-1][-1] <= 100:
            runs[-1].append(y)
        else:
            runs.append([y])
    gem_end = max(runs, key=len)[-1] if runs else bottom
    mid = (fx0 + fx1) / 2
    heads = []
    below = sorted([l for l in lines if l['y0'] > gem_end - 5], key=lambda l: -l['x1'])
    for l in below:
        # (A heading's words can stand apart, read as pieces.)
        row = [m for m in below if abs(m['base'] - l['base']) < 0.5 * l['h'] and m['x1'] <= l['x1'] and l['x0'] - m['x1'] < 4 * l['h']][:3]
        for n in range(1, len(row) + 1):
            part = row[:n]
            x0, x1 = min(m['x0'] for m in part), max(m['x1'] for m in part)
            if not linemap._heading(' '.join(m['text'] for m in part)):
                continue
            # Centred over its section, or leading a line of the foot from
            # the right edge (הגהות הב"ח).
            # (Inside the frame, its own line running on across the page;
            # one in a side column is outside it, beside the body's lines.)
            run_x0 = x0
            for m in sorted([m for m in below if abs(m['base'] - l['base']) < 0.8 * max(m['h'], l['h'])], key=lambda m: -m['x1']):
                if m['x1'] <= run_x0 + 2 and run_x0 - m['x1'] < 4 * l['h']:
                    run_x0 = min(run_x0, m['x0'])
            foot = any(h in linemap.fold(' '.join(m['text'] for m in part), linemap.FOLD_SQUARE) for h in ('הגהות', 'גליון'))
            leads = foot and x0 < fx1 - 20 and x1 >= fx1 - 0.12 * (fx1 - fx0) and run_x0 < mid
            if abs((x0 + x1) / 2 - mid) < 0.3 * (fx1 - fx0) or leads:
                heads.append(min(m['y0'] for m in part))
    if heads:
        bottom = min(bottom, min(heads) - 2)
        for l in lines:
            if l['y0'] > bottom and l.get('stream') in linemap.BODY:
                l['stream'], l['pos'] = 'other', None
    index = linemap._index({**streams, **extra})
    gs, rs = regions(grey, top - 10, bottom + 10, fx0, fx1, lines, index)
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    jobs, plan = [], []
    # The Gemara's band across the page: a column beside it that quotes it
    # (Rabbeinu Chananel) is not it.
    gem = [l for l in lines if l.get('stream') == 'main' and l.get('hits', 0) >= max(3, 0.3 * l.get('letters', 0))]
    gx0 = float(np.percentile([l['x0'] for l in gem], 5)) if gem else fx0
    gx1 = float(np.percentile([l['x1'] for l in gem], 95)) if gem else fx1
    for l in lines:
        if l.get('stream') == 'main' and not gx0 - 10 <= (l['x0'] + l['x1']) / 2 <= gx1 + 10:
            l['stream'], l['pos'] = 'other', None
    # A narrow column with a margin's heading in it (רבינו חננאל, עין
    # משפט) is that commentary's, however much of the Gemara it quotes.
    heads = [l for l in lines if linemap._heading(l['text']) and 'הדרן' not in l['text']]
    side = []
    for r in rs:
        if r[2] - r[0] < 0.3 * (fx1 - fx0) and any(
                r[1] - 60 <= l['base'] <= r[3] and abs((l['x0'] + l['x1']) / 2 - (r[0] + r[2]) / 2) < 0.25 * (r[2] - r[0]) for l in heads):
            side.append(r)
            for l in lines:
                if l.get('stream') in linemap.BODY and r[0] <= (l['x0'] + l['x1']) / 2 < r[2] and r[1] <= l['base'] <= r[3]:
                    l['stream'], l['pos'] = 'other', None
    for r in rs:
        if r in side:
            continue
        kind, votes = _region_kind(r, lines)
        if kind == 'main' and not gx0 - 10 <= (r[0] + r[2]) / 2 <= gx1 + 10:
            votes['main'] = 0
            kind = max(votes, key=votes.get)
        if votes[kind] < 20:
            # Too few of the first pass's letters to tell (a stretch of a
            # column cut off by a river): the kind of the regions just above
            # and below it, where they agree.
            kind = _kind_around(r, rs, lines)
        if kind in (None, 'other'):
            continue
        # A note set in a gutter is in neither column beside it: what
        # stands apart inside the gutter, where it is free of ink beside
        # this region (the strip found over the whole page can be wider).
        zones = [_free_strip(grey, g, r[1], r[3]) for g in gs if g[0] - 1 <= r[0] <= g[1] + 1 or g[0] - 1 <= r[2] <= g[1] + 1]
        zones = [z for z in zones if z]
        segs = lines_in(grey, r, zones=zones)
        if not segs:
            continue
        hs = [s['bottom'] - s['top'] for s in segs]
        med = float(np.median(hs))
        for p_, s_, n_ in zip([None] + segs[:-1], segs, segs[1:] + [None]):
            if p_:
                s_['above'] = p_['bottom']
            if n_:
                s_['below'] = n_['top']
        plan.append((r, kind, segs, med))
    _run_on(plan, grey, fx0, fx1)
    # A sliver between two lines (in a small region, where its own lines'
    # median is no guide) is no line: under half the letter height of its
    # kind's lines over the page.
    page_med = {}
    for r, kind, segs, med in plan:
        page_med.setdefault(kind, []).extend(s['bottom'] - s['top'] for s in segs)
    page_med = {k: float(np.median(v)) for k, v in page_med.items()}
    for r, kind, segs, med in plan:
        # (Its lines' median without the slivers, which can be most of a
        # small region's; the page's if all are.)
        whole = [s['bottom'] - s['top'] for s in segs if s['bottom'] - s['top'] >= 0.5 * page_med[kind]]
        med = float(np.median(whole)) if whole else page_med[kind]
        for s in segs:
            if s['bottom'] - s['top'] < 0.5 * page_med[kind]:
                s['sliver'] = True
            elif 0.5 * med <= s['bottom'] - s['top'] <= 1.8 * med:
                s['med'] = med
                jobs.append((s, SQUARE if kind == 'main' else RASHI))

    def read(job):
        s, model = job
        key = f"{s['x0']},{s['top']},{s['x1']},{s['bottom']},{s['k']:.4f},{s['med']:.1f},{s.get('above')},{s.get('below')},{model}"
        if key not in cache:
            # (At the scan's own size, as the models read it.)
            big = {k: s[k] / f for k in ('x0', 'x1', 'top', 'bottom', 'xc')}
            big.update(k=s['k'], above=s['above'] / f if 'above' in s else -1e9, below=s['below'] / f if 'below' in s else 1e9)
            k3 = 3 * min(1.0, f) if f < 1 else 3
            img, left = crop(full, big, k3=k3, ch=s['med'] / f)
            cache[key] = [[t, round((left + a / k3) * f, 1), round((left + b / k3) * f, 1), c] for t, a, b, c in read_words(img, model)]
        s['read'] = cache[key]
    with ThreadPoolExecutor(os.cpu_count()) as ex:
        list(ex.map(read, jobs))
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, ensure_ascii=False))

    W = im.width
    out = list(lines)
    gid = -1
    pitches = [_pitch(segs) for r, kind, segs, med in plan if kind == 'main' and len(segs) >= 4]
    main_pitch = float(np.median([v for v in pitches if np.isfinite(v)] or [1e-9]))
    for r, kind, segs, med in plan:
        new, keep = [], []
        for s in segs:
            if s.get('sliver'):
                continue
            if 'read' not in s:
                # Too tall (a big opening word over lines) or a scrap: the
                # first pass's lines there stay.
                keep.append(s)
                continue
            ws = [w for w in s['read'] if w[0].strip()]
            if not ws:
                continue
            xm = (s['x0'] + s['x1']) / 2
            base = s['bottom'] + s['k'] * (xm - s['xc'])
            # (Its letters' height: the column's, where a big opening word
            # makes the line's own taller.)
            ch = min(s['bottom'] - s['top'], med)
            h = 1.3 * ch
            words = [dict(x0=a, x1=b, y0=base + s['k'] * ((a + b) / 2 - xm) - h, y1=base + s['k'] * ((a + b) / 2 - xm), text=t)
                     for t, a, b, _ in sorted(ws, key=lambda w: -w[2])]
            l = linemap._line(words)
            l.update(group=gid, col=0, gutters=np.zeros(W + 1, bool), raw=None, seg=True, k=s['k'], ink=(s['x0'], s['x1']), low=s['low'])
            gid -= 1
            l['letters'] = len(linemap._flat(l['text'], linemap.FOLD_RASHI))
            l['core'] = s['bottom'] - s['top']
            cands = linemap._anchor(l, index)
            mine = {c: v for c, v in cands.items() if _kind_of(c) == kind and (c in streams or c in extra)}
            if mine and max(v[1] for v in mine.values()) < 0.12 * l['letters'] and l['letters'] >= 40:
                # A long line with a few of a text's runs in it only quotes
                # it (the body's lines read right have a third or more).
                l['stream'], l['pos'], l['hits'], l['why'] = 'other', None, 0, 'quote'
                best = max(mine, key=lambda c: mine[c][1])
                l['quote'] = (best, *mine[best])
            elif mine:
                best = max(mine, key=lambda c: mine[c][1])
                l['stream'], (l['pos'], l['hits']) = best, mine[best]
            else:
                l['stream'], l['pos'], l['hits'] = None, None, 0
            l['cands'] = mine
            new.append(l)
        # The region's first-pass lines go, but for those beside a line it
        # left to them.
        def inside(l):
            cx, cy = (l['x0'] + l['x1']) / 2, l['base'] - 0.4 * l['h']
            if not (r[0] <= cx < r[2] and r[1] <= cy < r[3]):
                return False
            return not any(s['top'] - 0.6 * med <= cy <= s['bottom'] + 0.6 * med for s in keep)
        out = [l for l in out if l.get('seg') or not inside(l)]
        # Lines without anchors take their text from the lines around them
        # in the region, and a place just after the one above; but a long
        # one with none at all is text none of Sefaria's have.
        unknown = 15 if linemap.OCR_LANG != 'heb' else 40
        for l in new:
            if l['stream'] is None and l['letters'] >= unknown and sum(l['any'].values()) < 2:
                l['stream'], l['pos'], l['why'] = 'other', None, 'unknown'
        for _ in range(3):
            for i, l in enumerate(new):
                if l['stream'] is not None or l['core'] < 0.7 * med:
                    continue
                for j in (i - 1, i + 1):
                    if 0 <= j < len(new) and new[j]['stream'] not in (None, 'other') and new[j]['pos'] is not None:
                        m = new[j]
                        l['stream'] = m['stream']
                        l['pos'] = m['pos'] + m['letters'] if j < i else m['pos'] - l['letters']
                        break
        # But a line whose place runs on from the line above it or into the
        # one below is the text itself, its runs only common phrases.
        for l in new:
            if l.get('why') == 'quote' and _fits(l, *l['quote'][:2], new):
                l['stream'], l['pos'], l['hits'] = l['quote']
                del l['why']
        # Nor is one that fills the gap its length between the lines of a
        # text above and below it (its runs found somewhere else).
        for l in new:
            if l.get('why') in ('quote', 'unknown'):
                gap = _gap_for(l, new)
                if gap:
                    l['stream'], l['pos'] = gap
                    del l['why']
        if kind == 'main':
            # (Not the small type of notes under the Gemara's last line.)
            for l in new:
                if l['stream'] is None and l['letters'] >= 2 and l['core'] >= 0.7 * med:
                    l['stream'], l['pos'] = 'main', None
        if kind == 'main' and _pitch(segs) < 0.75 * main_pitch:
            # Lines closer than the Gemara's: a commentary in square
            # letters at the foot (the Rosh), quoting it. (Each line by
            # its own spacing: the Gemara's last lines can be in the
            # region too, above it.)
            for l in new:
                # (To the lines above and below it as wide as it.)
                over = [m['base'] for m in new if m is not l and min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.5 * (l['x1'] - l['x0'])]
                steps = [d for d in (min([l['base'] - b for b in over if b < l['base'] - 2], default=None),
                                     min([b - l['base'] for b in over if b > l['base'] + 2], default=None)) if d]
                # (Or in letters smaller than the Gemara's.)
                if l['stream'] == 'main' and (not steps or max(steps) < 0.75 * main_pitch or l['core'] < 0.8 * page_med['main']):
                    l['stream'], l['pos'], l['why'] = 'other', None, 'pitch'
        out += [l for l in new if l['stream'] is not None]
    # (Again over the whole page: the lines around one can be in other
    # regions, as a short line's and a heading's in the middle of a column.)
    for l in out:
        if l.get('seg') and l.get('why') in ('quote', 'unknown'):
            gap = _gap_for(l, out)
            if gap:
                l['stream'], l['pos'] = gap
                del l['why']
    # The Gemara's last word on a line of its own, centred under its last
    # full line, has no anchors and takes its kind from a margin's lines
    # beside it.
    for l in out:
        if l.get('hits') or l.get('stream') not in ('inner', 'outer') or not gx0 <= (l['x0'] + l['x1']) / 2 <= gx1:
            continue
        def above(m, stream):
            return (m is not l and m.get('stream') == stream and m.get('pos') is not None
                    and 0.5 * l['h'] < l['base'] - m['base'] < 2.2 * l['h'] and m['x0'] <= l['x0'] and l['x1'] <= m['x1'])
        over = [m for m in out if above(m, 'main')]
        if over and not any(above(m, l['stream']) for m in out):
            m = max(over, key=lambda m: m['base'])
            l['stream'], l['pos'] = 'main', m['pos'] + m['letters']
    _settle(out)
    return out


def _run_on(plan, grey, fx0, fx1):
    """A line whose words run on past its region's edge (a short line set
    in the middle of a column, where a river of spaces down the blank
    beside it passed for a gutter) is as long as its ink: on across gaps no
    wider than a word space, where no other line is at its height, and
    within its column (a region of its kind near it spans that far)."""
    segs = [s for _, _, ss, _ in plan for s in ss]
    kind_of = {id(s): k for _, k, ss, _ in plan for s in ss}
    for r, kind, ss, _ in plan:
        for s in ss:
            top, bottom = int(s['top']), int(s['bottom'])
            ch = bottom - top
            if ch < 6:
                continue
            cols = (grey[top:bottom, :] < INK).any(0)
            gap = max(4, int(1.8 * ch))
            for end, step, limit in (('x1', 1, int(fx1)), ('x0', -1, int(fx0))):
                # The ends of the runs of ink on from it, nearest first.
                x, run, blank, ends = int(s[end]) + (0 if step > 0 else -1), False, 0, []
                while 0 <= x < len(cols) and (x <= limit if step > 0 else x >= limit):
                    if cols[x]:
                        run, blank = True, 0
                    else:
                        if run:
                            ends.append(x if step > 0 else x + 1)
                        run = False
                        blank += 1
                        if blank > gap:
                            break
                    x += step
                # The farthest that stays in its column and meets no other
                # line but pieces of its own.
                for new in reversed(ends):
                    lo, hi = (s['x1'], new) if step > 0 else (new, s['x0'])
                    if hi - lo < 4:
                        continue
                    if not any(k == kind and q[0] - 3 <= lo and hi <= q[2] + 3 and q[1] - 3 * ch < bottom < q[3] + 4 * ch
                               for q, k, _, _ in plan if q is not r):
                        continue
                    # (Nor into another text's region at its height.)
                    if any(k != kind and q[1] - ch <= bottom - ch / 2 <= q[3] and min(q[2], hi) - max(q[0], lo) > ch
                           for q, k, _, _ in plan):
                        continue
                    beside = [o for o in segs if o is not s and not o.get('sliver') and min(o['bottom'], bottom) - max(o['top'], top) > 0.3 * ch
                              and min(o['x1'], hi) - max(o['x0'], lo) > 0]
                    # (The rest of it, cut off as a line of its own, joins it.)
                    if any(not (lo - 2 <= o['x0'] and o['x1'] <= hi + 2 and abs(o['bottom'] - bottom) < 0.4 * ch
                                and o['x1'] - o['x0'] < 4 * ch) for o in beside):
                        continue
                    # (Nor up to a piece of the row just past it: joining
                    # pieces is join_pieces' to do.)
                    if any(o is not s and not o.get('sliver') and kind_of[id(o)] == kind
                           and min(o['bottom'], bottom) - max(o['top'], top) > 0.3 * ch
                           and (0 <= o['x0'] - hi < 3 * ch if step > 0 else 0 <= lo - o['x1'] < 3 * ch) for o in segs):
                        break
                    for o in beside:
                        o['sliver'] = True
                    s[end] = new
                    break

def _fits(l, stream, pos, lines):
    """Whether a line at [pos] in [stream] runs on from the line of that
    text just above it in its column, or into the one just below."""
    tol = max(10, 0.4 * l['letters'])
    for m in lines:
        if m is l or m.get('stream') != stream or m.get('pos') is None or not m.get('letters'):
            continue
        if min(m['x1'], l['x1']) - max(m['x0'], l['x0']) < 0.5 * min(m['x1'] - m['x0'], l['x1'] - l['x0']):
            continue
        d = l['base'] - m['base']
        if 0.5 * l['h'] < d < 2.5 * l['h'] and abs(m['pos'] + m['letters'] - pos) < tol:
            return True
        if 0.5 * l['h'] < -d < 2.5 * l['h'] and abs(pos + l['letters'] - m['pos']) < tol:
            return True
    return False


def _kind_around(r, rs, lines):
    """The kind of the regions just above and below r over its width, if
    they are of one kind."""
    kinds = set()
    for side in ('above', 'below'):
        y0, y1 = r[1], r[3]
        for _ in range(3):
            near = [q for q in rs if q is not r and min(q[2], r[2]) - max(q[0], r[0]) > 0.8 * (r[2] - r[0])
                    and (abs(q[3] - y0) < 6 if side == 'above' else abs(q[1] - y1) < 6)]
            if len(near) != 1:
                return None
            kind, votes = _region_kind(near[0], lines)
            if votes[kind] >= 20 or near[0][3] - near[0][1] >= 30:
                break
            # (A thin strip with no lines in it, between: past it.)
            y0, y1 = near[0][1], near[0][3]
        if votes[kind] < 20:
            return None
        kinds.add(kind)
    return kinds.pop() if len(kinds) == 1 else None


def _gap_for(l, lines):
    """(stream, pos) where l's text is, if the lines just above and below
    it in its column are of one text and leave a gap of about its length
    between them."""
    def near(below):
        ms = [m for m in lines if m is not l and m.get('stream') in linemap.BODY and m.get('pos') is not None
              and min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.5 * min(m['x1'] - m['x0'], l['x1'] - l['x0'])
              and 0.5 * l['h'] < (m['base'] - l['base'] if below else l['base'] - m['base']) < (2.8 if below else 2.2) * l['h']]
        return min(ms, key=lambda m: abs(m['base'] - l['base'])) if ms else None
    a, b = near(False), near(True)
    if not a or not b or a['stream'] != b['stream']:
        return None
    start = a['pos'] + a['letters']
    if 0.6 * l['letters'] <= b['pos'] - start <= 1.6 * l['letters'] + 10:
        return a['stream'], start
    return None


def _pitch(segs):
    """A region's line spacing: the median step from one line to the next."""
    segs = [s for s in segs if not s.get('sliver')]
    steps = [b['bottom'] - a['bottom'] for a, b in zip(segs, segs[1:])]
    return float(np.median(steps)) if len(steps) >= 3 else float('inf')


def _settle(lines):
    """Two lines can't be the same stretch of one text. Where two of the
    new lines claim to be (a commentary quoting the Gemara word for word,
    Rabbeinu Chananel's column), the one with fewer anchors gives it up:
    the quote is the shorter."""
    for _ in range(20):
        by = {}
        for l in lines:
            if l.get('seg') and l['stream'] in linemap.BODY and l.get('pos') is not None and l.get('hits'):
                by.setdefault(l['stream'], []).append(l)
        changed = False
        for ls in by.values():
            ls.sort(key=lambda l: l['pos'])
            for a, b in zip(ls, ls[1:]):
                overlap = min(a['pos'] + a['letters'], b['pos'] + b['letters']) - max(a['pos'], b['pos'])
                if overlap > 0.5 * min(a['letters'], b['letters']):
                    # The one whose place doesn't run on from the lines
                    # around it (the Gemara quoting its Mishnah further
                    # down); else the one with fewer anchors.
                    fa, fb = (_fits(l, l['stream'], l['pos'], lines) for l in (a, b))
                    # (Else the one more of whose letters are the text's: a
                    # note at the foot quoting it at length has its own
                    # words between.)
                    da, db = (l['hits'] / max(1, l['letters']) for l in (a, b))
                    wa, wb = (l['x1'] - l['x0'] for l in (a, b))
                    apart = max(wa, wb) > 1.8 * min(wa, wb)
                    loser = (b if fa and not fb else a if fb and not fa else b if apart and da > 1.4 * db
                             else a if apart and db > 1.4 * da else min((a, b), key=lambda l: l['hits']))
                    loser['stream'], loser['pos'], loser['hits'], loser['why'] = 'other', None, 0, 'settle'
                    changed = True
                    break
        if not changed:
            return
