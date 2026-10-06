#!/usr/bin/env python3
"""Builds the app's corpus assets from Amud's siddur text, corpus/siddur
(see corpus/SCHEMA.md): one gzip JSON per nusach. Stops at the first
siddur with errors; warnings are printed and don't stop the build.

    python3 tool/corpus/build_assets.py            # every siddur
    python3 tool/corpus/build_assets.py ashkenaz   # just these

assets/corpus/<nusach>.json.gz:
  {"book": title, "heTitle", "nusach": slug,
   "index": the table of contents, as Sefaria's schema ({"enTitle", "heTitle", "nodes"}),
   "editions": {"he"/"en": {"license", "segments", "sources": [{"version", "license", "source"?}]}},
   "labels": {if_…: label}, "inserts": [...], "services": {...},
   "leaves": {path: {"node", "when"?, "service"?,
                     "he": {"version", "segs": [[ref, [part, ...]], ...]},
                     "en": {"version", "segs": [[ref, [he ref, ...], [part, ...]], ...]}}}}

A part holds its fields and its text under "text"; a segment that isn't
split is one part. Editors' comments are left out.
"""
import gzip
import json
import os
import sys

import source

ROOT = source.ROOT
CORPUS = source.CORPUS
OUT = os.path.join(ROOT, 'assets', 'corpus')


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


def _part(p):
    return {k: v for k, v in p.items() if k != 'comment'}


def index(book, leaves):
    """The table of contents, in the order of the leaves: each section where
    its first leaf is. English titles are the parts of the paths."""
    root = {'enTitle': book['title'], 'heTitle': book['heTitle'], 'nodes': []}
    nodes = {'': root}
    for path, leaf in leaves.items():
        parts = path.split('/')
        for i in range(1, len(parts) + 1):
            pid = '/'.join(parts[:i])
            if pid in nodes:
                continue
            en = parts[i - 1]
            he = leaf.get('_title') if i == len(parts) else book['sections'].get(pid)
            node = {'enTitle': en, 'heTitle': he or en}
            if i < len(parts):
                node['nodes'] = []
            nodes['/'.join(parts[:i - 1])]['nodes'].append(node)
            nodes[pid] = node
    return root


def editions(book, leaves):
    out = {}
    for lang in ('he', 'en'):
        used = []
        for leaf in leaves.values():
            v = (leaf.get(lang) or {}).get('version')
            if v is not None and v not in used:
                used.append(v)
        if not used:
            continue
        sources = [{'version': v, **book['sources'][lang][v]} for v in used]
        out[lang] = {'license': source.combined_license([x['license'] for x in sources]),
                     'segments': sum(len(l[lang]['segs']) for l in leaves.values() if lang in l),
                     'sources': sources}
    return out


def build(nusach):
    book, chunks, errs, warns = source.load(nusach)
    for w in warns:
        print(f'warning: {w}')
    if errs:
        for e in errs[:40]:
            print(e)
        raise SystemExit(f'{nusach}: {len(errs)} problem(s); nothing built')
    leaves = {}
    for _, doc in chunks:
        for leaf in doc['leaves']:
            out = {k: leaf[k] for k in ('node', 'when', 'service') if k in leaf}
            if 'title' in leaf:
                out['_title'] = leaf['title']
            for lang in ('he', 'en'):
                t = leaf.get(lang)
                if not t:
                    continue
                segs = []
                for s in t['segs']:
                    ps = [_part(p) for p in source.parts(s)]
                    segs.append([s['ref'], ps] if lang == 'he' else [s['ref'], s.get('translates', []), ps])
                out[lang] = {'version': t['version'], 'segs': segs}
            leaves[leaf['path']] = out
    os.makedirs(OUT, exist_ok=True)
    target = os.path.join(OUT, f'{nusach}.json.gz')
    inserts, services = graph_inserts(nusach, list(leaves))
    toc = index(book, leaves)
    for leaf in leaves.values():
        leaf.pop('_title', None)
    data = json.dumps({'book': book['title'], 'heTitle': book['heTitle'], 'nusach': nusach, 'index': toc,
                       'editions': editions(book, leaves), 'labels': source.labels(), 'inserts': inserts,
                       'services': services,
                       'leaves': leaves},
                      ensure_ascii=False,
                      separators=(',', ':')).encode()
    with gzip.GzipFile(target, 'wb', mtime=0) as f:
        f.write(data)
    print(f'{target}: {len(leaves)} leaves, {len(inserts)} inserts, {len(services)} services, {len(data) // 1024} KB raw, {os.path.getsize(target) // 1024} KB gz')


def main(argv):
    for n in argv or source.nusachim():
        build(n)


if __name__ == '__main__':
    main(sys.argv[1:])
