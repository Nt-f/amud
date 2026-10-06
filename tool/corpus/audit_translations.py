#!/usr/bin/env python3
"""Translation audit for corpus/siddur.

    python3 tool/corpus/audit_translations.py            # counts per siddur
    python3 tool/corpus/audit_translations.py REGEX      # lists what matching sections lack

Gaps: a Hebrew prayer segment that no English segment translates, and an
instruction, note, heading or speaker with no `en`. Every section you touch
or add must come out clean; see CLAUDE.md.
"""
import collections
import glob
import json
import re
import sys

NIKUD = re.compile('[֑-ׇ]')
HEBREW = re.compile('[א-ת]')
NON_PRAYER = ('instruction', 'note', 'heading', 'speaker')
SAID = ('prayer', 'commentary')


def plain(t):
    return re.sub('<[^>]+>', '', t)


def main():
    filt = sys.argv[1] if len(sys.argv) > 1 else None
    counts = collections.defaultdict(collections.Counter)
    for f in sorted(glob.glob('corpus/siddur/*/*.json')):
        if f.endswith('book.json'):
            continue
        book = f.split('/')[2]
        for leaf in json.load(open(f)).get('leaves', []):
            if filt and not re.search(filt, leaf['path'], re.I):
                continue
            covered = set()
            for s in leaf.get('en', {}).get('segs', []):
                covered.update(s.get('translates', []))
            for s in leaf.get('he', {}).get('segs', []):
                parts = s.get('parts', [s])
                gaps = []
                if s['ref'] not in covered and any(p.get('kind') in SAID and HEBREW.search(plain(p['text'])) for p in parts):
                    gaps.append('no English translation')
                if any(p.get('kind') in NON_PRAYER and not p.get('en') for p in parts):
                    gaps.append('instruction/note without en')
                for g in gaps:
                    counts[book][g] += 1
                    if filt:
                        print(f'{book}  {leaf["path"]}  {s["ref"]}  {g}  | {NIKUD.sub("", plain(parts[0]["text"]))[:30]}')
    for book, c in sorted(counts.items()):
        print(book, dict(c))
    if not counts:
        print('no gaps')


main()
