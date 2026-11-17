#!/usr/bin/env python3
"""Why each word of an amud's own text isn't drawn: for every word of its
Gemara, Rashi and Tosafot (as Sefaria has them) that its printed page leaves
out, the stage that lost it.

    attrib.py --pages FILE [-j 12] [--out build/daf/attrib]

Per word, from the last stage back:

  low_score        a line of the body got it, but scored under 50 (svg.py
                   draws no line under 50): not on the page
  unlinked         a line got it with a good score and is drawn, but as the
                   scan reads it, not tied to this word (a word run into the
                   next, a misread): on the page, but a tap can't find it
  misaligned       the first pass found it on a line that is still this
                   text's, but the word ranges put it on no line
  other_stream:S   the first pass's line is text S's in the end
  demoted:WHY      the first pass's line was put out of the body by a rule
                   (WHY: below_heading, off_gemara, side_column, small, quote,
                   unknown, pitch, settle, low_bar, outside, catchword, ...)
  other_untagged   the same, by a rule that leaves no tag
  unassigned       the first pass's line is no text's in the end
  line_vanished    no line of the end is where the first pass's line was
  never_anchored   no line of the first pass was this text there

Words the print doesn't set in the column aren't counted: the Gemara's
verse references (in the margin in print) and a commentary's references to
the tractate by name (svg._verse_refs, svg._tokens). Words between the first and last drawn word of their text are "inside" (a gap
on the page); the rest are at its start or end, mostly a comment across the
page break, printed on the next or last amud; one drawn there (in its
outer_prev or the like) is counted "on_neighbour". The page's own lines are
re-made here (classify for the first pass, svg.amud_svg for the end), so the
counts are for the code as it is now.
"""

import argparse
import json
import os
import sys
import traceback
from collections import Counter, defaultdict
from multiprocessing import Pool
from pathlib import Path

os.environ.setdefault('OCR_LANG', 'heb_vilna')
os.environ.setdefault('OMP_THREAD_LIMIT', '1')
sys.path.insert(0, str(Path(__file__).parent))

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/daf/cache'
OWN = ('main', 'inner', 'outer')


def _overlap(a, b):
    return min(a['x1'], b['x1']) - max(a['x0'], b['x0'])


def _word_spans(words, table, linemap):
    """Each word's [start, end) in the text's letters as classify counts them."""
    out, at = [], 0
    for w in words:
        n = len(linemap._flat(w, table))
        out.append((at, at + n))
        at += n
    return out


def attribute(job):
    import linemap
    import svg
    book, amud = job
    try:
        img, rows = linemap.ocr(CACHE, book, amud)
        streams, extra = linemap.texts(CACHE, book, amud)
        im = linemap.page_image(img)
        first = linemap.lines_of(rows, im)
        linemap.classify(first, streams, extra)
        first = [dict(x0=l['x0'], x1=l['x1'], base=l['base'], h=l['h'], stream=l['stream'], pos=l['pos'],
                      letters=l['letters'], hits=l.get('hits', 0)) for l in first]
        lines = []
        svg.amud_svg(CACHE, book, amud, core=True, lines_out=lines)
        placed = svg.LAST_PLACED
    except SystemExit as e:
        return dict(page=f'{book} {amud}', error=str(e))
    except Exception:
        return dict(page=f'{book} {amud}', error=traceback.format_exc(limit=3))
    drawn = defaultdict(set)
    for w in placed['placed']:
        if w[0] in ('m', 'i', 'o') and w[1] >= 0:
            drawn[w[0]].add(w[1])
    out = Counter()
    undrawn = {sid: {} for sid in OWN}
    examples = defaultdict(list)
    for sid in OWN:
        words = streams[sid]
        if not words:
            continue
        printed = (set(range(len(words))) - svg._verse_refs(words) if sid == 'main' else
                   {t['k'] for t in svg._tokens(words, 0, len(words), sid, [], None, linemap.he_names(CACHE, book)[:1])})
        got = drawn[sid[0]]
        lo, hi = (min(got), max(got)) if got else (len(words), -1)
        spans = _word_spans(words, linemap.FOLD_SQUARE, linemap)
        mine = [l for l in lines if l.get('stream') == sid and 'range' in l]
        claims = [l for l in first if l['stream'] == sid and l['pos'] is not None]
        for k in range(len(words)):
            if k not in printed:
                out[sid, 'not_printed', 'all'] += 1
                continue
            if k in got:
                out[sid, 'drawn', 'all'] += 1
                continue
            where = 'inside' if lo < k < hi else 'edge'
            by = [l for l in mine if l['range'][0] <= k < l['range'][1]]
            if by:
                cat = 'low_score' if min(l.get('score', 100) for l in by) < 50 else 'unlinked'
            else:
                a, b = spans[k]
                cl = [l for l in claims if l['pos'] < b and a < l['pos'] + l['letters']]
                if not cl:
                    cat = 'never_anchored'
                else:
                    c = max(cl, key=lambda l: l['hits'])
                    near = [l for l in lines if abs(l['base'] - c['base']) < 0.5 * max(c['h'], l.get('h', c['h']))
                            and _overlap(l, c) > 0.5 * min(c['x1'] - c['x0'], l['x1'] - l['x0'])]
                    if not near:
                        cat = 'line_vanished'
                    elif any(l.get('stream') == sid for l in near):
                        cat = 'misaligned'
                    elif any(l.get('stream') in linemap.BODY for l in near):
                        cat = 'other_stream:' + next(l['stream'] for l in near if l.get('stream') in linemap.BODY)
                    else:
                        tags = [l.get('why') or ('catchword' if l.get('catchword') else '') or ('outside' if l.get('outside') else '')
                                for l in near]
                        tag = next((t for t in tags if t), '')
                        if tag:
                            cat = 'demoted:' + tag
                        elif any(l.get('stream') == 'other' for l in near):
                            cat = 'other_untagged'
                        else:
                            cat = 'unassigned' if all(l.get('stream') is None for l in near) else 'demoted:' + str(near[0].get('stream'))
            out[sid, cat, where] += 1
            undrawn[sid][k] = f'{cat}|{where}'
            if where == 'inside' and len(examples[cat]) < 3:
                examples[cat].append(k)
    # The neighbours' words drawn here: a comment begun on the last amud
    # and ended on this one (outer_prev), or the other way.
    carried = defaultdict(list)
    for l in lines:
        s = l.get('stream') or ''
        if s.endswith(('_prev', '_next')) and 'range' in l and l.get('score', 100) >= 50:
            carried[s].append(list(l['range']))
    return dict(page=f'{book} {amud}', counts={'|'.join(k): v for k, v in out.items()},
                examples=dict(examples), undrawn=undrawn, carried=dict(carried))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--pages', type=Path, required=True, help='a file of amudim, "Book 12a" a line')
    p.add_argument('-j', type=int, default=12)
    p.add_argument('--out', type=Path, default=ROOT / 'build/daf/attrib')
    a = p.parse_args()
    jobs = [tuple(s.rsplit(' ', 1)) for s in a.pages.read_text().splitlines() if s.strip()]
    a.out.mkdir(parents=True, exist_ok=True)
    rows = []
    with Pool(a.j) as pool:
        for n, r in enumerate(pool.imap_unordered(attribute, jobs), 1):
            rows.append(r)
            if n % 50 == 0:
                print(f'{n}/{len(jobs)}', flush=True)
    (a.out / 'pages.jsonl').write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
    report(rows)


def _neighbours(rows):
    """Per amud and text, the words a neighbour draws (a comment carried
    over the page break)."""
    import linemap
    got = defaultdict(set)
    for r in rows:
        book, amud = r['page'].rsplit(' ', 1)
        for s, ranges in r.get('carried', {}).items():
            sid, side = s.rsplit('_', 1)
            other = f"{book} {linemap.neighbor(amud, -1 if side == 'prev' else 1)}"
            for a, b in ranges:
                got[other, sid].update(range(a, b))
    return got


def report(rows):
    tot = Counter()
    pages = defaultdict(Counter)
    there = _neighbours(rows)
    for r in rows:
        if 'error' in r:
            print('error', r['page'], r['error'].strip().splitlines()[-1])
            continue
        for k, v in r['counts'].items():
            sid, cat, where = k.split('|')
            tot[sid, cat, where] += v
        # (Undrawn here but drawn on the next or last amud: counted there.)
        for sid, ks in r.get('undrawn', {}).items():
            for k, cw in ks.items():
                if int(k) in there[r['page'], sid]:
                    cat, where = cw.split('|')
                    tot[sid, cat, where] -= 1
                    tot[sid, 'on_neighbour', 'all'] += 1
                    if where == 'inside':
                        pages[cat][r['page']] -= 1
    for r in rows:
        for k, v in r.get('counts', {}).items():
            sid, cat, where = k.split('|')
            if where == 'inside':
                pages[cat][r['page']] += v
    words = Counter()
    for (sid, cat, where), v in tot.items():
        if cat != 'not_printed':
            words[sid] += v
    print('not set in the column (verse references, the tractate\'s name):', {s: tot[s, 'not_printed', 'all'] for s in OWN})
    print(f"{'':16}" + ''.join(f'{s:>14}' for s in OWN) + f"{'all':>14}")
    for where in ('inside', 'edge'):
        cats = sorted({c for (s, c, w) in tot if w == where and c not in ('drawn', 'not_printed')},
                      key=lambda c: -sum(tot[s, c, where] for s in OWN))
        print(f'-- undrawn, {where}')
        for c in cats:
            vals = [tot[s, c, where] for s in OWN]
            if not any(vals):
                continue
            print(f'{c:16}' + ''.join(f'{v:8} {100 * v / max(1, words[s]):4.1f}%' for v, s in zip(vals, OWN))
                  + f'{sum(vals):8} {100 * sum(vals) / max(1, sum(words.values())):4.1f}%')
    for c in ('drawn', 'on_neighbour'):
        print(f"{c:16}" + ''.join(f"{tot[s, c, 'all']:8} {100 * tot[s, c, 'all'] / max(1, words[s]):4.1f}%" for s in OWN))
    print('\nworst pages per cause (inside):')
    for cat, c in sorted(pages.items(), key=lambda kv: -sum(kv[1].values())):
        if c.most_common(1)[0][1] > 0:
            print(f'  {cat:16} ' + ', '.join(f'{p} {v}' for p, v in c.most_common(5) if v > 0))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--report':
        report([json.loads(l) for l in Path(sys.argv[2]).read_text().splitlines()])
    else:
        main()
