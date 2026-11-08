#!/usr/bin/env python3
"""All of Shas, a page per worker: `ocr` fetches each amud's scan and texts
and reads it (the slow part, done once); `render` sets each amud's core page
(svg.py --core) as SVG and as the app's placed words (build/daf/place), and
scores it (`bare` print words with nothing drawn near them, line-map lines
it couldn't match), for a list of the pages to look at.

    tool/daf/shas.py ocr [-j 12] [Berakhot ...]
    tool/daf/shas.py render [-j 12] [Berakhot ...]
    tool/daf/shas.py flagged           # the pages to look at, worst first

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


def pages(books):
    import linemap
    return [(b, a) for b, first, last in tractates() if not books or b in books for a in linemap.amudim([f'{first}-{last}'])]


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
    book, amud = job
    name = f'{book.replace(" ", "_")}_{amud}'
    try:
        lines = []
        page = svg.amud_svg(CACHE, book, amud, core=True, lines_out=lines)
        (OUT / 'svg_shas' / f'{name}.core.svg').write_text(page)
        (OUT / 'place' / f'{name}.json').write_text(json.dumps(svg.LAST_PLACED, ensure_ascii=False, separators=(',', ':')))
        body = [l for l in lines if l.get('stream') in linemap.BODY]
        row = dict(page=f'{book} {amud}', lines=len(body), catch=len(svg.LAST_PLACED['catch']),
                   low=sum(1 for l in body if l.get('score', 100) < 50 or 'range' not in l),
                   bare=len(bare.gaps(CACHE, OUT / 'svg_shas' / f'{name}.core.svg', lines)))
        return row
    except SystemExit as e:
        return dict(page=f'{book} {amud}', error=str(e))
    except Exception:
        return dict(page=f'{book} {amud}', error=traceback.format_exc(limit=3))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('stage', choices=('ocr', 'render', 'flagged'))
    p.add_argument('books', nargs='*')
    p.add_argument('-j', type=int, default=12)
    a = p.parse_args()
    os.environ.setdefault('OMP_THREAD_LIMIT', '1')
    if a.stage == 'flagged':
        rows = [json.loads(l) for l in SCORES.read_text().splitlines()]
        bad = [r for r in rows if r.get('error') or r['bare'] or r['low']]
        for r in sorted(bad, key=lambda r: -(1000 if r.get('error') else r['bare'] + r['low'])):
            print(r['page'], r.get('error', '').splitlines()[-1:] or f"bare {r['bare']} low {r['low']} / {r['lines']}")
        print(f'{len(bad)} of {len(rows)} pages flagged')
        return
    jobs = pages(set(a.books))
    if a.stage == 'render':
        (OUT / 'svg_shas').mkdir(parents=True, exist_ok=True)
        (OUT / 'place').mkdir(parents=True, exist_ok=True)
        SCORES.parent.mkdir(parents=True, exist_ok=True)
        if SCORES.exists() and a.books:
            # (Re-rendering some tractates: keep the others' scores.)
            keep = [l for l in SCORES.read_text().splitlines() if json.loads(l)['page'].rsplit(' ', 1)[0] not in a.books]
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
                for n, row in enumerate(pool.imap_unordered(_render, jobs), 1):
                    f.write(json.dumps(row, ensure_ascii=False) + '\n')
                    f.flush()
                    if row.get('error'):
                        print(row['page'], row['error'].strip().splitlines()[-1], flush=True)
                    if n % 100 == 0:
                        print(f'{n}/{len(jobs)}', flush=True)


if __name__ == '__main__':
    sys.exit(main())
