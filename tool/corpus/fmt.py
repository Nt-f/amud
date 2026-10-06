#!/usr/bin/env python3
"""Rewrites corpus/siddur files in the canonical layout (one line per
segment or part, fields in a fixed order), after editing by hand or by
script. Content is unchanged.

    python3 tool/corpus/fmt.py                 # every file
    python3 tool/corpus/fmt.py corpus/siddur/sefard/03_….json [more…]
"""
import json
import os
import sys

import source


def main(argv):
    paths = argv or [p for n in source.nusachim() for p in source.files(n)]
    changed = 0
    for p in paths:
        text = open(p).read()
        out = source.dumps(json.loads(text))
        if out != text:
            open(p, 'w').write(out)
            changed += 1
            print(f'formatted {os.path.relpath(p, source.ROOT)}')
    print(f'{changed} of {len(paths)} file(s) changed')


if __name__ == '__main__':
    main(sys.argv[1:])
