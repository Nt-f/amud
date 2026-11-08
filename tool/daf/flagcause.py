#!/usr/bin/env python3
"""Why check.py flags a body line: for each shift or low line, where in its
stream the line's own re-read matches best. Far from the words it was given
(over 5 words away): an order error (the line's text is elsewhere in the
stream: Sefaria's comment order, or a line put in the wrong place). Near:
a break error (a word or two off at an end).

    flagcause.py Book amud...
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check  # noqa: E402
import linemap  # noqa: E402


def best_place(read, ws, n):
    """The window of about n words of ws that the read matches best."""
    best = (0, 0, 0)
    for a in range(0, max(1, len(ws) - n + 1)):
        for b in (a + n - 1, a + n, a + n + 1):
            if a < b <= len(ws):
                s = check.score(read, ws[a:b])
                if s > best[0]:
                    best = (s, a, b)
    return best


def main():
    book, specs = sys.argv[1], sys.argv[2:]
    cache = Path('build/daf/cache')
    total = Counter()
    for amud in linemap.amudim(specs):
        r = check.check_amud(cache, book, amud)
        streams, extra = linemap.texts(cache, book, amud)
        texts = {**extra, **streams}
        c = Counter()
        for kind, l, _ in r['problems']:
            if kind not in ('shift', 'low'):
                continue
            ws = texts[l['stream']]
            a, b = l['range']
            n = max(1, len(l['check_read'].split()))
            s, x, y = best_place(l['check_read'], ws, n)
            far = min(abs(x - a), abs(y - b)) > 5 and s > check.score(l['check_read'], ws[a:b]) + 10
            why = 'order' if far else ('garbled' if s < 60 else 'break')
            c[(kind, l['stream'], why)] += 1
            print(f'  {kind:5} {l["stream"]:6} {why:7} y{l["base"]:5.0f} given {a}-{b}, best {x}-{y} ({s:.0f})')
        print(amud, dict(c), flush=True)
        total.update(c)
    for k, v in sorted(total.items()):
        print(*k, v)


if __name__ == '__main__':
    main()
