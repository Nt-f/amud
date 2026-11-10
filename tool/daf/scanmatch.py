#!/usr/bin/env python3
"""Is each scan the amud it's filed under? The share of the amud's Gemara
word pairs (Sefaria's) that the scan's page OCR holds, against its
neighbours' (two either side). A scan filed under the wrong name matches
its own text hardly at all (Pesachim 43a and 45a were swapped at
manuscripts.sefaria.org; Makkot_13b.jpg is a second scan of 14b): fix it
with SCAN_FILE or NO_SCAN in linemap.py.

    scanmatch.py                     # every amud in build/daf/shas/scores.jsonl
    scanmatch.py --which "Pesachim 43a" ...   # the amudim a scan holds best, over all Shas

Reads the Vilna-model page OCR (cache/ocr/heb_vilna); the stock model's
garbles some pages enough to look like a wrong scan (Shabbat 104a). Pages
with under 40 words of Gemara aren't checked."""

import argparse
import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
FIN = str.maketrans('ךםןףץ', 'כמנפצ')


def norm(t):
    return re.sub(r'[^א-ת]', '', re.sub(r'<[^>]+>', '', t)).translate(FIN)


def gemara(cache, book, amud):
    p = cache / 'text' / f'{book}.{amud}.hebrew_{linemap.WIKISOURCE}.json'
    if not p.exists():
        return None
    d = json.loads(p.read_text())
    if not d or not d.get('versions'):
        return []
    t = d['versions'][0]['text']
    segs = t if isinstance(t, list) else [t]
    ws = [norm(w) for s in segs for w in (s if isinstance(s, str) else ' '.join(s)).split()]
    return [w for w in ws if w]


def pairs(ws):
    return {(a, b) for a, b in zip(ws, ws[1:]) if len(a) + len(b) >= 5}


def ocr_words(cache, book, amud, lang):
    p = cache / 'ocr' / lang / f'{book}_{amud}.tsv'
    if not p.exists():
        return None
    with open(p, newline='') as f:
        return [t for t in (norm(w.get('text') or '') for w in csv.DictReader(f, delimiter='\t', quoting=csv.QUOTE_NONE)) if t]


def check_all(cache, lang):
    rows = [json.loads(l) for l in (ROOT / 'build/daf/shas/scores.jsonl').read_text().splitlines()]
    bad = unchecked = 0
    for r in rows:
        book, amud = r['page'].rsplit(' ', 1)
        o, g = ocr_words(cache, book, amud, lang), gemara(cache, book, amud)
        if not o or not g or len(g) < 40:
            unchecked += 1
            continue
        po = pairs(o)
        own = len(pairs(g) & po) / len(pairs(g))
        best = (None, 0)
        for step in (-2, -1, 1, 2):
            other = amud
            for _ in range(abs(step)):
                other = linemap.neighbor(other, 1 if step > 0 else -1) if other else None
            gn = gemara(cache, book, other) if other else None
            if gn and len(gn) >= 40:
                s = len(pairs(gn) & po) / len(pairs(gn))
                if s > best[1]:
                    best = (other, s)
        if own < 0.4 or best[1] > own:
            bad += 1
            print(f'{r["page"]:22} own {own:.2f} ({len(g)} words); best neighbour {best[0]} {best[1]:.2f}')
    print(f'{bad} suspicious, {unchecked} unchecked (no OCR, or under 40 words of Gemara)')


def which(cache, lang, pages):
    allg = {}
    for p in (cache / 'text').glob(f'*.hebrew_{linemap.WIKISOURCE}.json'):
        book, amud = p.name[:-len(f'.hebrew_{linemap.WIKISOURCE}.json')].rsplit('.', 1)
        g = gemara(cache, book, amud)
        if g and len(g) >= 40:
            allg[book, amud] = pairs(g)
    for page in pages:
        book, amud = page.rsplit(' ', 1)
        o = pairs(ocr_words(cache, book, amud, lang) or [])
        top = sorted(((len(pg & o) / len(pg), k) for k, pg in allg.items()), reverse=True)[:3]
        print(page, '->', ', '.join(f'{b} {a} {s:.2f}' for s, (b, a) in top))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--which', nargs='+', metavar='PAGE')
    p.add_argument('--cache', type=Path, default=ROOT / 'build/daf/cache')
    p.add_argument('--lang', default='heb_vilna', help='the page OCR to read (cache/ocr/LANG)')
    a = p.parse_args()
    if a.which:
        which(a.cache, a.lang, a.which)
    else:
        check_all(a.cache, a.lang)


if __name__ == '__main__':
    main()
