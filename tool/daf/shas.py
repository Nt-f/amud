#!/usr/bin/env python3
"""All of Shas, a page per worker: `ocr` fetches each amud's scan and texts
and reads it (the slow part, done once); `render` sets each amud's core page
(svg.py --core) as SVG and as the app's placed words (build/daf/place), and
scores it (`bare` print words with nothing drawn near them, line-map lines
it couldn't match), for a list of the pages to look at.

    tool/daf/shas.py ocr [-j 12] [Berakhot ...]
    tool/daf/shas.py kraken [-j 6] [Berakhot ...]   # kraken's lines, before render
    tool/daf/shas.py render [-j 12] [Berakhot ...]
    tool/daf/shas.py flagged           # the pages to look at, worst first

`--pages FILE` takes the amudim from a file ("Book 12a" a line) and `--out
DIR` writes there instead of build/daf (to compare a sample with the last
run). The OCR model is the Vilna one (OCR_LANG=heb_vilna) unless OCR_LANG
says otherwise: the 2026-11-08 run was made with stock `heb` by mistake.
kraken runs on the CPU, about 25 s and 1.6 GB a page; run its stage with
fewer workers than render, which would otherwise start it on every page.

Niddah has no Vilna scans at manuscripts.sefaria.org, so it is left out."""

import argparse
import json
import os
import re
import sys
import traceback
from multiprocessing import Pool
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
# (Before linemap is imported: it reads the model's name then.)
os.environ.setdefault('OCR_LANG', 'heb_vilna')

CACHE = ROOT / 'build' / 'daf' / 'cache'
OUT = ROOT / 'build' / 'daf'
SCORES = OUT / 'shas' / 'scores.jsonl'


def tractates():
    """(book, first amud, last amud) of the Bavli, from the app's list."""
    src = (ROOT / 'lib' / 'features' / 'gemara' / 'gemara_data.dart').read_text()
    out = []
    for m in re.finditer(r"Tractate\('([^']+)', '[^']+', '[^']+', '[^']+', '(\d+[ab])'(?:, first: '(\d+[ab])')?\)", src):
        out.append((m.group(1), m.group(3) or '2a', m.group(2)))
    return [t for t in out if t[0] != 'Niddah']


def pages(books, listed=None):
    import linemap
    if listed:
        return [tuple(l.strip().rsplit(' ', 1)) for l in Path(listed).read_text().splitlines() if l.strip()]
    return [(b, a) for b, first, last in tractates() if not books or b in books for a in linemap.amudim([f'{first}-{last}'])]


def _kraken(job):
    import linemap
    book, amud = job
    img = CACHE / 'scan' / f'{book}_{amud}.jpg'
    if not img.exists():
        return book, amud, 'no scan'
    return book, amud, None if linemap.kraken_lines(CACHE, book, amud, img) else 'no lines'


def _ocr(job):
    import linemap
    book, amud = job
    try:
        linemap.ocr(CACHE, book, amud)
        linemap.texts(CACHE, book, amud)
        return book, amud, None
    except SystemExit as e:
        return book, amud, str(e)
    except Exception:
        return book, amud, traceback.format_exc(limit=2)


def _render(job):
    import linemap
    import svg
    import bare
    # (The output dir rides with the job: workers are started fresh, not
    # forked, on Python 3.14, so they don't see main()'s --out.)
    book, amud, OUT = job
    name = f'{book.replace(" ", "_")}_{amud}'
    try:
        lines = []
        page = svg.amud_svg(CACHE, book, amud, core=True, lines_out=lines)
        (OUT / 'svg_shas' / f'{name}.core.svg').write_text(page)
        (OUT / 'place' / f'{name}.json').write_text(json.dumps(svg.LAST_PLACED, ensure_ascii=False, separators=(',', ':')))
        body = [l for l in lines if l.get('stream') in linemap.BODY]
        row = dict(page=f'{book} {amud}', lines=len(body), catch=len(svg.LAST_PLACED['catch']),
                   kraken=(CACHE / 'kraken' / f'{book}_{amud}.json').exists(),
                   low=sum(1 for l in body if l.get('score', 100) < 50 or 'range' not in l),
                   bare=len(bare.gaps(CACHE, OUT / 'svg_shas' / f'{name}.core.svg', lines)))
        return row
    except SystemExit as e:
        return dict(page=f'{book} {amud}', error=str(e))
    except Exception:
        return dict(page=f'{book} {amud}', error=traceback.format_exc(limit=3))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('stage', choices=('ocr', 'kraken', 'render', 'flagged'))
    p.add_argument('books', nargs='*')
    p.add_argument('-j', type=int, default=12)
    p.add_argument('--pages', help='a file of amudim ("Book 12a" a line) instead of whole tractates')
    p.add_argument('--out', type=Path, help='write the SVGs, placed words and scores here (default build/daf)')
    a = p.parse_args()
    global OUT, SCORES
    if a.out:
        OUT = a.out.resolve()
        SCORES = OUT / 'shas' / 'scores.jsonl'
    os.environ.setdefault('OMP_THREAD_LIMIT', '1')
    if a.stage == 'flagged':
        rows = [json.loads(l) for l in SCORES.read_text().splitlines()]
        bad = [r for r in rows if r.get('error') or r['bare'] or r['low']]
        for r in sorted(bad, key=lambda r: -(1000 if r.get('error') else r['bare'] + r['low'])):
            print(r['page'], r.get('error', '').splitlines()[-1:] or f"bare {r['bare']} low {r['low']} / {r['lines']}")
        print(f'{len(bad)} of {len(rows)} pages flagged')
        return
    jobs = pages(set(a.books), a.pages)
    if a.stage == 'kraken':
        with Pool(a.j) as pool:
            failed = 0
            for n, (book, amud, err) in enumerate(pool.imap_unordered(_kraken, jobs), 1):
                if err:
                    failed += 1
                    print(book, amud, err, flush=True)
                if n % 100 == 0:
                    print(f'{n}/{len(jobs)}, {failed} failed', flush=True)
        return
    if a.stage == 'render':
        (OUT / 'svg_shas').mkdir(parents=True, exist_ok=True)
        (OUT / 'place').mkdir(parents=True, exist_ok=True)
        SCORES.parent.mkdir(parents=True, exist_ok=True)
        if SCORES.exists() and (a.books or a.pages):
            # (Re-rendering some tractates: keep the others' scores.)
            redo = {f'{b} {am}' for b, am in jobs}
            keep = [l for l in SCORES.read_text().splitlines() if json.loads(l)['page'] not in redo]
            SCORES.write_text(''.join(k + '\n' for k in keep))
        elif SCORES.exists():
            SCORES.unlink()
    with Pool(a.j, maxtasksperchild=20) as pool:
        if a.stage == 'ocr':
            for n, (book, amud, err) in enumerate(pool.imap_unordered(_ocr, jobs), 1):
                if err:
                    print(book, amud, err.strip().splitlines()[-1], flush=True)
                if n % 100 == 0:
                    print(f'{n}/{len(jobs)}', flush=True)
        else:
            with SCORES.open('a') as f:
                for n, row in enumerate(pool.imap_unordered(_render, [(b, am, OUT) for b, am in jobs]), 1):
                    f.write(json.dumps(row, ensure_ascii=False) + '\n')
                    f.flush()
                    if row.get('error'):
                        print(row['page'], row['error'].strip().splitlines()[-1], flush=True)
                    if n % 100 == 0:
                        print(f'{n}/{len(jobs)}', flush=True)


if __name__ == '__main__':
    sys.exit(main())
