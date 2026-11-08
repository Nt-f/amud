#!/usr/bin/env python3
"""A page for looking over the vision models' review answers beside the
map's and the reference answers: build/daf/review/compare.html, one card per
line with its picture and each answer's words, disagreements first.

    vlm_page.py [name=answers_vlm12.json ...]

Each argument is a label and an answers file name in the packet folders."""

import html
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from vlm_review import REVIEW, key  # noqa: E402

DEFAULT = ['12b=answers_vlm12.json', '12b think=answers_vlm12_think.json', 'qwen3.6=answers_qwen.json']


def words_of(texts, stream):
    return dict((int(i), w) for i, _, w in (t.partition(':') for t in texts.get(stream, '').split(' ') if t))


def show(a, text):
    k = key(a)
    if k[0] == 'unsure':
        return '<i>unsure</i>' + (f' <small>{html.escape(str(a.get("unsure", "")))[:120]}</small>' if a else '')
    if k[0] == 'drop':
        return '<i>drop</i>'
    runs = k[1] if k[0] == 'multi' else [k[1]]
    out = []
    for r in runs:
        if len(r) != 2:
            continue
        ws = [text.get(i, '?') for i in range(r[0], r[1])]
        out.append(f'<span class=r>[{r[0]}–{r[1]})</span> <span class=he>{html.escape(" ".join(ws))}</span>')
    s = ' + '.join(out) or '<i>none</i>'
    return s + (f' <small>({a["stream"]})</small>' if a.get('stream') else '')


def main():
    models = [a.split('=', 1) for a in (sys.argv[1:] or DEFAULT)]
    cards = []
    for d in sorted(p for p in REVIEW.iterdir() if (p / 'answers.json').exists()):
        pk = json.loads((d / 'packet.json').read_text())
        ref = {a['id']: a for a in json.loads((d / 'answers.json').read_text())}
        got = {}
        for label, name in models:
            f = d / name
            if f.exists():
                got[label] = {a['id']: a for a in json.loads(f.read_text())}
        for l in pk['lines']:
            text = words_of(pk['texts'], l['stream'])
            r = ref.get(l['id'])
            given = {'id': l['id'], 'words': l['given']} if l.get('given') else None
            rows = [('map', given), ('sub-agent', r)] + [(m, got[m].get(l['id'])) for m in got]
            keys = {key(a)[:2] for _, a in rows if a}
            split = len(keys) > 1
            body = ''.join(
                f'<tr class="{"ok" if key(a)[:2] == key(r)[:2] else "bad"}"><th>{lab}</th><td>{show(a, text)}</td></tr>'
                for lab, a in rows)
            cards.append((not split, f'''<div class=card><h3>{d.name} · line {l["id"]} · {l["stream"]} · {l["flag"]}</h3>
<img src="{d.name}/{l["id"]:02d}.png" loading=lazy>
<p class=read>OCR: <span class=he>{html.escape(l["read"])}</span></p>
<table>{body}</table>
{f'<p class=why>{html.escape(r.get("why", ""))}</p>' if r else ''}</div>'''))
    cards.sort(key=lambda c: c[0])
    n = sum(1 for c in cards if not c[0])
    page = f'''<!doctype html><meta charset=utf-8><title>Line review comparison</title>
<style>
:root{{--bg:#fff;--fg:#111;--mut:#666;--ok:#e6f4ea;--bad:#fde8e8;--line:#ddd}}
@media (prefers-color-scheme:dark){{:root{{--bg:#16181c;--fg:#eee;--mut:#999;--ok:#1d3324;--bad:#3a1f22;--line:#333}}}}
body{{background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif;margin:0 auto;max-width:1120px;padding:16px}}
.card{{border:1px solid var(--line);border-radius:8px;padding:12px;margin:16px 0}}
h3{{margin:0 0 8px;font-size:14px}} img{{max-width:100%;background:#fff;border-radius:4px}}
table{{border-collapse:collapse;width:100%}} th{{text-align:left;width:90px;padding:4px 8px;font-weight:600;white-space:nowrap}}
td{{padding:4px 8px}} tr.ok{{background:var(--ok)}} tr.bad{{background:var(--bad)}}
.he{{direction:rtl;unicode-bidi:isolate;font-size:17px}} .r{{color:var(--mut);font-size:12px}}
.read,.why{{color:var(--mut);margin:6px 0}} small{{color:var(--mut)}}
</style>
<h1>Line review comparison</h1>
<p>Green rows match the sub-agent's answer (the reference, not hand-checked); red rows differ. The {n} lines where any answer differs come first, then the {len(cards) - n} where all agree.</p>
{''.join(c[1] for c in cards)}'''
    (REVIEW / 'compare.html').write_text(page)
    print(REVIEW / 'compare.html', len(cards), 'lines,', n, 'with differences')


if __name__ == '__main__':
    sys.exit(main())
