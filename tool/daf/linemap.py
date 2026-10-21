#!/usr/bin/env python3
"""Line maps of the Vilna page: which words of the app's text fall on each
printed line of an amud, and where that line is on the page.

The app's tzuras hadaf used to reflow the text with daf-renderer's rules,
which looks like a daf but breaks every line in the wrong place. This reads
the line breaks off the Romm Vilna scans instead (National Library of
Israel, served by Sefaria at manuscripts.sefaria.org) and keeps only that:
the boxes and word ranges, not the image. The app sets the words itself, in
its own fonts, into the printed lines.

    linemap.py Berakhot 2a-10b … [--out DIR] [--cache DIR] [--debug]

For each amud:

1. OCR the scan with Tesseract (`heb`) at 3×, word boxes.
2. Regroup words into lines, splitting a line where a gap is wider than the
   text is tall (Tesseract sometimes runs a line across a gutter).
3. Say which text each line is. Square letters (Gemara, Rav Nissim Gaon,
   Ein Mishpat) OCR well; Rashi script comes out as look-alike letters, so
   it is compared folded to letter classes (FOLD). Where on the page the
   line is decides between the Gemara, the inner margin (Rashi) and the
   outer one (Tosafot), and lines outside that frame are the small
   commentaries.
4. Per text, align its lines in page order (top to bottom) to the app's
   words of it, character by character, and read off the word that ends
   each line. OCR errors don't move the result much: only the line ends
   matter, and the alignment is over the whole column.

Words are counted exactly as the app counts them (`dafWords` in
lib/features/gemara/daf_page.dart): the Gemara is Sefaria's Wikisource text
and the margins are Sefaria's default Hebrew of Rashi and Tosafot, each
comment split into its opening words and the rest (`Comment.split`).

Needs `tesseract` with `heb` (set TESSERACT and TESSDATA_PREFIX if it isn't
installed), numpy, Pillow and rapidfuzz. Rashi script reads far better with
the model train_ocr.py makes from the pages themselves: OCR_LANG=heb_vilna.
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from rapidfuzz import fuzz

SCAN = 'https://manuscripts.sefaria.org/vilna-romm/{book}_{amud}.jpg'
API = 'https://www.sefaria.org/api/v3/texts/'
WIKISOURCE = 'Wikisource Talmud Bavli'
OCR_SCALE = 3
# The Tesseract model: heb, or heb_vilna from train_ocr.py, which reads
# Rashi script as itself.
OCR_LANG = os.environ.get('OCR_LANG', 'heb')

# ------------------------------------------------------------------ text

# Rashi script read as square letters: what Tesseract confuses, folded to
# one letter per class. Square text is compared with only final forms
# folded.
_CLASSES = ['אהסתםחש', 'טש', 'בכך', 'רלד', 'וזיןן', 'נגן', 'עצץ', 'פף', 'מם']
FOLD_RASHI = {}
for cls in _CLASSES:
    for c in cls:
        FOLD_RASHI.setdefault(c, cls[0])
FOLD_SQUARE = dict(zip('ךםןףץ', 'כמנפצ'))
_HEB = re.compile(r'[א-ת]')


def fold(s, table):
    out = []
    for c in s:
        if _HEB.match(c):
            out.append(table.get(c, c))
        elif c.isspace() and out and out[-1] != ' ':
            out.append(' ')
    return ''.join(out).strip()


_FOOTNOTE = re.compile(r'<sup[^>]*class="footnote-marker"[^>]*>.*?</sup>|<i[^>]*class="footnote"[^>]*>.*?</i>', re.S)


def words_of_html(html):
    """The words of `wordsOfHtml` (daf_layout.dart): tags break words,
    footnotes are skipped, whitespace and &nbsp;/&thinsp; separate."""
    html = _FOOTNOTE.sub(' ', html)
    html = re.sub(r'<[^>]+>', ' ', html).replace('&nbsp;', ' ').replace('&thinsp;', ' ')
    return html.split()


def comment_split(he):
    """`Comment.split` in gemara_data.dart: (opening words, rest)."""
    plain = he.strip()
    m = re.match(r'^<b>(.*?)</b>\.?', plain, re.S)
    if m:
        return m.group(1).strip(), plain[m.end():].strip()
    m = re.search(r'\s[–\-—]\s', plain)
    if m and m.start() < 120:
        return plain[:m.start()].strip(), plain[m.end():].strip()
    dot = plain.find('.')
    if 0 < dot < 80:
        return plain[:dot + 1].strip(), plain[dot + 1:].strip()
    return '', plain


def comment_words(segments):
    """Margin words in page order: per Gemara segment, each comment."""
    out = []
    for seg in segments:
        for c in (seg if isinstance(seg, list) else [seg]):
            if not isinstance(c, str):
                continue
            dh, rest = comment_split(c)
            out += words_of_html(dh) + words_of_html(rest)
    return out


def flat_words(text):
    if isinstance(text, list):
        return [w for t in text for w in flat_words(t)]
    return words_of_html(text) if isinstance(text, str) else []

# ------------------------------------------------------------------ fetch


def fetch(url, path):
    path = Path(path)
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={'User-Agent': 'amud-linemap/1'})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
                break
            except urllib.error.HTTPError as e:
                if e.code in (400, 404):
                    path.write_bytes(b'null')
                    return None
                if attempt == 4 or e.code < 500 and e.code != 429:
                    raise
            except (urllib.error.URLError, TimeoutError):
                if attempt == 4:
                    raise
            time.sleep(5 * 2 ** attempt)
        path.write_bytes(data)
    data = path.read_bytes()
    return None if data == b'null' else data


def sefaria(cache, ref, version):
    q = urllib.parse.urlencode({'version': version})
    data = fetch(API + urllib.parse.quote(ref.replace(' ', '_')) + '?' + q, cache / 'text' / f'{ref}.{version.replace("|", "_")}.json')
    if data is None:
        return None
    vs = json.loads(data).get('versions') or []
    return vs[0]['text'] if vs else None


def _margins(cache, book, amud):
    """The app's words of an amud's inner margin (Rashi, and the Rashbam or
    the Mefaresh where they print) and outer one (Tosafot)."""
    ref = f'{book}.{amud}'
    inner_ids = ['Rashi'] + (['Rashbam'] if book == 'Bava Batra' else []) + (['Mefaresh'] if book == 'Tamid' else [])
    inner_by_id = {c: sefaria(cache, f'{c} on {ref}', 'hebrew') or [] for c in inner_ids}
    # margin(inner: true): per segment, each inner commentary in turn.
    inner = []
    segs = max(len(v) for v in inner_by_id.values()) if inner_by_id else 0
    for i in range(segs):
        for c in inner_ids:
            v = inner_by_id[c]
            if i < len(v):
                inner += comment_words([v[i]])
    return inner, comment_words(sefaria(cache, f'Tosafot on {ref}', 'hebrew') or [])


def neighbor(amud, step):
    """'3a', -1 → '2b'; None before 2a."""
    n = int(amud[:-1]) * 2 - (amud[-1] == 'a') + step
    return f'{(n + 1) // 2}{"a" if n % 2 else "b"}' if n >= 3 else None


def texts(cache, book, amud):
    """The streams to find on the page: the app's words for the Gemara and
    margins, and the others it may hold, by id: the small commentaries
    Sefaria has, and the neighboring amudim's Rashi and Tosafot (a comment
    printed across a page break is all filed under one amud)."""
    ref = f'{book}.{amud}'
    main = []
    for seg in sefaria(cache, ref, f'hebrew|{WIKISOURCE}') or []:
        main += words_of_html(seg)
    inner, outer = _margins(cache, book, amud)
    streams = {'main': main, 'inner': inner, 'outer': outer}
    extra = {}
    for cid, name in [('rng', 'Rav Nissim Gaon'), ('gilyon', 'Gilyon HaShas')]:
        t = sefaria(cache, f'{name} on {ref}', 'hebrew')
        if t:
            extra[cid] = flat_words(t)
    for step, tag in ((-1, 'prev'), (1, 'next')):
        other = neighbor(amud, step)
        if other and sefaria(cache, f'{book}.{other}', f'hebrew|{WIKISOURCE}'):
            i, o = _margins(cache, book, other)
            extra[f'inner_{tag}'], extra[f'outer_{tag}'] = i, o
    return streams, extra

# ------------------------------------------------------------------ OCR


def ocr(cache, book, amud):
    tsv = cache / 'ocr' / ('' if OCR_LANG == 'heb' else OCR_LANG) / f'{book}_{amud}.tsv'
    img_path = cache / 'scan' / f'{book}_{amud}.jpg'
    if fetch(SCAN.format(book=book.replace(' ', '_'), amud=amud), img_path) is None:
        raise SystemExit(f'no scan for {book} {amud}')
    if not tsv.exists():
        tsv.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(img_path).convert('L')
        im = im.resize((im.width * OCR_SCALE, im.height * OCR_SCALE), Image.LANCZOS)
        big = tsv.with_suffix('.tmp.png')
        im.save(big)
        exe = os.environ.get('TESSERACT', 'tesseract')
        subprocess.run([exe, str(big), str(tsv.with_suffix('')), '-l', OCR_LANG, '--psm', '3', '-c', 'tessedit_create_tsv=1'],
                       check=True, capture_output=True)
        big.unlink()
    rows = _words(tsv.read_text())
    gaps = tsv.with_name(tsv.stem + '.gaps.tsv')
    if not gaps.exists():
        gaps.write_text(_fill_gaps(Image.open(img_path), rows))
    return img_path, rows + _words(gaps.read_text())


def _words(tsv_text):
    return [r for r in csv.DictReader(io.StringIO(tsv_text), delimiter='\t', quoting=csv.QUOTE_NONE)
            if r['level'] == '5' and (r['text'] or '').strip()]


def _fill_gaps(image, rows):
    """Tesseract's page segmentation sometimes skips a run of clean lines
    outright. Ink no word covers is grouped into line-shaped blobs, and each
    is read as a line; its words come back as TSV rows (in the 3× page's
    pixels, like the rest), blocks numbered from 10000."""
    gray = np.asarray(image.convert('L'))
    ink = gray < 140
    covered = np.zeros_like(ink)
    k = OCR_SCALE
    for r in rows:
        # A letter or two is often a scrap Tesseract boxed across several
        # lines it otherwise skipped: it doesn't count as reading them.
        if len(_HEB.findall(r['text'])) <= 2:
            continue
        x0, y0 = int(r['left']) // k, int(r['top']) // k
        x1, y1 = x0 + int(r['width']) // k + 1, y0 + int(r['height']) // k + 1
        covered[max(0, y0 - 2):y1 + 2, max(0, x0 - 2):x1 + 2] = True
    left = ink & ~covered
    # Smear along the line, a little across it, and find the blobs.
    h = np.zeros(left.shape, dtype=np.int32)
    run = np.cumsum(left, axis=1)
    h[:, 8:-8] = run[:, 16:] - run[:, :-16]
    blob = h > 0
    out = ['level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext']
    rows_with_ink = blob.any(axis=1)
    y = 0
    block = 10000
    while y < blob.shape[0]:
        if not rows_with_ink[y]:
            y += 1
            continue
        y_end = y
        while y_end < blob.shape[0] and rows_with_ink[y_end]:
            y_end += 1
        for a, b in _cut_lines(left, y, y_end):
            band = blob[a:b].any(axis=0)
            x = 0
            while x < band.shape[0]:
                if not band[x]:
                    x += 1
                    continue
                x_end = x
                while x_end < band.shape[0] and band[x_end]:
                    x_end += 1
                if x_end - x >= 30 and 8 <= b - a <= 40 and left[a:b, x:x_end].sum() > 60:
                    out += _read_line(image, x, a, x_end, b, block)
                    block += 1
                x = x_end
        y = y_end
    return '\n'.join(out) + '\n'


def _cut_lines(ink, y0, y1):
    """Rows y0..y1 of ink cut into lines where the ink is thinnest (lines
    touch through their ascenders and descenders)."""
    if y1 - y0 <= 36:
        return [(y0, y1)]
    prof = ink[y0:y1].sum(axis=1).astype(float)
    mid = len(prof) // 2
    lo, hi = max(8, mid - 15), min(len(prof) - 8, mid + 15)
    if hi <= lo:
        return [(y0, y1)]
    cut = y0 + lo + int(np.argmin(prof[lo:hi]))
    return _cut_lines(ink, y0, cut) + _cut_lines(ink, cut, y1)


def _read_line(image, x0, y0, x1, y1, block):
    """TSV word rows for one line of the scan, read with --psm 7."""
    pad = 6
    crop = image.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)).convert('L')
    crop = crop.resize((crop.width * OCR_SCALE, crop.height * OCR_SCALE), Image.LANCZOS)
    exe = os.environ.get('TESSERACT', 'tesseract')
    with tempfile.TemporaryDirectory() as d:
        png = Path(d) / 'line.png'
        crop.save(png)
        subprocess.run([exe, str(png), str(Path(d) / 'line'), '-l', OCR_LANG, '--psm', '7', '-c', 'tessedit_create_tsv=1'], capture_output=True)
        tsv = Path(d) / 'line.tsv'
        if not tsv.exists():
            return []
        words = _words(tsv.read_text())
        # Scraps of letters a word's box missed read as a letter or two; a
        # line that was really skipped has a line's worth.
        if sum(len(_HEB.findall(r['text'])) for r in words) < 8:
            return []
        out = []
        for r in words:
            left = int(r['left']) + (x0 - pad) * OCR_SCALE
            top = int(r['top']) + (y0 - pad) * OCR_SCALE
            out.append('\t'.join(['5', '1', str(block), '1', '1', r['word_num'], str(left), str(top), r['width'], r['height'], r['conf'], r['text']]))
        return out


def lines_of(rows, image):
    """OCR words → lines. Tesseract sometimes runs a line across a gutter
    (Gemara into Rashi, Rashi into Masoret HaShas), so a line is split where
    a gap lies on one of the page's gutters, or is wider than the text is
    tall. Justified Gemara lines have wide spaces too, but not on a gutter."""
    g = defaultdict(list)
    for r in rows:
        g[(r['block_num'], r['par_num'], r['line_num'])].append(r)
    k = OCR_SCALE
    groups = []
    for ws in g.values():
        ws = [dict(x0=int(w['left']) / k, y0=int(w['top']) / k, x1=(int(w['left']) + int(w['width'])) / k,
                   y1=(int(w['top']) + int(w['height'])) / k, text=w['text']) for w in ws]
        ws.sort(key=lambda w: -w['x1'])
        groups.append(ws)
    # Specks and rules read as "=" or "-" would bridge a gutter.
    groups = [[w for w in ws if _HEB.search(w['text']) or re.search(r'\d', w['text']) or w['x1'] - w['x0'] > 0.6 * (w['y1'] - w['y0'])]
              for ws in groups]
    groups = [part for ws in groups if ws for part in _rows(ws)]
    words = [w for ws in groups for w in ws]
    out = []
    for gi, ws in enumerate(groups):
        h = float(np.median([w['y1'] - w['y0'] for w in ws]))
        base = float(np.median([w['y1'] for w in ws]))
        mine = {id(w) for w in ws}
        gutters = _gutters([w for w in words if abs(w['y1'] - base) < 5 * h and id(w) not in mine], image.width)
        raw = (min(w['x0'] for w in ws), max(w['x1'] for w in ws), min(w['y0'] for w in ws))
        # A piece remembers its OCR line (group), and which column of it
        # (col, counting splits at gutters but not at wide spaces).
        col = 0
        ws = [dict(p, raw=raw, group=gi, col=0, gutters=gutters) for w in ws for p in _split_word(w, gutters, image)]
        cur = [ws[0]]
        for w in ws[1:]:
            a, b = w['x1'], cur[-1]['x0']
            at_gutter = w.get('cut') or (b - a > 0.2 * h and gutters[int(a):int(b) + 1].any())
            if at_gutter or b - a > max(0.9 * h, 8):
                col += at_gutter
                out.append(cur)
                cur = [w]
            else:
                cur.append(w)
            w['col'] = col
        out.append(cur)
    return [_line(ws) for ws in out]


def _same_line(a, b):
    """Whether two pieces on one baseline are one printed line: never
    across a gutter."""
    h = max(a['h'], b['h'])
    if abs(a['base'] - b['base']) >= 0.5 * h or _overlap(a, b) > 0:
        return False
    if a.get('pos') is not None and b.get('pos') is not None and a.get('stream') == b.get('stream'):
        # The text runs on from the right piece into the left.
        right, left = (a, b) if a['x1'] > b['x1'] else (b, a)
        if abs(left['pos'] - (right['pos'] + right['letters'])) > max(8, 0.3 * min(a['letters'], b['letters'])):
            return False
    if a['group'] == b['group'] and a['group'] is not None:
        return a['col'] == b['col']
    x0, x1 = sorted((a['x1'], b['x0']) if a['x1'] < b['x0'] else (b['x1'], a['x0']))
    gap = _gap(a, b)
    return gap < 1.2 * h and not a['gutters'][int(x0):int(x1) + 1].any() and not b['gutters'][int(x0):int(x1) + 1].any()


def _rows(ws):
    """Tesseract now and then puts two printed lines in one: its words, cut
    where their centers jump down by more than half a line."""
    h = float(np.median([w['y1'] - w['y0'] for w in ws]))
    by_y = sorted(ws, key=lambda w: (w['y0'] + w['y1']) / 2)
    out, cur = [], [by_y[0]]
    for w in by_y[1:]:
        if (w['y0'] + w['y1']) / 2 - (cur[-1]['y0'] + cur[-1]['y1']) / 2 > 0.6 * h:
            out.append(cur)
            cur = [w]
        else:
            cur.append(w)
    out.append(cur)
    return [sorted(part, key=lambda w: -w['x1']) for part in out]


def _split_word(w, gutters, image):
    """A word box that crosses a gutter is two words of neighboring columns
    run together (no space between them in the OCR): cut the image at the
    gutter and read each side again."""
    x0, x1 = int(w['x0']), int(w['x1'])
    inside = np.flatnonzero(gutters[x0 + 3:x1 - 2]) + x0 + 3
    if len(inside) < 4:
        return [w]
    cut = int(np.median(inside))
    out = []
    for a, b in ((cut, x1), (x0, cut)):  # right to left
        piece = _ink(image, a, w['y0'], b, w['y1'])
        if piece:
            out.append(dict(piece, text=_read(image, piece), cut=bool(out)))
    return [p for p in out if p['text']] or [w]


def _ink(image, x0, y0, x1, y1):
    """The box of the ink in a region of the scan, or None."""
    a = np.asarray(image.crop((int(x0), int(y0), int(x1) + 1, int(y1) + 1)).convert('L')) < 128
    cols, rows = np.flatnonzero(a.any(axis=0)), np.flatnonzero(a.any(axis=1))
    if len(cols) == 0:
        return None
    return dict(x0=int(x0) + cols[0], x1=int(x0) + cols[-1] + 1, y0=int(y0) + rows[0], y1=int(y0) + rows[-1] + 1)


def _read(image, box):
    """OCR one piece of a line: as a line, else as a word (Tesseract
    sometimes reads nothing in a short piece as a line)."""
    pad = 10
    crop = image.crop((box['x0'] - pad, box['y0'] - pad, box['x1'] + pad, box['y1'] + pad)).convert('L')
    crop = crop.resize((crop.width * OCR_SCALE, crop.height * OCR_SCALE), Image.LANCZOS)
    exe = os.environ.get('TESSERACT', 'tesseract')
    with tempfile.NamedTemporaryFile(suffix='.png') as f:
        crop.save(f.name)
        for psm in ('7', '8', '6'):
            r = subprocess.run([exe, f.name, 'stdout', '-l', OCR_LANG, '--psm', psm], capture_output=True)
            text = ' '.join(r.stdout.decode('utf-8', 'replace').split())
            if text:
                return text
    return ''


def _gutters(words, width):
    """x positions that few of these words (the lines around one) cover
    compared with the text beside them: the white columns between the
    page's columns, where they are."""
    cov = np.zeros(width + 1)
    for w in words:
        cov[int(w['x0']):int(w['x1']) + 1] += 1
    cov = np.convolve(cov, np.ones(5) / 5, mode='same')
    around = np.array([cov[max(0, x - 60):x + 61].max() for x in range(len(cov))])
    return (cov <= 0.15 * around) & (around >= 5)


def _line(ws):
    hs = [w['y1'] - w['y0'] for w in ws]
    return dict(
        x0=min(w['x0'] for w in ws), x1=max(w['x1'] for w in ws),
        y0=min(w['y0'] for w in ws), y1=max(w['y1'] for w in ws),
        # The baseline: the bottom of most words (descenders and the big
        # opening words aside).
        base=float(np.median([w['y1'] for w in ws])), h=float(np.median(hs)),
        text=' '.join(w['text'] for w in ws), words=ws, raw=ws[0].get('raw'),
        group=ws[0].get('group') if len({w.get('group') for w in ws}) == 1 else None,
        col=ws[0].get('col'), gutters=ws[0].get('gutters'))

# ------------------------------------------------------------------ classify

# Anchors: runs of K letters (folded, spaces dropped) that occur exactly
# once in all the amud's texts together. A piece of OCR that contains a few
# of them is that text, at that place: chance matches of seven folded
# letters are rare, and seven letters read right are common.
K = 7
# The page body's texts: the amud's own, and its neighbors' margins
# carried across the page break.
CARRIED = ('inner_prev', 'outer_prev', 'inner_next', 'outer_next')
BODY = ('main', 'inner', 'outer') + CARRIED
HEADINGS = ['תורה אור', 'מסורת הש"ס', 'עין משפט', 'נר מצוה', 'הגהות הב"ח', 'גליון הש"ס', 'רבינו חננאל', 'רב נסים גאון',
            'הגהות הגר"א', 'ליקוטי רש"י', 'תוספות ישנים', 'הדרן עלך']


def _heading(text):
    f = fold(text, FOLD_SQUARE)
    return 0 < len(f) <= 14 and any(fuzz.ratio(f, fold(h, FOLD_SQUARE)) >= 75 for h in HEADINGS)


def _flat(s, table):
    return fold(s, table).replace(' ', '')


def _index(texts_by_id):
    """For each fold, every K-letter run of every text: where it occurs.
    Folding maps a letter to a letter, so positions agree between folds."""
    out = []
    for table in (FOLD_RASHI, FOLD_SQUARE):
        idx = defaultdict(list)
        for k, words in texts_by_id.items():
            r = _flat(' '.join(words), table)
            for i in range(len(r) - K + 1):
                idx[r[i:i + K]].append((k, i))
        out.append((table, idx))
    return out


def _anchor(l, index):
    """Per text with two hits or more: (where the piece starts in it, hits).
    Also sets l['any']: the texts any of its runs are in, unique or not."""
    hits = defaultdict(dict)  # text → piece offset → where it puts the start
    l['any'] = defaultdict(int)
    for table, idx in index:
        f = _flat(l['text'], table)
        for i in range(len(f) - K + 1):
            e = idx.get(f[i:i + K])
            if e and len(e) == 1:
                hits[e[0][0]][i] = e[0][1] - i
            for k in {k for k, _ in e or ()}:
                l['any'][k] += 1
    return {k: (float(np.median(list(v.values()))), len(v)) for k, v in hits.items() if len(v) >= 2}


def _word_hits(l, index):
    """Per word of a piece (right to left), the texts its anchors hit."""
    out = [defaultdict(int) for _ in l['words']]
    for table, idx in index:
        flat = [_flat(w['text'], table) for w in l['words']]
        f = ''.join(flat)
        owner = [k for k, w in enumerate(flat) for _ in w]
        for i in range(len(f) - K + 1):
            e = idx.get(f[i:i + K])
            if e and len(e) == 1:
                out[owner[i]][e[0][0]] += 1
    return out


def split_by_text(lines, index):
    """A piece whose right words are one text and left words another is
    two columns run together across a gutter too narrow (or too full of
    notes) to see: cut it where the text changes."""
    out, todo = [], list(lines)
    while todo:
        l = todo.pop()
        hits = _word_hits(l, index) if len(l['words']) >= 2 else []
        best = None
        for s in range(1, len(hits)):
            right, left = defaultdict(int), defaultdict(int)
            for h in hits[:s]:
                for k, v in h.items():
                    right[k] += v
            for h in hits[s:]:
                for k, v in h.items():
                    left[k] += v
            if not right or not left:
                continue
            a, b = max(right, key=right.get), max(left, key=left.get)
            if a != b and right[a] >= 3 and left[b] >= 3 and right[a] > 2 * right.get(b, 0) and left[b] > 2 * left.get(a, 0):
                score = right[a] + left[b] - right.get(b, 0) - left.get(a, 0)
                if best is None or score > best[0]:
                    best = (score, s)
        if best:
            s = best[1]
            for part in (l['words'][:s], l['words'][s:]):
                piece = _line(part)
                piece.update(group=None, col=None, gutters=l['gutters'])
                todo.append(piece)
        else:
            out.append(l)
    return out


def _take_best(l):
    # A neighbor's margin needs more to go on: a short quote matches it by
    # chance more easily than it matches a whole column.
    for k in [k for k in l['cands'] if k in CARRIED and l['cands'][k][1] < 4]:
        del l['cands'][k]
    if l['cands']:
        best = max(l['cands'], key=lambda k: l['cands'][k][1])
        l['stream'], (l['pos'], l['hits']) = best, l['cands'][best]
    else:
        l['stream'] = l['pos'] = None
        l['hits'] = 0


def _settle_claims(lines):
    """Two lines can't be the same stretch of one text. Where they claim to
    be (a commentary quoting the Gemara with the page's abbreviations, which
    the Gemara's own text spells out), the one with fewer hits gives that
    text up for its next best, or for its neighbors'."""
    for _ in range(10):
        changed = False
        by = defaultdict(list)
        for l in lines:
            if l['stream'] is not None:
                by[l['stream']].append(l)
        for ls in by.values():
            ls.sort(key=lambda l: l['pos'])
            for a, b in zip(ls, ls[1:]):
                overlap = min(a['pos'] + a['letters'], b['pos'] + b['letters']) - max(a['pos'], b['pos'])
                if overlap > 0.5 * min(a['letters'], b['letters']):
                    loser = a if a['hits'] < b['hits'] else b
                    loser['cands'].pop(loser['stream'], None)
                    _take_best(loser)
                    changed = True
                    break
        if not changed:
            return


def classify(lines, streams, extra):
    """Which text each line is (and roughly where in it): by its anchors,
    else by its neighbors'. Lines outside the body (the side columns, and
    the notes run the width of the page below it) are the small
    commentaries or "other"."""
    index = _index({**streams, **extra})
    lines[:] = split_by_text(lines, index)
    for l in lines:
        l['letters'] = len(_flat(l['text'], FOLD_RASHI))
        l['stream'] = l['pos'] = None
        l['any'] = {}
        l['cands'] = _anchor(l, index) if l['letters'] >= 2 and not _heading(l['text']) else {}
        _take_best(l)
    _settle_claims(lines)
    body = [l for l in lines if l['stream'] in ('main', 'inner', 'outer') and l['hits'] >= 3]
    if not any(l['stream'] == 'main' for l in body):
        raise SystemExit('no Gemara lines found')
    fx0 = float(np.percentile([l['x0'] for l in body], 2))
    fx1 = float(np.percentile([l['x1'] for l in body], 98))
    top = min(l['y0'] for l in body)
    # Below the body, notes run the width of the page past the frame on
    # both sides (Rav Nissim Gaon's continuation). As OCR'd, before being
    # split at the gutters; above the Gemara's end, such a line is the top
    # band run into the side columns.
    gem_end = max(l['y1'] for l in body if l['stream'] == 'main')
    wide = [l['raw'][2] for l in lines if l['raw'] and l['raw'][0] < fx0 - 20 and l['raw'][1] > fx1 + 20 and l['raw'][2] > gem_end - 4]
    bottom = min(wide) if wide else float('inf')
    for l in lines:
        outside = l['base'] > bottom or l['x1'] < fx0 + 6 or l['x0'] > fx1 - 6 or l['x0'] < fx0 - 20 or l['x1'] > fx1 + 20
        if outside and l['stream'] in BODY:
            l['stream'] = None
        if outside or l['y1'] < top - 4:
            l['outside'] = True
    # The rest of the body takes its neighbors' text, and a place in it
    # just before or after theirs.
    # A long line with no anchors at all is text none of these have (Sefaria
    # leaves out some Tosafot): it stays out rather than take a neighbor's.
    unknown = 15 if OCR_LANG != 'heb' else 40
    todo = [l for l in lines if l['stream'] is None and not l.get('outside') and 2 <= l['letters'] < unknown and not _heading(l['text'])]
    for l in lines:
        if l['stream'] is None and not l.get('outside') and l['letters'] >= unknown and sum(l['any'].values()) < 2:
            l['stream'] = 'other'
    _by_column(lines)
    done = [l for l in lines if l['stream'] in BODY]
    for _ in range(6):
        changed = False
        for l in todo:
            if l['stream'] is not None:
                continue
            n = _neighbor(l, done)
            if n:
                m, where = n
                l['stream'] = m['stream']
                l['pos'] = m['pos'] + (m['letters'] if where == 'after' else -l['letters'])
                done.append(l)
                changed = True
        if not changed:
            break
    _sandwiched(lines)
    for l in lines:
        if l['stream'] is None and l.get('outside') and l['letters'] >= 2:
            l['stream'] = 'other'
        if l['stream'] in streams and not streams[l['stream']]:
            l['stream'] = 'other'
    return dict(frame=(fx0, top, fx1, bottom if bottom < float('inf') else max(l['y1'] for l in body)))


def _by_column(lines):
    """A line whose text is on the page more than once (a passage the
    commentaries quote) has no anchors of its own, only runs found in
    several texts. It is the text of the nearest line above or below it in
    its column, if its runs are in that text; repeated, so a column's
    first lines take the text of those under them."""
    for _ in range(6):
        body = [l for l in lines if l['stream'] in BODY and l['pos'] is not None and not l.get('outside')]
        changed = False
        for l in lines:
            if l['stream'] is not None or l.get('outside') or not l['any']:
                continue
            h = l['h']
            # Beside it on its line first (Hebrew runs right to left).
            side = [m for m in body if m['stream'] in l['any'] and _same_line(l, m)]
            if side:
                m = min(side, key=lambda m: _gap(l, m))
                l['stream'] = m['stream']
                l['pos'] = m['pos'] - l['letters'] if m['x0'] < l['x0'] else m['pos'] + m['letters']
                body.append(l)
                changed = True
                continue
            near = [(abs(m['base'] - l['base']), m) for m in body
                    if m is not l and 0.5 * h < abs(m['base'] - l['base']) < 3.5 * h and _overlap(l, m) >= 0.8 and m['stream'] in l['any']]
            if not near:
                continue
            m = min(near, key=lambda dm: dm[0])[1]
            l['stream'] = m['stream']
            l['pos'] = m['pos'] + m['letters'] if m['base'] < l['base'] else m['pos'] - l['letters']
            body.append(l)
            changed = True
        if not changed:
            return


def _sandwiched(lines):
    """A line between two lines of one text, in their column, is that text
    unless its own anchors say otherwise strongly: a passage repeated on
    the page (or quoted by a commentary) has few anchors of its own."""
    body = [l for l in lines if l['stream'] in ('main', 'inner', 'outer') and not l.get('outside')]
    for l in lines:
        if l.get('outside') or l['letters'] < 2 or _heading(l['text']):
            continue
        if l['stream'] in ('main', 'inner', 'outer') and l['hits'] >= 6:
            continue
        h = l['h']
        # A piece of a line counts as in the column when it lies within it.
        above = [m for m in body if m is not l and 0.5 * h < l['base'] - m['base'] < 2.6 * h and _overlap(l, m) >= 0.8]
        below = [m for m in body if m is not l and 0.5 * h < m['base'] - l['base'] < 2.6 * h and _overlap(l, m) >= 0.8]
        if not above or not below:
            continue
        a = min(above, key=lambda m: l['base'] - m['base'])
        b = min(below, key=lambda m: m['base'] - l['base'])
        if a['stream'] == b['stream'] and a['stream'] != l['stream'] and a['pos'] is not None and _overlap_wide(a, b) >= 0.7:
            l['stream'], l['pos'], l['hits'] = a['stream'], a['pos'] + a['letters'], 0


def _neighbor(l, others):
    """The line this one continues: the piece beside it on its baseline
    (Hebrew runs right to left), else the one above or below it in its
    column. Returns (line, 'after' or 'before')."""
    best = None
    for m in others:
        h = max(m['h'], l['h'])
        if _same_line(l, m):
            d = _gap(l, m)
            if best is None or d < best[0]:
                best = (d, m, 'after' if m['x0'] > l['x0'] else 'before')
        elif _overlap_wide(l, m) >= 0.5 and 0.5 * h < abs(m['base'] - l['base']) < 2.6 * h:
            d = 1000 + abs(m['base'] - l['base'])
            if best is None or d < best[0]:
                best = (d, m, 'after' if m['base'] < l['base'] else 'before')
    return best[1:] if best else None


def _overlap(a, b):
    """How much of the narrower line's width the other covers."""
    o = min(a['x1'], b['x1']) - max(a['x0'], b['x0'])
    return max(0, o) / max(1, min(a['x1'] - a['x0'], b['x1'] - b['x0']))


def _overlap_wide(a, b):
    """How much of the wider line's width the other covers."""
    o = min(a['x1'], b['x1']) - max(a['x0'], b['x0'])
    return max(0, o) / max(1, max(a['x1'] - a['x0'], b['x1'] - b['x0']))


def _gap(a, b):
    """Horizontal space between two lines' nearest words."""
    return min((max(0, max(u['x0'], v['x0']) - min(u['x1'], v['x1'])) for u in a['words'] for v in b['words']), default=0)


def reading_order(ls, by_text):
    """A text's lines in reading order, pieces of one printed line joined.
    The Gemara reads down its column; a commentary goes where its anchors
    put it (the top band's half, then the column, or on into the other
    margin when it takes both)."""
    key = (lambda l: l['pos']) if by_text else (lambda l: (l['base'], -l['x1']))
    out = []
    for l in sorted(ls, key=key):
        p = out[-1] if out else None
        if p and _same_line(p, l):
            j = _line(sorted(p['words'] + l['words'], key=lambda w: -w['x1']))
            j.update(group=p['group'] if p['group'] == l['group'] else None, col=p['col'], gutters=p['gutters'])
            j.update(stream=p['stream'], pos=p['pos'], letters=p['letters'] + l['letters'])
            out[-1] = j
        else:
            out.append(l)
    return out


def _drop_specks(ls):
    """A scrap of a gutter note between two lines of a column isn't a line."""
    out = []
    for i, l in enumerate(ls):
        near = [m for m in ls[max(0, i - 1):i + 2] if m is not l and abs(m['base'] - l['base']) < 0.7 * m['h']]
        if near and l['letters'] <= 3 and l['x1'] - l['x0'] < 30 and not l.get('hits'):
            l['stream'] = 'other'
            continue
        out.append(l)
    return out

# ------------------------------------------------------------------ align


def align(a, b):
    """Edit-distance alignment of OCR string `a` to reference `b`: for each
    position of `a`, the position of `b` it lines up with. Skipping the
    start and end of `b` is free (the OCR may have missed lines)."""
    n, m = len(a), len(b)
    A = np.frombuffer(a.encode('utf-32-le'), dtype=np.uint32)
    B = np.frombuffer(b.encode('utf-32-le'), dtype=np.uint32)
    INS = 1.0
    prev = np.zeros(m + 1)  # free start in b
    moves = np.zeros((n + 1, m + 1), dtype=np.uint8)  # 0 diag, 1 up (a only), 2 left (b only)
    moves[0, 1:] = 2
    js = np.arange(m + 1) * INS
    for i in range(1, n + 1):
        sub = prev[:-1] + (B != A[i - 1])
        up = prev + 1
        tmp = np.empty(m + 1)
        tmp[0] = up[0]
        tmp[1:] = np.minimum(sub, up[1:])
        mv = np.ones(m + 1, dtype=np.uint8)
        mv[1:][sub <= up[1:]] = 0
        row = np.minimum.accumulate(tmp - js) + js
        mv[row < tmp - 1e-9] = 2
        moves[i] = mv
        prev = row
    # Free end in b.
    i, j = n, int(np.argmin(prev))
    pos = [0] * (n + 1)
    pos[n] = j
    while i > 0:
        mv = moves[i, j]
        if mv == 0:
            i -= 1; j -= 1
            pos[i] = j
        elif mv == 1:
            i -= 1
            pos[i] = j
        else:
            j -= 1
    return pos


def line_ranges(lines, words, table, whole=True):
    """Each line's [from, to) in `words`. The lines start where the first
    one lines up and end where the last does: part of a text can be printed
    on the next or the previous amud. With [whole], an end within a few
    words of the text's own is taken to be it."""
    ref, owner = [], []
    for k, w in enumerate(words):
        f = fold(w, table)
        if not f:
            continue
        if ref:
            ref.append(' '); owner.append(-1)
        for c in f.replace(' ', ''):
            ref.append(c); owner.append(k)
    ocr_s, ends = '', []
    for l in lines:
        f = fold(l['text'], table)
        if ocr_s:
            ocr_s += ' '
        ocr_s += f
        ends.append(len(ocr_s))
    pos = align(ocr_s, ''.join(ref))
    j = pos[0] if ocr_s else 0
    while j < len(owner) - 1 and owner[j] < 0:
        j += 1
    start = owner[j] if owner else 0
    if whole and start <= 3:
        start = 0
    out = []
    for l, e in zip(lines, ends):
        # The reference char the line's last letter matched; the line ends
        # after that word.
        j = pos[e - 1] if e > 0 else 0
        while j > 0 and (j >= len(owner) or owner[j] < 0):
            j -= 1
        end = owner[j] + 1 if owner and j < len(owner) and owner[j] >= 0 else start
        end = max(end, start)
        out.append((start, end))
        start = end
    if out and (not whole or len(words) - out[-1][1] <= 3):
        out[-1] = (out[-1][0], len(words) if whole else out[-1][1])
    return out

# ------------------------------------------------------------------ main


def amud_map(cache, book, amud, debug_dir=None, verbose=False, training_dir=None):
    img_path, rows = ocr(cache, book, amud)
    streams, extra = texts(cache, book, amud)
    im = Image.open(img_path)
    lines = lines_of(rows, im)
    info = classify(lines, streams, extra)
    result = {'book': book, 'amud': amud, 'page': [im.width, im.height],
              'frame': [round(v) for v in info['frame']], 'columns': {}, 'other': [],
              # The app uses a map only with the text it was made from.
              'words': {k: len(v) for k, v in streams.items()}}
    report = {}
    for sid in ['main', 'inner', 'outer']:
        ls = _drop_specks(sorted([l for l in lines if l['stream'] == sid], key=lambda l: l['base']))
        ls = reading_order(ls, by_text=sid != 'main')
        lines = [l for l in lines if l['stream'] != sid] + ls
        words = streams[sid]
        # Rashi script read as square letters needs folding; read by the
        # Vilna model, it doesn't.
        table = FOLD_SQUARE if sid == 'main' or OCR_LANG != 'heb' else FOLD_RASHI
        ranges = line_ranges(ls, words, table) if ls and words else []
        for k, l in enumerate(ls):
            l['order'] = k
        col = []
        for l, (a, b) in zip(ls, ranges):
            if a == b:
                continue  # matched no words: a heading or a note, not this text
            col.append([round(l['x0']), round(l['x1']), round(l['base']), round(l['h']), a, b])
            l['range'] = (a, b)
        result['columns'][sid] = col
        report[sid] = _quality(ls, words, table)
    result['carried'] = {}
    for sid in CARRIED:
        ls = _drop_specks(sorted([l for l in lines if l['stream'] == sid], key=lambda l: l['base']))
        if not ls or not extra.get(sid):
            continue
        ls = reading_order(ls, by_text=True)
        lines = [l for l in lines if l['stream'] != sid] + ls
        table = FOLD_SQUARE if OCR_LANG != 'heb' else FOLD_RASHI
        col = []
        for l, (a, b) in zip(ls, line_ranges(ls, extra[sid], table, whole=False)):
            if a < b:
                col.append([round(l['x0']), round(l['x1']), round(l['base']), round(l['h']), a, b])
                l['range'] = (a, b)
        _quality([l for l in ls if 'range' in l], extra[sid], table)
        if col:
            # Word ranges in that amud's margin, as the app counts its words.
            result['carried'][sid] = {'amud': neighbor(amud, -1 if sid.endswith('prev') else 1), 'words': len(extra[sid]), 'lines': col}
    small = []
    for sid in sorted({l['stream'] for l in lines} - set(BODY) - {None}):
        ls = sorted([l for l in lines if l['stream'] == sid], key=lambda l: (l['base'], -l['x1']))
        if training_dir and extra.get(sid) and all(l.get('pos') is not None for l in ls):
            # Not shown yet, but Sefaria has their text: training lines in
            # the small type.
            table = FOLD_SQUARE if OCR_LANG != 'heb' else FOLD_RASHI
            ordered = reading_order(ls, by_text=True)
            for l, (a, b) in zip(ordered, line_ranges(ordered, extra[sid], table, whole=False)):
                if a < b:
                    l['range'] = (a, b)
                    small.append(l)
            _quality([l for l in ordered if 'range' in l], extra[sid], table)
        result['other'].append({'id': sid, 'lines': [[round(l['x0']), round(l['x1']), round(l['base']), round(l['h']), l['text']] for l in ls]})
    if training_dir:
        _export_training(im, lines + small, {**extra, **streams}, Path(training_dir), f'{book.replace(" ", "_")}_{amud}')
    if verbose:
        _dump(lines, streams)
    if debug_dir:
        _debug(img_path, lines, streams, Path(debug_dir) / f'{book}_{amud}.png')
    return result, report


def _export_training(im, lines, streams, out, name):
    """Line images and their text, to fine-tune Tesseract on the Vilna
    type (tesstrain's layout: NAME.png, NAME.gt.txt and a line box file).
    Only lines that matched their words well, and none with a citation in
    parentheses (Sefaria spells those out). The Gemara's text has its
    abbreviations spelled out, so a Gemara line is used only where
    Tesseract already read it right, with what it read."""
    out.mkdir(parents=True, exist_ok=True)
    for k, l in enumerate(lines):
        if l.get('score', 0) < 80 or 'range' not in l or l['stream'] not in streams:
            continue
        a, b = l['range']
        if l['stream'] == 'main':
            if l['score'] < 100:
                continue
            gt = ' '.join(re.sub(r'[\u200e\u200f\u202a-\u202e]', '', l['text']).split())
        else:
            gt = ' '.join(w for w in streams[l['stream']][a:b] if w not in '–-—')
        gt = re.sub(r'<[^>]+>', '', gt).replace('&nbsp;', ' ').strip()
        # heb has none of Hebrew's own punctuation (the print sets " ' - :)
        # or vowel points (the print has none).
        for x, y in (('\u05f4', '"'), ('\u05f3', "'"), ('\u05be', '-'), ('\u05c3', ':')):
            gt = gt.replace(x, y)
        gt = re.sub(r'[\u0591-\u05c7]', '', gt)
        if not gt or '(' in gt or ')' in gt:
            continue
        # From the baseline, not the box: one tall word box (a big opening
        # word, a box run into the line above) would take in a line too many.
        top, bottom = l['base'] - 1.25 * l['h'], l['base'] + 0.35 * l['h']
        crop = im.crop((int(l['x0']) - 4, int(top), int(l['x1']) + 4, int(bottom) + 1)).convert('L')
        crop = crop.resize((crop.width * OCR_SCALE, crop.height * OCR_SCALE), Image.LANCZOS)
        # NAME_STREAM_K, the stream without underscores (inner_prev →
        # innerprev): train_ocr.py splits on them.
        base = out / f'{name}_{l["stream"].replace("_", "")}_{k:03}'
        crop.save(base.with_suffix('.png'))
        base.with_suffix('.gt.txt').write_text(gt + '\n')
        w, h = crop.size
        # heb's network reads left to right: its training text goes in
        # visual order, the line reversed.
        box = ''.join(f'{c} 0 0 {w} {h} 0\n' for c in gt[::-1]) + f'\t 0 0 {w} {h} 0\n'
        base.with_suffix('.box').write_text(box)


def _quality(lines, words, table):
    """Per line, how well the OCR matches the words it was given (0–100):
    a low score is a line to look at."""
    scores = []
    for l in lines:
        a, b = l.get('range', (0, 0))
        got = fold(' '.join(words[a:b]), table)
        mine = fold(l['text'], table)
        # Abbreviations are spelled out in the text (ר' → רבי), so allow it
        # to be somewhat longer than the print.
        ratio = len(got.replace(' ', '')) / max(1, len(mine.replace(' ', '')))
        scores.append(fuzz.ratio(mine, got) if got and 0.7 <= ratio <= 1.6 else 0)
        l['score'] = scores[-1]
    return dict(lines=len(lines), words=len(words), low=sum(1 for s in scores if s < 50),
                median=float(np.median(scores)) if scores else 0)


_COLORS = {'main': (200, 0, 0), 'inner': (0, 120, 220), 'outer': (0, 160, 60), 'rng': (160, 0, 160), 'gilyon': (200, 120, 0), 'other': (120, 120, 120)}


def _debug(img_path, lines, streams, out):
    im = Image.open(img_path).convert('RGB')
    d = ImageDraw.Draw(im)
    for l in lines:
        c = _COLORS.get(l['stream'], (0, 0, 0))
        d.rectangle([l['x0'], l['y0'], l['x1'], l['y1']], outline=c, width=2)
        if 'range' in l:
            d.text((l['x1'] + 2, l['y0']), f"{l['range'][1]}", fill=c)
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def _dump(lines, streams):
    for sid in ['main', 'inner', 'outer']:
        print(f'--- {sid}')
        for l in sorted([l for l in lines if l['stream'] == sid and 'order' in l], key=lambda l: l['order']):
            a, b = l.get('range', (0, 0))
            flag = '!' if l.get('score', 100) < 50 else ' '
            print(f"{flag}{l['x0']:5.0f}{l['x1']:5.0f}{l['base']:5.0f} {a:4}-{b:<4}", ' '.join(streams[sid][a:b]))
            if flag == '!':
                print('      ocr:', l['text'])


def amudim(specs):
    """'3a', '2a-10b' → amudim in order."""
    def n(a):
        return int(a[:-1]) * 2 - (a[-1] == 'a')
    out = []
    for spec in specs:
        first, _, last = spec.partition('-')
        for k in range(n(first), n(last or first) + 1):
            out.append(f'{(k + 1) // 2}{"a" if k % 2 else "b"}')
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+', help="amudim, or ranges like 2a-10b")
    p.add_argument('--cache', default='build/daf_cache')
    p.add_argument('--out', default='build/daf_linemap')
    p.add_argument('--debug', action='store_true', help='write each scan with its lines drawn on, into OUT/debug')
    p.add_argument('--verbose', action='store_true', help='print each line\'s words')
    p.add_argument('--export-training', metavar='DIR', help='save well-matched lines as Tesseract training data')
    a = p.parse_args()
    cache, out = Path(a.cache), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for amud in amudim(a.amudim):
        try:
            res, rep = amud_map(cache, a.book, amud, out / 'debug' if a.debug else None, a.verbose, a.export_training)
        except (SystemExit, OSError, urllib.error.URLError) as e:
            print(amud, 'failed:', e)
            continue
        (out / f'{a.book.replace(" ", "_")}_{amud}.json').write_text(json.dumps(res, ensure_ascii=False, separators=(',', ':')))
        print(amud, '  '.join(f"{k}: {v['lines']} lines, median {v['median']:.0f}, {v['low']} low" if v['words'] else f'{k}: no text'
                              for k, v in rep.items()))


if __name__ == '__main__':
    sys.exit(main())
