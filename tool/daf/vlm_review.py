#!/usr/bin/env python3
"""Answer review packets (see REVIEW.md) with a local vision model through
Ollama, and score its answers against answers already in the packets.

    vlm_review.py Book_amud... [--model gemma4:e4b] [--out answers_vlm.json]
    vlm_review.py --score [--out answers_vlm.json]

Each line gets its picture, the OCR read and the numbered words near it;
the model names the first and last word printed on the boxed row, or says
it's unsure or not part of the text."""

import argparse
import base64
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

REVIEW = Path('build/daf/review')
URL = 'http://localhost:11434/api/chat'
STREAM = {'main': 'the Gemara, in square letters', 'inner': 'Rashi, in Rashi script',
          'outer': 'Tosafot, in Rashi script'}

PROMPT = """This is a crop of a page of the Vilna Talmud. The red box marks one printed row of {stream}. Hebrew reads right to left: the row's first word is at the box's right end.

An OCR reading of the row (may have errors): {read}

The numbered words of the text around it (from a digital edition, which spells out some abbreviations the print shortens, and adds references in parentheses the print doesn't have):
{words}

Which numbered words are printed in the red box's row? Look at the picture, not just the OCR. Answer with JSON only:
{{"first": N, "last": N}} for the first and last word on the row,
{{"drop": true}} if the row is a heading or note, not part of this text,
{{"unsure": "reason"}} if you can't tell."""


def ask(model, img, prompt, think):
    body = {'model': model, 'stream': False, 'format': 'json', 'think': think,
            'options': {'temperature': 0, 'num_ctx': 8192},
            'messages': [{'role': 'user', 'content': prompt,
                          'images': [base64.b64encode(img.read_bytes()).decode()]}]}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)['message']['content']


def answer(model, d, l, think):
    if 'words' not in l:
        return {'id': l['id'], 'unsure': 'no stream'}
    words = '\n'.join(f'{i}: {w}' for i, w in l['words'])
    prompt = PROMPT.format(stream=STREAM.get(l['stream'], l['stream']), read=l['read'], words=words)
    raw = ask(model, d / f"{l['id']:02d}.png", prompt, think)
    try:
        a = json.loads(raw)
    except ValueError:
        m = re.search(r'\{.*\}', raw, re.S)
        a = json.loads(m.group(0)) if m else {'unsure': raw[:200]}
    out = {'id': l['id']}
    if a.get('drop'):
        out['drop'] = True
    elif isinstance(a.get('first'), int) and isinstance(a.get('last'), int):
        out['words'] = [a['first'], a['last'] + 1]
    else:
        out['unsure'] = str(a.get('unsure', raw))[:200]
    return out


def key(a):
    if not a or 'unsure' in a:
        return ('unsure',)
    if a.get('drop'):
        return ('drop',)
    w = a.get('words')
    if w and isinstance(w[0], list):
        return ('multi', tuple(map(tuple, w)))
    return ('words', tuple(w or ()), a.get('stream'))


def score(name):
    tally = {'same': 0, 'differ': 0, 'model unsure': 0, 'ref unsure': 0}
    wrong = []
    for f in sorted(REVIEW.glob(f'*/{name}')):
        ref = {a['id']: a for a in json.loads((f.parent / 'answers.json').read_text())}
        given = {l['id']: l.get('given') for l in json.loads((f.parent / 'packet.json').read_text())['lines']}
        tally['given right'] = tally.get('given right', 0) + sum(
            key(r)[:2] == ('words', tuple(given[i] or ())) and not r.get('stream') for i, r in ref.items())
        for a in json.loads(f.read_text()):
            r = ref.get(a['id'])
            if key(r)[0] == 'unsure':
                tally['ref unsure'] += 1
            elif key(a)[0] == 'unsure':
                tally['model unsure'] += 1
            elif key(a)[:2] == key(r)[:2] and not r.get('stream'):
                tally['same'] += 1
            else:
                tally['differ'] += 1
                wrong.append((f.parent.name, a['id'], key(r)[:2], key(a)[:2]))
    for w in wrong:
        print(*w)
    print(tally)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('pages', nargs='*')
    p.add_argument('--model', default='gemma4:e4b')
    p.add_argument('--out', default='answers_vlm.json')
    p.add_argument('--think', action='store_true')
    p.add_argument('--score', action='store_true')
    a = p.parse_args()
    if a.score:
        return score(a.out)
    for page in a.pages or sorted(d.name for d in REVIEW.iterdir() if d.is_dir()):
        d = REVIEW / page
        pk = json.loads((d / 'packet.json').read_text())
        t, res = time.time(), [answer(a.model, d, l, a.think) for l in pk['lines']]
        (d / a.out).write_text(json.dumps(res, ensure_ascii=False, indent=0))
        print(f'{page}: {len(res)} lines, {time.time() - t:.0f}s', flush=True)


if __name__ == '__main__':
    sys.exit(main())
