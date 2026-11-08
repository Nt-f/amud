#!/usr/bin/env python3
"""The printed page's text where Sefaria has none: the small commentaries
in the margins and at the foot of the page, and lines of the body that
match none of Sefaria's text.

    textpass.py Berakhot 2a-10b [--cache build/daf_cache] [--out build/daf_text]

writes OUT/<Book>_<amud>.json:

    {"book", "amud",
     "body":    [{"stream", "box", "text"}],       lines Sefaria lacks
     "margins": [{"side", "section", "heading": [{"box", "text"}],
                  "lines": [{"box", "base", "text", "words"}]}]}

`side` is "left", "right" or "foot"; `section` is the commentary's heading
as printed above it on the page (עין משפט נר מצוה, מסורת הש"ס, …); at the
top of a margin, the section it carries on from the amud before
("continued": true, when that amud was done first), or null. Boxes are
[x0, y0, x1, y1] on the scan; a margin line's `words` are [text, x0, x1]
each, its words as read with where they are on the scan. `heading` is the
heading's own line or two.

Lines are read by heb_vilna_rashi (the margins' Rashi script; the Gemara
by heb_vilna_square). The
page's own OCR and line map come from linemap.py, with its environment
(OCR_LANG, TESSERACT, TESSDATA_PREFIX).
"""

import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image
from rapidfuzz import fuzz

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from lineread import best_words  # noqa: E402

SQUARE = os.environ.get('OCR_SQUARE', 'heb_vilna_square')
RASHI = os.environ.get('OCR_RASHI', 'heb_vilna_rashi')

# The commentaries Sefaria has, by the line map's name for them.
KNOWN = {'rng': 'רב נסים גאון', 'gilyon': 'גליון הש"ס'}

# The small commentaries' headings, as printed (some over two lines).
HEADINGS = ['עין משפט נר מצוה', 'מסורת הש"ס', 'תורה אור השלם', 'תורה אור', 'הגהות הב"ח', 'גליון הש"ס',
            'רב נסים גאון', 'הגהות הגר"א', 'רבינו חננאל', 'תוספות ישנים', 'הגהות מהר"ב רנשבורג',
            'ליקוטי רש"י', 'שיטה מקובצת', 'רבינו גרשום', 'תוספות שאנץ']


def _words(rows):
    """The page OCR's words, in scan pixels."""
    k = linemap.OCR_SCALE
    out = []
    for r in rows:
        x0, y0 = int(r['left']) / k, int(r['top']) / k
        out.append(dict(text=r['text'].strip(), x0=x0, y0=y0, x1=x0 + int(r['width']) / k, y1=y0 + int(r['height']) / k,
                        key=(r['block_num'], r['par_num'], r['line_num'])))
    return out


def _lines(words, gap):
    """Words into printed lines: by height on the page, then cut where a
    gap wider than `gap` parts them (two notes side by side at the foot)."""
    if not words:
        return []
    h = float(np.median([w['y1'] - w['y0'] for w in words]))
    rows, cur = [], []
    for w in sorted(words, key=lambda w: (w['y0'] + w['y1']) / 2):
        if cur and (w['y0'] + w['y1']) / 2 - np.mean([(v['y0'] + v['y1']) / 2 for v in cur]) > 0.6 * h:
            rows.append(cur)
            cur = []
        cur.append(w)
    rows.append(cur)
    out = []
    for row in rows:
        row.sort(key=lambda w: -w['x1'])
        piece = [row[0]]
        for w in row[1:]:
            if piece[-1]['x0'] - w['x1'] > gap:
                out.append(piece)
                piece = []
            piece.append(w)
        out.append(piece)
    return [_line(p) for p in out]


def _line(ws):
    """A line made of these words (in reading order)."""
    ws = sorted(ws, key=lambda w: -w['x1'])
    return dict(x0=min(w['x0'] for w in ws), x1=max(w['x1'] for w in ws), y0=min(w['y0'] for w in ws), y1=max(w['y1'] for w in ws),
                base=float(np.median([w['y1'] for w in ws])), h=float(np.median([w['y1'] - w['y0'] for w in ws])), words=ws)


def _tess_lines(words, h):
    """Words into printed lines as Tesseract grouped them (which allows for
    a page scanned a little askew, across the whole width), with pieces on
    one baseline joined."""
    groups = {}
    for w in words:
        groups.setdefault(w['key'], []).append(w)
    out = []
    for l in sorted((_line(g) for g in groups.values()), key=lambda l: (l['base'], -l['x1'])):
        # One line: their boxes share most of their height (baselines can
        # wander a little across the page).
        m = next((m for m in out if min(m['y1'], l['y1']) - max(m['y0'], l['y0']) > 0.5 * min(m['y1'] - m['y0'], l['y1'] - l['y0'])
                  and l['x0'] - m['x1'] < 3 * h and m['x0'] - l['x1'] < 3 * h), None)
        if m:
            out[out.index(m)] = _line(m['words'] + l['words'])
        else:
            out.append(l)
    return sorted(out, key=lambda l: l['base'])


def _heading(text):
    """The heading a line's text is, if it is one."""
    t = linemap.fold(text.replace('.', ''), linemap.FOLD_SQUARE)
    best = max(HEADINGS, key=lambda s: fuzz.ratio(t, linemap.fold(s, linemap.FOLD_SQUARE)))
    return best if fuzz.ratio(t, linemap.fold(best, linemap.FOLD_SQUARE)) >= 75 else None


def _sections(lines, side):
    """A column's lines (top to bottom) under the heading each follows. A
    heading is a line or two of a few words that read as one of HEADINGS
    (עין משפט / נר מצוה); an ornament between sections reads as no text."""
    out, cur, k = [], dict(side=side, section=None, lines=[]), 0
    by_label = False  # the section came from the line map, not a heading
    while k < len(lines):
        l = lines[k]
        name = None
        if len(l['text'].split()) <= 3:
            name = _heading(l['text'])
            # Over two lines, unless the next is one by itself (and this
            # line the ornament above it).
            two = (not name and k + 1 < len(lines) and len(lines[k + 1]['text'].split()) <= 3
                   and not _heading(lines[k + 1]['text']))
            if two and _heading(l['text'] + ' ' + lines[k + 1]['text']):
                name = _heading(l['text'] + ' ' + lines[k + 1]['text'])
                k += 1
        heading = name is not None
        if not heading and (cur['section'] is None or by_label):
            # No heading above it on this page: the commentary the line map
            # matched it to, if any (Sefaria's text of Rav Nissim Gaon or
            # Gilyon HaShas, carried on from the margin).
            known = KNOWN.get(l.get('label'))
            if known and known != cur['section']:
                name = known
        if name:
            if cur['lines'] or cur['section']:
                out.append(cur)
            cur, by_label = dict(side=side, section=name, lines=[]), not heading
            if heading:
                cur['heading'] = [dict(box=x['box'], text=x['text']) for x in lines[k - (l is not lines[k]):k + 1]]
        if not heading and len(linemap._HEB.findall(l['text'])) >= 2:
            cur['lines'].append(dict(box=l['box'], base=round(l['base'], 1), text=l['text'], words=l['read']))
        k += 1
    if cur['lines'] or cur['section']:
        out.append(cur)
    return out


def amud_text(cache, book, amud, lines_out=None):
    """The amud's text (see above); with `lines_out`, the line map's lines
    are added there too (svg.py sets them)."""
    lines = [] if lines_out is None else lines_out
    res, _ = linemap.amud_map(cache, book, amud, lines_out=lines)
    img_path, rows = linemap.ocr(cache, book, amud)
    im = Image.open(img_path)
    im.load()  # before the threads crop it
    fx0, top, fx1, bottom = res['frame']
    # The frame's sides from the lines matched to the body's texts: a stray
    # piece can widen the line map's frame over a margin's column.
    matched = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]
    if matched:
        fx0, fx1 = min(l['x0'] for l in matched), max(l['x1'] for l in matched)
    words = _words(rows)
    h = float(np.median([w['y1'] - w['y0'] for w in words]))

    # The body's lines that matched none of Sefaria's text.
    body = [l for l in lines if l.get('stream') in ('main', 'inner', 'outer') and ('range' not in l or l.get('score', 100) < 50)
            and l.get('letters', 99) >= 4]
    # The margins outside the frame, and the foot of the page below the
    # body (its lines can run past the frame's width).
    end = max((l['base'] for l in lines if l.get('stream') in ('main', 'inner', 'outer') and 'range' in l), default=bottom)
    cx = lambda w: (w['x0'] + w['x1']) / 2
    cy = lambda w: (w['y0'] + w['y1']) / 2
    foot = [w for w in words if cy(w) > end + 0.5 * h]
    margin = {'right': _lines([w for w in words if cx(w) > fx1 + 3 and cy(w) <= end + 0.5 * h], 2.5 * h),
              'left': _lines([w for w in words if cx(w) < fx0 - 3 and cy(w) <= end + 0.5 * h], 2.5 * h),
              'foot': _split_columns(_tess_lines(foot, h), foot, h)}

    # Each line, as the line map labelled the line on its baseline there.
    for ls in margin.values():
        for l in ls:
            m = [n for n in lines if n.get('stream') in KNOWN and abs(n['base'] - l['base']) < 0.5 * l['h']
                 and min(n['x1'], l['x1']) - max(n['x0'], l['x0']) > 0]
            l['label'] = m[0]['stream'] if m else None

    # A body line matching none of Sefaria's text may be in either script,
    # whatever the line map called it.
    jobs = [(l, (SQUARE, RASHI)) for l in body]
    for s, ls in margin.items():
        mh = float(np.median([l['h'] for l in ls])) if ls else 0
        # Headings are square letters; the rest Rashi script.
        jobs += [(l, SQUARE if l['h'] > 1.25 * mh else RASHI) for l in ls]

    def one(job):
        l, model = job
        l['box'] = linemap.line_box(l)
        img = linemap.line_image(im, l['box'])
        k = linemap.OCR_SCALE
        l['read'] = [[t, round(l['box'][0] + x0 / k, 1), round(l['box'][0] + x1 / k, 1)]
                     for t, x0, x1, _ in best_words(img, model if isinstance(model, tuple) else (model,))]
        l['text'] = ' '.join(w[0] for w in l['read'])
    with ThreadPoolExecutor(os.cpu_count()) as ex:
        list(ex.map(one, jobs))

    out = dict(book=book, amud=amud,
               body=[dict(stream=l['stream'], box=l['box'], text=l['text']) for l in sorted(body, key=lambda l: (l['stream'], l['base']))],
               margins=[])
    for s, ls in margin.items():
        if s == 'foot':
            # Side by side notes: each runs down its own part of the width.
            for part in _foot_parts(ls):
                out['margins'] += _sections(part, s)
        else:
            out['margins'] += _sections(sorted(ls, key=lambda l: l['base']), s)
    return out


def _split_columns(lines, words, h):
    """The foot's notes are set in columns side by side, with a narrow white
    gutter: lines cut where few of the foot's words cross it."""
    if len(lines) < 4:
        return lines  # too few lines to tell a gutter from a wide space
    x0, x1 = int(min(w['x0'] for w in words)), int(max(w['x1'] for w in words)) + 1
    cov = np.zeros(x1 - x0 + 1)
    for w in words:
        cov[int(w['x0']) - x0:int(w['x1']) - x0 + 1] += 1
    # Free: inside at least three lines' extent (and half of them), yet
    # crossed by almost none of their words.
    span = np.zeros_like(cov)
    for l in lines:
        span[int(l['x0']) - x0:int(l['x1']) - x0 + 1] += 1
    free = (span >= max(3, 0.5 * len(lines))) & (cov <= 0.1 * span)
    # Gutters: runs of free x at least a third of a letter wide, away from
    # the edges.
    cuts, k = [], 0
    while k < len(free):
        if free[k]:
            j = k
            while j < len(free) and free[j]:
                j += 1
            if j - k >= h / 2 and k > 2 * h and j < len(free) - 2 * h:
                cuts.append(x0 + (k + j) / 2)
            k = j
        else:
            k += 1
    if not cuts:
        return lines
    out = []
    for l in lines:
        for a, b in zip([-np.inf] + cuts, cuts + [np.inf]):
            part = [w for w in l['words'] if a <= (w['x0'] + w['x1']) / 2 < b]
            if part:
                out.append(_line(part))
    return out


def _foot_parts(lines):
    """The foot's lines, grouped into the notes set side by side there:
    pieces of a line that share an edge with the piece above go with it."""
    parts = []
    for l in sorted(lines, key=lambda l: (l['base'], -l['x1'])):
        for p in parts:
            last = p[-1]
            if last['base'] < l['base'] and min(last['x1'], l['x1']) - max(last['x0'], l['x0']) > 0.5 * min(last['x1'] - last['x0'], l['x1'] - l['x0']):
                p.append(l)
                break
        else:
            parts.append([l])
    return parts


def _role(side, amud):
    """A side margin as inner (by the binding) or outer: on an a-side the
    binding is on the right."""
    return side if side == 'foot' else ('inner' if (side == 'right') == amud.endswith('a') else 'outer')


def carry(prev, cur):
    """A margin's first section, untitled on this amud, goes on with the
    section its margin (inner or outer, the same commentaries) ended with
    on the amud before."""
    last = {}
    for m in prev['margins']:
        if m['side'] != 'foot':
            last[_role(m['side'], prev['amud'])] = m['section']
    seen = set()
    for m in cur['margins']:
        if m['side'] in seen or m['side'] == 'foot':
            continue
        seen.add(m['side'])
        if m['section'] is None and last.get(_role(m['side'], cur['amud'])):
            m['section'] = last[_role(m['side'], cur['amud'])]
            m['continued'] = True


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+', help='amudim, or ranges like 2a-10b')
    p.add_argument('--cache', default='build/daf_cache')
    p.add_argument('--out', default='build/daf_text')
    a = p.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for amud in linemap.amudim(a.amudim):
        try:
            res = amud_text(Path(a.cache), a.book, amud)
        except SystemExit as e:
            print(amud, 'failed:', e)
            continue
        before = out / f'{a.book.replace(" ", "_")}_{linemap.neighbor(amud, -1)}.json'
        if before.exists():
            carry(json.loads(before.read_text()), res)
        (out / f'{a.book.replace(" ", "_")}_{amud}.json').write_text(json.dumps(res, ensure_ascii=False, indent=1))
        print(amud, f'{len(res["body"])} body lines Sefaria lacks;',
              ', '.join(f'{m["section"] or "?"} ({m["side"]}, {len(m["lines"])})' for m in res['margins']))


if __name__ == '__main__':
    sys.exit(main())
