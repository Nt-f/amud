#!/usr/bin/env python3
"""Fine-tune Tesseract's Hebrew model on the Vilna page's type.

Tesseract's `heb` reads the Gemara's square letters well but Rashi script
(Rashi and Tosafot) as look-alike square letters, which linemap.py can only
half undo. This trains it on lines of the page itself: linemap.py
--export-training saves lines whose text it placed with confidence, with
that text, and this fine-tunes tessdata_best's heb on them.

    linemap.py Berakhot 2a-30b --export-training build/daf_train/gt
    train_ocr.py build/daf_train [--iterations 40000] [--script rashi]

writes build/daf_train/heb_vilna.traineddata (heb_vilna_rashi with
--script rashi, and so on); point linemap.py at it with OCR_LANG=heb_vilna
and TESSDATA_PREFIX at a folder holding it. --script trains on one type
only: square (the Gemara) or rashi (the commentaries, in Rashi script).
Then it scores the new model and heb, script by script, on the pages it
held out.

Some lines' text doesn't match their image: the crop missed part of the
line or took in the next one, the word range is a word off, or Sefaria's
text differs from the print. --clean MODEL reads each line with an earlier
model and leaves out lines it reads far from their text (more than
--max-error of their characters), from training and from the score.

Needs tesseract and lstmtraining (tesseract-tools) and
tessdata_best/heb.traineddata (downloaded if missing).
"""

import argparse
import difflib
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
import urllib.request
from pathlib import Path

BEST = 'https://github.com/tesseract-ocr/tessdata_best/raw/main/heb.traineddata'

# Tesseract's lstm.train config, which distribution packages leave out.
LSTM_TRAIN = """file_type                   .bl
textord_fast_pitch_test     T
tessedit_zero_rejection     T
tessedit_minimal_rejection  F
tessedit_write_rep_codes    F
edges_children_fix          F
edges_childarea             0.65
edges_boxarea               0.9
tessedit_train_line_recognizer T
textord_no_rejects          T
tessedit_init_config_only   T
"""


def tool(name):
    d = os.environ.get('TESSERACT_BIN')
    return str(Path(d) / name) if d else name


def script(f):
    """A line's type, from its name (NAME_STREAM_K): the Gemara's square
    letters, or Rashi script."""
    return 'square' if Path(f).name.rsplit('_', 2)[1] == 'main' else 'rashi'


def page(f):
    return Path(f).name.rsplit('_', 2)[0]


def score(model, listfile, env):
    """lstmeval's character and word error rates (%) on a list of lines."""
    r = subprocess.run([tool('lstmeval'), '--model', str(model), '--eval_listfile', str(listfile)],
                       env=env, capture_output=True, text=True)
    m = re.search(r'BCER eval=([\d.]+), BWER eval=([\d.]+)', r.stdout + r.stderr)
    return (float(m[1]), float(m[2])) if m else None


def read(png, model, env):
    """MODEL's reading of a line image (cached beside it)."""
    cache = png.with_suffix(f'.{model}.txt')
    if not cache.exists():
        text = ''
        for psm in ('7', '13', '6'):  # 7 sometimes reads nothing
            r = subprocess.run([tool('tesseract'), str(png), 'stdout', '-l', model, '--psm', psm],
                               env=dict(env, OMP_THREAD_LIMIT='1'), capture_output=True, text=True)
            text = ' '.join(r.stdout.split())
            if text:
                break
        cache.write_text(text)
    return cache.read_text()


def error(gt, got):
    """The share of gt's characters a reading gets wrong."""
    ops = difflib.SequenceMatcher(None, gt, got, autojunk=False).get_opcodes()
    return sum(max(b - a, d - c) for tag, a, b, c, d in ops if tag != 'equal') / max(1, len(gt))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('dir', type=Path, help='holds gt/ (from linemap.py --export-training); the model is written here')
    p.add_argument('--iterations', type=int, default=40000)
    p.add_argument('--script', choices=['all', 'square', 'rashi'], default='all')
    p.add_argument('--clean', metavar='MODEL', help='leave out lines this model (in DIR/tessdata) reads far from their text')
    p.add_argument('--max-error', type=float, default=0.15)
    # Fine-tuning from heb's own rate diverges on these lines.
    p.add_argument('--learning-rate', type=float, default=0.0001)
    a = p.parse_args()
    d = a.dir
    best = d / 'tessdata' / 'heb.traineddata'
    if not best.exists():
        best.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(BEST, best)
    (d / 'tessdata' / 'configs').mkdir(exist_ok=True)
    (d / 'tessdata' / 'configs' / 'lstm.train').write_text(LSTM_TRAIN)
    env = dict(os.environ, TESSDATA_PREFIX=str(d / 'tessdata'))

    # Each line → .lstmf.
    def lstmf(png):
        out = png.with_suffix('')
        if not out.with_suffix('.lstmf').exists():
            subprocess.run([tool('tesseract'), str(png), str(out), '-l', 'heb', '--psm', '13', 'lstm.train'],
                           env=dict(env, OMP_THREAD_LIMIT='1'), capture_output=True)
        return str(out.with_suffix('.lstmf')) if out.with_suffix('.lstmf').exists() else None

    with ThreadPoolExecutor(os.cpu_count()) as ex:
        lines = [f for f in ex.map(lstmf, sorted((d / 'gt').glob('*.png'))) if f]
    if a.clean:
        def keep(f):
            png = Path(f).with_suffix('.png')
            return error(png.with_suffix('.gt.txt').read_text().strip(), read(png, a.clean, env)) <= a.max_error
        with ThreadPoolExecutor(os.cpu_count()) as ex:
            ok = list(ex.map(keep, lines))
        print(f'{a.clean} reads {ok.count(False)} of {len(lines)} lines far from their text: left out')
        lines = [f for f, k in zip(lines, ok) if k]
    if len(lines) < 50:
        sys.exit(f'only {len(lines)} training lines')
    # A tenth held out, by page, so the score is on pages it never saw;
    # the same pages whatever the script.
    pages = sorted({page(f) for f in lines})
    random.Random(1).shuffle(pages)
    held = set(pages[:max(1, len(pages) // 10)])
    mine = [f for f in lines if a.script == 'all' or script(f) == a.script]
    train = [f for f in mine if page(f) not in held]
    # The print's period sits mid-line, not on the baseline as heb learned
    # it, and few lines have one: heb_vilna dropped every one until these
    # lines were trained on more often.
    train += [f for f in train if '.' in Path(f).with_suffix('.gt.txt').read_text()] * 4
    random.Random(2).shuffle(train)
    evals = [f for f in mine if page(f) in held]
    name = 'heb_vilna' if a.script == 'all' else f'heb_vilna_{a.script}'
    (d / f'{name}.train.txt').write_text('\n'.join(train) + '\n')
    (d / f'{name}.eval.txt').write_text('\n'.join(evals) + '\n')
    print(f'{len(train)} lines to train on, {len(evals)} held out ({len(held)} pages)')
    for k in ('square', 'rashi'):
        (d / f'eval.{k}.txt').write_text('\n'.join(f for f in lines if page(f) in held and script(f) == k) + '\n')

    if not (d / 'heb.lstm').exists():
        subprocess.run([tool('combine_tessdata'), '-e', str(best), str(d / 'heb.lstm')], check=True, capture_output=True)
    (d / 'out').mkdir(exist_ok=True)
    subprocess.run([
        tool('lstmtraining'),
        '--continue_from', str(d / 'heb.lstm'),
        '--traineddata', str(best),
        '--model_output', str(d / 'out' / name),
        '--train_listfile', str(d / f'{name}.train.txt'),
        '--eval_listfile', str(d / f'{name}.eval.txt'),
        '--max_iterations', str(a.iterations),
        '--learning_rate', str(a.learning_rate),
        '--target_error_rate', '0.01',
    ], check=True, env=env)
    subprocess.run([
        tool('lstmtraining'), '--stop_training',
        '--continue_from', str(d / 'out' / f'{name}_checkpoint'),
        '--traineddata', str(best),
        '--model_output', str(d / f'{name}.traineddata'),
    ], check=True, env=env)
    print(f'wrote {d / f"{name}.traineddata"}')
    print('held-out error, characters / words (%):')
    for k in ('square', 'rashi'):
        print(f'  {k}: {name} {score(d / f"{name}.traineddata", d / f"eval.{k}.txt", env)}, '
              f'heb {score(best, d / f"eval.{k}.txt", env)}')


if __name__ == '__main__':
    main()
