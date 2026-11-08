#!/usr/bin/env python3
"""Review packets for the lines check.py flags (and, with --sample N, N
lines it passed, or with --all every body line): per line a picture of it on the scan,
boxed, with the lines around it, and the words of its text near the ones it
was given, numbered, so a reviewer can say which words are printed on it.

    review.py Book amud... [--all | --sample N] [--out build/daf/review]

writes OUT/<Book>_<amud>/NN.png and OUT/<Book>_<amud>/packet.json. A
reviewer's answers go in OUT/<Book>_<amud>/answers.json as

    [{"id": 3, "words": [from, to]}           the line holds words from..to-1
     {"id": 6, "words": [[a, b], [c, d]]}      a..b-1, then c..d-1 (comments
                                               printed in another order)
     {"id": 4, "drop": true}                   not a line of this text
     {"id": 7, "stream": "inner", "words": …}  a line of another text
     {"id": 5, "unsure": "why"}]               left for a person

and `review.py --apply Book amud` checks them and adds them to
tool/daf/corrections/<Book>_<amud>.json, which linemap.py applies.
"""

import argparse
import json
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import check  # noqa: E402
import linemap  # noqa: E402

CONTEXT = 12  # words either side of the given range


def packet(cache, book, amud, out, mode='flagged', sample=0):
    r = check.check_amud(cache, book, amud)
    streams, extra = linemap.texts(cache, book, amud)
    texts = {**extra, **streams}
    lines = []
    linemap.amud_map(cache, book, amud, lines_out=lines)
    body = [l for l in lines if l.get('stream') in linemap.BODY and 'range' in l]
    if mode == 'all':
        items = [('line', l, '') for l in body]
    else:
        items, seen = [], set()
        for kind, l, note in r['problems']:
            if id(l) not in seen and not l.get('reviewed'):
                seen.add(id(l))
                items.append((kind, l, note))
        if sample:
            # And some lines the check passed, to learn what it misses.
            rest = [l for l in body if id(l) not in seen and not l.get('reviewed')]
            items += [('sample', l, '') for l in random.Random(f'{book}{amud}').sample(rest, min(sample, len(rest)))]
    img_path, _ = linemap.ocr(cache, book, amud)
    im = Image.open(img_path).convert('RGB')
    d = out / f'{book.replace(" ", "_")}_{amud}'
    d.mkdir(parents=True, exist_ok=True)
    for old in list(d.glob('*.png')) + list(d.glob('answers.json')):
        old.unlink()  # a new round (answers already applied are in corrections)
    entries = []
    for n, (kind, l, note) in enumerate(sorted(items, key=lambda t: (t[1].get('stream') or '', t[1]['base']))):
        h = l['h']
        side = max(60, 5 * h)  # enough of the lines beside it to see where it ends
        box = (max(0, int(l['x0'] - side)), max(0, int(l['base'] - 3.2 * h)), min(im.width, int(l['x1'] + side)), min(im.height, int(l['base'] + 2.4 * h)))
        crop = im.crop(box)
        dr = ImageDraw.Draw(crop)
        dr.rectangle((l['x0'] - box[0] - 3, l['base'] - h - box[1], l['x1'] - box[0] + 3, l['base'] + 0.35 * h - box[1]), outline=(220, 0, 0), width=2)
        k = min(3.0, max(0.6, 36 / h))  # letters about 28px high, whatever the scan's size
        crop = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
        crop.save(d / f'{n:02d}.png')
        sid = l.get('stream')
        e = dict(id=n, flag=kind, note=note, stream=sid, base=round(l['base']), x0=round(l['x0']), x1=round(l['x1']), h=round(h),
                 read=l.get('check_read') or l.get('text', ''))
        if sid in texts and texts[sid]:
            ws = texts[sid]
            a, b = l.get('range', (None, None))
            if a is None:
                # No words: those of its text around the lines beside it.
                near = [m for m in body if m['stream'] == sid]
                m = min(near, key=lambda m: abs(m['base'] - l['base'])) if near else None
                a = b = m['range'][1] if m else 0
            e['given'] = [a, b]
            lo, hi = max(0, a - CONTEXT), min(len(ws), b + CONTEXT)
            e['words'] = [[i, linemap.print_text(ws[i])] for i in range(lo, hi)]
        entries.append(e)
    gaps = {sid: [[a, b, linemap.print_text(' '.join(texts[sid][a:b]))] for a, b in holes] for sid, holes in r['gaps'].items()}
    # Each body text whole, numbered by place, to find a comment the print
    # sets elsewhere.
    whole = {sid: ' '.join(f'{i}:{linemap.print_text(w)}' for i, w in enumerate(texts[sid])) for sid in linemap.BODY if texts.get(sid)}
    (d / 'packet.json').write_text(json.dumps(dict(book=book, amud=amud, lines=entries, gaps=gaps, texts=whole), ensure_ascii=False, indent=1))
    return d, len(entries)


def _ref_words(ws):
    """The places of words inside Sefaria's parenthesized references."""
    out, depth = set(), 0
    for i, w in enumerate(ws):
        if '(' in w:
            depth += 1
        if depth:
            out.add(i)
        if ')' in w:
            depth = max(0, depth - 1)
    return out


def _only_refs(ws, got, given):
    """Whether two ranges differ only by reference words at their ends."""
    refs = _ref_words(ws)
    diff = set(range(*got)) ^ set(range(*given))
    return bool(diff) and diff <= refs


def apply(out, book, amud):
    d = out / f'{book.replace(" ", "_")}_{amud}'
    pk = json.loads((d / 'packet.json').read_text())
    answers = json.loads((d / 'answers.json').read_text())
    streams, extra = linemap.texts(Path('build/daf/cache'), book, amud)
    texts = {**extra, **streams}
    by_id = {e['id']: e for e in pk['lines']}
    path = linemap.CORRECTIONS / f'{book.replace(" ", "_")}_{amud}.json'
    have = json.loads(path.read_text())['lines'] if path.exists() else []
    added, unsure = 0, []
    for a in answers:
        e = dict(by_id[a['id']])
        if a.get('unsure'):
            unsure.append((e['id'], a['unsure']))
            continue
        if a.get('stream'):
            e['stream'] = a['stream']  # taken for another text than it is
        if e['stream'] not in linemap.BODY:
            if a.get('drop'):
                # Seen: a note or heading, not a line of a body text.
                fix = dict(stream=None, base=e['base'], x0=e['x0'], x1=e['x1'], h=e['h'], ignore=True, by=a.get('by', 'agent'))
                have = [h for h in have if not (h['stream'] is None and abs(h['base'] - fix['base']) < 0.5 * fix['h'])]
                have.append(fix)
                added += 1
            continue
        if a.get('unsure'):
            unsure.append((e['id'], a['unsure']))
            continue
        fix = dict(stream=e['stream'], base=e['base'], x0=e['x0'], x1=e['x1'], h=e['h'], by=a.get('by', 'agent'))
        if a.get('drop'):
            fix['drop'] = True
        else:
            runs = [a['words']] if isinstance(a['words'][0], int) else a['words']
            ws = texts[e['stream']]
            if len(runs) == 1 and e.get('given') and _only_refs(ws, runs[0], e['given']):
                # Differs only by a reference the print sets in the margin,
                # not in a line: which row it goes with is no matter.
                runs = [e['given']]
            if not all(0 <= f < t <= len(ws) for f, t in runs):
                print(f"  {e['id']}: words {runs} out of range", file=sys.stderr)
                continue
            if len(runs) == 1:
                (f, t), = runs
                fix.update(words=[f, t], first=ws[f], last=ws[t - 1])
            else:
                fix.update(words=runs, first=[ws[f] for f, t in runs], last=[ws[t - 1] for f, t in runs])
            if runs == [e.get('given')]:
                fix['confirmed'] = True
        have = [h for h in have if not (h['stream'] == fix['stream'] and abs(h['base'] - fix['base']) < 0.5 * fix['h'] and h['x0'] < fix['x1'] and fix['x0'] < h['x1'])]
        have.append(fix)
        added += 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(dict(book=book, amud=amud, lines=sorted(have, key=lambda h: (h['stream'] or '', h['base']))), ensure_ascii=False, indent=1))
    print(f'{book} {amud}: {added} lines put in {path}; {len(unsure)} left for a person')
    for i, why in unsure:
        print(f'  {i}: {why}')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('book')
    p.add_argument('amudim', nargs='+')
    p.add_argument('--cache', default='build/daf/cache')
    p.add_argument('--out', default='build/daf/review')
    p.add_argument('--all', action='store_true')
    p.add_argument('--sample', type=int, default=0)
    p.add_argument('--apply', action='store_true')
    a = p.parse_args()
    for amud in linemap.amudim(a.amudim):
        if a.apply:
            apply(Path(a.out), a.book, amud)
        else:
            mode = 'all' if a.all else 'flagged'
            d, n = packet(Path(a.cache), a.book, amud, Path(a.out), mode, a.sample)
            print(f'{d}: {n} lines')


if __name__ == '__main__':
    sys.exit(main())
