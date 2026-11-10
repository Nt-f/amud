#!/usr/bin/env python3
"""The printed page set again as an SVG: every line of the scan, its words
where the print has them, in the app's fonts.

    svg.py Berakhot 5a [2a-10b …] [--cache build/daf_cache] [--out build/daf_svg] [--scan]

writes OUT/<Book>_<amud>.svg, the scan's size (1530×2450 units). Each line
is justified between the ends of the printed line, on its baseline. A line
of the Gemara, Rashi or Tosafot has the words read off it (segment.py), in
the print's order with its abbreviations and periods, each spelled as
Sefaria has it where they are the same word; a big opening word is set as
big as it stands. The rest (the margins' small commentaries, headings,
lines Sefaria lacks) is the Vilna model's reading of the line. Rashi and
Tosafot are set in Rashi script, Tosafot's opening words in square
letters, as printed.

--scan lays the scan faintly under the text, to check the two against each
other. The letters are outlines, not text: a file needs no fonts and shows
the same in any viewer.
"""

import argparse
import base64
import json
import os
import re
import sys
from pathlib import Path

import numpy as np
from rapidfuzz import fuzz
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
import textpass  # noqa: E402

FONTS = Path(__file__).resolve().parents[2] / 'assets' / 'fonts'
SQUARE = 'FrankRuehlCLM-Medium.otf'
RASHI = 'NotoRashiHebrew-Regular.ttf'
# The height of a line's letters (the line map's h) to the font size.
EM = {SQUARE: 1.55, RASHI: 1.35}
# Each word of a line read off the scan set over its own ink (_fitted).
FIT = os.environ.get('SVG_FIT', '1') != '0'
# How a fitted line's words are spaced: each at its own place on the scan
# ('centre'), or justified with equal spaces ('justify').
PLACE = os.environ.get('SVG_PLACE', 'centre')
# Extra stroke on each font's letters, in its units (1000 to the em).
RASHI_WEIGHT = float(os.environ.get('SVG_RASHI_WEIGHT', '30'))
SQUARE_WEIGHT = float(os.environ.get('SVG_SQUARE_WEIGHT', '0'))
# Big words the print sets by rule, to their column's size: a Tosafot
# comment's first word, and the labels מתני' and גמ' in any column.
TOS_BIG = 1.6
LABEL_BIG = {'main': 1.45}
LABEL_BIG_MARGIN = 1.3


def _label(t):
    return linemap.fold(t, linemap.FOLD_SQUARE).rstrip(".:'׳") in ('מתני', 'גמ')


def _hadran(t):
    return 'הדרנ' in linemap.fold(t, linemap.FOLD_SQUARE)


def _starts(words, flags, sid, a):
    """Whether word a of a stream opens a section: the text's first, or
    after a colon or period, or (in a commentary) a comment's first."""
    if a <= 0:
        return True
    if linemap.print_text(words[a - 1]).rstrip().endswith((':', '.')):
        return True
    return sid != 'main' and a < len(flags) and flags[a] and not flags[a - 1]


def _flags(cache, book, amud):
    """Whether each word of the inner and outer margins (as linemap._margins
    counts them) is in a comment's opening words."""
    def of(segments):
        out = []
        for seg in segments:
            for c in (seg if isinstance(seg, list) else [seg]):
                if isinstance(c, str):
                    dh, rest = linemap.comment_split(c)
                    out += [True] * len(linemap.words_of_html(dh)) + [False] * len(linemap.words_of_html(rest))
        return out
    ref = f'{book}.{amud}'
    ids = ['Rashi'] + (['Rashbam'] if book == 'Bava Batra' else []) + (['Mefaresh'] if book == 'Tamid' else [])
    by_id = {c: linemap.sefaria(cache, f'{c} on {ref}', 'hebrew') or [] for c in ids}
    inner = []
    for i in range(max(len(v) for v in by_id.values())):
        for c in ids:
            if i < len(by_id[c]):
                inner += of([by_id[c][i]])
    return inner, of(linemap.sefaria(cache, f'Tosafot on {ref}', 'hebrew') or [])


class Fonts:
    """The fonts as outlines: each glyph a path in <defs>, each word <use>s
    of them, so the page needs no fonts (and no viewer's text support) to
    show as set."""
    MIRROR = {'(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{', '<': '>', '>': '<'}

    def __init__(self):
        self.fonts, self.defs, self.inks = {}, {}, {}
        # Every word set, for the app (see placement()): its column and word
        # number in the app's words where it is one of them (`tag`, set by
        # the caller before each word), font, text and transform.
        self.placed, self.tag = [], None

    def _record(self, font, word, left, base, sx, sy):
        col, k, big = self.tag or ('', -1, False)
        self.placed.append([col, int(k), int(font == RASHI), word, round(float(left), 1), round(float(base), 1), round(float(sx), 2), round(float(sy), 2)]
                           + ([1] if big else []))

    def _font(self, name):
        if name not in self.fonts:
            tt = TTFont(str(FONTS / name))
            self.fonts[name] = (tt, tt.getBestCmap(), tt.getGlyphSet(), tt['head'].unitsPerEm)
        return self.fonts[name]

    def _glyph(self, name, ch):
        """(glyph id in defs or None, advance in em) for a character, from
        the other font if this one lacks it."""
        for n in (name, SQUARE if name == RASHI else RASHI):
            tt, cmap, gs, upm = self._font(n)
            g = cmap.get(ord(self.MIRROR.get(ch, ch)))
            if g:
                key = f'{"s" if n == SQUARE else "r"}{g}'
                if key not in self.defs:
                    pen = SVGPathPen(gs)
                    gs[g].draw(pen)
                    self.defs[key] = pen.getCommands()
                return (key if self.defs[key] else None), gs[g].width / upm
        return None, 0.3

    def width(self, font, size, word):
        return sum(self._glyph(font, c)[1] for c in word) * size

    def word(self, font, size, word, x1, base, width=None):
        """A word set right to left, ending at x1 on the baseline; squeezed
        or stretched to `width` if given."""
        nat = self.width(font, size, word)
        sx = size * (width / nat if width and nat else 1)
        x, uses = nat / size, []  # in em, from the word's left
        for c in word:
            key, adv = self._glyph(font, c)
            x -= adv
            if key:
                uses.append(f'<use xlink:href="#{key}" x="{x * 1000:.0f}"/>')
        left = x1 - nat * sx / size
        self._record(font, word, left, base, sx, size)
        return (f'<g transform="matrix({sx / 1000:.5f},0,0,{-size / 1000:.5f},{left:.1f},{base:.1f})">'
                + ''.join(uses) + '</g>')

    def _bounds(self, name, ch):
        """A character's ink (xmin, ymin, xmax, ymax) in em, or None."""
        key = (name, ch)
        if key not in self.inks:
            box = None
            for n in (name, SQUARE if name == RASHI else RASHI):
                tt, cmap, gs, upm = self._font(n)
                g = cmap.get(ord(self.MIRROR.get(ch, ch)))
                if g:
                    pen = BoundsPen(gs)
                    gs[g].draw(pen)
                    if pen.bounds:
                        box = tuple(v / upm for v in pen.bounds)
                    break
            self.inks[key] = box
        return self.inks[key]

    def core(self, name):
        """The height of the font's letters' bodies, in em (a he's)."""
        return self._bounds(name, 'ה')[3]

    def ink(self, name, word):
        """A word's ink, (left, right) in em from its left edge as word()
        sets it."""
        x, lo, hi = self.width(name, 1, word), None, None
        for c in word:
            adv = self._glyph(name, c)[1]
            x -= adv
            b = self._bounds(name, c)
            if b:
                lo = x + b[0] if lo is None else min(lo, x + b[0])
                hi = x + b[2] if hi is None else max(hi, x + b[2])
        return (lo, hi) if lo is not None else (0, self.width(name, 1, word))

    def fit(self, name, word, x0, x1, base, core):
        """A word whose ink spans x0..x1 on the page, its letters' bodies
        `core` tall standing on `base`: as the print has it there. (Not
        squeezed or stretched past a third: a box that wide or narrow is
        wrong, the word goes in its middle.)"""
        sy = core / self.core(name)
        lo, hi = self.ink(name, word)
        sx = (x1 - x0) / max(hi - lo, 1e-6)
        k = min(max(sx / sy, 0.5), 1.3)
        sx = sy * k
        left = (x0 + x1) / 2 - (lo + hi) / 2 * sx
        self._record(name, word, left, base, sx, sy)
        uses, x = [], self.width(name, 1, word)
        for c in word:
            key, adv = self._glyph(name, c)
            x -= adv
            if key:
                uses.append(f'<use xlink:href="#{key}" x="{x * 1000:.0f}"/>')
        return (f'<g transform="matrix({sx / 1000:.5f},0,0,{-sy / 1000:.5f},{left:.1f},{base:.1f})">'
                + ''.join(uses) + '</g>')

    def vink(self, name, word):
        """A word's ink, (bottom, top) in em from the baseline."""
        lo = hi = None
        for c in word:
            b = self._bounds(name, c)
            if b:
                lo = b[1] if lo is None else min(lo, b[1])
                hi = b[3] if hi is None else max(hi, b[3])
        return (lo, hi) if lo is not None else (0, self.core(name))

    def fit_box(self, name, word, x0, x1, y0, y1):
        """A word whose ink fills the box x0..x1, y0..y1 on the page (a big
        opening word, as tall as it stands)."""
        lo, hi = self.vink(name, word)
        sy = (y1 - y0) / max(hi - lo, 1e-6)
        base = y1 + lo * sy
        return self.fit(name, word, x0, x1, base, sy * self.core(name))

    def svg_defs(self):
        # Paths are in font units; words scale them by size/1000, so make
        # each font's em 1000 units.
        out = []
        for key, d in self.defs.items():
            if not d:
                continue
            upm = self._font(SQUARE if key[0] == 's' else RASHI)[3]
            t = f' transform="scale({1000 / upm:.5f})"' if upm != 1000 else ''
            # (Rashi script as heavy as the print's: the font's strokes are
            # thinner.)
            w = RASHI_WEIGHT if key[0] == 'r' else SQUARE_WEIGHT
            sw = f' stroke="#111111" stroke-width="{w}" stroke-linejoin="round"' if w else ''
            out.append(f'<path id="{key}" d="{d}"{t}{sw}/>')
        return '<defs>' + ''.join(out) + '</defs>'


def _set(words, x0, x1, base, size, fonts, justify=True, tags=None):
    """SVG for one line: (word, font) or (word, font, scale) laid right to
    left from x1, the spaces stretched to end it at x0. A word at `scale`
    is that much bigger than the line's (a big opening word). `tags`: each
    word's Fonts.tag."""
    tags = [g for t, g in zip(words, tags) if t[0]] if tags and len(tags) == len(words) else None
    words = [(t[0], t[1], t[2] if len(t) > 2 else 1.0, t[3] if len(t) > 3 else 0) for t in words if t[0]]
    if not words:
        return ''
    ws = [fonts.width(f, size * EM[f] * k, w) for w, f, k, _ in words]
    space = 0.28 * size
    avail = x1 - x0
    natural = sum(ws) + space * (len(ws) - 1)
    squeeze = 1.0
    if natural > avail:
        squeeze = avail / natural
        gap = space * squeeze
    elif justify and len(ws) > 1:
        gap = (avail - sum(ws)) / (len(ws) - 1)
        if gap > 4 * space:
            gap = space  # a short line: the last of a paragraph, or a part line
    else:
        gap = space
    out, x = [], x1
    for n, ((w, f, k, drop), wd) in enumerate(zip(words, ws)):
        wd *= squeeze
        if tags:
            fonts.tag = tags[n]
        out.append(fonts.word(f, size * EM[f] * k, w, x, base + drop, wd if squeeze < 1 else None))
        x -= wd + gap
    return ''.join(out)


def _tall(grey, x0, x1, base, core):
    """The height of a word's letters on the scan (the rows where its ink
    runs thick, so not a lamed's thin stem), and the bottom of them: a
    line's letter height for most words; for a big opening word more, and
    it can hang down to a line below."""
    y0 = max(0, int(base - 4 * core))
    a = grey[y0:int(base + 3 * core), int(x0) + 2:max(int(x0) + 3, int(x1) - 1)] < 128
    if not a.size:
        return 0, base
    p = a.sum(1)
    mid = int(base - 0.5 * core) - y0
    around = p[max(0, mid - int(core / 2)):mid + int(core / 2) + 1]
    peak = around.max() if around.size else 0
    if peak == 0:
        return 0, base
    thick = np.flatnonzero(p >= 0.3 * peak)
    # Thick rows from the middle up and down, across thin ones inside a
    # letter (Rashi script's are thin across the middle) but not across
    # the space between lines.
    gap = max(2, int(0.4 * core))
    top = bottom = mid
    for r in thick[::-1]:
        if r < mid and top - r <= gap:
            top = r
    for r in thick:
        if r > mid and r - bottom <= gap:
            bottom = r
    return bottom - top + 1, y0 + bottom + 1


def _verse_refs(words):
    """The word numbers of the Gemara's verse references (Sefaria's, in
    parentheses: a book, its chapter and verse, so with a comma). Its other
    parentheses are the print's own, as are its brackets."""
    out, run = set(), None
    for k, w in enumerate(words):
        t = linemap.print_text(w)
        if run is None and t.startswith('('):
            run = []
        if run is not None:
            run.append(k)
            if t.endswith(')'):
                if any(',' in linemap.print_text(words[j]) for j in run):
                    out.update(run)
                run = None
    return out


def _print_words(words, a, b, sid, flags, idx=None):
    """Words a..b of a stream as the print sets them, each with its font
    (and in `idx`, if given, each one's word number).
    The Gemara's verse references (Sefaria's, in parentheses) are in the
    margin in print, a ° before the verse in their place. Rashi's opening
    words end in a period; Tosafot's are in square letters too."""
    f = SQUARE if sid == 'main' else RASHI
    out, ks = [], []
    refs = _verse_refs(words) if sid == 'main' else ()
    for k in range(a, b):
        t = linemap.print_text(words[k])
        if k in refs:
            if k + 1 not in refs and k + 1 < len(words):
                out.append(('°', None))
                ks.append(None)
            continue
        dh = k < len(flags) and flags[k]
        if dh and (k + 1 == len(flags) or not flags[k + 1]) and t[-1:] not in '.:':
            t += '.'
        if out and out[-1][1] is None and len(out[-1]) == 2:
            t = '°' + t
            out.pop()
            ks.pop()
        ks.append(k)
        if dh and sid == 'outer' and (k == 0 or k - 1 >= len(flags) or not flags[k - 1]):
            out.append((t, SQUARE, TOS_BIG))
        elif _label(t) and (k == 0 or linemap.print_text(words[k - 1]).rstrip().endswith((':', '.'))):
            out.append((t, SQUARE, LABEL_BIG.get(sid, LABEL_BIG_MARGIN)))
        else:
            out.append((t, f))
    if idx is not None:
        idx[:] = [k for t, k in zip(out, ks) if t[1]]
    return [t for t in out if t[1]]


def _tokens(words, a, b, sid, flags, inside=None, names=()):
    """Words a..b of a stream as dicts: the print's spelling of each (no
    verse references, which are in the margin in print; in a commentary's
    references, not the tractate's own name, as on its own pages), its
    font, whether it ends a comment's opening words, and whether it is in
    `inside` (the line's own range)."""
    out, after, paren, skip = [], False, False, 0
    refs = _verse_refs(words) if sid == 'main' else ()
    for k in range(max(0, a), min(len(words), b)):
        t = linemap.print_text(words[k])
        if k in refs:
            after = k + 1 not in refs
            continue
        if sid != 'main' and t.startswith('(') and not paren:
            # The tractate's name, a word or two, after the parenthesis.
            for name in names:
                n = name.split()
                if [linemap.print_text(w) for w in words[k:k + len(n)]] == ['(' + n[0]] + n[1:]:
                    paren, skip = True, len(n) - 1
                    break
            if paren:
                continue
        if skip:
            skip -= 1
            continue
        if paren:
            t, paren = '(' + t, False
        if not t:
            continue
        dh = k < len(flags) and flags[k]
        end = dh and (k + 1 == len(flags) or not flags[k + 1])
        # (The verse after a reference has a ° before it.)
        # (A label is big only where it opens a section: after a colon, or a
        # commentary's own comment on it; elsewhere it names the Mishnah.)
        opens = k == 0 or linemap.print_text(words[k - 1]).rstrip().endswith((':', '.'))
        big = (TOS_BIG if dh and sid == 'outer' and (k == 0 or k - 1 >= len(flags) or not flags[k - 1])
               else LABEL_BIG.get(sid, LABEL_BIG_MARGIN) if _label(t) and opens else 1)
        out.append(dict(t=t, k=k, font=SQUARE if sid == 'main' or big > 1 else RASHI, end=end, verse=after, big=big,
                        inside=inside is None or inside[0] <= k < inside[1]))
        after = False
    return out


def _unstack(words):
    """A line's read words with no box over another's: the reading
    sometimes gives a word a box that takes in its neighbours too
    (בעידנא over לך and אמינא), and so puts it out of order. Such a box is
    cut to the longest stretch the other words leave it; right to left
    again after."""
    out = []
    for w in words:
        if not w['text'].strip():
            out.append(w)
            continue
        free = [(w['x0'], w['x1'])]
        for v in words:
            if v is w or not v['text'].strip() or v['x1'] - v['x0'] >= w['x1'] - w['x0']:
                continue
            if min(v['x1'], w['x1']) - max(v['x0'], w['x0']) < 0.6 * (v['x1'] - v['x0']):
                continue
            free = [p for a, b in free for p in ((a, min(b, v['x0'] - 2)), (max(a, v['x1'] + 2), b)) if p[1] - p[0] > 2]
        if free and free != [(w['x0'], w['x1'])]:
            a, b = max(free, key=lambda p: p[1] - p[0])
            w = dict(w, x0=a, x1=b)
        out.append(w)
    return sorted(out, key=lambda w: -w['x1'])


def _fold(t):
    return linemap.fold(t, linemap.FOLD_SQUARE).replace(' ', '')


# What _from_read set that Sefaria didn't vouch for, for --stats: words as
# read that match none of Sefaria's, misread words set as Sefaria's, and
# Sefaria's words put in where the OCR missed them.
STATS = {'unmatched': [], 'fixed': [], 'inserted': []}
# (Debugging: why _from_read left a read word out, by id.)
WHY = {}


def _from_read(read, tokens, sid, ink=None, src=None, idx=None):
    """A line's words as read off the scan (the print's order, its
    abbreviations and periods), fitted to Sefaria's words of it: a word
    read in a Sefaria word's place is spelled as Sefaria has it (a misread
    letter or two, or a misread word between two read right), in Sefaria's
    font for it; a word of the line's own the OCR missed goes in where it
    was, between words it read or (by `ink`, the line's ends on the scan)
    where there is ink it didn't read; the rest as read. `read` is the
    line's words as dicts of text, x0, x1, right to left. `src`, if
    given, gets for each word the read word (dict) it stands for, None
    for one put in; `idx` each word's number in the stream (-1 for one
    only read)."""
    rs = [w for w in read if w['text'].strip()]
    # Two words read as one (no space seen between them): two, the box
    # shared by their letters.
    tfs = [_fold(t['t']) for t in tokens]
    split = []
    for r in rs:
        f = _fold(r['text'])
        hit = next((j for j in range(len(tokens) - 1) if len(f) >= 5 and len(tfs[j]) >= 2 and len(tfs[j + 1]) >= 2
                    and fuzz.ratio(f, tfs[j] + tfs[j + 1]) >= 90 and fuzz.ratio(f, tfs[j]) < 75 and fuzz.ratio(f, tfs[j + 1]) < 75), None)
        if hit is None:
            split.append(r)
            continue
        a_, b_ = len(tfs[hit]), len(tfs[hit + 1])
        cut = r['x1'] - (r['x1'] - r['x0']) * a_ / (a_ + b_)
        split.append(dict(r, text=tokens[hit]['t'], x0=cut + 1))
        split.append(dict(r, text=tokens[hit + 1]['t'], x1=cut - 1))
    rs = split
    n, m = len(rs), len(tokens)
    rf, tf = [_fold(r['text']) for r in rs], [_fold(t['t']) for t in tokens]

    def sim(i, j):
        return fuzz.ratio(rf[i], tf[j]) if rf[i] and tf[j] else 0
    # Edit distance over words: a pair costs what they differ by; Sefaria's
    # words before and after the line's are free to skip.
    D = np.zeros((n + 1, m + 1))
    D[:, 0] = np.arange(n + 1)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            D[i, j] = min(D[i - 1, j] + 1, D[i, j - 1] + (1 if i < n else 0), D[i - 1, j - 1] + (1 - sim(i - 1, j - 1) / 100) * 2)
    i, j = n, int(np.argmin(D[n]))
    path = [('sef', None, k) for k in range(m - 1, j - 1, -1)]
    while i > 0 and j > 0:
        if D[i, j] == D[i - 1, j - 1] + (1 - sim(i - 1, j - 1) / 100) * 2:
            path.append(('pair', i - 1, j - 1))
            i, j = i - 1, j - 1
        elif D[i, j] == D[i - 1, j] + 1:
            path.append(('read', i - 1, None))
            i -= 1
        else:
            path.append(('sef', None, j - 1))
            j -= 1
    path += [('read', k, None) for k in range(i - 1, -1, -1)] + [('sef', None, k) for k in range(j - 1, -1, -1)]
    path.reverse()
    good = [x for x, (op, i, j) in enumerate(path) if op == 'pair' and sim(i, j) >= 60]
    if not good:
        if src is not None:
            src[:] = list(rs)
        if idx is not None:
            idx[:] = [-1] * len(rs)
        return [(r['text'].lstrip('*°'), SQUARE if sid == 'main' else RASHI) for r in rs]
    first, last = good[0], good[-1]
    plain = SQUARE if sid == 'main' else RASHI
    out, kinds, srcs, ks = [], [], [], []

    def tok(j, r=''):
        t = tokens[j]
        w, mark = t['t'], '°' if t.get('verse') or r[:1] in '*°' else ''
        if r[-1:] in ('.', ':') and w[-1:] not in ('.', ':'):
            w += r[-1]
        elif t['end'] and w[-1:] not in ('.', ':'):
            w += '.'
        out.append((mark + w, t['font']) + ((t['big'], 0) if t.get('big', 1) > 1 else ()))
        kinds.append(('sef', tf[j]))
        ks.append(t.get('k', -1))
    for x, (op, i, j) in enumerate(path):
        if op == 'pair':
            if sim(i, j) >= 60 or tokens[j]['inside']:
                tok(j, rs[i]['text'])
                if sim(i, j) < 60:
                    STATS['fixed'].append(f"{rs[i]['text']}→{tokens[j]['t']}")
            else:
                out.append((rs[i]['text'].lstrip('*°'), plain))
                kinds.append(('read', rf[i]))
                # (Misread, but in this word's place.)
                ks.append(tokens[j].get('k', -1) if sim(i, j) >= 40 else -1)
            if rs[i].get('scale', 1) > 1:
                out[-1] = (out[-1][0], SQUARE, rs[i]['scale'], rs[i].get('drop', 0))
            srcs.append(i)
        elif op == 'read':
            r = rs[i]['text']
            # Scraps: at either end and short (a note in the gutter, a
            # heading beside the line), or a letter or two between words
            # read right.
            # (A word: three letters, or two with an abbreviation's mark, ב"ד.)
            word = len(rf[i]) >= 3 or len(rf[i]) == 2 and re.search('["\'׳״]', r)
            inside = ink and ink[0] + 4 <= (rs[i]['x0'] + rs[i]['x1']) / 2 <= ink[1] - 4 and word
            if x < first and sum(len(rf[k]) for k in range(i + 1)) <= 6 and not inside:
                WHY[id(rs[i])] = 'end scrap'
                continue
            if x > last and sum(len(rf[k]) for k in range(i, n)) <= 6 and not inside:
                WHY[id(rs[i])] = 'end scrap'
                continue
            if first < x < last and not word:
                WHY[id(rs[i])] = 'short between'
                continue
            # No letters (a page number, a mark), or a heading beside it.
            if not rf[i] or x > last and linemap._heading(' '.join(rs[k]['text'] for k in range(i, n))) \
                    or x < first and linemap._heading(' '.join(rs[k]['text'] for k in range(i + 1))):
                WHY[id(rs[i])] = 'heading/no letters'
                continue
            if x > last and any(linemap._heading(' '.join(rs[k]['text'] for k in range(m, n))) for m in range(i)):
                WHY[id(rs[i])] = 'heading word'
                continue  # (the heading's first word, after the line's own)
            kinds.append(('read', rf[i]))
            ks.append(-1)
            srcs.append(i)
            if _label(r) and (not out or out[-1][0].rstrip().endswith((':', '.'))):
                out.append((r.lstrip('*°'), SQUARE, LABEL_BIG.get(sid, LABEL_BIG_MARGIN), 0))
                continue
            out.append(((('°' if r[:1] in '*°' else '') + r.lstrip('*°')), plain)
                       + ((SQUARE, rs[i]['scale'], rs[i].get('drop', 0))[1:] if rs[i].get('scale', 1) > 1 else ()))
            if rs[i].get('scale', 1) > 1:
                out[-1] = (out[-1][0], SQUARE, rs[i]['scale'], rs[i].get('drop', 0))
        elif tokens[j]['inside']:
            if x < first and linemap.fold(tokens[j]['t'], linemap.FOLD_SQUARE) in ('מתני', 'גמ'):
                continue  # Sefaria's label where the print has a big opening word
            if (first < x < last or ink and x < first and rs and ink[1] - rs[0]['x1'] > 12
                    or ink and x > last and rs and rs[-1]['x0'] - ink[0] > 12):
                # (Between words read, or before the first or after the last
                # where there is ink it didn't read.)
                tok(j)
                kinds[-1] = ('ins', tf[j])
                srcs.append(None)
    # A word read where Sefaria has it a little before or after (the two
    # put a word in a different order): once, as read.
    drop = set()
    for x, (kind, f) in enumerate(kinds):
        if kind == 'ins' and any(k == 'read' and fuzz.ratio(f, g) >= 80 for k, g in kinds):
            drop.add(x)
    for x, (kind, f) in enumerate(kinds):
        if x not in drop:
            if kind == 'read':
                STATS['unmatched'].append(out[x][0])
            elif kind == 'ins':
                STATS['inserted'].append(out[x][0])
    if src is not None:
        src[:] = [None if v is None else rs[v] for x, v in enumerate(srcs) if x not in drop]
    if idx is not None:
        idx[:] = [k for x, k in enumerate(ks) if x not in drop]
    return [w for x, w in enumerate(out) if x not in drop]


def _core(grey, x0, x1, base, h):
    """The height of a line's letters on the scan (their bodies, without
    what rises above or hangs below): the rows around the baseline where
    ink runs at least a third as thick as at its thickest."""
    y0, y1 = int(base - 1.3 * h), int(base + 0.2 * h) + 1
    a = grey[max(0, y0):y1, max(0, int(x0)):int(x1) + 1]
    if a.size == 0 or a.shape[0] < 4:
        return None
    ink = (a < (int(np.median(a)) + int(a.min())) / 2).sum(1)
    top = int(ink.argmax())
    lo = hi = top
    while lo > 0 and ink[lo - 1] > ink[top] / 3:
        lo -= 1
    while hi + 1 < len(ink) and ink[hi + 1] > ink[top] / 3:
        hi += 1
    return hi - lo + 1


def _pitch(lines):
    """The usual distance between a line's baseline and the next one's
    below it in the same column; lines are (x0, x1, base)."""
    gaps = []
    for x0, x1, base in lines:
        below = [b - base for a0, a1, b in lines if b > base + 2 and min(x1, a1) - max(x0, a0) > 0.5 * min(x1 - x0, a1 - a0)]
        if below:
            gaps.append(min(below))
    return float(np.median(gaps)) if len(gaps) >= 3 else None


def _numeral(n):
    """n in Hebrew letters, as the print numbers its pages (טו, טז)."""
    out = ''
    for v, c in ((400, 'ת'), (300, 'ש'), (200, 'ר'), (100, 'ק'), (90, 'צ'), (80, 'פ'), (70, 'ע'), (60, 'ס'), (50, 'נ'),
                 (40, 'מ'), (30, 'ל'), (20, 'כ'), (10, 'י'), (9, 'ט'), (8, 'ח'), (7, 'ז'), (6, 'ו'), (5, 'ה'), (4, 'ד'),
                 (3, 'ג'), (2, 'ב'), (1, 'א')):
        while n >= v:
            out, n = out + c, n - v
    return out.replace('יה', 'טו').replace('יו', 'טז')


def _place(words, boxes, base, size, fonts, tags=None):
    """SVG for words each set in its own [x0, x1] on the scan: fitted to it
    if near its width, else at its natural width in the middle of it."""
    out = []
    for n, ((w, f), (x0, x1)) in enumerate(zip(words, boxes)):
        if not w:
            continue
        if tags:
            fonts.tag = tags[n]
        nat = fonts.width(f, size * EM[f], w)
        box = x1 - x0
        if 0.75 < box / max(nat, 1) < 1.35 or nat > box:
            out.append(fonts.word(f, size * EM[f], w, x1, base, box))
        else:
            out.append(fonts.word(f, size * EM[f], w, x1 - (box - nat) / 2, base))
    return ''.join(out)


def _centered(text, x0, x1, base, size, fonts):
    """A heading, in square letters, centered over [x0, x1]."""
    nat = fonts.width(SQUARE, size * EM[SQUARE], text)
    x = (x0 + x1 + min(nat, x1 - x0)) / 2
    # Word by word, so the outlines keep the spaces.
    space = 0.28 * size * EM[SQUARE] * min(1, (x1 - x0) / nat)
    out = []
    for w in text.split():
        wd = fonts.width(SQUARE, size * EM[SQUARE], w) * min(1, (x1 - x0) / nat)
        out.append(fonts.word(SQUARE, size * EM[SQUARE], w, x, base, wd))
        x -= wd + space
    return ''.join(out)


def _opening(grey, l, size, sid, heading, starts, ratio=1.3):
    """(scale, drop) for a line's first word where the print sets it big (a
    chapter's or section's opening), or None: only where a section starts,
    and as measured against the line's other words, so a lamed's stem or a
    word of the line above or below doesn't count."""
    ws = l['words']
    if heading or not starts or not ws or len(ws[0]['text'].strip()) < 2:
        return None
    core = size / 1.3

    def tall(w):
        inset = 0.15 * (w['x1'] - w['x0'])
        return _tall(grey, w['x0'] + inset, w['x1'] - inset, l['base'], core)
    rest = [tall(w)[0] for w in ws[1:] if len(linemap.fold(w['text'], linemap.FOLD_SQUARE).strip(".:'\"")) >= 3]
    rest = [t for t in rest if t]
    med = float(np.median(rest)) if len(rest) >= 2 else 0.88 * core
    t, bottom = tall(ws[0])
    if not ratio * med < t <= (3.4 if sid == 'main' else 2.2) * med:
        return None
    # (Hanging below its line only where it is much bigger: a chapter's.)
    return min(3.2, t / core), (bottom - l['base'] if t > 2 * med else 0)


ORDINALS = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'ששי', 'שביעי', 'שמיני', 'תשיעי', 'עשירי',
            'אחד עשר', 'שנים עשר', 'שלשה עשר', 'ארבעה עשר', 'חמשה עשר', 'ששה עשר', 'שבעה עשר', 'שמונה עשר',
            'תשעה עשר', 'עשרים', 'עשרים ואחד', 'עשרים ושנים', 'עשרים ושלשה', 'עשרים וארבעה']


def _daf(ref):
    """'13b:16' → (13, 1, 16)."""
    a, _, seg = ref.partition(':')
    return int(a[:-1]), a[-1] == 'b', int(seg or 0)


def _head_words(cache, book, amud):
    """The running head's words right to left: the chapter in force at the
    amud's top, פרק and its number, the tractate's name."""
    try:
        idx = json.loads((cache / 'index' / f'{book}.json').read_text())
        nodes = idx['alt_structs']['Chapters']['nodes']
    except (OSError, KeyError, ValueError):
        return []
    top = _daf(f'{amud}:1')
    for n, c in enumerate(nodes):
        span = c['wholeRef'].rsplit(' ', 1)[1]
        a, _, b = span.partition('-')
        start = _daf(a)
        end = _daf(b) if ':' in b else (*_daf(b + ':0')[:2], 10 ** 6)
        if start <= top <= end or start[:2] <= top[:2] <= end[:2] and n + 1 == len(nodes):
            name = next((t['text'] for t in c.get('titles', []) if t.get('lang') == 'he' and t.get('primary')), '')
            tractate = (linemap.he_names(cache, book) or [''])[0]
            if not name or not tractate or n >= len(ORDINALS):
                return []
            return name.split() + ['פרק'] + ORDINALS[n].split() + tractate.split()
    return []


def _running_head(want, pieces, fonts, grey=None):
    """The running head set from `want` (its words right to left) where the
    print has them: each word at the OCR word it best matches, the rest
    beside the matched words of their group, at the head's size. `pieces`
    are the head's lines read off the scan."""
    got = [w for l in pieces for w in l.get('words') or [] if w['text'].strip()]
    if not want or not got:
        return []
    size = float(np.median([l['h'] for l in pieces]))
    em = size * EM[SQUARE]
    space = 0.6 * size
    at = {}
    used = set()
    # Two of its words read as one (no space seen between them): that
    # word's box shared between them by their widths.
    for i in range(len(want) - 1):
        pair = _fold(want[i] + want[i + 1])
        for k, g in enumerate(got):
            r = fuzz.ratio(pair, _fold(g['text']))
            if k not in used and r >= 85 and r > max(fuzz.ratio(_fold(w), _fold(g['text'])) for w in want):
                a_, b_ = (fonts.width(SQUARE, em, w) for w in want[i:i + 2])
                cut = g['x1'] - (g['x1'] - g['x0']) * a_ / (a_ + b_)
                at[i], at[i + 1] = (cut + 0.15 * size, g['x1']), (g['x0'], cut - 0.15 * size)
                used.add(k)
                break
    for i, w in enumerate(want):
        if i in at:
            continue
        best = max(((fuzz.ratio(_fold(w), _fold(g['text'])), k) for k, g in enumerate(got) if k not in used), default=(0, None))
        if best[0] >= 60:
            at[i] = (got[best[1]]['x0'], got[best[1]]['x1'])
            used.add(best[1])
    if not at:
        return []
    # The print's chapter name can run on past Sefaria's short one (מבוי
    # שהוא גבוה, דיני ממונות בשלשה): words read just left of its last
    # word, before פרק, as read.
    p = want.index('פרק') if 'פרק' in want else None
    if p and p - 1 in at:
        x0 = at[p - 1][0]
        extra = []
        for k, g in sorted(enumerate(got), key=lambda t: -t[1]['x1']):
            if k in used or g['x1'] > x0 + 2 or x0 - g['x1'] > 1.5 * size or fuzz.ratio(_fold(g['text']), 'פרק') >= 60:
                continue
            t = g['text'].strip(".,:'\"")
            if len(_fold(t)) < 2:
                continue
            extra.append((t, (g['x0'], g['x1'])))
            used.add(k)
            x0 = g['x0']
        if extra:
            want = want[:p] + [t for t, _ in extra] + want[p:]
            at = {(i if i < p else i + len(extra)): v for i, v in at.items()}
            for j, (_, box) in enumerate(extra):
                at[p + j] = box
    # As big as the print's: its words about as wide as their boxes (a
    # box is the ink, a word's width has its letters' side bearings too).
    fit = [(at[i][1] - at[i][0]) / fonts.width(SQUARE, em, want[i]) for i in at if len(want[i]) >= 3]
    if fit:
        em *= min(1.0, 1.15 * float(np.median(fit)))
    # Unmatched words beside the nearest matched one (on its left if that
    # one is before it in the head, else on its right).
    for _ in range(len(want)):
        for i in range(len(want)):
            if i in at:
                continue
            wd = fonts.width(SQUARE, em, want[i])
            if i - 1 in at:
                x1 = at[i - 1][0] - space
                at[i] = (x1 - wd, x1)
            elif i + 1 in at:
                x0 = at[i + 1][1] + space
                at[i] = (x0, x0 + wd)
    base = float(np.median([l['base'] for l in pieces]))
    if grey is not None and len(at) == len(want):
        fitted = _head_on_ink(want, [at[i] for i in range(len(want))], pieces, grey, fonts)
        if fitted:
            return fitted
    out = []
    for i, w in enumerate(want):
        if i in at:
            x0, x1 = at[i]
            wd = fonts.width(SQUARE, em, w)
            out.append(fonts.word(SQUARE, em, w, (x0 + x1 + wd) / 2, base))
    return out


def _head_on_ink(want, near, pieces, grey, fonts):
    """The running head's words each over its own ink: the head's ink cut
    into words at the wide blanks between them, the cuts taken nearest the
    places the words were matched to (`near`, right to left)."""
    x0 = int(min([l['x0'] for l in pieces] + [n[0] for n in near])) - 10
    x1 = int(max([l['x1'] for l in pieces] + [n[1] for n in near])) + 10
    size = float(np.median([l['h'] for l in pieces]))
    base = float(np.median([l['base'] for l in pieces]))
    y0, y1 = int(base - 1.2 * size), int(base + 0.15 * size)
    a = grey[max(0, y0):y1, max(0, x0):x1] < 128
    cols = a.sum(0) > 0
    # Blobs: ink runs, joined across gaps narrower than a letter's.
    runs, start, blank = [], None, 0
    for i, c in enumerate(cols):
        if c:
            if start is None:
                start = i
            blank, end = 0, i + 1
        elif start is not None:
            blank += 1
            if blank > 0.3 * size:
                runs.append((start, end))
                start = None
    if start is not None:
        runs.append((start, end))
    blobs = [(x0 + s, x0 + e) for s, e in runs if e - s > 0.3 * size][::-1]  # right to left
    if len(blobs) < len(want):
        return None
    # Join the blobs nearest each other until one per word.
    while len(blobs) > len(want):
        k = min(range(len(blobs) - 1), key=lambda k: blobs[k][0] - blobs[k + 1][1])
        blobs[k:k + 2] = [(blobs[k + 1][0], blobs[k][1])]
    # (Each where it was matched, else the order is off: no.)
    for (b0, b1), (n0, n1) in zip(blobs, near):
        if min(b1, n1) - max(b0, n0) <= 0:
            return None
    t, bottom = _tall(grey, x0, x1, base, size / 1.3)
    if not t:
        return None
    return [fonts.fit(SQUARE, w, b0, b1, bottom, t) for w, (b0, b1) in zip(want, blobs)]


def _column_of(l, lines):
    """The body text whose column a line Sefaria has nothing for stands in:
    one text's lines just above and below it, as wide as it, its letters
    their size (Tosafot's lines that Sefaria lacks); else None."""
    if not l.get('seg') or l.get('stream') in linemap.BODY:
        return None
    near = {}
    for below in (False, True):
        ms = [m for m in lines if m is not l and m.get('stream') in linemap.BODY and 'range' in m
              and min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.8 * max(m['x1'] - m['x0'], l['x1'] - l['x0'])
              and 0.5 * l['h'] < (m['base'] - l['base'] if below else l['base'] - m['base']) < 10 * l['h']]
        if not ms:
            return None
        m = min(ms, key=lambda m: abs(m['base'] - l['base']))
        near[below] = m
    a, b = near[False], near[True]
    # (Its own amud's or the one before's: one column.)
    if a['stream'].split('_')[0] != b['stream'].split('_')[0] or abs(l['h'] - a['h']) > 0.2 * a['h']:
        return None
    return b['stream'].split('_')[0]


def _ink_box(grey, x0, x1, base, core):
    """A word's box narrowed to its ink, in the rows of its letters'
    bodies (not what a line above hangs into it), or None if blank."""
    y0, y1 = int(base - 1.05 * core), int(base + 0.1 * core) + 1
    a = grey[max(0, y0):y1, max(0, int(x0) - 2):int(x1) + 3] < 128
    cols = np.flatnonzero(a.sum(0) >= 1)
    if not len(cols):
        return None
    return max(0, int(x0) - 2) + cols[0], max(0, int(x0) - 2) + cols[-1] + 1


def _extent(grey, x0, x1, base, core):
    """The rows a word's ink takes, (top, bottom): the run of rows with ink
    through its letters' middle, across no blank row (a big word's thin
    middle has ink in every row; the line above or below is past a blank
    one)."""
    y0 = max(0, int(base - 3.2 * core))
    a = grey[y0:int(base + 2.4 * core), int(x0):max(int(x0) + 1, int(x1))] < 128
    rows = a.sum(1) >= 1
    mid = int(base - 0.5 * core) - y0
    if not 0 <= mid < len(rows) or not rows[mid]:
        return None
    top = bottom = mid
    while top > 0 and rows[top - 1]:
        top -= 1
    while bottom + 1 < len(rows) and rows[bottom + 1]:
        bottom += 1
    return y0 + top, y0 + bottom + 1


def _big_box(grey, boxes, k, e, core):
    """A big word's ink across, in its rows: from its reading's box out to
    where the ink stops, short of its neighbours' boxes (the reading boxes
    a big word narrower than it is)."""
    top, bottom = int(e[0]), int(e[1])
    lim0 = boxes[k + 1][1] + 2 if k + 1 < len(boxes) else boxes[k][0] - 4 * core
    lim1 = boxes[k - 1][0] - 2 if k > 0 else boxes[k][1] + 4 * core
    # (Its middle rows: the line beside it is shorter than it.)
    y0, y1 = int(top + 0.15 * (bottom - top)), int(bottom - 0.15 * (bottom - top))
    cols = (grey[y0:y1, :] < 128).any(0)
    x0, x1 = int(boxes[k][0]), int(boxes[k][1])
    gap = max(3, int(0.35 * core))
    blank = 0
    while x0 - 1 > lim0 and blank <= gap:
        x0 -= 1
        blank = 0 if cols[x0] else blank + 1
    x0 += blank
    blank = 0
    while x1 + 1 < min(lim1, len(cols) - 1) and blank <= gap:
        x1 += 1
        blank = 0 if cols[x1] else blank + 1
    x1 -= blank
    return _ink_box(grey, x0, x1, bottom, bottom - top)


def _under(l, lines):
    """The lines of l's column just below it, nearest first, while each
    starts short of l's right end (a big word of l's hangs beside them)."""
    out, base = [], l['base']
    col = sorted([m for m in lines if m is not l and m.get('stream') == l.get('stream') and m['base'] > base
                  and min(m['x1'], l['x1']) - max(m['x0'], l['x0']) > 0.5 * (l['x1'] - l['x0'])], key=lambda m: m['base'])
    for m in col:
        if m['base'] - base > 1.6 * l['h'] or m['x1'] > l['x1'] - 0.6 * l['h']:
            break
        out.append(m)
        base = m['base']
    return out


def _fitted(ws, src, rs, l, core, grey, fonts, starts, sid='main', bigs=None, under=(), idx=None):
    """SVG for a line whose words were read off the scan, each word set
    over its own ink there (as an OCR layer over a scan, but drawn): its
    width the ink's, its letters the line's height, a big opening word as
    big as it stands. Words the reading missed share the ink between the
    words beside them. None where that can't be done (too little room)."""
    if not ws or len(src) != len(ws):
        return None
    # (Not a note in the gutter beside the line, read with it: outside
    # the line's own ink.)
    ink = l.get('ink') or (l['x0'], l['x1'])
    keep = [k for k, r in enumerate(src) if r is None or ink[0] - 4 <= (r['x0'] + r['x1']) / 2 <= ink[1] + 4]
    idx = [idx[k] for k in keep] if idx and len(idx) == len(ws) else [-1] * len(keep)
    ws, src = [ws[k] for k in keep], [src[k] for k in keep]
    n = len(ws)
    if not n:
        return None
    boxes, bases = [None] * n, [l['base']] * n
    for x, r in enumerate(src):
        if r is None:
            continue
        b = r.get('y1', l['base'])
        box = _ink_box(grey, r['x0'], r['x1'], b, core)
        if box:
            boxes[x], bases[x] = box, b
    if sum(b is not None for b in boxes) < 0.5 * n:
        return None
    # (Not over a big word of a line above that hangs down into this one.)
    for k, b in enumerate(boxes):
        if b is None:
            continue
        for g0, g1, t0, t1 in bigs or ():
            if t0 < bases[k] - 0.3 * core < t1 and b[0] < g1 and g0 < b[1]:
                b = (b[0], g0 - 2) if (b[0] + b[1]) / 2 < (g0 + g1) / 2 else (g1 + 2, b[1])
        boxes[k] = b if b[1] - b[0] > 2 else None
    if sum(b is not None for b in boxes) < 0.5 * n:
        return None
    gap = 0.35 * core
    x = 0
    while x < n:
        if boxes[x] is not None:
            x += 1
            continue
        q = x
        while q + 1 < n and boxes[q + 1] is None:
            q += 1
        hi = boxes[x - 1][0] - gap if x > 0 else ink[1]
        lo = boxes[q + 1][1] + gap if q + 1 < n else ink[0]
        nat = [fonts.width(ws[k][1], core / fonts.core(ws[k][1]), ws[k][0]) for k in range(x, q + 1)]
        room = hi - lo - gap * (q - x)
        if room < 0.6 * sum(nat):
            return None
        cur = hi
        for k, wd in zip(range(x, q + 1), nat):
            w = wd * room / sum(nat)
            boxes[k] = (cur - w, cur)
            bases[k] = bases[x - 1] if x > 0 else bases[q + 1] if q + 1 < n else l['base']
            cur -= w + gap
        x = q + 1
    # Boxes the reading put over each other: cut where they meet.
    for k in range(n - 1):
        if boxes[k + 1][1] > boxes[k][0]:
            m = (boxes[k + 1][1] + boxes[k][0]) / 2
            boxes[k] = (min(m + 1, boxes[k][1] - 2), boxes[k][1])
            boxes[k + 1] = (boxes[k + 1][0], max(m - 1, boxes[k + 1][0] + 2))
    # A box far wider than its word (the reading runs a line's last word
    # out to the column's edge, over a gutter's ornament or mark): the word
    # is the ink from its start, the box's right end, up to the first
    # blank as wide as a word space. (Not a big opening word.)
    for k in range(1, n):
        if src[k] is None or ws[k - 1][0].rstrip().endswith((':', '.')):
            continue
        lo, hi = fonts.ink(ws[k][1], ws[k][0])
        nat = (hi - lo) * core / fonts.core(ws[k][1])
        x0, x1 = boxes[k]
        if x1 - x0 < 1.5 * nat:
            continue
        a = grey[int(bases[k] - core):int(bases[k]) + 1, int(x0):int(x1) + 1] < 128
        cols = a.any(0)
        end, blank = len(cols) - 1, 0
        for c in range(len(cols) - 1, -1, -1):
            if cols[c]:
                end, blank = c, 0
            else:
                blank += 1
                if blank >= 0.45 * core and x1 - (x0 + end) >= 0.6 * nat:
                    break
        if x1 - (x0 + end) >= 0.6 * nat:
            boxes[k] = (x0 + end, x1)
    # The line's baseline as its words stand on the scan: the foot of their
    # letters' bodies (the reading's can be off where a big word is in the
    # line, or the line slopes).
    feet = []
    for k in range(n):
        x0, x1 = boxes[k]
        inset = 0.15 * (x1 - x0)
        t, bottom = _tall(grey, x0 + inset, x1 - inset, bases[k], core)
        if 0.6 * core <= t <= 1.4 * core:
            feet.append(bottom)
    base_line = float(np.median(feet)) if len(feet) >= 2 else float(np.median(bases))
    if abs(base_line - np.median(bases)) > 0.6 * core:
        base_line = float(np.median(bases))
    bases = [base_line] * n
    # Big words: as they stand on the scan, only where a section opens
    # (the line's first word, one after a colon or period, a label, a
    # Tosafot comment's first word set in square letters).
    # (Told by its thick strokes' height against the line's other words',
    # not a lamed's stem; its box is all its ink.)
    talls = []
    for k in range(n):
        x0, x1 = boxes[k]
        inset = 0.15 * (x1 - x0)
        talls.append(_tall(grey, x0 + inset, x1 - inset, bases[k], core)[0])
    med = float(np.median([t for t in talls if t])) if any(talls) else core
    # Each word as big as the line's letters, all squeezed alike if they
    # must be to fit the line, each as near where it stands on the scan as
    # its neighbours leave room for, a word space at least between them:
    # no word stretched, none over another.
    big = []
    for k, w in enumerate(ws):
        # (Rashi's comments open in his own small letters: there only a
        # label is big; Tosafot's open with a big word.)
        if sid == 'inner':
            opens = _label(w[0]) and (k == 0 or ws[k - 1][0].rstrip().endswith((':', '.')))
        else:
            opens = k == 0 and starts or k > 0 and ws[k - 1][0].rstrip().endswith((':', '.')) or len(w) > 2
        e = None
        # (Big: its ink taller than the line's letters and wider than the
        # word set at their size; thick strokes alone miss a big letter's
        # thin middle.)
        lo_, hi_ = fonts.ink(w[1], w[0])
        wide = (boxes[k][1] - boxes[k][0]) > 1.3 * (hi_ - lo_) * core / fonts.core(w[1])
        # (Where the text says it opens a section in big letters, a Tosafot
        # comment's first word, a label, it is; its ink says how big.)
        if opens and (talls[k] > 1.3 * med or wide or len(w) > 2) and len(_fold(w[0])) >= 2:
            # (All its ink's rows, a big letter's thin strokes too; up to a
            # line's height above its line and no lower than its baseline
            # unless it hangs, as a chapter's first word does, down past a
            # line or more.)
            # (Across all of it: a final nun or kuf hangs at its end.)
            e = _extent(grey, boxes[k][0], boxes[k][1], base_line, core)
            if e:
                top = max(e[0], base_line - 3.6 * core)
                # (It hangs into the lines below it that start short of it,
                # as a big opening word does; down to the last of them.)
                bx = _big_box(grey, boxes, k, (top, e[1]), core) or boxes[k]
                deep = [m['base'] for m in under if m['x1'] < bx[0] + 0.3 * (bx[1] - bx[0])]
                if k == 0 and deep and e[1] > base_line + 0.6 * core:
                    bottom = min(e[1], max(deep) + 0.25 * core)
                else:
                    bottom = min(e[1], base_line + 0.25 * core)
                e = (top, bottom) if bottom - top > 1.2 * core else None
        big.append(e)
    nat = []
    for k, w in enumerate(ws):
        if big[k]:
            box = _big_box(grey, boxes, k, big[k], core) or boxes[k]
            boxes[k] = box
            nat.append(box[1] - box[0])
        else:
            lo, hi = fonts.ink(w[1], w[0])
            nat.append((hi - lo) * core / fonts.core(w[1]))
    if PLACE == 'justify':
        # Justified as the print is: from the line's first ink to its last,
        # every word at its letters' width, the spaces alike; a short line (a
        # comment's last) at a word space from its right end. All narrowed
        # alike where they don't fit.
        span = (min(ink[0], boxes[-1][0]), max(ink[1], boxes[0][1]))
        # (A word space as wide as the print's least: letters narrowed before
        # the spaces close up.)
        g = 0.45 * core
        fixed = sum(nat[k] for k in range(n) if big[k])
        free = sum(nat[k] for k in range(n) if not big[k])
        room = span[1] - span[0]
        sq = 1.0
        if free and fixed + free + g * (n - 1) > room:
            sq = max(0.5, (room - fixed - g * (n - 1)) / free)
        wd = [nat[k] if big[k] else nat[k] * sq for k in range(n)]
        gap = (room - sum(wd)) / (n - 1) if n > 1 else 0
        ragged = n > 1 and gap > 3 * core and boxes[-1][0] - ink[0] > 2 * core
        if ragged or n == 1:
            gap = 0.45 * core
        gap = max(gap, g)
        x1, cur = [], span[1]
        for k in range(n):
            x1.append(cur)
            cur -= wd[k] + gap
    else:
        span = (min(ink[0], min(b[0] for b in boxes)), max(ink[1], max(b[1] for b in boxes)))
        g = 0.25 * core
        # Each word centred on its box, as wide as the box but never wider
        # than its own letters or narrower than 0.7 of them; then pushed apart
        # where two would touch, and all narrowed alike if the line can't hold
        # them.
        cen = [(b[0] + b[1]) / 2 for b in boxes]
        want_w = [nat[k] if big[k] else min(nat[k], max(0.7 * nat[k], boxes[k][1] - boxes[k][0])) for k in range(n)]
        shrink = 1.0
        for _ in range(15):
            wd = [want_w[k] if big[k] else want_w[k] * shrink for k in range(n)]
            x1 = [min(span[1], cen[k] + wd[k] / 2) for k in range(n)]
            for k in range(1, n):
                x1[k] = min(x1[k], x1[k - 1] - wd[k - 1] - g)
            over = span[0] - (x1[-1] - wd[-1])
            if over > 0:
                x1[-1] += over
                for k in range(n - 2, -1, -1):
                    x1[k] = max(x1[k], x1[k + 1] + g + wd[k])
            if x1[0] <= span[1] + 1 and x1[-1] - wd[-1] >= span[0] - 1:
                break
            shrink *= 0.95
    out = []
    for k, w in enumerate(ws):
        a0, a1 = x1[k] - wd[k], x1[k]
        if big[k] and bigs is not None:
            bigs.append((a0, a1, big[k][0], big[k][1]))
        fonts.tag = (sid, idx[k], bool(big[k]))
        if big[k]:
            out.append(fonts.fit_box(SQUARE, w[0], a0, a1, big[k][0], big[k][1]))
        else:
            out.append(fonts.fit(w[1], w[0], a0, a1, bases[k], core))
    return ''.join(out)


def _catch_ink(grey, last, lines, core):
    """The ink of a column's catchword under its last line `last`: a short
    word at the line's left end, a line's height below it (often smaller
    than the column's letters; a commentary's line can run on beside or
    under it). (x0, x1, top, bottom) or None."""
    w = last['x1'] - last['x0']
    y0, y1 = int(last['base'] + 0.25 * core), int(last['base'] + 3.4 * core)
    x0, x1 = int(last['x0']), int(last['x0'] + 0.45 * w)
    a = grey[max(0, y0):y1, max(0, x0):x1] < 128
    if not a.size:
        return None

    def first_part(m):
        """The leftmost stretch of ink across, its letters no further apart
        than a word's: (start, end) or None."""
        cols = np.flatnonzero(m.sum(0) >= 1)
        if not len(cols):
            return None
        parts = np.split(cols, np.flatnonzero(np.diff(cols) > 0.8 * core) + 1)
        part = next((q for q in parts if q[-1] - q[0] >= 0.5 * core), None)
        return (part[0], part[-1] + 1) if part is not None else None
    # Its rows: the first run of ink rows over the leftmost ink, a word's
    # height (not the descenders of the line above, nor two lines run
    # together).
    p = first_part(a)
    if p is None:
        return None
    # (In a strip at its left end: it starts flush with the column, where
    # a line under it, or the line above's descenders, mostly don't reach.)
    strip = a[:, p[0]:min(p[1], p[0] + int(2.5 * core))]
    rows = np.flatnonzero(strip.sum(1) >= 2)
    runs = np.split(rows, np.flatnonzero(np.diff(rows) > 1) + 1) if len(rows) else []
    band = next((r for r in runs if 0.45 * core <= len(r) <= 2.2 * core and r[0] > 0), None)
    if band is None:
        return None
    p = first_part(a[band[0]:band[-1] + 1])
    if p is None:
        return None
    cx0, cx1 = max(0, x0) + p[0], max(0, x0) + p[1]
    if cx1 - cx0 > 0.4 * w or cx1 - cx0 < 0.7 * core or cx0 < last['x0'] - 4:
        return None
    top, bottom = max(0, y0) + band[0], max(0, y0) + band[-1] + 1
    # (Not a line of text there, a word or two of which this is.)
    if any(m is not last and m.get('stream') is not None and len(m['text'].split()) > 2
           and top - 0.3 * core < m['base'] < bottom + 0.5 * core and m['x0'] < cx1 and cx0 < m['x1'] for m in lines):
        return None
    return cx0, cx1, top, bottom


def placement(fonts, size, counts, **more):
    """The app's page (daf/v2): every word set, in scan pixels, as
    [column, word number, font, text, left, baseline, sx, sy(, 1 if big)]:
    column m/i/o for the Gemara, Rashi and Tosafot ('' for the running head,
    catchwords, the page number), the word's number among the app's words
    of its column (-1 where it is none of them, as read off the scan), font
    0 square or 1 Rashi script, the left end of its advance, sx and sy the
    pixels per em across and up. `frame` is the ink's extent."""
    out, xs, ys = [], [], []
    for col, k, font, word, left, base, sx, sy, *big in fonts.placed:
        c = {'main': 'm', 'inner': 'i', 'outer': 'o'}.get(col.split('_')[0] if not col.startswith('catch') else '', '')
        if '_' in col:
            k = -1  # (a comment carried from the amud before or after)
        out.append([c, k, font, word, left, base, sx, sy, *big])
        xs += [left, left + fonts.width(RASHI if font else SQUARE, 1, word) * sx]
        ys += [base - 1.1 * sy, base + 0.35 * sy]
    frame = [round(v) for v in (min(xs), min(ys), max(xs), max(ys))] if out else [0, 0, size[0], size[1]]
    return dict(v=2, **more, size=list(size), frame=frame, words=counts, weight=RASHI_WEIGHT / 1000, placed=out)


# The last page amud_svg set, as placement() gives it.
LAST_PLACED = None


def amud_svg(cache, book, amud, scan=False, core=False, lines_out=None):
    global LAST_PLACED
    lines = [] if lines_out is None else lines_out
    text = textpass.amud_text(cache, book, amud, lines_out=lines)
    streams, extra = linemap.texts(cache, book, amud)
    words = {**extra, **streams}
    flags = dict(zip(('inner', 'outer'), _flags(cache, book, amud)))
    for sid in ('inner', 'outer'):
        if len(flags[sid]) != len(streams[sid]):
            flags[sid] = []
    img_path, _ = linemap.ocr(cache, book, amud)
    w, h = Image.open(img_path).size
    fonts = Fonts()

    main_h = float(np.median([l['h'] for l in lines if l.get('stream') == 'main'] or [20]))
    rashi_h = float(np.median([l['h'] for l in lines if l.get('stream') in ('inner', 'outer')] or [14]))
    grey = np.asarray(linemap.page_image(img_path).convert('L'), dtype=np.int16)
    rc = [c for c in (_core(grey, l['x0'], l['x1'], l['base'], l['h']) for l in lines
                      if l.get('stream') in ('inner', 'outer') and 'range' in l) if c]
    rashi_core = float(np.median(rc)) if rc else None
    # The height of each column's letters' bodies on the scan.
    core_of = {}
    for sid in words:
        cs = [c for c in (_tall(grey, l['x0'], l['x1'], l['base'], l['h'] / 1.3)[0] for l in lines
                          if l.get('stream') == sid and 'range' in l) if c]
        core_of[sid] = float(np.median(cs)) if cs else (rashi_core if sid != 'main' and rashi_core else 0.75 * main_h)
    rashi_pitch = _pitch([(l['x0'], l['x1'], l['base']) for l in lines if l.get('stream') in ('inner', 'outer') and 'range' in l])
    placed, body = [], []

    def free(box):
        """Not over a line set already."""
        for b in placed:
            ix = min(b[2], box[2]) - max(b[0], box[0])
            iy = min(b[3], box[3]) - max(b[1], box[1])
            if ix > 0 and iy > 0 and ix * iy > 0.3 * min((b[2] - b[0]) * (b[3] - b[1]), (box[2] - box[0]) * (box[3] - box[1])):
                return False
        return True

    def put(x0, x1, base, size, ws, boxes=None, justify=True, check=True, tags=None):
        """A line: its words at `boxes` ([x0, x1] each, from the scan) when
        there are as many as words, else justified from x0 to x1."""
        core = [x0, base - 0.7 * size, x1, base]  # its letters, not its neighbors'
        if check and not free(core):
            return
        placed.append(core)
        # Smaller, not squeezed, where the print sets it smaller than its
        # column's size (the notes, the foot's small type): a tenth's
        # squeeze at most.
        if tags and len(tags) == len(ws):
            tags = [g for t, g in zip(ws, tags) if t[0]]
        ws = [t for t in ws if t[0]]
        if boxes and len(boxes) == len(ws):
            nat = sum(fonts.width(t[1], size * EM[t[1]], t[0]) for t in ws)
            room = sum(max(0, b - a) for a, b in boxes)
        else:
            nat = sum(fonts.width(t[1], size * EM[t[1]] * (t[2] if len(t) > 2 else 1), t[0]) for t in ws) + 0.28 * size * (len(ws) - 1)
            room = x1 - x0
        if ws and room > 0 and nat > 1.1 * room:
            size *= 1.1 * room / nat
        if boxes and len(boxes) == len(ws):
            body.append(_place(ws, boxes, base, size, fonts, tags))
        else:
            body.append(_set(ws, x0, x1, base, size, fonts, justify, tags))
        fonts.tag = None

    # Sefaria's words first: the lines the line map matched, each column in
    # its own size.
    size_of = {}
    for sid in words:
        hs = [l['h'] for l in lines if l.get('stream') == sid and 'range' in l]
        size_of[sid] = float(np.median(hs)) if hs else rashi_h
    line_h = size_of
    # (The body's: the small commentaries come from the margins' reading
    # below, all of a column from one source in one size.)
    tractate = linemap.he_names(cache, book)[:1]
    # A column's last words the line map placed nowhere, where the line
    # under its last one is one it left unclaimed, as tall and wide: that
    # line's.
    for sid in ('main', 'inner', 'outer'):
        col = [l for l in lines if l.get('stream') == sid and 'range' in l and l.get('score', 100) >= 50]
        if not col:
            continue
        last = max(col, key=lambda l: l['range'][1])
        end = last['range'][1]
        if end >= len(words[sid]) or last is not max(col, key=lambda l: l['base']):
            continue
        below = [l for l in lines if l.get('stream') in (None, 'other') and not l.get('catchword')
                 and 0.6 * last['h'] < l['base'] - last['base'] < 1.8 * last['h'] and abs(l['h'] - last['h']) < 0.3 * last['h']
                 and min(l['x1'], last['x1']) - max(l['x0'], last['x0']) > 0.7 * (last['x1'] - last['x0'])]
        if len(below) == 1:
            l = below[0]
            l.update(stream=sid, range=(end, min(len(words[sid]), end + len(l['text'].split()) + 3)), score=60, tail=True)
    ranked = sorted([l for l in lines if l.get('stream') in linemap.BODY and l['stream'] in words and 'range' in l
                     and l.get('score', 100) >= 50], key=lambda l: l['stream'] != 'main')
    bigs = []
    for l in sorted(ranked, key=lambda l: l['base']):
        a, b = l['range']
        sid = l['stream']
        ix = []
        # (A chapter's closing line on its own; in a commentary it can end
        # a line of the comment, set as the rest of it.)
        heading = (_hadran(l['text']) or _hadran(' '.join(words[sid][a:b]))) and b - a <= 7
        if heading:
            # Its words as the text has them: big letters read badly.
            ws = [(linemap.print_text(t).rstrip(':'), SQUARE) for t in words[sid][a:b]]
            ix = list(range(a, b))
        elif l.get('seg') and l['words']:
            # Read on its own off the scan: the print's words, in its order;
            # a big opening word as big as it stands.
            l['words'] = _unstack(l['words'])
            for wd in l['words']:
                wd['scale'], wd['drop'] = 1, 0
            big = _opening(grey, l, size_of[sid], sid, heading, _starts(words[sid], flags.get(sid) or [], sid, a))
            if big:
                l['words'][0]['scale'], l['words'][0]['drop'] = big
            if l.get('more'):
                # Runs of the text in the print's order: just those words.
                toks = [t for c, d in [(a, b)] + l['more'] for t in _tokens(words[sid], c, d, sid, flags.get(sid) or [], (c, d), tractate)]
            else:
                toks = _tokens(words[sid], a - 4, b + 4, sid, flags.get(sid) or [], (a, b), tractate)
            src = []
            ws = _from_read(l['words'], toks, sid, l.get('ink'), src, ix)
            if FIT:
                fitted = _fitted(ws, src, [w for w in l['words'] if w['text'].strip()], l, core_of[sid], grey, fonts,
                                 _starts(words[sid], flags.get(sid) or [], sid, a), sid, bigs,
                                 _under(l, ranked), ix)
                fonts.tag = None
                if fitted:
                    body.append(fitted)
                    placed.append([l['x0'], l['base'] - 0.7 * size_of[sid], l['x1'], l['base']])
                    continue
        else:
            ws = []
            for c, d in [(a, b)] + l.get('more', []):
                k = []
                ws += _print_words(words[sid], c, d, sid, flags.get(sid) or [], k)
                ix += k
            own = linemap.fold((l['text'].split() or [''])[0], linemap.FOLD_SQUARE)
            label = ws and linemap.fold(ws[0][0], linemap.FOLD_SQUARE) in ('מתני', 'גמ') and own not in ('מתני', 'גמ')
            if label:
                ws, ix = ws[1:], ix[1:]  # Sefaria's label where the print has a big opening word
            if ws and len(ws[0][0]) >= 2 and l.get('words'):
                # A big opening word, as big as it stands on the scan (a
                # little bigger is enough where a section opens).
                got = sorted(l['words'], key=lambda w: -w['x1'])
                big = _opening(grey, dict(l, words=got), size_of[sid], sid, heading,
                               _starts(words[sid], flags.get(sid) or [], sid, a), 1.15 if label else 1.3)
                if big and len(ws[0]) < 3:
                    ws[0] = (ws[0][0], SQUARE) + big
        # A chapter's closing line (הדרן עלך) is set whole over its ink.
        if heading and FIT:
            ib = _ink_box(grey, l['x0'], l['x1'], l['base'], l['h'] / 1.3)
            e = ib and _extent(grey, ib[0] + 0.3 * (ib[1] - ib[0]), ib[1] - 0.3 * (ib[1] - ib[0]), l['base'], l['h'] / 1.3)
            if ib and e:
                fonts.tag = (sid, a, True)
                body.append(fonts.fit_box(SQUARE, ' '.join(t for t, *_ in ws), ib[0], ib[1], e[0], e[1]))
                fonts.tag = None
                placed.append([ib[0], e[0], ib[1], e[1]])
                continue
        size = size_of[sid] * min(1.6, l['h'] / line_h[sid]) if heading and l['h'] > 1.2 * line_h[sid] else size_of[sid]
        put(l['x0'], l['x1'], l['base'], size, ws, check=False,
            tags=[(sid, k, len(t) > 2 and t[2] > 1) for t, k in zip(ws, ix)] if len(ix) == len(ws) else None)

    # The margins' small commentaries, as the Vilna model read them, each
    # word where it is on the scan; each section in one size, under its
    # heading as printed.
    tops = {}
    for m in [] if core else text['margins']:
        hs = [(x['box'][3] - 1 - x['box'][1]) / 1.6 for x in m['lines']]
        mh = float(np.median(hs)) if hs else rashi_h
        # Small type's word boxes say little of its size: the height of its
        # letters on the scan, as Rashi's lines measure against theirs.
        cores = [c for c in (_core(grey, x['box'][0], x['box'][2], x.get('base', 0), (x['box'][3] - 1 - x['box'][1]) / 1.6)
                             for x in m['lines'] if 'base' in x) if c]
        if len(cores) >= 3 and rashi_core:
            mh = rashi_h * float(np.median(cores)) / rashi_core
        # Nor bigger than its line spacing allows, as Rashi's is to his size.
        p = _pitch([(x['box'][0], x['box'][2], x['base']) for x in m['lines'] if 'base' in x])
        if p and rashi_pitch:
            mh = min(mh, rashi_h * p / rashi_pitch)
        # No bigger than sets its words a little wider than they are on
        # the scan (a dense column can read as taller than it is).
        fit = [(x1 - x0) / fonts.width(RASHI, mh * EM[RASHI], t) for x in m['lines'] for t, x0, x1 in x.get('words') or []
               if len(t) >= 3 and x1 > x0]
        if len(fit) >= 5:
            mh *= min(1.0, 1.25 * float(np.median(fit)))
        if m.get('heading'):
            hl = m['heading']
            if len(hl) == 2 and abs(hl[0]['box'][3] - hl[1]['box'][3]) < 0.5 * (hl[0]['box'][3] - hl[0]['box'][1]):
                # Both pieces on one line: one heading across them.
                b0, b1 = hl[0]['box'], hl[1]['box']
                hl = [dict(box=[min(b0[0], b1[0]), min(b0[1], b1[1]), max(b0[2], b1[2]), max(b0[3], b1[3])], text=m['section'])]
            canon = m['section'].split()
            n = len(hl[0]['text'].split()) if len(hl) == 2 else len(canon)
            n = min(max(n, 1), len(canon) - (len(hl) == 2))
            parts = [canon[:n], canon[n:]] if len(hl) == 2 else [canon]
            for x, part in zip(hl, parts):
                bx = x['box']
                hh = min((bx[3] - 1 - bx[1]) / 1.6, 1.6 * mh)
                base = bx[1] + 1.25 * (bx[3] - 1 - bx[1]) / 1.6
                if free([bx[0], base - 0.7 * hh, bx[2], base]):
                    placed.append([bx[0], base - 0.7 * hh, bx[2], base])
                    body.append(_centered(' '.join(part), bx[0], bx[2], base, hh, fonts))
            # The printed ornament between sections.
            bx = hl[0]['box']
            above = tops.get(m['side'])
            if above is not None and bx[1] - above > 8:
                y = (above + bx[1] + 6) / 2
                cx, half = (bx[0] + bx[2]) / 2, min(60, 2.5 * (bx[2] - bx[0]))
                body.append(f'<path d="M{cx - half:.0f} {y:.0f}H{cx + half:.0f}M{cx - 5:.0f} {y:.0f}l5 -4l5 4l-5 4z" stroke="#111" fill="#111" stroke-width="1.2"/>')
        for x, lh in zip(m['lines'], hs):
            bx = x['box']
            if any(c.get('catchword') and c['x0'] < bx[2] and bx[0] < c['x1'] and bx[1] < c['base'] < bx[3] + 0.5 * c['h'] for c in lines):
                continue  # a column's catchword, set with the body
            f = SQUARE if lh > 1.25 * mh else RASHI
            ws = [[t, x0, x1] for t, x0, x1 in x.get('words') or [[t, 0, 0] for t in x['text'].split()]]
            put(bx[0] + 4, bx[2] - 4, x.get('base', bx[1] + 1.25 * lh), mh, [(t, f) for t, _, _ in ws], justify=len(ws) > 3)
        if m['lines']:
            tops[m['side']] = max(x['box'][3] for x in m['lines'])

    # Each column's catchword, the next amud's first word, under its last
    # line, over its ink: where the reading found it, else where ink is.
    nxt = linemap.neighbor(amud, 1)
    try:
        heads_next = linemap.texts(cache, book, nxt)[0] if nxt else {}
    except SystemExit:
        heads_next = {}
    caught, catches = set(), []
    for sid in ('main', 'inner', 'outer'):
        col = [l for l in ranked if l['stream'] == sid]
        nw = heads_next.get(sid) or []
        if not col or not nw:
            continue
        # (Of its own size: a footnote line the reading gave its words to
        # isn't it.)
        mh = float(np.median([l['h'] for l in col]))
        col = [l for l in col if abs(l['h'] - mh) < 0.25 * mh] or col
        last = max(col, key=lambda l: (l['range'][1], l['base']))
        # (Or a line of the column under it the map matched no text to,
        # drawn as read.)
        low = [l for l in lines if l.get('stream') == sid and 'range' not in l and l['base'] > last['base']
               and abs(l['h'] - mh) < 0.25 * mh and l['base'] - last['base'] < 3 * mh
               and min(l['x1'], last['x1']) - max(l['x0'], last['x0']) > 0]
        if low:
            last = max(low, key=lambda l: l['base'])
        found = [l for l in lines if l.get('catchword') == sid]
        if not found and low and len(last['text'].split()) <= 2 and fuzz.ratio(_fold(last['text']), _fold(linemap.print_text(nw[0]))) >= 60:
            # (Read as a line of the column's own, under its last.)
            found, last = [last], max(col, key=lambda l: (l['range'][1], l['base']))
        c = core_of.get(sid) or 0.75 * main_h
        box = None
        if found:
            l = found[0]
            caught.add(id(l))
            ib = _ink_box(grey, l['x0'], l['x1'], l['base'], c)
            e = ib and _extent(grey, ib[0], ib[1], l['base'], c)
            if ib and e:
                box = (ib[0], ib[1], e[0], e[1])
        else:
            box = _catch_ink(grey, last, lines, c)
        if box:
            word = linemap.print_text(nw[0])
            fonts.tag = ('catch_' + sid, -1, False)
            catches.append(sid)
            body.append(fonts.fit_box(SQUARE if sid == 'main' else RASHI, word, *box))
            placed.append([box[0], box[2], box[1], box[3]])
            fonts.tag = None

    # The rest (the running head, big opening words, lines Sefaria lacks):
    # the line's own reading, each word where it is.
    main = [l for l in lines if l.get('stream') == 'main' and 'range' in l]
    names = [n for n in linemap.he_names(cache, book) if ' ' not in n and '"' not in n]
    head = min([l['base'] - 1.5 * l['h'] for l in lines if l.get('stream') in words and 'range' in l] or [0])
    # The page number: a big letter or two in the running head, at its outer
    # end (the left of an a-side).
    nums = [l for l in lines if l['base'] < head and l['h'] > 1.2 * main_h and l.get('letters', 99) <= 2]
    # (Only an a-side has one; a b-side's head has the reprint's own page
    # number in digits, no part of the Vilna page.)
    number = min(nums, key=lambda l: l['x0']) if nums and amud.endswith('a') else None
    # The running head itself, as the text's chapter and name, where the
    # print has its words.
    ranged = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]
    bx0, bx1 = min([l['x0'] for l in ranged] or [0]), max([l['x1'] for l in ranged] or [w])
    pieces = [l for l in lines if l['base'] < head and l is not number and l['h'] > 1.2 * main_h
              and bx0 <= (l['x0'] + l['x1']) / 2 <= bx1]
    fonts.tag = ('head', -1, False)
    set_head = _running_head(_head_words(cache, book, amud), pieces, fonts, grey)
    fonts.tag = None
    if set_head:
        body += set_head
    for l in lines:
        if set_head and l in pieces or l['base'] < head and l['text'].strip().isdigit():
            continue
        if l.get('read'):
            ws, boxes = [w[0] for w in l['read']], [[w[1], w[2]] for w in l['read']]
        else:
            got = sorted([w for w in l.get('words') or [] if w['text'].strip()], key=lambda w: -w['x1'])
            ws, boxes = [w['text'].strip() for w in got], [[w['x0'], w['x1']] for w in got]
        if l['base'] < head and len(ws) == 1:
            # The tractate's name in the running head, as Sefaria spells it.
            best = max(names, key=lambda n: fuzz.ratio(n, ws[0]), default=None)
            if best and fuzz.ratio(best, ws[0]) >= 60:
                ws, boxes = [best], None
        if l.get('catch_text'):
            ws, boxes = [l['catch_text']], None  # the next amud's first word, as Sefaria spells it
        if l is number:
            ws = [_numeral(int(amud[:-1]))]  # the page number, by the amud's own
            boxes = None
        # (One letter alone: a speck.)
        elif not ws or l.get('letters', 99) < 2:
            continue
        sid = l.get('stream')
        if sid in linemap.BODY and 'range' in l and l in ranked or id(l) in caught or l.get('catchword'):
            continue  # set above
        own = _column_of(l, lines) if l['base'] >= head else None
        if own:
            sid = own  # a line of a body text that Sefaria lacks, as read
        if core and not own and not l.get('catchword') and not _hadran(l['text']) and (
                l['base'] >= head and sid not in linemap.BODY
                or l['base'] < head and l is not number and (not bx0 <= (l['x0'] + l['x1']) / 2 <= bx1 or linemap._heading(l['text'])
                                                              or set_head and l not in pieces)):
            continue  # only the body's lines, their catchwords and headings, the running head and number
        cx = (l['x0'] + l['x1']) / 2
        if sid not in words and l['h'] < 0.75 * rashi_h and any(
                abs(m['base'] - l['base']) < 3 * main_h and m['x0'] < cx < m['x1'] for m in main):
            continue  # specks and stray marks among the Gemara's lines
        f = SQUARE if sid == 'main' or l.get('catchword') == 'main' or l['h'] > 1.25 * rashi_h and not l.get('catchword') else RASHI
        size = size_of[sid] if sid in size_of and l['h'] < 1.5 * size_of[sid] else l['h']
        put(l['x0'], l['x1'], l['base'], size, [(x, f) for x in ws], boxes,
            tags=[(sid if own or sid in linemap.BODY and l['base'] >= head else 'head' if l['base'] < head else '', -1, False)] * len(ws))

    # (`catch`: the columns whose catchword was found, for shas.py's scores.)
    LAST_PLACED = placement(fonts, (w, h), {sid: len(streams[sid]) for sid in ('main', 'inner', 'outer')},
                            book=book, amud=amud, catch=catches)
    under = ''
    if scan:
        data = base64.b64encode(Path(img_path).read_bytes()).decode()
        under = f'<image xlink:href="data:image/jpeg;base64,{data}" width="{w}" height="{h}" opacity="0.35"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" '
            f'viewBox="0 0 {w} {h}" width="{w}" height="{h}" style="background:#ffffff">{fonts.svg_defs()}'
            f'<rect x="0" y="0" width="{w}" height="{h}" fill="#ffffff"/>{under}<g fill="#111111">'
            + '\n'.join(body) + '</g></svg>')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+', help='amudim, or ranges like 2a-10b')
    p.add_argument('--cache', default='build/daf_cache')
    p.add_argument('--out', default='build/daf_svg')
    p.add_argument('--scan', action='store_true', help='lay the scan faintly under the text')
    p.add_argument('--core', action='store_true', help='only the Gemara, Rashi and Tosafot (and the running head)')
    p.add_argument('--place', action='store_true', help="also write the app's placed words (placement()) beside each SVG")
    p.add_argument('--stats', action='store_true', help='list the body words set that Sefaria has none like')
    a = p.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for amud in linemap.amudim(a.amudim):
        path = out / f'{a.book.replace(" ", "_")}_{amud}{".scan" if a.scan else ""}{".core" if a.core else ""}.svg'
        for v in STATS.values():
            v.clear()
        path.write_text(amud_svg(Path(a.cache), a.book, amud, a.scan, a.core))
        if a.place:
            path.with_suffix('.json').write_text(json.dumps(LAST_PLACED, ensure_ascii=False, separators=(',', ':')))
        print(path)
        if a.stats:
            for k, v in STATS.items():
                print(f'  {k} {len(v)}:', ' '.join(v))


if __name__ == '__main__':
    sys.exit(main())
