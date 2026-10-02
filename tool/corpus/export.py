#!/usr/bin/env python3
"""Exports the bundled Sefaria siddurim into corpus/raw: one file per chunk
(a subtree of ~250 Hebrew segments), each segment with a stable id, for
the tagging agents to annotate (see corpus/SCHEMA.md).

Per leaf, the Hebrew and English come from the first version in the book's
defaultVersions (assets/rules/rules.json) that has text there, as the app
does by default.

    python3 tool/corpus/export.py
"""
import gzip
import json
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEFARIA = os.path.join(ROOT, 'assets', 'sefaria')
OUT = os.path.join(ROOT, 'corpus', 'raw')

# Book title -> corpus slug. Versions in preference order (defaultVersions
# where rules.json has them).
BOOKS = {
    'Siddur Ashkenaz': 'ashkenaz',
    'Siddur Sefard': 'sefard',
    'Siddur Edot HaMizrach': 'edot_hamizrach',
    'Weekday Siddur Chabad': 'chabad',
    'The Koren Shalem Siddur; Ashkenaz': 'koren',
}
FALLBACK_VERSIONS = {
    'The Koren Shalem Siddur; Ashkenaz': {
        'he': ['Hebrew Edition; Koren Publishers Jerusalem, 2017'],
        'en': ['English Edition; Koren Publishers Jerusalem, 2017'],
    },
}
CHUNK_TARGET = 250


def load_gz(name):
    with gzip.open(os.path.join(SEFARIA, name)) as f:
        return json.load(f)


def leaves(node, path=()):
    kids = node.get('nodes') or []
    title = node.get('enTitle') or node.get('key') or node.get('title') or ''
    here = path + (title,) if path or node.get('_child') else path
    if not kids:
        yield here, node
        return
    for k in kids:
        k['_child'] = True
        yield from leaves(k, here)


def he_titles(node, path=(), out=None):
    out = {} if out is None else out
    for k in node.get('nodes') or []:
        p = path + (k.get('enTitle') or k.get('key') or '',)
        out['/'.join(p)] = k.get('heTitle') or ''
        he_titles(k, p, out)
    return out


def segments_at(text, path):
    t = text
    for p in path:
        if isinstance(t, dict):
            t = t.get(p, t.get(''))
        else:
            return None
    while isinstance(t, dict) and '' in t:
        t = t['']
    if not isinstance(t, list):
        return None
    out = []

    def walk(n, prefix):
        if isinstance(n, list):
            for i, c in enumerate(n):
                walk(c, f'{prefix}:{i + 1}' if prefix else f'{i + 1}')
        elif isinstance(n, str) and n.strip():
            out.append((prefix, n))

    walk(t, '')
    return out or None


def pack(leaf_data):
    """Groups leaves (in book order) into chunks of about CHUNK_TARGET
    segments. A subtree that fits stays whole; a larger one is split
    between its children, and neighbouring small pieces are packed
    together. Returns [(name, [entry, ...])]."""
    def size(e):
        return len(e.get('he', {}).get('segments', [])) or len(e.get('en', {}).get('segments', []))

    def split(items, depth):
        # items: [(path, entry)] sharing path[:depth]
        total = sum(size(e) for _, e in items)
        if total <= CHUNK_TARGET or all(len(p) <= depth for p, _ in items):
            return [items]
        groups, out = [], []
        for p, e in items:
            k = p[depth] if len(p) > depth else ''
            if groups and groups[-1][0] == k:
                groups[-1][1].append((p, e))
            else:
                groups.append((k, [(p, e)]))
        for _, g in groups:
            out.extend(split(g, depth + 1))
        return out

    pieces = split(leaf_data, 0)
    chunks, cur, n = [], [], 0
    for piece in pieces:
        m = sum(size(e) for _, e in piece)
        if cur and n + m > CHUNK_TARGET:
            chunks.append(cur)
            cur, n = [], 0
        cur.extend(piece)
        n += m
    if cur:
        chunks.append(cur)

    named, seen = [], {}
    for c in chunks:
        paths = [p for p, _ in c]
        common = paths[0]
        for p in paths[1:]:
            i = 0
            while i < min(len(common), len(p)) and common[i] == p[i]:
                i += 1
            common = common[:i]
        first, last = paths[0], paths[-1]
        name = '/'.join(common) if common else 'book'
        if len(paths) > 1 and first[:len(common) + 1] != last[:len(common) + 1]:
            name += f' [{first[len(common)] if len(first) > len(common) else ""} .. {last[len(common)] if len(last) > len(common) else ""}]'
        seen[name] = seen.get(name, 0) + 1
        if seen[name] > 1:
            name += f' #{seen[name]}'
        named.append((name, [e for _, e in c]))
    return named


def slug(s):
    return re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')


def main():
    manifest = json.load(open(os.path.join(SEFARIA, 'manifest.json')))
    rules = json.load(open(os.path.join(ROOT, 'assets', 'rules', 'rules.json')))
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    summary = []
    for book in manifest['books']:
        if book['title'] not in BOOKS:
            continue
        bslug = BOOKS[book['title']]
        index = load_gz(book['index'])
        hetitle = he_titles(index['schema'])
        prefs = (rules.get(book['title'], {}).get('defaultVersions')
                 or FALLBACK_VERSIONS[book['title']])
        versions = {}
        for lang in ('he', 'en'):
            versions[lang] = []
            for title in prefs.get(lang, []):
                v = next((v for v in book['versions']
                          if v['language'] == lang and v['versionTitle'] == title), None)
                if v:
                    versions[lang].append((v, load_gz(v['file'])['text']))

        leaf_data = []
        for path, _ in leaves(index['schema']):
            entry = {'path': '/'.join(path), 'title': {'en': path[-1], 'he': hetitle.get('/'.join(path), '')}}
            for lang in ('he', 'en'):
                for v, text in versions[lang]:
                    segs = segments_at(text, list(path))
                    if segs:
                        entry[lang] = {
                            'version': v['versionTitle'].strip(),
                            'license': v.get('license', 'unknown'),
                            'segments': [{'id': f"{lang}:{entry['path']}:{ref}", 'html': html} for ref, html in segs],
                        }
                        break
            leaf_data.append((path, entry))

        chunks = pack(leaf_data)

        os.makedirs(os.path.join(OUT, bslug), exist_ok=True)
        for i, (key, entries) in enumerate(chunks):
            name = f'{i + 1:02d}_' + slug(key)[:60]
            nhe = sum(len(e.get('he', {}).get('segments', [])) for e in entries)
            nen = sum(len(e.get('en', {}).get('segments', [])) for e in entries)
            doc = {'book': book['title'], 'nusach': bslug, 'chunk': key, 'leaves': entries}
            with open(os.path.join(OUT, bslug, name + '.json'), 'w') as f:
                json.dump(doc, f, ensure_ascii=False, indent=1)
            summary.append({'book': bslug, 'chunk': key, 'file': f'{bslug}/{name}.json', 'he': nhe, 'en': nen})

    with open(os.path.join(OUT, 'chunks.json'), 'w') as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    for s in summary:
        print(f"{s['he']:5} {s['en']:5}  {s['file']}")
    print(len(summary), 'chunks,', sum(s['he'] for s in summary), 'he,', sum(s['en'] for s in summary), 'en')


if __name__ == '__main__':
    main()
