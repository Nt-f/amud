#!/usr/bin/env python3
"""Which of an amud's words no printed line holds, looking at the amudim
before and after it too: Sefaria files some of the Gemara, Rashi and Tosafot
under one amud that the print sets on the next or the previous (the line
maps carry those, as `carried`). What is left over is text the print lacks,
or a line the maps missed.

    coverage.py Book amud... [--cache build/daf/cache] [-v]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import linemap  # noqa: E402

_maps = {}


def amud_map(cache, book, amud):
    if (book, amud) not in _maps:
        try:
            _maps[book, amud] = linemap.amud_map(cache, book, amud)[0]
        except SystemExit:
            _maps[book, amud] = None
    return _maps[book, amud]


def held(cache, book, amud):
    """Per stream (main, inner, outer), the ranges of the amud's words some
    line holds: on this amud, or carried onto a neighbour."""
    out = {sid: [] for sid in ('main', 'inner', 'outer')}
    m = amud_map(cache, book, amud)
    if m:
        for sid, col in m['columns'].items():
            for l in col:
                out[sid] += [tuple(l[i:i + 2]) for i in range(4, len(l), 2)]
    for step, tag in ((-1, 'next'), (1, 'prev')):
        other = linemap.neighbor(amud, step)
        n = amud_map(cache, book, other) if other else None
        for sid in ('main', 'inner', 'outer'):
            c = (n or {}).get('carried', {}).get(f'{sid}_{tag}')
            if c and c['amud'] == amud:
                out[sid] += [tuple(l[4:6]) for l in c['lines']]
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('-v', '--verbose', action='store_true')
    a = p.parse_args()
    cache = Path(a.cache)
    for amud in linemap.amudim(a.amudim):
        streams, _ = linemap.texts(cache, a.book, amud)
        got = held(cache, a.book, amud)
        report = []
        for sid, rs in got.items():
            words = streams[sid]
            have = [False] * len(words)
            for x, y in rs:
                for i in range(max(0, x), min(len(words), y)):
                    have[i] = True
            holes, i = [], 0
            while i < len(words):
                if not have[i]:
                    j = i
                    while j < len(words) and not have[j]:
                        j += 1
                    holes.append((i, j))
                    i = j
                else:
                    i += 1
            report.append((sid, len(words), holes))
        n = sum(j - i for _, _, hs in report for i, j in hs)
        print(f'{a.book} {amud}: {n} words held by no line', flush=True)
        if a.verbose:
            for sid, total, holes in report:
                for i, j in holes:
                    print(f'  {sid:6} {i}-{j} of {total}:', linemap.print_text(' '.join(streams[sid][i:j]))[:120])


if __name__ == '__main__':
    sys.exit(main())
