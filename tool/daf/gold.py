#!/usr/bin/env python3
"""A hand-checked set of printed lines, to score the OCR against.

Training and its held-out score read against Sefaria's text, which isn't
always what's printed (and for the Gemara spells out the abbreviations),
on crops and word ranges that are now and then a word off. These lines'
text was read off the scan: gold.jsonl, a line per printed line, with the
amud, the line's box on the scan and its text. The scans are cached by
linemap.py.

    gold.py sample Berakhot:60b Pesachim:50a … --out build/daf/gold
        candidate lines from pages no model trained on, each with Sefaria's
        text and the OCR's reading, and sheets of their images to check
    gold.py score [--gold tool/daf/gold.jsonl]
        each model's error on the gold lines, script by script

The OCR models are heb_vilna_square (the Gemara) and heb_vilna_rashi (the
rest) in TESSDATA_PREFIX; see linemap.py for TESSERACT and the cache.
"""

import argparse
import difflib
import json
import os
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402
from lineread import read  # noqa: E402

GOLD = Path(__file__).parent / 'gold.jsonl'
# The commentaries in Rashi script, on Sefaria (the rest of the small
# commentaries have no text there, so their candidates are the OCR's alone).
RASHI = ('inner', 'outer', 'rng', 'gilyon') + linemap.CARRIED


def script(stream):
    return 'square' if stream == 'main' else 'rashi'


def model(stream):
    return os.environ.get('OCR_SQUARE', 'heb_vilna_square') if script(stream) == 'square' else os.environ.get('OCR_RASHI', 'heb_vilna_rashi')


def plain(text):
    """Text without the print's note markers (* and °, which point to the
    margin), which the gold leaves out."""
    return ' '.join(text.replace('*', '').replace('°', '').split())


def error(gt, got):
    """Characters wrong, and the length they're out of."""
    gt, got = plain(gt), plain(got)
    ops = difflib.SequenceMatcher(None, gt, got, autojunk=False).get_opcodes()
    return sum(max(b - a, d - c) for tag, a, b, c, d in ops if tag != 'equal'), len(gt)


def sample(a):
    cache, out = Path(a.cache), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(7)
    picked = []
    for spec in a.pages:
        book, amud = spec.split(':')
        lines = []
        linemap.amud_map(cache, book, amud, lines_out=lines)
        streams, extra = linemap.texts(cache, book, amud)
        texts = {**extra, **streams}
        im = Image.open(cache / 'scan' / f'{book}_{amud}.jpg')
        kinds = {'main': [], 'rashi': [], 'small': [], 'other': []}
        for l in lines:
            s = l.get('stream')
            if s == 'main' and 'range' in l:
                kinds['main'].append(l)
            elif s in ('inner', 'outer') + linemap.CARRIED and 'range' in l:
                kinds['rashi'].append(l)
            elif s in ('rng', 'gilyon') and 'range' in l:
                kinds['small'].append(l)
            elif s == 'other' and len(l['text']) > 6:
                kinds['other'].append(l)
        for kind, n in (('main', a.main), ('rashi', a.rashi), ('small', a.small), ('other', a.other)):
            for l in rnd.sample(kinds[kind], min(n, len(kinds[kind]))):
                box = linemap.line_box(l)
                sef = None
                if 'range' in l:
                    x, y = l['range']
                    sef = linemap.print_text(' '.join(w for w in texts[l['stream']][x:y] if w not in '–-—'))
                ocr = read(linemap.line_image(im, box), model(l['stream']))
                picked.append(dict(id=len(picked), book=book, amud=amud, stream=l['stream'], box=box,
                                   sefaria=sef, ocr=ocr, agree=sef == ocr))
                im.crop(tuple(box)).save(out / f'{len(picked) - 1:03}.png')
        print(spec, len(picked))
    with open(out / 'candidates.jsonl', 'w') as f:
        for p in picked:
            f.write(json.dumps(p, ensure_ascii=False) + '\n')
    todo = [p for p in picked if not p['agree']]
    print(f'{len(picked)} lines, {len(picked) - len(todo)} where Sefaria and the OCR agree; {len(todo)} to check')
    # Sheets of the ones to check, ten to a sheet, three times life size.
    for k in range(0, len(todo), 10):
        ims = [Image.open(out / f'{p["id"]:03}.png').convert('L') for p in todo[k:k + 10]]
        ims = [i.resize((i.width * 3, i.height * 3), Image.LANCZOS) for i in ims]
        w = max(i.width for i in ims) + 60
        sheet = Image.new('L', (w, sum(i.height + 16 for i in ims)), 255)
        d, y = ImageDraw.Draw(sheet), 0
        for p, i in zip(todo[k:k + 10], ims):
            sheet.paste(i, (w - i.width, y))
            d.text((4, y + i.height // 2 - 6), str(p['id']), fill=0)
            y += i.height + 16
        sheet.save(out / f'sheet_{k // 10:02}.png')


def score(a):
    cache = Path(a.cache)
    tot = {}
    worst = []
    for line in open(a.gold):
        g = json.loads(line)
        im = Image.open(cache / 'scan' / f'{g["book"]}_{g["amud"]}.jpg')
        got = read(linemap.line_image(im, g['box']), model(g['stream']))
        e, n = error(g['text'], got)
        k = g['stream'] if g['stream'] in ('main', 'other') else ('small' if g['stream'] in ('rng', 'gilyon') else 'rashi')
        t = tot.setdefault(k, [0, 0, 0, 0])
        t[0] += e
        t[1] += n
        t[2] += 1
        t[3] += e > 0
        if e:
            worst.append((e, g['id'], g['text'], got))
    for k, (e, n, lines, bad) in sorted(tot.items()):
        print(f'{k:6} {lines:4} lines, {100 * e / max(1, n):.2f}% of characters wrong, {bad} lines with an error')
    if a.verbose:
        for e, i, gt, got in sorted(worst, reverse=True):
            print(f'{i:4} {e:3}\n  gold: {gt}\n  ocr : {got}')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--cache', default='build/daf_cache')
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('sample')
    s.add_argument('pages', nargs='+', help='BOOK:AMUD')
    s.add_argument('--out', default='build/daf/gold')
    s.add_argument('--main', type=int, default=5)
    s.add_argument('--rashi', type=int, default=8)
    s.add_argument('--small', type=int, default=2)
    s.add_argument('--other', type=int, default=2)
    s = sub.add_parser('score')
    s.add_argument('--gold', default=str(GOLD))
    s.add_argument('--verbose', action='store_true')
    a = p.parse_args()
    {'sample': sample, 'score': score}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
