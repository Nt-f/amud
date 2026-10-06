#!/usr/bin/env python3
"""Finds prayer text tagged as an instruction.

    python3 tool/corpus/audit_tags.py          # the weekday services (the default)
    python3 tool/corpus/audit_tags.py all      # every section

The app shows an instruction, note or heading in English only, so a prayer
tagged that way vanishes from the Hebrew. Prayer text is vowelled and a real
instruction isn't, so vowelled Hebrew in an instruction is a mistake, except
the meditations before putting on a tallis or tefillin (said, but optional).
Also look for a whole day's section with no `when` (the Daily Psalm for all
six days at once, Avinu Malkeinu on an ordinary day): resolve the service
and read it.
"""
import collections
import glob
import gzip
import json
import re
import sys

NIKUD = re.compile('[ְ-ׇֽֿׁׂ]')
HEBREW = re.compile('[א-ת]')
NOT_PRAYER = ('instruction', 'note', 'heading', 'speaker', 'commentary')


def plain(t):
    return re.sub('<[^>]+>', '', t)


def vowelled(p):
    t = plain(re.sub(r'<i class="instruction">.*?</i>', '', p['text']))
    letters = len(HEBREW.findall(t))
    return letters >= 8 and len(NIKUD.findall(t)) / letters > 0.5


def main():
    everywhere = len(sys.argv) > 1 and sys.argv[1] == 'all'
    for book in ('ashkenaz', 'sefard', 'chabad', 'edot_hamizrach', 'koren'):
        asset = json.load(gzip.open(f'assets/corpus/{book}.json.gz'))
        sections = [s for k in ('shacharit.weekday', 'mincha.weekday', 'maariv.weekday') for s in asset['services'][k]['sections']]
        found = collections.Counter()
        for f in sorted(glob.glob(f'corpus/siddur/{book}/*.json')):
            if f.endswith('book.json'):
                continue
            for leaf in json.load(open(f)).get('leaves', []):
                if not everywhere and not any(leaf['path'] == s or leaf['path'].startswith(s + '/') for s in sections):
                    continue
                for seg in leaf.get('he', {}).get('segs', []):
                    for part in seg.get('parts', [seg]):
                        if part.get('kind') in NOT_PRAYER and vowelled(part):
                            found[(leaf['path'], seg['ref'])] += 1
        print(book, sum(found.values()))
        for (path, ref), n in sorted(found.items()):
            print(f'    {path}  {ref}  ({n})')


main()
