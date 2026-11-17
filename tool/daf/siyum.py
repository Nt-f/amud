#!/usr/bin/env python3
"""The siyum at a tractate's end: the block the print sets under the last
amud's text (הדרן, יהי רצון, the sons of Rav Papa, Kaddish, and in some
printings a gloss in Rashi script), in no text Sefaria has. Its text is
read over on the scans: tool/daf/siyum_proof.json holds it whole, one text
per printing, with the words the printings set differently as
alternatives. Each row of a page is drawn from the span of those texts its
reading matches, the printing and the span's ends where the line reader's
loss on the row is least, and only where that loss says the words are
the row's (or its neighbours' drawn spans fix them); the words go where
the reader puts them, big opening words read on their own boxes.

Runs in kraken's venv:

    build/daf/kraken-venv/bin/python tool/daf/siyum.py MODEL PLACE_DIR OUT_DIR --lines DIR [--lines2 DIR]

Writes OUT_DIR/<name>.json for every amud of PLACE_DIR (the siyum's rows
put in place of what was drawn there as read), and a report of every row
(--text): its box, readings, span and what became of it (`tried`).
SIYUM_DEBUG=1 says why, row by row.
"""

import argparse
import difflib
import json
import os
import re
import shutil
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
START = 'אחר השלמת המסכת יאמר זה ויועיל לזכרון בעזרת השם יתברך'
GLOSS = 'פירוש הגון על זה תמצא בספר החיים שחבר אחי הגאון מהרל מפראג בספר זכיות חא פג בסיומא דסוף תשובת הרמא זל וכן בסוף ספר ים של שלמה בבק כתוב רמזים על הזכרת שמות הללו'
NAME = 'ץץץ'
MAX_LOSS = 0.4
SOFT_LOSS = 1.0  # a pale or blurred row: passes if its readings agree word by word (seen())
WIDE = 0.54  # a wide letter's height (ה, ב, מ) in the square font, per em


def _t(s):
    return re.sub(r'[^א-ת ]', '', s or '')


def block(lines, ink):
    """The siyum's rows on an amud (its line map's lines; the scan's ink),
    top to bottom: each a box (x0, x1, base, h) with the OCR's reading of
    it. (None where the amud has no siyum.)"""
    import numpy as np
    from scipy import ndimage
    from rapidfuzz import fuzz
    L = sorted(lines, key=lambda l: l['base'])
    s = [l for l in L if len(_t(l.get('text')).replace(' ', '')) >= 15
         and fuzz.partial_ratio('אחר השלמת המסכת יאמר זה', _t(l.get('text'))) > 85]
    if not s:
        # (A heading misread: the line above the tractate's hadran, or that
        # line itself; not a chapter's hadran, which goes on וסליקא לה.)
        hd = [l for l in L if len(_t(l.get('text')).replace(' ', '')) >= 10
              and fuzz.partial_ratio('עלך מסכת', _t(l.get('text'))) > 80
              and 'סליקא' not in _t(l.get('text')) and fuzz.partial_ratio('והדרך עלן דעתן עלך', _t(l.get('text'))) > 75]
        if not hd:
            return []
        above = [l for l in L if hd[0]['base'] - 4.5 * hd[0]['h'] < l['base'] < hd[0]['base'] - 0.5 * hd[0]['h']
                 and fuzz.partial_ratio(START, _t(l.get('text'))) > 60 and len(_t(l.get('text')).replace(' ', '')) >= 6]
        s = above[:1] or hd[:1]
    # (Down from there while the rows are a row apart.)
    ls = [s[0]]
    for l in L:
        if l['base'] > ls[-1]['base'] + 4.5 * s[0]['h']:
            if l['base'] > s[0]['base']:
                break
            continue
        if l['base'] > s[0]['base'] and len(_t(l.get('text')).replace(' ', '')) >= 2:
            ls.append(l)
    # (To the Kaddish's last words, full or cut short: the text after it is
    # another's, a note's or the next tractate's.)
    end = [l for l in ls if 'עושה שלום' in _t(l.get('text'))]
    if end:
        last = stop_ = end[-1]['base']
        ls = [l for l in ls if l['base'] <= stop_ + 3]
        # (And the gloss on the sons of Rav Papa some printings set under
        # it, in Rashi script: its lines, a row or so apart.)
        for l in L:
            if stop_ + 3 < l['base'] <= last + 3 * s[0]['h'] and fuzz.partial_ratio(_t(l.get('text')), GLOSS) > 70 \
                    and len(_t(l.get('text')).replace(' ', '')) >= 6:
                ls.append(l)
                last = max(last, l['base'])
    else:
        ls = ls[:200]
    # (The siyum's column: where its full lines start and end. A gloss in a
    # narrow column beside it, on its rows' lines, is no part of its rows.)
    W = max(l['x1'] - l['x0'] for l in ls)
    full = [l for l in ls if l['x1'] - l['x0'] > 0.6 * W]
    hm = statistics.median(l['h'] for l in ls)
    c0, c1 = min(l['x0'] for l in full), max(l['x1'] for l in full)
    side = [l for l in ls if not c0 - hm <= (l['x0'] + l['x1']) / 2 <= c1 + hm]
    ls = [l for l in ls if c0 - hm <= (l['x0'] + l['x1']) / 2 <= c1 + hm]
    h = statistics.median(l['h'] for l in ls)
    X0, X1 = int(min(l['x0'] for l in ls)) - 5, int(max(l['x1'] for l in ls)) + 5
    Y0, Y1 = int(ls[0]['base'] - 1.5 * h), int(ls[-1]['base'] + 0.6 * h)
    lab, _ = ndimage.label(ink[Y0:Y1, X0:X1])
    objs = [o for o in ndimage.find_objects(lab) if o is not None]
    hs = [o[0].stop - o[0].start for o in objs if o[1].stop - o[1].start > 2]
    mh = statistics.median(hs) if hs else h
    rows = []
    for l in ls:
        if rows and l['base'] - rows[-1][-1]['base'] < 0.45 * h:
            rows[-1].append(l)
        else:
            rows.append([l])
    out = []
    for r in rows:
        # (Its baseline and height the widest line's: a big opening word's
        # pieces read as lines of their own sit lower and stand taller.)
        wide = max(r, key=lambda l: l['x1'] - l['x0'])
        box = dict(x0=min(l['x0'] for l in r), x1=max(l['x1'] for l in r), base=wide['base'], h=wide['h'], big=False)
        box['lines'] = r
        if box['x1'] - box['x0'] > 2 * h:
            out.append(box)
    # (A gloss in a narrow column beside it: rows of their own, one
    # stream a side, read down the column.)
    e0, e1 = min(l['x0'] for l in ls), max(l['x1'] for l in ls)
    srow_boxes = []
    for name_ in ('left', 'right'):
        sl = sorted((l for l in side if ((l['x0'] + l['x1']) / 2 < c0) == (name_ == 'left')), key=lambda l: l['base'])
        srows = []
        for l in sl:
            if srows and l['base'] - srows[-1][-1]['base'] < 0.45 * l['h']:
                srows[-1].append(l)
            else:
                srows.append([l])
        for r in srows:
            wide = max(r, key=lambda l: l['x1'] - l['x0'])
            b = dict(x0=min(l['x0'] for l in r), x1=max(l['x1'] for l in r), base=wide['base'], h=wide['h'], big=False,
                     lines=r, stream=name_)
            # (Within its own column, out over its words the OCR left off.)
            if name_ == 'right':
                b['x0'] = max(b['x0'], e1 + 0.3 * hm)
                _widen(b, ink, e1 + 0.3 * hm, ink.shape[1] - 1)
            else:
                b['x1'] = min(b['x1'], e0 - 0.3 * hm)
                _widen(b, ink, 0, e0 - 0.3 * hm)
            if b['x1'] - b['x0'] > b['h']:
                srow_boxes.append(b)
                rows.append(r)
        # (Where the OCR's lines run two together or miss one: lines cut
        # from the ink's row profile in their place.)
        hs_ = sorted(b['h'] for b in srow_boxes)
        med_h = hs_[len(hs_) // 2] if hs_ else hm
        keep = [b for b in srow_boxes if b['h'] <= 1.4 * med_h]
        for b in _profile_rows(ink, sl, name_, e0, e1, hm):
            if not any(abs(b['base'] - k['base']) < 0.5 * k['h'] for k in keep):
                keep.append(b)
        out += keep
        srow_boxes = []
    # (A line the OCR missed altogether, a short one in Rashi script on its
    # own: in a gap between two rows wider than a row's, cut from the ink's
    # row profile across the column.)
    import numpy as np
    main_ = sorted((b for b in out if not b.get('stream')), key=lambda b: b['base'])
    for a_, b_ in zip(main_, main_[1:]):
        gap_top, gap_bot = int(a_['base'] + 0.35 * a_['h']), int(b_['base'] - 1.1 * b_['h'])
        if gap_bot - gap_top < 0.6 * hm:
            continue
        X0, X1 = int(c0), int(c1)
        prof = ink[gap_top:gap_bot, X0:X1].sum(1)
        on = prof >= max(3, 0.01 * (X1 - X0))
        runs, st = [], None
        for y, v in enumerate(on):
            if v and st is None:
                st = y
            elif not v and st is not None:
                runs.append((st, y))
                st = None
        if st is not None:
            runs.append((st, len(on)))
        for y0_, y1_ in runs:
            if y1_ - y0_ < 0.35 * hm:
                continue
            p_ = prof[y0_:y1_]
            dense = [y for y in range(len(p_)) if p_[y] >= 0.3 * p_.max()]
            base_ = gap_top + y0_ + dense[-1] + 1
            cols = ink[gap_top + y0_:gap_top + y1_, X0:X1].any(0)
            xs_ = np.nonzero(cols)[0]
            if len(xs_) and xs_[-1] - xs_[0] > 2 * hm:
                out.append(dict(x0=X0 + int(xs_[0]), x1=X0 + int(xs_[-1]) + 1, base=base_, h=max((base_ - gap_top - y0_) / 0.75, 8),
                                big=False, lines=[]))
    for b in out:
        b['ocr'] = ocr_of(b, [l for r in rows for l in r])
    return sorted(out, key=lambda b: (b['base'], -b['x1']))


def _profile_rows(ink, sl, name_, e0, e1, hm):
    """A side column's lines cut from its ink's row profile (each a box
    with its baseline), lines run together cut at the thinnest row."""
    import numpy as np
    if not sl:
        return []
    if name_ == 'right':
        X0, X1 = int(max(min(l['x0'] for l in sl), e1 + 0.3 * hm)), int(max(l['x1'] for l in sl))
    else:
        X0, X1 = int(min(l['x0'] for l in sl)), int(min(max(l['x1'] for l in sl), e0 - 0.3 * hm))
    if X1 - X0 < hm:
        return []
    Y0 = int(min(l['base'] - l['h'] for l in sl) - hm)
    Y1 = int(max(l['base'] for l in sl) + hm)
    prof = ink[Y0:Y1, X0:X1].sum(1)
    on = prof >= max(2, 0.04 * (X1 - X0))
    runs, st = [], None
    for y, v in enumerate(on):
        if v and st is None:
            st = y
        elif not v and st is not None:
            runs.append([st, y])
            st = None
    if st is not None:
        runs.append([st, len(on)])
    merged = []
    for r_ in runs:
        if merged and (r_[0] - merged[-1][1] <= 1 or r_[1] - r_[0] < 3):
            merged[-1][1] = r_[1]
        else:
            merged.append(r_)
    tall = sorted(y1_ - y0_ for y0_, y1_ in merged if y1_ - y0_ >= 0.35 * hm)
    pitch = tall[len(tall) // 2] if tall else hm
    cut = []
    for y0_, y1_ in merged:
        while y1_ - y0_ > 1.5 * pitch:
            lo_, hi_ = y0_ + int(0.6 * pitch), min(y1_ - int(0.4 * pitch), y0_ + int(1.4 * pitch))
            if hi_ <= lo_:
                break
            m_ = lo_ + int(np.argmin(prof[lo_:hi_]))
            cut.append([y0_, m_])
            y0_ = m_ + 1
        cut.append([y0_, y1_])
    out = []
    for y0_, y1_ in cut:
        if y1_ - y0_ < 0.35 * hm:
            continue
        p_ = prof[y0_:y1_]
        dense = [y for y in range(len(p_)) if p_[y] >= 0.3 * p_.max()]
        base_ = Y0 + y0_ + dense[-1] + 1
        cols = ink[Y0 + y0_:Y0 + y1_, X0:X1].any(0)
        xs_ = np.nonzero(cols)[0]
        if not len(xs_):
            continue
        b = dict(x0=X0 + int(xs_[0]), x1=X0 + int(xs_[-1]) + 1, base=base_, h=max((base_ - Y0 - y0_) / 0.75, 8), big=False,
                 lines=[], stream=name_)
        if b['x1'] - b['x0'] > b['h']:
            out.append(b)
    return out


def _widen(b, ink, lo, hi, gap=0.75):
    """A row's box out over the ink beside it on its line, word by word
    (a word space apart), up to the column's sides: the OCR's lines can
    stop short of a row's first or last word."""
    h = b['h']
    y0, y1 = int(b['base'] - 0.7 * h), int(b['base'])
    cols = ink[y0:y1].any(0)
    x = int(b['x0'])
    while True:
        k = next((x_ for x_ in range(x - 1, max(int(lo), x - int(gap * h)) - 1, -1) if cols[x_]), None)
        if k is None:
            break
        while k > lo and cols[k - 1]:
            k -= 1
        x = k
    b['x0'] = min(b['x0'], x)
    x = int(b['x1'])
    while True:
        k = next((x_ for x_ in range(x + 1, min(int(hi), x + int(gap * h)) + 1) if x_ < len(cols) and cols[x_]), None)
        if k is None:
            break
        while k < hi and k + 1 < len(cols) and cols[k + 1]:
            k += 1
        x = k
    b['x1'] = max(b['x1'], x)
    return b


def _cut_notes(b, ink, any_size=False):
    """A side note in smaller type set on a row's baseline (a gloss beside
    the siyum): the row's box cut short of it, at a white gap wider than a
    letter, where the ink past the gap is smaller than the row's."""
    import numpy as np
    from scipy import ndimage
    h = b['h']
    y0, y1 = int(b['base'] - 0.8 * h), int(b['base'] + 0.2 * h)
    x0, x1 = int(b['x0']), int(b['x1'])
    band = ink[y0:y1, x0:x1]
    cols = band.any(0)
    gaps, run = [], 0
    for x, v in enumerate(cols):
        run = 0 if v else run + 1
        if run and (x + 1 == len(cols) or cols[x + 1]):
            if run >= 1.0 * h:
                gaps.append((x + 1 - run, x + 1))

    def tall(a, c):
        if c - a < 2:
            return 0
        lab, _ = ndimage.label(ink[int(b['base'] - 1.6 * h):int(b['base'] + 0.6 * h), x0 + a:x0 + c])
        hs = [o[0].stop - o[0].start for o in ndimage.find_objects(lab) if o and o[1].stop - o[1].start >= 0.25 * h]
        return float(np.median(hs)) if len(hs) >= 4 else None
    W = x1 - x0
    for g0, g1 in gaps:
        # (Size aside, only the gap nearest each end.)
        if any_size and (g0, g1) not in (gaps[0], gaps[-1]):
            continue
        if g0 < 0.4 * W:
            # (Left of the gap: the note, where it's the smaller.)
            a_, c_ = tall(0, g0), tall(g1, W)
            if os.environ.get('SIYUM_DEBUG'):
                print('GAP left', round(b['base']), x0 + g0, a_, c_, file=sys.stderr)
            if any_size or (a_ and c_ and a_ < 0.8 * c_):
                b['x0'] = x0 + g1
                if os.environ.get('SIYUM_DEBUG'):
                    print('CUT left', round(b['base']), x0, x0 + g1, file=sys.stderr)
        elif g1 > 0.6 * W:
            a_, c_ = tall(g1, W), tall(0, g0)
            if os.environ.get('SIYUM_DEBUG'):
                print('GAP right', round(b['base']), x0 + g0, a_, c_, file=sys.stderr)
            if any_size or (a_ and c_ and a_ < 0.8 * c_):
                b['x1'] = x0 + g0
                if os.environ.get('SIYUM_DEBUG'):
                    print('CUT right', round(b['base']), x0 + g0, x1, file=sys.stderr)
    return b


def _square_h(rows, ink):
    """The siyum's square letters' height: the median of its rows' wide
    shapes on their lines (most of its words are square type)."""
    from scipy import ndimage
    hs = []
    for r in rows:
        Y0 = int(r['base'] - 1.6 * r['h'])
        lab, _ = ndimage.label(ink[Y0:int(r['base'] + 0.4 * r['h']), int(r['x0']):int(r['x1'])])
        objs = ndimage.find_objects(lab)
        for o in objs:
            if o and abs(o[0].stop + Y0 - r['base']) < 0.3 * r['h'] and o[1].stop - o[1].start >= 0.6 * (o[0].stop - o[0].start):
                hs.append(o[0].stop - o[0].start)
    return statistics.median(hs) if hs else None


def ocr_of(box, lines):
    """The OCR's reading of a row: its lines on the row's baseline whose
    middle is in the row's box (not a big opening word's pieces)."""
    ls = [l for l in lines if abs(l['base'] - box['base']) < 0.45 * box['h'] and box['x0'] - 2 <= (l['x0'] + l['x1']) / 2 <= box['x1'] + 2]
    return _words(' '.join(l.get('text', '') for l in sorted(ls, key=lambda l: -l['x1'])))


def _words(s):
    return [w for w in re.sub(r'[^א-ת\'":.() ]', '', s).split() if re.search('[א-ת]', w)]


def vote(readings):
    """One row's text from its readings (lists of words): the reading
    nearest all the others, each of its words the one most readings have
    in its place."""
    from rapidfuzz.distance import Levenshtein
    if not readings:
        return []
    strs = [' '.join(r) for r in readings]
    med = min(range(len(readings)), key=lambda i: sum(Levenshtein.distance(strs[i], s) for s in strs))
    base = readings[med]
    votes = [Counter([w]) for w in base]
    for j, r in enumerate(readings):
        if j == med:
            continue
        sm = difflib.SequenceMatcher(None, base, r, autojunk=False)
        for tag, a0, a1, b0, b1 in sm.get_opcodes():
            if tag == 'equal' or (tag == 'replace' and a1 - a0 == b1 - b0):
                for k in range(a1 - a0):
                    votes[a0 + k][r[b0 + k]] += 1
    return [v.most_common(1)[0][0] for v in votes]


def _letters(w):
    return re.sub(r'[^א-ת]', '', w)


def confirm(text, readings):
    """A row's words: the read-over text's, each confirmed on this row by
    one of its readings (the reader's, the OCRs'); where two read another
    word alike, theirs (a printing's own: ה' for יי, תורידם for תורדם).
    The words neither confirms nor reads otherwise alike are returned
    apart, to be read on their own boxes. None where two of the readings
    read words in that the text hasn't, or leave out its words (another printing's row, or a row
    cut otherwise). (Words read on at either end are the next row's or a
    big word's pieces.)"""
    T = [_letters(w) for w in text]

    def pairs(rd):
        out, sm = {}, difflib.SequenceMatcher(None, T, [_letters(w) for w in rd], autojunk=False)
        for op, a0, a1, b0, b1 in sm.get_opcodes():
            if op == 'equal' or (op == 'replace' and a1 - a0 == b1 - b0):
                out.update({a0 + k: rd[b0 + k] for k in range(a1 - a0)})
            elif op == 'insert' and (a0 == 0 or a0 == len(T)):
                continue
            elif op != 'delete' or any(T[a0:a1]):
                out.setdefault('gap', []).append((op, a0, a1))
        return out
    P = [pairs(rd) for rd in readings if rd]
    if sum('gap' in x for x in P) >= 2 or not P:
        return None, []
    out, pending = [], []
    for k, w in enumerate(text):
        got = [x.get(k) for x in P if x.get(k) is not None]
        if any(_letters(g) == T[k] for g in got):
            out.append(w)
            continue
        alike = Counter(_letters(g) for g in got if _letters(g))
        best = alike.most_common(1)
        # (Not a piece of the word, or it of theirs: a big word read in
        # pieces, a word cut at the row's end.)
        if best and best[0][1] >= 2 and best[0][0] not in T[k] and T[k] not in best[0][0]:
            out.append(next(g for g in got if _letters(g) == best[0][0]))
        else:
            # (Left to be read on its own box.)
            out.append(w)
            pending.append(k)
    return out, pending


def seen(text, readings):
    """Whether a row's read-over words are what its readings see there,
    allowing for misread letters: every word met in one reading at least
    half alike (a word of one or two letters, in any), and no words two
    readings see inside the row that the text hasn't."""
    from rapidfuzz import fuzz
    T = [_letters(w) for w in text]
    hit = [len(t) <= 2 for t in T]
    extra = Counter()
    for rd in readings:
        R = [_letters(w) for w in rd]
        sm = difflib.SequenceMatcher(None, T, R, autojunk=False)
        for op, a0, a1, b0, b1 in sm.get_opcodes():
            if op == 'equal':
                for k in range(a0, a1):
                    hit[k] = True
            elif op == 'replace':
                got = ' '.join(R[b0:b1])
                for k in range(a0, a1):
                    if fuzz.partial_ratio(T[k], got) >= 50:
                        hit[k] = True
                if b1 - b0 > a1 - a0 + 1 and 0 < a0 and a1 < len(T):
                    extra[a0] += 1
            elif op == 'insert' and 0 < a0 < len(T) and len(''.join(R[b0:b1])) > 2:
                extra[a0] += 1
    return all(hit) and not any(v >= 2 for v in extra.values())


def tess_word(im, box):
    """Tesseract's reading of one word's box (big type, which the line
    reader never saw): with the Vilna model and the stock Hebrew one."""
    import subprocess
    import tempfile
    exe = os.environ.get('TESSERACT', 'tesseract')
    c = im.convert('L').crop((int(box['x0']) - 6, int(box['base'] - 0.85 * box['h']) - 6, int(box['x1']) + 6, int(box['base']) + 6))
    c = c.resize((c.width * 2, c.height * 2))
    out = []
    with tempfile.NamedTemporaryFile(suffix='.png') as t:
        c.save(t.name)
        for lang in ('heb_vilna', 'heb'):
            r = subprocess.run([exe, t.name, '-', '-l', lang, '--psm', '8'], capture_output=True, text=True)
            out.append(_words(r.stdout))
    return out


def name_of(book):
    j = json.loads(next(CACHE.glob(f'text/{book}.*.hebrew_*.json')).read_text())
    return j['heIndexTitle']


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('model')
    p.add_argument('place', type=Path)
    p.add_argument('out', type=Path)
    p.add_argument('--lines', type=Path, required=True, help="the base render's lines/")
    p.add_argument('--lines2', type=Path, help="another render's lines/ (its OCR another reading)")
    p.add_argument('--text', type=Path, default=ROOT / 'build/daf/siyum.json')
    p.add_argument('--proof', type=Path, default=ROOT / 'tool/daf/siyum_proof.json',
                   help='the read-over texts, their printings and the tractate names')
    a = p.parse_args()
    import numpy as np
    import svg
    from PIL import Image
    from rapidfuzz import fuzz
    from ctcalign import Reader
    from nnalign import _snap
    reader = Reader(a.model)
    fonts = svg.Fonts()
    proof = json.loads(a.proof.read_text()) if a.proof.exists() else {}
    # Each tractate's last amud.
    last = {}
    for f in a.place.glob('*.json'):
        book, amud = f.stem.rsplit('_', 1)
        k = (int(amud[:-1]), amud[-1])
        if book not in last or k > last[book][0]:
            last[book] = (k, f.stem)
    pages = {}
    for book, (_, name) in sorted(last.items()):
        lf = a.lines / f'{name}.json'
        if not lf.exists():
            continue
        b, amud = name.rsplit('_', 1)
        img, _ = linemap.ocr(CACHE, b.replace('_', ' '), amud)
        im = Image.open(img)
        ink = np.asarray(im.convert('L')) < 128
        rows = block(json.loads(lf.read_text()), ink)
        if not rows:
            continue
        ems = reader.emissions(im, rows)
        geo = list(reader.geometry)
        nm = name_of(b.replace('_', ' '))
        # (The print's own spelling of the name, where it has another: the
        # one its rows read most.)
        alts_ = [nm] + proof.get('names', {}).get(nm, [])
        if len(alts_) > 1:
            seen_ = Counter()
            for r in rows:
                for w in _words(' '.join(r['ocr'])):
                    if _letters(w) in [_letters(x) for x in alts_]:
                        seen_[_letters(w)] += 1
            if seen_:
                nm = max(alts_, key=lambda x: seen_[_letters(x)])
        l2 = a.lines2 / f'{name}.json' if a.lines2 else None
        l2 = json.loads(l2.read_text()) if l2 and l2.exists() else []
        for r, em, g in zip(rows, ems, geo):
            r['em'], r['geo'] = em, g
            r['read'] = _words(reader.read(em).replace(nm, NAME)) if em is not None else []
            r['ocr'] = _words(' '.join(r['ocr']).replace(nm, NAME))
            r['ocr2'] = _words(' '.join(ocr_of(r, l2)).replace(nm, NAME))
        pages[name] = dict(rows=rows, im=im, ink=ink, name=nm, square_h=_square_h(rows, ink))
        print(name, len(rows), 'rows', flush=True)
    (a.text.parent / 'siyum_reads.json').write_text(json.dumps(
        {n: [dict(read=r['read'], ocr=r['ocr'], ocr2=r['ocr2'], big=r['big'], at=[round(r['x0']), round(r['x1']), round(r['base']), round(r['h'])])
             for r in p['rows']] for n, p in pages.items()}, ensure_ascii=False))
    # Each row's text: the span of a read-over text its reading matches
    # best; where the printings differ (a|b, words joined by _), the one
    # the reader's loss on the row is least for; its ends likewise. A
    # paragraph's big opening word (marked \u00b6) at the span's start is
    # tried first (read on its own box), then the row without it.
    def alts(tok):
        # (§: words the printings set in Rashi script or in square type;
        # which, the scan decides: see draw().)
        rs = tok.lstrip('\u00b6').startswith('\u00a7')
        a = [[] if alt == '-' else [('\u00a7' if rs else '') + w for w in alt.split('_')]
             for alt in tok.lstrip('\u00b6').lstrip('\u00a7').split('|')]
        # (The print's stops, some printings without them.)
        a += [w[:-1] + [w[-1].rstrip(':.')] for w in a if w and w[-1][-1] in ':.' and w[-1].rstrip(':.').lstrip('\u00a7')]
        return a + [tok.startswith('\u00b6')]
    texts = [[alts(tok) for tok in v.split()] for v in proof['texts'].values()]

    def flat(T, ch):
        return [w for tok, c in zip(T, ch) for w in tok[c]]

    def nostop(tok, c):
        """Whether printing c of a token is another of its printings
        without its stop: kept only where the reader is clearly the
        better for it (it barely sees a stop)."""
        w = tok[c]
        return bool(w) and any(o is not w and o and o[:-1] == w[:-1] and o[-1].rstrip(':.') == w[-1] and o[-1] != w[-1]
                                for o in tok[:-1])
    STOP = 0.05

    def nomark(tok, c):
        """Whether printing c of a token leaves out a note marker (*), א)…)
        the others print: the reader barely sees one either."""
        return not tok[c] and any(o and re.fullmatch(r'\u00a7?[*\u05d0-\u05ea]{1,2}\)', o[0]) for o in tok[:-1])
    import itertools
    for name, pg in pages.items():
        prev_ends = {}
        for r in pg['rows']:
            r['page'] = name
            prev_end = prev_ends.get(r.get('stream'))
            R = r['read'] if len(_letters(''.join(r['read']))) >= 0.7 * len(_letters(''.join(r['ocr']))) else r['ocr']
            Rs = ' '.join(_letters(w) for w in R)
            r['cands'], r['span'] = [], None

            def loss(T, ch):
                return reader.score(r['em'], ' '.join(flat(T, ch)).replace(NAME, pg['name']).replace('\u00a7', ''))
            if len(Rs.replace(' ', '')) < 8 or r['em'] is None:
                # (A row of a word or two, a paragraph's last: the words
                # after the row above's, as many as the reader finds.)
                if r['em'] is not None and prev_end and len(Rs.replace(' ', '')) >= 2:
                    t, j = prev_end
                    T = texts[t]
                    opts = []
                    for n in (1, 2, 3):
                        if j + n <= len(T) and not any(T[q][-1] for q in range(j, j + n)):
                            for combo in itertools.product(*[range(len(T[q]) - 1) for q in range(j, j + n)]):
                                if flat(T[j:j + n], combo):
                                    opts.append((loss(T[j:j + n], list(combo)) + STOP * sum(nostop(T[j + q], c) for q, c in enumerate(combo)), n, combo))
                    if opts and min(opts)[0] <= SOFT_LOSS:
                        _, n, combo = min(opts)
                        words = flat(T[j:j + n], combo)
                        r['span'] = (0, ' '.join(words))
                        r['pos'] = (t, j, j + n)
                        r['cands'] = [(words, False)]
                        prev_ends[r.get('stream')] = (t, j + n)
                continue
            best = (0, None)
            # (The reader's own reading of the row's box first; the OCRs'
            # lines can run into the next row's.)
            for rd in (r['read'], r['ocr'], r['ocr2']):
                if len(_letters(''.join(rd))) < 8 or best[0] >= 70:
                    continue
                Rs = ' '.join(_letters(w) for w in rd)
                for t, T in enumerate(texts):
                    LT = [' '.join(_letters(w) for w in tok[0]) for tok in T]
                    for n in range(max(1, len(rd) - 8), len(rd) + 8):
                        for i in range(len(T) - n + 1):
                            sc = fuzz.ratio(' '.join(LT[i:i + n]), Rs)
                            if sc > best[0]:
                                best = (sc, (t, i, i + n))
            if best[0] < 70:
                continue
            t, i, j = best[1]
            T = texts[t]
            j = next((q for q in range(i + 1, j) if T[q][-1]), j)
            if T[i][-1]:
                i += 1
            if i >= j:
                continue
            # (The printing's words, then the ends, then the words again.)
            ch = {k: 0 for k in range(len(T))}

            def choose(i, j):
                for k in list(range(i, j)) * 2:
                    if len(T[k]) > 2:
                        sub = T[i:j]
                        cs = [ch[q] for q in range(i, j)]
                        tries = []
                        for c in range(len(T[k]) - 1):
                            cs[k - i] = c
                            tries.append((loss(sub, cs) + STOP * (nostop(T[k], c) + nomark(T[k], c)), c))
                        ch[k] = min(tries)[1]
            choose(i, j)
            got = (loss(T[i:j], [ch[q] for q in range(i, j)]), i, j)
            for _ in range(40):
                was = got
                for s_ in range(got[1] - 4, got[1] + 5):
                    for e_ in range(got[2] - 4, got[2] + 5):
                        if 0 <= s_ < e_ <= len(T) and (s_, e_) != was[1:] and not any(T[q][-1] for q in range(s_, e_)):
                            # (A word the edge takes in: its printing too.)
                            for q in set(range(s_, e_)) - set(range(was[1], was[2])):
                                if len(T[q]) > 2:
                                    ch[q] = min((loss(T[s_:e_], [c if p_ == q else ch[p_] for p_ in range(s_, e_)]) + STOP * (nostop(T[q], c) + nomark(T[q], c)), c)
                                                for c in range(len(T[q]) - 1))[1]
                            ls = loss(T[s_:e_], [ch[q] for q in range(s_, e_)])
                            if ls < got[0] - 0.02:
                                got = (ls, s_, e_)
                if got == was:
                    break
            _, i, j = got
            choose(i, j)
            opener = i - 1 if i > 0 and T[i - 1][-1] else None
            words = flat(T[i:j], [ch[q] for q in range(i, j)])
            r['span'] = (best[0], ' '.join(words))
            r['pos'] = (t, i, j)
            # (Which printing it took where they differ, by the set of them.)
            r['choice'] = [(repr(T[q][:-1]), ch[q]) for q in range(i, j) if len(T[q]) > 2]
            prev_ends[r.get('stream')] = (t, j)
            r['cands'] = ([(flat(T[opener:opener + 1], [ch[opener]]) + words, True)] if opener is not None else []) + [(words, False)]
    # A word between one row's span and the next's (one the reader can't
    # read, set apart: Eruvin's last row's ויקריה): tried first at the
    # next row's start, read on its own box.
    for name, pg in pages.items():
        spanned = [r for r in pg['rows'] if r.get('pos')]
        for a_, b_ in ((a_, b_) for st in {q.get('stream') for q in spanned}
                       for a_, b_ in zip([q for q in spanned if q.get('stream') == st], [q for q in spanned if q.get('stream') == st][1:])):
            (t1, i1, j1), (t2, i2, j2) = a_['pos'], b_['pos']
            if t1 != t2:
                # (The texts are one up to where the printings part: the row
                # above's end found in the next row's text, just before it.)
                key = [tuple(map(tuple, tok[:-1])) for tok in texts[t1][max(0, j1 - 4):j1]]
                at_ = [k for k in range(len(key), i2 + 1)
                       if [tuple(map(tuple, tok[:-1])) for tok in texts[t2][k - len(key):k]] == key]
                if not at_:
                    continue
                t1, j1 = t2, at_[-1]
            # (The next row's paragraph opening word is its own, not the gap's.)
            if t1 == t2 and i2 > j1 and texts[t2][i2 - 1][-1]:
                i2 -= 1
            if t1 == t2 and i2 - j1 == 1 and not texts[t1][j1][-1] and b_['cands'] and not b_['cands'][0][1]:
                # (Its printings; drawn once both rows are, below.)
                if all(texts[t1][j1][:-1]):
                    b_['gap'] = [' '.join(w) for w in texts[t1][j1][:-1] if len(w) == 1]
            if t1 == t2 and i2 - j1 >= 2 and i2 - j1 <= 12 and not any(texts[t1][q][-1] for q in range(j1, i2)) and a_['cands']:
                # (Several words: the row above with them at its end first,
                # their printings as the reader has them there.)
                G = texts[t1][j1:i2]
                em_ = a_['em']
                best_ = None
                for combo in itertools.islice(itertools.product(*[range(len(g) - 1) for g in G]), 64):
                    ws_ = flat(G, combo)
                    ls_ = reader.score(em_, ' '.join(a_['cands'][0][0] + ws_).replace(NAME, pg['name']).replace('\u00a7', '')) if em_ is not None else 9
                    if best_ is None or ls_ < best_[0]:
                        best_ = (ls_, ws_)
                if best_ and best_[1]:
                    a_['ext'] = (a_['cands'][0][0] + best_[1], a_['cands'][0][1])
    # Each page: its rows drawn from the text.
    a.out.mkdir(parents=True, exist_ok=True)
    tot = Counter()
    for f in sorted(a.place.glob('*.json')):
        if f.stem not in pages:
            shutil.copy(f, a.out / f.name)
            continue
        pg = pages[f.stem]
        place = json.loads(f.read_text())
        ink = pg['ink']
        new, boxes = [], []
        def draw(r, text, opener):
            """A row drawn from `text`: its words placed and the boxes they
            cover, or why not."""
            nw, bx = [], []
            # (The text is read over: the reader's loss on the row is the
            # check, below; a big opening word is read on its own box.)
            got, pending, need_head = list(text), [], opener
            ws, at, maybe_rashi = [], [], []
            for w in got:
                at.append(len(ws))
                parts = w.lstrip('\u00a7').replace(NAME, pg['name']).split()
                ws += parts
                maybe_rashi += [w.startswith('\u00a7')] * len(parts)
            pending = [at[k] for k in pending]
            xs, _ = reader.align(r['em'], r['geo'], ws)
            if xs is None:
                return 'align'
            xs = _snap(ink, r, xs, r['geo'][1] * r['geo'][2])

            nat = [fonts.width(svg.SQUARE, 1, w) for w in ws]

            def letters_of(x0, x1, grow=False):
                """The ink of a word's letters: the shapes that cross the
                row's line in the word's span (left, right, top, bottom);
                with `grow`, and the shapes beside them their height (a
                big word's letters the span cut)."""
                from scipy import ndimage
                pad = int(3 * r['h']) if grow else 0
                X0_, Y0_ = max(0, int(x0) - pad), int(r['base'] - 3 * r['h'])
                lab, _ = ndimage.label(ink[Y0_:int(r['base'] + 2.5 * r['h']), X0_:int(x1) + pad])
                objs = ndimage.find_objects(lab)
                line = slice(int(r['base'] - 0.7 * r['h']) - Y0_, int(r['base']) - Y0_)
                ids = {i for i in np.unique(lab[line, int(x0) - X0_:int(x1) - X0_]) if i}
                if not ids:
                    return None
                box = [min(objs[i - 1][1].start for i in ids), max(objs[i - 1][1].stop for i in ids),
                       min(objs[i - 1][0].start for i in ids), max(objs[i - 1][0].stop for i in ids)]
                while grow:
                    H = box[3] - box[2]
                    more = {i + 1 for i, o in enumerate(objs) if o and i + 1 not in ids
                            and o[1].start >= int(x0) - X0_ - 0.4 * H and o[1].stop <= int(x1) - X0_ + H
                            and min(o[0].stop, box[3]) - max(o[0].start, box[2]) > 0.6 * (o[0].stop - o[0].start)
                            and o[0].stop - o[0].start > 0.3 * (box[3] - box[2])
                            and (o[1].start - box[1] < 0.15 * (box[3] - box[2]) and box[0] - o[1].stop < 0.15 * (box[3] - box[2]))}
                    if not more:
                        break
                    ids |= more
                    box = [min(box[0], *(objs[i - 1][1].start for i in more)), max(box[1], *(objs[i - 1][1].stop for i in more)),
                           min(box[2], *(objs[i - 1][0].start for i in more)), max(box[3], *(objs[i - 1][0].stop for i in more))]
                # (The wide letters' height: not י's, nor ל's or ק's.)
                hw = [(o[0].stop - o[0].start, o[1].stop - o[1].start) for o in (objs[i - 1] for i in ids)]
                wide = [a for a, b_ in hw if b_ >= 0.7 * a] or [a for a, _ in hw]
                med = statistics.median(wide)
                # (On a pale page the letters break up: the height of the
                # word's thick band of ink rows, past ל's top and ק's foot,
                # where that is the taller.)
                sub_ = np.isin(lab[box[2]:box[3], box[0]:box[1]], list(ids))
                prof = sub_.sum(1)
                run = best_ = 0
                for v in prof >= 0.12 * prof.max():
                    run = run + 1 if v else 0
                    best_ = max(best_, run)
                med = max(med, best_)
                return (X0_ + box[0], X0_ + box[1], Y0_ + box[2], Y0_ + box[3], med)
            head = None
            rest = [(x1 - x0) / n_ for (x0, x1), n_ in list(zip(xs, nat))[1:] if n_ > 0]
            if os.environ.get('SIYUM_DEBUG') and rest and nat[0]:
                print('FIRST', f.stem, round(r['base']), ws[0], [round(v) for v in xs[0]], round((xs[0][1] - xs[0][0]) / nat[0] / statistics.median(rest), 2), file=sys.stderr)
            if rest and nat[0] and need_head:
                # The row's first word set big (an opening, over one row or
                # two): read on its own box, at its height; else no row.
                # (Where the row's box stops short of it, past the box.)
                def known(g):
                    # (The read-over opening word: its letters' height from
                    # its ink's, as the font sets that word; letters that
                    # break up on a pale page measure short one by one.)
                    if not (g and need_head):
                        return g
                    lo, hi = fonts.vink(svg.SQUARE, ws[0])
                    est = (g[3] - g[2]) / max(hi - lo, 1e-6) * WIDE
                    return g[:4] + (max(g[4], min(est, 3 * WIDE * statistics.median(rest))),)
                letters = WIDE * statistics.median(rest)
                # Where the word may be, in turn: past the row's box (its
                # letters measured, then as the font sets the word), then
                # the row's first word's place; the first the readings
                # confirm.
                past = letters_of(r['x1'] + 1, r['x1'] + 3 * r['h'], grow=True) if need_head is True else None
                tries = [past, letters_of(*xs[0], grow=True), known(past)]
                failed = None
                for k_, g in enumerate(tries):
                    if k_ == 1:
                        g = known(g)
                    if not g:
                        continue
                    # (Not a speck or a stroke past the box: ink about as
                    # wide as the word would be at that height.)
                    if k_ != 1 and not g[1] - g[0] > 0.5 * nat[0] * g[4] / WIDE:
                        continue
                    # (A word the rows either side leave out, need_head
                    # 'gap': its own size, read on its own box all the same.)
                    if not (g[4] > 1.25 * letters or need_head == 'gap'):
                        continue
                    y = g[2:4]
                    # (Its first letters can stand apart, a big מ: the box
                    # out to the right over ink a letter space away.)
                    band_ = ink[int(y[0]):int(y[1]), :]
                    colz = band_[int(0.2 * (y[1] - y[0])):].any(0)
                    x_, blank_ = int(g[1]), 0
                    for xx in range(int(g[1]) + 1, min(ink.shape[1], int(g[1] + 1.5 * (y[1] - y[0])))):
                        if colz[xx]:
                            x_, blank_ = xx, 0
                        else:
                            blank_ += 1
                            if blank_ > 0.25 * (y[1] - y[0]):
                                break
                    g = (g[0], x_ + 1) + tuple(g[2:])
                    if os.environ.get('SIYUM_DEBUG'):
                        print('HEIGHT', f.stem, round(r['base']), ws[0], k_, g, letters, file=sys.stderr)
                    box = dict(x0=g[0] - 3, x1=g[1] + 3, base=y[1], h=(y[1] - y[0]) / 0.85, head=True)
                    em = reader.emissions(pg['im'], [box])[0]
                    rds = [_words(reader.read(em)) if em is not None else []] + tess_word(pg['im'], box)
                    if os.environ.get('SIYUM_DEBUG'):
                        print('OPENING', f.stem, ws[0], rds, y, letters, file=sys.stderr)
                    # (The word is read over: one reading of it, alone or
                    # with specks beside it, or one's letters.)
                    hit = [any(_letters(w) == _letters(ws[0]) for w in rd) or _letters(''.join(rd)) == _letters(ws[0]) for rd in rds]
                    if any(hit):
                        head = (box, g[4], letters)
                        break
                    failed = 'opening'
                if failed and not head:
                    return failed
            if need_head and not head:
                return 'unconfirmed'
            # The reader's loss for the row's words on their own ink (a big
            # opening word's left out: the reader never saw such type).
            em, geo = r['em'], r['geo']
            if head:
                sub = dict(r, x1=head[0]['x0'] - 1)
                em = reader.emissions(pg['im'], [sub])[0]
                geo = reader.geometry[0]
            loss = reader.score(em, ' '.join(ws[1:] if head else ws))
            r['loss'] = round(loss, 3)
            if loss > MAX_LOSS and not loss <= r.get('ext_ok', 0) and not (loss <= SOFT_LOSS and seen(ws[1:] if head else ws, [
                    [w.replace(NAME, pg['name']) for w in rd] for rd in (r['read'], r['ocr'], r['ocr2'])])):
                if os.environ.get('SIYUM_DEBUG'):
                    print('LOSS', f.stem, round(r['base']), round(loss, 3), ' '.join(ws)[:60], file=sys.stderr)
                return 'loss'
            if head:
                sx_, _ = reader.align(em, geo, ws[1:])
                if sx_ is None:
                    return 'align'
                xs = xs[:1] + _snap(ink, sub, sx_, geo[1] * geo[2])
            # The words no line's reading confirmed: Tesseract on each
            # one's own box (a word the line's OCR ran into the next).
            bad = []
            for k in pending:
                if k == 0 and head:
                    continue
                rds = tess_word(pg['im'], dict(x0=xs[k][0], x1=xs[k][1], base=r['base'] + 0.25 * r['h'], h=1.4 * r['h']))
                # (Tesseract gives some one word back to front.)
                if not any(len(rd) == 1 and _letters(ws[k]) in (_letters(rd[0]), _letters(rd[0])[::-1]) for rd in rds):
                    bad.append((ws[k], rds))
            if os.environ.get('SIYUM_DEBUG') and pending:
                print('PENDING', f.stem, round(r['base']), [ws[k] for k in pending], bad, file=sys.stderr)
            if bad:
                return 'unconfirmed'
            # (A § word in Rashi script where its letters stand shorter
            # than the square type's: the row's other words', else the
            # siyum's.)
            def core_h(x0, x1):
                from scipy import ndimage
                Y0_ = int(r['base'] - 1.6 * r['h'])
                lab, _ = ndimage.label(ink[Y0_:int(r['base'] + 0.4 * r['h']), max(0, int(x0)):int(x1)])
                band = slice(int(r['base'] - 0.5 * r['h']) - Y0_, int(r['base']) - Y0_)
                ids = {i for i in np.unique(lab[band]) if i}
                objs = ndimage.find_objects(lab)
                hs = [objs[i - 1][0].stop - objs[i - 1][0].start for i in ids
                      if objs[i - 1][1].stop - objs[i - 1][1].start >= 0.6 * (objs[i - 1][0].stop - objs[i - 1][0].start)]
                return statistics.median(hs) if hs else None
            rashi = [False] * len(ws)
            if any(maybe_rashi):
                sq = [h_ for k, h_ in ((k, core_h(*xs[k])) for k in range(len(ws)) if not maybe_rashi[k] and not (k == 0 and head)) if h_]
                ref = statistics.median(sq) if len(sq) >= 2 else pg['square_h']
                rh = [core_h(*xs[k]) if maybe_rashi[k] else None for k in range(len(ws))]
                ms = [v for v in rh if v]
                if ms and ref and statistics.median(ms) < 0.8 * ref:
                    rashi = list(maybe_rashi)
            if os.environ.get('SIYUM_DEBUG') and any(maybe_rashi):
                print('FONT', f.stem, round(r['base']), any(rashi), file=sys.stderr)
            natf = [fonts.width(svg.RASHI if rashi[k] else svg.SQUARE, 1, w) for k, w in enumerate(ws)]

            def size_of(want):
                v = [(x1 - x0) / n_ for k, ((x0, x1), n_) in enumerate(zip(xs, natf)) if n_ > 0 and rashi[k] == want and not (k == 0 and head)]
                return statistics.median(v) if v else None
            size = size_of(False) or size_of(True)
            size_r = size_of(True) or size
            tilt = None

            def base_at(x0, x1):
                return float(np.polyval(tilt, (x0 + x1) / 2)) if tilt is not None else r['base']
            for i, (w, (x0, x1), n_) in enumerate(zip(ws, xs, natf)):
                if i == 0 and head:
                    # (Its size and baseline from its ink's top and foot, as
                    # the font sets this word: a ן or ק runs below the line.)
                    lo, hi = fonts.vink(svg.SQUARE, w)
                    y1 = head[0]['base']
                    y0 = y1 - 0.85 * head[0]['h']
                    big = (y1 - y0) / max(hi - lo, 1e-6)
                    base_ = y1 + lo * big
                    x0, x1 = head[0]['x0'] + 3, head[0]['x1'] - 3
                    sx = big * min(1.3, max(0.5, (x1 - x0) / n_ / big))
                    nw.append(['', -1, 0, w, round(float(x0), 1), round(float(base_), 1), round(float(sx), 2), round(float(big), 2)])
                    bx.append(head[0])
                    continue
                sz = size_r if rashi[i] else size
                # (Never stretched, squeezed to 0.7 at most: centred on its
                # ink, as svg.py sets the body's words.)
                sx = sz * min(1.0, max(0.7, (x1 - x0) / n_ / sz)) if n_ else sz
                left = (x0 + x1) / 2 - n_ * sx / 2 if n_ else x0
                nw.append(['', -1, int(rashi[i]), w, round(float(left), 1), round(base_at(x0, x1), 1), round(float(sx), 2), round(float(sz), 2)])
            # (Words drawn over one another: the row's last words past its
            # box, squeezed in. Once more with the box out over its line's
            # ink; else no row, rather than words on words.)
            mine = sorted((w for w in nw if abs(w[5] - r['base']) < 0.5 * r['h']), key=lambda w: w[4])
            over = any(a[4] + fonts.width(svg.RASHI if a[2] else svg.SQUARE, a[6], a[3]) - b[4] > 0.3 * a[7] for a, b in zip(mine, mine[1:]))
            if over:
                if r.get('widened'):
                    return 'overlap'
                lo_ = min(q['x0'] for q in pg['rows'] if not q.get('stream')) - 1.5 * r['h']
                hi_ = max(q['x1'] for q in pg['rows'] if not q.get('stream')) + 0.5 * r['h']
                r2 = _widen(dict(r), ink, lo_, hi_, gap=2.0)
                if (r2['x0'], r2['x1']) == (r['x0'], r['x1']):
                    return 'overlap'
                r2['em'] = reader.emissions(pg['im'], [r2])[0]
                r2['geo'] = reader.geometry[0]
                r2['widened'] = True
                return draw(r2, text, opener)
            bx.append(r)
            return nw, bx

        heads = []
        prev_drawn = {}

        def gap_word(r, rr, prev, res):
            """The word between the row above's words and this row's, the
            OCR's lines stopping short of it: its ink just past the row
            above's last word or just before this row's first, on that
            row's line (or raised a little), read as the word by one of the
            readers (the line reader, Tesseract's two), or by the line
            reader's loss; or, where they make out little, ink as wide as
            the word, read half alike. The best of its printings and of the
            ink there: the placed word and its box, or None."""
            from rapidfuzz import fuzz
            pr, pres = prev
            best = None
            for row, words, side in ((pr, pres[0], 'end'), (rr, res[0], 'start')):
                ws_ = [w for w in words if abs(w[5] - row['base']) < 0.5 * row['h']]
                if not ws_:
                    continue
                h = row['h']
                size = statistics.median(x[7] for x in ws_)
                y0, y1 = int(row['base'] - 0.75 * h), int(row['base'] + 0.1 * h)
                if side == 'end':
                    edge = min(w[4] for w in ws_)
                    X0, X1 = int(edge - 7 * h), int(edge + 0.5 * h)
                else:
                    edge = max(w[4] + fonts.width(svg.SQUARE, w[6], w[3]) for w in ws_)
                    X0, X1 = int(edge - 0.5 * h), int(edge + 7 * h)
                # (Within the siyum's rows' reach: not the scan's dark edge.)
                X0 = max(0, X0, int(min(q['x0'] for q in pg['rows']) - 1.5 * h))
                X1 = min(ink.shape[1], X1, int(max(q['x1'] for q in pg['rows']) + 1.5 * h))
                if X1 - X0 < 4:
                    continue
                cols = ink[y0:y1, X0:X1].any(0)
                # The words there (ink runs a letter space apart): the
                # nearest past the drawn words' edge, by its middle, and the
                # one past the drawn word's own ink and a word space.
                words_, cur, blank = [], None, 0
                for x in range(len(cols)):
                    if cols[x]:
                        if cur and blank <= 0.5 * h:
                            cur[1] = x
                        else:
                            if cur:
                                words_.append(cur)
                            cur = [x, x]
                        blank = 0
                    else:
                        blank += 1
                if cur:
                    words_.append(cur)
                e_ = edge - X0
                out_ = (lambda w_: w_[1] < e_) if side == 'end' else (lambda w_: w_[0] > e_)
                mid_ = (lambda w_: (w_[0] + w_[1]) / 2 < e_) if side == 'end' else (lambda w_: (w_[0] + w_[1]) / 2 > e_)
                near = (lambda ws: max(ws, key=lambda w_: w_[1])) if side == 'end' else (lambda ws: min(ws, key=lambda w_: w_[0]))
                blobs = {tuple(near(c)) for c in ([w_ for w_ in words_ if mid_(w_)], [w_ for w_ in words_ if out_(w_)]) if c}
                if os.environ.get('SIYUM_DEBUG'):
                    print('GAPSEARCH', f.stem, round(row['base']), side, r['gap'], X0, X1, round(edge), [(X0 + a, X0 + b) for a, b in words_][:8], file=sys.stderr)
                # (And each one's outer part, cut at its widest space: two
                # words a narrow space apart read as one.)
                for a, b in list(blobs):
                    gaps_, run, start = [], 0, None
                    for x in range(a, b + 1):
                        if not cols[x]:
                            run += 1
                        else:
                            if run:
                                gaps_.append((run, x - run, x))
                            run = 0
                    if gaps_:
                        _, g0, g1 = max(gaps_)
                        blobs.add((a, g0 - 1) if side == 'end' else (g1, b))
                for a, b in blobs:
                    lo_, hi_ = X0 + a, X0 + b + 1
                    if hi_ - lo_ < 0.4 * h or hi_ - lo_ > 6 * h:
                        continue
                    # (Its own baseline as well as the row's: a row can tilt
                    # a few px, a row's last word can be set raised.)
                    Y0 = int(row['base'] - 1.5 * h)
                    prof = ink[Y0:int(row['base'] + 0.1 * h), lo_:hi_].sum(1)
                    runs, cur = [], []
                    for y in range(len(prof)):
                        if prof.max() and prof[y] >= 0.3 * prof.max():
                            cur.append(y)
                        elif cur:
                            runs.append(cur)
                            cur = []
                    if cur:
                        runs.append(cur)
                    for base_ in [row['base']] + ([Y0 + max(runs, key=len)[-1] + 1] if runs else []):
                        box = dict(x0=lo_ - 2, x1=hi_ + 2, base=base_, h=h)
                        em = reader.emissions(pg['im'], [box])[0]
                        rds = [_words(reader.read(em)) if em is not None else []] + tess_word(pg['im'], dict(box, base=base_ + 0.25 * h, h=1.4 * h))
                        got = [_letters(''.join(rd)) for rd in rds]
                        for w in [g.lstrip('\u00a7') for g in r['gap']]:
                            hit = any(_letters(w) in (g, g[::-1]) for g in got) or any(_letters(w) == _letters(x) for rd in rds for x in rd)
                            ls = reader.score(em, w) if em is not None else 9
                            n_ = fonts.width(svg.SQUARE, 1, w)
                            wide = (hi_ - lo_) / (n_ * size) if n_ else 0
                            alike = max((fuzz.ratio(_letters(w), g) for g in got if g), default=0)
                            if os.environ.get('SIYUM_DEBUG'):
                                print('GAP', f.stem, round(row['base']), side, w, rds, round(ls, 2), lo_, hi_, round(base_), round(wide, 2), alike, file=sys.stderr)
                            if not (hit or ls <= MAX_LOSS or (0.55 <= wide <= 1.4 and alike >= 50)):
                                continue
                            key = (hit, -min(ls, 9), alike, -abs(1 - wide))
                            if best is None or key > best[0]:
                                l2, h2 = lo_, hi_
                                if wide > 1.3:
                                    # (The ink takes in the drawn word's end:
                                    # the word at its outer end.)
                                    if side == 'end':
                                        h2 = lo_ + n_ * size
                                    else:
                                        l2 = hi_ - n_ * size
                                sx = size * min(1.0, max(0.7, (h2 - l2) / n_ / size)) if n_ else size
                                l2 = (l2 + h2) / 2 - n_ * sx / 2 if n_ else l2
                                best = (key, (['', -1, 0, w, round(float(l2), 1), round(float(base_), 1), round(float(sx), 2), round(float(size), 2)], dict(box, x0=l2 - 2, x1=h2 + 2)))
            return best[1] if best else None
        for r in pg['rows']:
            res, tried = 'unmatched', []
            # (A big opening word above that hangs down beside this row:
            # the row stops short of it.)
            hang = [b for b in heads if b['base'] > r['base'] - 0.5 * r['h'] and b['base'] - 0.85 * b['h'] < r['base'] - 0.3 * r['h']
                    and b['x0'] < r['x1'] and b['x1'] > r['x1'] - 2 * r['h']]
            rr = r
            if hang and r.get('cands'):
                rr = dict(r, x1=min(b['x0'] for b in hang) - 2)
                rr['em'] = reader.emissions(pg['im'], [rr])[0]
                rr['geo'] = reader.geometry[0]
                tried.append('beside a big word')
            base_rr = rr
            for text, opener in ([r['ext']] if r.get('ext') else []) + (r.get('cands') or []):
                rr = base_rr
                if r.get('ext') and text is r['ext'][0]:
                    # (The words past the row's OCR line: the box out over
                    # the ink on its line, to the siyum's sides.)
                    lo_ = min(q['x0'] for q in pg['rows'] if not q.get('stream')) - r['h']
                    hi_ = max(q['x1'] for q in pg['rows'] if not q.get('stream')) + 0.5 * r['h']
                    wide_ = _widen(dict(rr), ink, lo_, hi_, gap=2.0)
                    if os.environ.get('SIYUM_DEBUG'):
                        print('EXT', f.stem, round(r['base']), (rr['x0'], rr['x1']), (wide_['x0'], wide_['x1']), ' '.join(text)[-80:], file=sys.stderr)
                    if (wide_['x0'], wide_['x1']) != (rr['x0'], rr['x1']):
                        wide_['em'] = reader.emissions(pg['im'], [wide_])[0]
                        wide_['geo'] = reader.geometry[0]
                        rr = wide_
                    # (The words between two rows' spans are the text's: a
                    # row the reader reads poorly at its end passes at a
                    # higher loss, if the row without them passes as is.)
                    rr = dict(rr)
                    plain = draw(dict(base_rr), *r['cands'][0])
                    if not isinstance(plain, str):
                        rr['ext_ok'] = 1.6
                rr['loss'] = None
                res = draw(rr, text, opener)
                r['loss'] = rr['loss']
                tried.append(res if isinstance(res, str) else 'drawn')
                if isinstance(res, str):
                    tried[-1] += f" {r.get('loss')}"
                else:
                    break
            if isinstance(res, str) and r.get('cands'):
                # (A gloss in smaller type on the row's line: the row again
                # without it.)
                r2 = _cut_notes(dict(rr), ink)
                if (r2['x0'], r2['x1']) == (rr['x0'], rr['x1']):
                    r2 = _cut_notes(dict(rr), ink, any_size=True)
                if (r2['x0'], r2['x1']) != (rr['x0'], rr['x1']):
                    r2['em'] = reader.emissions(pg['im'], [r2])[0]
                    r2['geo'] = reader.geometry[0]
                    for text, opener in r['cands']:
                        res = draw(r2, text, opener)
                        tried.append(('cut ' + res) if isinstance(res, str) else 'drawn cut')
                        if not isinstance(res, str):
                            break
            r['tried'] = tried
            if not isinstance(res, str) and r.get('gap') and prev_drawn.get(r.get('stream')):
                g = gap_word(r, rr, prev_drawn[r.get('stream')], res)
                if g:
                    res = (res[0] + [g[0]], res[1] + [g[1]])
                    tried.append('gap ' + g[0][3])
                else:
                    tried.append('gap not found')
            if isinstance(res, str):
                r['result'] = res
                tot[res] += 1
                continue
            r['result'] = 'drawn: ' + ' '.join(w[3] for w in res[0])
            new += res[0]
            boxes += res[1]
            heads += [b for b in res[1] if b.get('head')]
            prev_drawn[r.get('stream')] = (rr, res)
            tot['rows'] += 1
            tot['words'] += len(res[0])


        # Second pass: rows the reader reads poorly (small type, a pale
        # page) between two drawn rows: the words between those rows' spans
        # are the text's, shared out among them where the reader's loss
        # says each row ends; they pass at a higher loss.
        def to_text(row, t2):
            """A row's span end as an index in text t2 (the texts are one
            up to where the printings part)."""
            t1, _, j1 = row['pos']
            if t1 == t2:
                return j1
            key = [tuple(map(tuple, tok[:-1])) for tok in texts[t1][max(0, j1 - 4):j1]]
            at_ = [k for k in range(len(key), len(texts[t2]) + 1) if [tuple(map(tuple, tok[:-1])) for tok in texts[t2][k - len(key):k]] == key]
            return at_[0] if at_ else None
        sp = [q for q in pg['rows'] if q.get('pos')]
        for st in {q.get('stream') for q in sp}:
            same = [q for q in sp if q.get('stream') == st]
            k_ = 0
            while k_ < len(same):
                if (same[k_].get('result') or '').startswith('drawn') or k_ == 0:
                    k_ += 1
                    continue
                run = []
                while k_ < len(same) and not (same[k_].get('result') or '').startswith('drawn'):
                    run.append(same[k_])
                    k_ += 1
                up, dn = same[same.index(run[0]) - 1], (same[k_] if k_ < len(same) else None)
                if os.environ.get('SIYUM_DEBUG'):
                    print('RUN', f.stem, [round(q['base']) for q in run], up.get('result', '')[:12], dn and (dn.get('result') or '')[:12], file=sys.stderr)
                if not (up.get('result') or '').startswith('drawn') or dn is None or len(run) > 4:
                    continue
                t = dn['pos'][0]
                s0 = to_text(up, t)
                e_end = dn['pos'][1] - (1 if texts[t][dn['pos'][1] - 1][-1] else 0)
                if s0 is None or not 0 < e_end - s0 <= 30 * len(run):
                    continue
                T = texts[t]
                for n_, r in enumerate(run):
                    if r['em'] is None:
                        break
                    # (Its box a few px up or down, where the reader reads
                    # the row best: an OCR line's baseline can be off.)
                    def plain_loss(rb):
                        return reader.score(rb['em'], ' '.join(rb['read_'])) if rb['em'] is not None and rb['read_'] else 9
                    best_r = None
                    for off in (0, -3, 3, -6, 6):
                        rb = dict(r, base=r['base'] + off)
                        rb['em'] = reader.emissions(pg['im'], [rb])[0]
                        rb['geo'] = reader.geometry[0]
                        txt = ' '.join(w for w in flat(T[s0:e_end], [0] * (e_end - s0)) if w).replace(NAME, pg['name']).replace('\u00a7', '')
                        sc_ = reader.score(rb['em'], txt) if rb['em'] is not None else 9
                        if best_r is None or sc_ < best_r[0]:
                            best_r = (sc_, rb)
                    r = best_r[1] if len(run) == 1 else r
                    if len(run) > 1:
                        # (Several rows: each at the offset its own reading
                        # is clearest.)
                        cand_ = []
                        for off in (0, -3, 3, -6, 6):
                            rb = dict(r, base=r['base'] + off)
                            rb['em'] = reader.emissions(pg['im'], [rb])[0]
                            rb['geo'] = reader.geometry[0]
                            if rb['em'] is None:
                                continue
                            em_ = rb['em']
                            cand_.append((float(-(em_.max(1)[0].log() if hasattr(em_.max(1), '__getitem__') else 0).mean()) if False else
                                          -float(em_.max(1).values.mean()) if hasattr(em_.max(1), 'values') else 0, off, rb))
                        if cand_:
                            r = min(cand_, key=lambda c: c[0])[2]
                    ch_ = {q: 0 for q in range(s0, e_end)}
                    left = len(run) - n_ - 1
                    ends = [e_end] if not left else range(s0 + 2, e_end - 2 * left + 1)

                    def L_(a, b, rw=r):
                        # (A paragraph's big opening word starts a row.)
                        if any(T[q][-1] for q in range(a + 1, b)):
                            return 9
                        ws_ = [w for w in flat(T[a:b], [ch_[q] for q in range(a, b)]) if w]
                        if T[a][-1]:
                            ws_ = ws_[len(T[a][0]):]
                        return reader.score(rw['em'], ' '.join(ws_).replace(NAME, pg['name']).replace('\u00a7', '')) if ws_ and rw['em'] is not None else 9
                    # (A printing the page's well-read rows use for the same
                    # words decides; the reader's loss only where they don't:
                    # it can't tell ה' from יי in small type.)
                    used = Counter(c for q in sp if (q.get('result') or '').startswith('drawn') for c in q.get('choice', []))
                    for q in range(s0, e_end):
                        if len(T[q]) > 2:
                            key_ = repr(T[q][:-1])
                            seen_c = [(used[(key_, c)], c) for c in range(len(T[q]) - 1)]
                            if max(seen_c)[0] > 0:
                                ch_[q] = max(seen_c)[1]
                    fixed = {q for q in range(s0, e_end) if len(T[q]) > 2 and max(used[(repr(T[q][:-1]), c)] for c in range(len(T[q]) - 1)) > 0}

                    def choose_in(a, b, rw):
                        for _ in range(2):
                            for q in range(a, b):
                                if len(T[q]) > 2 and q not in fixed:
                                    best_c = []
                                    for c in range(len(T[q]) - 1):
                                        ch_[q] = c
                                        best_c.append((L_(a, b, rw) + STOP * (nostop(T[q], c) + nomark(T[q], c)), c))
                                    ch_[q] = min(best_c)[1]
                    if left:
                        # (This row's end and the rest's together: the least
                        # loss over the run, not this row's alone.)
                        rest = run[n_ + 1:]
                        memo = {}

                        def tail(k, a):
                            if (k, a) in memo:
                                return memo[k, a]
                            rw = rest[k]
                            if k == len(rest) - 1:
                                v = L_(a, e_end, rw) if a < e_end else 9
                            else:
                                v = min((L_(a, b2, rw) + tail(k + 1, b2) for b2 in range(a + 1, e_end - (len(rest) - k - 1) + 1)), default=99)
                            memo[k, a] = v
                            return v
                        e = min(ends, key=lambda e: L_(s0, e) + tail(0, e))
                        choose_in(s0, e, r)
                        memo.clear()
                        e = min(ends, key=lambda e: L_(s0, e) + tail(0, e))
                    else:
                        e = e_end
                    choose_in(s0, e, r)
                    words = flat(T[s0:e], [ch_[q] for q in range(s0, e)])
                    opener = bool(T[s0][-1])
                    rr = dict(r, ext_ok=2.0)
                    res = draw(rr, words, opener) if words else 'empty'
                    if os.environ.get('SIYUM_DEBUG'):
                        print('BETWEEN', f.stem, round(r['base']), opener, res if isinstance(res, str) else 'ok', rr.get('loss'), ' '.join(words)[:70], file=sys.stderr)
                    if isinstance(res, str) and opener:
                        res = draw(dict(r, ext_ok=2.0), words[len(T[s0][0]):], False)
                    if isinstance(res, str):
                        s0 = e
                        continue
                    run[n_]['tried'] = (run[n_].get('tried') or []) + ['drawn between its neighbours']
                    run[n_]['result'] = 'drawn: ' + ' '.join(w[3] for w in res[0])
                    new += res[0]
                    boxes += res[1]
                    tot['rows'] += 1
                    tot['words'] += len(res[0])
                    s0 = e

        def under(w):
            return any(abs(w[5] - b['base']) < 0.6 * b['h'] and b['x0'] - 5 <= w[4] <= b['x1'] + 5 for b in boxes)
        old = [w for w in place['placed'] if not (w[1] < 0 and under(w))]
        tot['replaced'] += len(place['placed']) - len(old)
        place['placed'] = old + new
        # The app sizes the page by `frame` (the ink's extent, as
        # svg.placement measures it), so it must take in the new words.
        if new:
            x0, y0, x1, y1 = place['frame']
            for w in new:
                x0 = min(x0, w[4])
                x1 = max(x1, w[4] + fonts.width(svg.RASHI if w[2] else svg.SQUARE, 1, w[3]) * w[6])
                y0 = min(y0, w[5] - 1.1 * w[7])
                y1 = max(y1, w[5] + 0.35 * w[7])
            place['frame'] = [round(x0), round(y0), round(x1), round(y1)]
        (a.out / f.name).write_text(json.dumps(place, ensure_ascii=False, separators=(',', ':')))
        print(f.stem, 'drawn', len(boxes), 'of', len(pg['rows']), flush=True)
    a.text.write_text(json.dumps([dict(page=n, at=[round(r['x0']), round(r['x1']), round(r['base']), round(r['h'])],
                                       read=' '.join(r['read']), span=r.get('span'), result=r.get('result'), loss=r.get('loss'), tried=r.get('tried'))
                                  for n, pg in pages.items() for r in pg['rows']], ensure_ascii=False, indent=1))
    print('total', dict(tot))


if __name__ == '__main__':
    main()
