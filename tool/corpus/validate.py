#!/usr/bin/env python3
"""Checks Amud's siddur text, corpus/siddur (see corpus/SCHEMA.md): the
fields and their values, conditions, refs and English alignment. Warns
about HTML tags that aren't closed in order.

    python3 tool/corpus/validate.py            # every siddur
    python3 tool/corpus/validate.py sefard     # just these
"""
import sys

import source


def main(argv):
    bad = 0
    for n in argv or source.nusachim():
        _, chunks, errs, warns = source.load(n)
        for w in warns:
            print(f'warning: {w}')
        for e in errs[:60]:
            print(e)
        if len(errs) > 60:
            print(f'… and {len(errs) - 60} more')
        print(f'{n}: {len(chunks)} files, {len(errs)} problem(s), {len(warns)} warning(s)')
        bad += len(errs)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
