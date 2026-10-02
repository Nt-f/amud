#!/usr/bin/env python3
"""Builds the app's corpus assets from corpus/raw + corpus/tagged: one
gzip JSON per nusach whose chunks are all tagged and valid.

    python3 tool/corpus/build_assets.py            # every complete nusach
    python3 tool/corpus/build_assets.py ashkenaz   # just these

assets/corpus/<nusach>.json.gz:
  {"book": title, "nusach": slug,
   "leaves": {path: {"node", "when"?, "service"?,
                     "he": {"version", "segs": [[ref, [part, ...]], ...]},
                     "en": {"version", "segs": [[ref, [he ref, ...], [part, ...]], ...]}}}}

A part is the annotation with its text under "text"; an unsplit segment is
one part holding the whole original html.
"""
import glob
import gzip
import json
import os
import re
import sys

import reconcile
import validate

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPUS = os.path.join(ROOT, 'corpus')
OUT = os.path.join(ROOT, 'assets', 'corpus')


def parts_of(nusach, ann, html, leaf_node):
    if 'parts' in ann:
        return [reconcile.part(nusach, p, leaf_node) for p in ann['parts']]
    part = {k: v for k, v in ann.items() if k != 'he'}
    part['text'] = html
    return [reconcile.part(nusach, part, leaf_node)]


def graph_inserts(nusach, paths):
    """The insertions the service graph (corpus/graph.json) implies for this
    siddur, as InsertRules: each insert goes after the nearest anchor
    before it that the siddur has, else before the nearest after it."""
    graph = json.load(open(os.path.join(CORPUS, 'graph.json')))
    units = json.load(open(os.path.join(CORPUS, 'units.json')))

    def where(unit):
        path = units.get(unit, {}).get(nusach)
        if path is None:
            return None
        if not any(p == path or p.startswith(path + '/') for p in paths):
            raise SystemExit(f'units.json: {unit} -> {nusach} {path!r} is not in the siddur')
        return path

    out = []
    services = {}
    for name, service in graph['services'].items():
        steps = [st for st in service['steps'] if nusach in st.get('only', [nusach])]
        for i, st in enumerate(steps):
            if 'insert' not in st:
                continue
            target = where(st['insert'])
            if target is None:
                continue
            before = [where(a['anchor']) for a in steps[:i] if 'anchor' in a]
            after = [where(a['anchor']) for a in steps[i + 1:] if 'anchor' in a]
            before = [b for b in before if b]
            after = [a for a in after if a]
            rule = {'insert': target, 'when': st.get('whenBy', {}).get(nusach, st['when']),
                    'labelEn': st['en'], 'labelHe': st['he'],
                    'service': name}
            if before:
                rule['after'] = before[-1]
            elif after:
                rule['before'] = after[0]
            else:
                continue  # This siddur doesn't have the service.
            out.append(rule)
        if service.get('unit'):
            spec = units.get(service['unit'], {}).get(nusach)
            if spec is not None:
                whole = spec if isinstance(spec, str) else spec.get('path')
                services[name] = {'en': service['en'], 'he': service['he'], 'whole': whole,
                                  'sections': service_sections(spec, paths),
                                  'inserts': [r for r in out if r['service'] == name]}
    return out, services


def service_sections(spec, paths):
    """The sections of a service, in book order: a section's children (or
    the leaf itself), minus 'except', or a run of sibling sections."""
    def children(path):
        kids = []
        for p in paths:
            if p.startswith(path + '/'):
                k = path + '/' + p[len(path) + 1:].split('/')[0]
                if k not in kids:
                    kids.append(k)
        if not kids and path not in paths:
            raise SystemExit(f'units.json: service section {path!r} is not in the siddur')
        return kids or [path]

    if isinstance(spec, str):
        return children(spec)
    if 'from' in spec:
        parent = spec['from'].rsplit('/', 1)[0]
        kids = children(parent)
        if spec['from'] not in kids or spec['to'] not in kids:
            raise SystemExit(f'units.json: run {spec} is not in the siddur')
        return kids[kids.index(spec['from']):kids.index(spec['to']) + 1]
    kids = children(spec['path'])
    missing = [e for e in spec.get('except', []) if e not in kids]
    if missing:
        raise SystemExit(f'units.json: {missing} are not sections of {spec["path"]!r}')
    return [k for k in kids if k not in spec.get('except', [])]


def build(nusach):
    raws = sorted(glob.glob(os.path.join(CORPUS, 'raw', nusach, '*.json')))
    leaves, book = {}, None
    for raw_path in raws:
        tagged_path = raw_path.replace(os.sep + 'raw' + os.sep, os.sep + 'tagged' + os.sep)
        if not os.path.exists(tagged_path):
            raise SystemExit(f'{nusach}: {os.path.basename(raw_path)} is not tagged yet')
        errors = validate.validate(tagged_path)
        if errors:
            raise SystemExit(f'{tagged_path}: {errors[:3]}')
        raw = json.load(open(raw_path))
        ann = json.load(open(tagged_path))
        book = raw['book']
        for leaf in raw['leaves']:
            path = leaf['path']
            out = reconcile.leaf(nusach, path, ann['leaves'][path])
            for lang in ('he', 'en'):
                src = leaf.get(lang)
                if not src:
                    continue
                segs = []
                for s in src['segments']:
                    ref = s['id'][len(f'{lang}:{path}:'):]
                    a = ann[lang].get(s['id'], {})
                    parts = parts_of(nusach, a, s['html'], out.get('node'))
                    if lang == 'he':
                        segs.append([ref, parts])
                    else:
                        he = [h[len(f'he:{path}:'):] for h in a.get('he', []) if h.startswith(f'he:{path}:')]
                        segs.append([ref, he, parts])
                out[lang] = {'version': src['version'], 'segs': segs}
            leaves[path] = out
    os.makedirs(OUT, exist_ok=True)
    target = os.path.join(OUT, f'{nusach}.json.gz')
    inserts, services = graph_inserts(nusach, list(leaves))
    data = json.dumps({'book': book, 'nusach': nusach, 'labels': reconcile.labels(), 'inserts': inserts,
                       'services': services,
                       'leaves': leaves},
                      ensure_ascii=False,
                      separators=(',', ':')).encode()
    with gzip.GzipFile(target, 'wb', mtime=0) as f:
        f.write(data)
    print(f'{target}: {len(leaves)} leaves, {len(inserts)} inserts, {len(services)} services, {len(data) // 1024} KB raw, {os.path.getsize(target) // 1024} KB gz')


def main(argv):
    nusachim = argv or sorted(os.path.basename(d) for d in glob.glob(os.path.join(CORPUS, 'raw', '*'))
                              if os.path.isdir(d))
    for n in nusachim:
        if not argv and any(not os.path.exists(p.replace('/raw/', '/tagged/'))
                            for p in glob.glob(os.path.join(CORPUS, 'raw', n, '*.json'))):
            print(f'{n}: incomplete, skipped')
            continue
        build(n)


if __name__ == '__main__':
    main(sys.argv[1:])
