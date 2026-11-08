"""One printed line read by Tesseract: its words, their boxes, and, if
asked, the print's periods put back by dots.py (the models since round
five read the periods themselves: their training text got them from
dots.py, and the detector on top now does slightly worse)."""

import csv
import io
import os
import subprocess
import tempfile
from pathlib import Path

import dots


def words(img, lang):
    """`lang`'s words of a line image, as (text, x0, x1, confidence) in
    reading order.
    --psm 7 (one line) sometimes reads nothing; then 13 (raw line), then 6
    (a block)."""
    exe = os.environ.get('TESSERACT', 'tesseract')
    with tempfile.TemporaryDirectory() as d:
        png = Path(d) / 'line.png'
        img.save(png)
        for psm in ('7', '13', '6'):
            subprocess.run([exe, str(png), str(Path(d) / 'line'), '-l', lang, '--psm', psm, '-c', 'tessedit_create_tsv=1'],
                           capture_output=True, env=dict(os.environ, OMP_THREAD_LIMIT='1'))
            tsv = Path(d) / 'line.tsv'
            if not tsv.exists():
                continue
            rows = [r for r in csv.DictReader(io.StringIO(tsv.read_text()), delimiter='\t', quoting=csv.QUOTE_NONE)
                    if r['level'] == '5' and (r['text'] or '').strip()]
            if rows:
                return [(r['text'].strip(), int(r['left']), int(r['left']) + int(r['width']), float(r['conf'])) for r in rows]
    return []


def read(img, lang, periods=False):
    """The line's text."""
    ws = words(img, lang)
    if periods:
        ws = dots.place(ws, dots.periods(img))
    return ' '.join(w[0] for w in ws)


def best_words(img, langs):
    """`words` by whichever of `langs` reads the line most confidently (for
    a line that could be in either script)."""
    return max((words(img, lang) for lang in langs), key=lambda ws: sum(w[3] for w in ws) / max(1, len(ws)))


def read_best(img, langs, periods=False):
    """The line's text by whichever of `langs` reads it most confidently."""
    best = best_words(img, langs)
    if periods:
        best = dots.place(best, dots.periods(img))
    return ' '.join(w[0] for w in best)
