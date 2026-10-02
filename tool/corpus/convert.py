#!/usr/bin/env python3
"""Resume corpus annotation using an OpenAI-compatible server (stdlib only)."""
import argparse
import copy
from datetime import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import time
import unicodedata
import urllib.request
import urllib.error

import validate
import commands

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'corpus'


def anchor_parts(raw, ann):
    """Replace equivalent generated part text with exact slices of the source."""
    for leaf in raw['leaves']:
        for lang in ('he', 'en'):
            for segment in leaf.get(lang, {}).get('segments', []):
                parts = ann.get(lang, {}).get(segment['id'], {}).get('parts')
                if not isinstance(parts, list) or not parts:
                    continue
                original = segment['html']
                generated = ''.join(p.get('text', '') for p in parts)
                # Model text is only a proposed boundary. Recover exact source
                # vowels and punctuation when letters agree; never use its copy.
                def compare(text):
                    return ''.join(c for c in unicodedata.normalize('NFD', validate.comparable(text))
                                   if c.isalnum() and unicodedata.category(c) != 'Mn')
                if compare(generated) != compare(original):
                    continue  # Let the validator reject actual text alterations.
                boundaries = [0]
                prefix = ''
                # Boundaries cannot fall inside an HTML tag or entity.
                positions = [m.end() for m in re.finditer(r'<[^>]*>|&[^;\s]+;|[^<&]|[<&]', original)]
                positions = [i for i in positions
                             if not (i < len(original) and unicodedata.category(original[i]) == 'Mn')
                             and not re.match(r'</[^>]*>|[)\]:;,]', original[i:])]
                for part in parts[:-1]:
                    prefix += part['text']
                    want = compare(prefix)
                    boundary = next((i for i in positions if i > boundaries[-1]
                                     and compare(original[:i]) == want), None)
                    if boundary is None:
                        raise ValueError(f'{segment["id"]}: cannot anchor split to original text')
                    boundaries.append(boundary)
                boundaries.append(len(original))
                for part, start, end in zip(parts, boundaries, boundaries[1:]):
                    part['text'] = original[start:end]


def semantic_errors(raw, ann):
    """Catch observable rubric problems; not a substitute for expert review."""
    errors = []
    for leaf in raw['leaves']:
        for segment in leaf.get('he', {}).get('segments', []):
            entry = ann.get('he', {}).get(segment['id'], {})
            def letters(text):
                return ''.join(c for c in unicodedata.normalize('NFD', validate.comparable(text))
                               if c.isalnum() and unicodedata.category(c) != 'Mn')
            original_letters = letters(segment['html'])
            if 'מגדיל' in original_letters and 'מגדול' in original_letters:
                alternatives = [p for p in entry.get('parts', [entry])
                                if p.get('kind') == 'prayer' and any(
                                    word in letters(p.get('text', segment['html']))
                                    for word in ('מגדיל', 'מגדול'))]
                if (len(alternatives) != 2 or any(not p.get('when') or not p.get('alt') for p in alternatives)
                        or len({p.get('alt') for p in alternatives}) != 1):
                    errors.append(f'{segment["id"]}: Magdil/Migdol are mutually exclusive alternatives; '
                                  'each needs when and the same alt ID, not two unconditional prayers')
            for part in entry.get('parts', [entry]):
                text = part.get('text', segment['html'])
                if part.get('kind') in ('instruction', 'speaker', 'heading', 'note') and not part.get('en'):
                    errors.append(f'{segment["id"]}: Hebrew rubric/note needs English rendering')
                # These literal rubrics cannot be embedded in a prayer part.
                if part.get('kind') == 'prayer' and re.search(r'<small>[^<]*(?:בעשרה|אומרים|המוסיפים)', text):
                    errors.append(f'{segment["id"]}: split the small-tag instruction from the prayer')
                if ('parts' not in entry and part.get('kind') in ('instruction', 'speaker')
                        and re.search(r'<small(?:\s[^>]*)?>', text, re.I)):
                    outside = re.sub(r'<small>.*?</small>', '', text, flags=re.S)
                    if validate.comparable(outside):
                        errors.append(f'{segment["id"]}: mixed rubric and prayer needs parts')
                if 'Birkat HaMazon' in leaf['path'] and re.search(r'\bminyan\b', part.get('when', '')):
                    errors.append(f'{segment["id"]}: ten diners is x_zimunTen, not prayer minyan; '
                                  'report new_variable and split its rubric')
                if part.get('kind') == 'instruction' and part.get('when') == 'x_zimunTen':
                    letters = ''.join(c for c in unicodedata.normalize('NFD', validate.comparable(text))
                                      if c.isalnum() and unicodedata.category(c) != 'Mn')
                    if 'אלהינו' in letters:
                        errors.append(f'{segment["id"]}: אלהינו is spoken prayer; split it from the instruction')
    return errors


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    with open(temporary, 'w') as handle:
        handle.write(json.dumps(value, ensure_ascii=False, indent=1) + '\n')
        # Without this a crash can leave the renamed file empty.
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def check(raw, annotation, relative):
    """Use the existing validator against a temporary, possibly partial corpus."""
    old = validate.CORPUS
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        write_json(root / 'raw' / relative, raw)
        target = root / 'tagged' / relative
        write_json(target, annotation)
        try:
            validate.CORPUS = directory
            return validate.validate(str(target))
        finally:
            validate.CORPUS = old


def request(args, messages, schema=commands.RESPONSE_SCHEMA, max_tokens=None):
    body = {'model': args.model, 'messages': messages,
            'max_tokens': max_tokens or args.max_tokens, 'temperature': 0.2,
            'response_format': {'type': 'json_schema', 'json_schema': {
                'name': 'annotation_commands', 'schema': schema}},
            'chat_template_kwargs': {'enable_thinking': False}}
    headers = {'Content-Type': 'application/json'}
    key = os.environ.get(args.api_key_env)
    if key:
        headers['Authorization'] = 'Bearer ' + key
    req = urllib.request.Request(args.base_url.rstrip('/') + '/chat/completions',
                                 json.dumps(body).encode(), headers)
    waited = 0
    while True:
        try:
            with urllib.request.urlopen(req, timeout=args.timeout) as response:
                result = json.load(response)
            break
        except urllib.error.HTTPError as exc:
            if exc.code in (502, 503, 504):
                pass  # Server restarting; wait like a refused connection.
            else:
                raise ValueError(f'HTTP {exc.code}: {exc.read().decode()}') from exc
        except urllib.error.URLError as exc:
            if not isinstance(exc.reason, (ConnectionError, OSError)) or isinstance(exc.reason, TimeoutError):
                raise
        # The server is down or restarting: wait for it rather than spend
        # this batch's retries.
        if waited % 300 == 0:
            print(f'{datetime.now().isoformat(timespec="seconds")} server unavailable; waiting', flush=True)
        time.sleep(30)
        waited += 30
    choice = result['choices'][0]
    args.last_usage = result.get('usage', {})
    if choice['finish_reason'] != 'stop':
        raise ValueError('Incomplete response: ' + str(choice['finish_reason']))
    return json.loads(choice['message']['content'])


def translation_cache():
    """Reuse only exact-text English renderings, never context-dependent tags."""
    cache = {}
    paths = list((CORPUS / 'tagged').glob('*/*.json')) + list((CORPUS / 'work').glob('*/*.json'))
    for path in paths:
        if path.name.endswith('.pilot.json'):
            continue
        relative = path.relative_to(path.parent.parent)
        source = CORPUS / 'raw' / relative
        if not source.exists():
            continue
        try:
            ann = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue  # A checkpoint cut off mid-write; its chunk redoes it.
        raw = json.loads(source.read_text())
        for leaf in raw['leaves']:
            for segment in leaf.get('he', {}).get('segments', []):
                entry = ann.get('he', {}).get(segment['id'], {})
                for part in entry.get('parts', [dict(entry, text=segment['html'])]):
                    if isinstance(part.get('en'), str):
                        cache[part['text']] = part['en']
    return cache


def convert(args):
    schema = (CORPUS / 'SCHEMA.md').read_text()
    # One line per entry: the server has no prefix cache, so every request
    # pays for the whole system prompt.
    variables = '\n'.join(f'{k}: {v.get("doc", "")}' for k, v in
                          json.loads((CORPUS / 'variables.json').read_text()).items())
    nodes = '\n'.join(f'{k}: {v.get("en", "")}' for k, v in
                      json.loads((CORPUS / 'nodes.json').read_text()).items())
    system = ('You annotate siddur texts. Follow this specification exactly. '
              'Use the compact annotation command tools described AFTER the specification. '
              'The specification describes the final artifact; Python constructs it for you. '
              'Never output prayer text. Read every selected segment carefully. '
              'Do not infer uncertain customs: record ambiguous issues.\n\n' + schema
              + '\n\nVARIABLES:\n' + variables + '\n\nNODES:\n' + nodes
              + '\n\nCOMMAND PROTOCOL (your response format):\n' + commands.PROTOCOL)
    translations = translation_cache()
    done = 0
    batches = 0
    for source in sorted((CORPUS / 'raw').glob('*/*.json')):
        relative = source.relative_to(CORPUS / 'raw')
        if args.chunk and args.chunk != str(relative):
            continue
        target = CORPUS / 'tagged' / relative
        if target.exists():
            errors = validate.validate(str(target))
            if errors:
                raise ValueError(f'Existing file needs repair: {relative}: {errors[:3]}')
            continue
        raw = json.loads(source.read_text())
        checkpoint = CORPUS / 'work' / relative
        try:
            saved = json.loads(checkpoint.read_text()) if checkpoint.exists() else None
        except json.JSONDecodeError:
            saved = None  # Cut off mid-write: start the chunk again.
        ann = saved or {
            'nusach': raw['nusach'], 'chunk': raw['chunk'], 'leaves': {},
            'he': {}, 'en': {}, 'issues': []}
        for leaf in raw['leaves']:
            if args.leaf and args.leaf != leaf['path']:
                continue
            segments = {lang: leaf.get(lang, {}).get('segments', []) for lang in ('he', 'en')}
            # Keep the whole leaf available for translation alignment and context.
            count = max(len(segments['he']), len(segments['en']), 1)
            for offset in range(0, count, args.batch_size):
                selected = {lang: [s for s in segments[lang][offset:offset + args.batch_size]
                                   if s['id'] not in ann[lang]] for lang in ('he', 'en')}
                if not any(selected.values()) and leaf['path'] in ann['leaves']:
                    continue
                partial = copy.deepcopy(raw)
                part_leaf = copy.deepcopy(leaf)
                for lang in ('he', 'en'):
                    if lang in part_leaf:
                        part_leaf[lang]['segments'] = selected[lang]
                partial['leaves'] = [part_leaf]
                prepared = commands.prepare(raw, leaf, selected, ann['leaves'].get(leaf['path']),
                                            translations, args.batch_size)
                prompt = commands.prompt(prepared)
                messages = [{'role': 'system', 'content': system}, {'role': 'user', 'content': prompt}]
                start = time.monotonic()
                print(f'{datetime.now().isoformat(timespec="seconds")} {relative}: '
                      f'{leaf["path"]} batch {offset // args.batch_size + 1} '
                      f'({len(prepared["required"])} segments, compact tools)', flush=True)
                for attempt in range(args.retries + 1):
                    response = None
                    result = None
                    try:
                        response = request(args, messages, commands.response_schema(prepared),
                                           min(args.max_tokens, 800 + 200 * len(prepared['required'])))
                        leaf_key = hashlib.sha256(leaf['path'].encode()).hexdigest()[:12]
                        audit = (CORPUS / 'work' / 'commands' / relative.parent / checkpoint.stem
                                 / f'{leaf_key}-batch-{offset}.json')
                        write_json(audit.with_name(audit.stem + f'.attempt-{attempt}.json'),
                                   {'leaf': leaf['path'], 'offset': offset, 'response': response,
                                    'usage': args.last_usage})
                        result = commands.apply(prepared, response, lenient=attempt == args.retries)
                        # Allow English alignment to Hebrew outside the selected batch.
                        alignment_errors = []
                        all_he = {s['id'] for s in segments['he']}
                        for sid, entry in result.get('en', {}).items():
                            alignment = entry.get('he')
                            if not isinstance(alignment, list) or any(h not in all_he for h in alignment):
                                alignment_errors.append(f'{sid}: invalid or missing Hebrew alignment')
                        validation_result = copy.deepcopy(result)
                        for entry in validation_result.get('en', {}).values():
                            entry['he'] = []
                        errors = check(partial, validation_result, relative) + alignment_errors
                        if result.get('nusach') != raw['nusach']:
                            errors.append('Incorrect nusach')
                        semantic = semantic_errors(partial, result)
                        if attempt == args.retries:
                            # Last attempt: these are judgments about the
                            # tags, not the text; keep them for review.
                            for e in semantic:
                                result['issues'].append({'id': e.split(': ')[0], 'type': 'engine_bug_risk',
                                                         'detail': 'Unresolved by the tagger: ' + e})
                        else:
                            errors.extend(semantic)
                        prior = ann['leaves'].get(leaf['path'])
                        if prior is not None and result.get('leaves', {}).get(leaf['path']) != prior:
                            errors.append('Leaf default differs from prior: ' + json.dumps(prior))
                        if errors:
                            raise ValueError('\n'.join(errors[:30]))
                        write_json(audit, {'leaf': leaf['path'], 'offset': offset, 'response': response,
                                          'usage': args.last_usage})
                        break
                    except Exception as exc:
                        if attempt == args.retries:
                            result = None
                            leaf_key = hashlib.sha256(leaf['path'].encode()).hexdigest()[:12]
                            failure = (CORPUS / 'work' / 'failures' / relative.parent / checkpoint.stem
                                       / f'{leaf_key}-batch-{offset}.json')
                            write_json(failure, {'chunk': str(relative), 'leaf': leaf['path'],
                                                 'offset': offset, 'error': str(exc),
                                                 'time': datetime.now().isoformat(),
                                                 'ids': {k: [s['id'] for s in selected[k]] for k in ('he', 'en')}})
                            print(f'DEFERRED {relative}: {leaf["path"]} batch {offset}: {exc}', flush=True)
                            break
                        print(f'  retry {attempt + 1}: {exc}', flush=True)
                        if response is not None:
                            messages.append({'role': 'assistant', 'content': json.dumps(response, ensure_ascii=False)})
                        messages.append({'role': 'user', 'content': 'Previous attempt failed: ' + str(exc)
                                         + '\nReturn corrected compact commands and reviewed ONLY. Do not copy source text.'})
                        time.sleep(2)
                if result is None:
                    continue
                failure = (CORPUS / 'work' / 'failures' / relative.parent / checkpoint.stem
                           / f'{leaf_key}-batch-{offset}.json')
                if failure.exists():
                    failure.unlink()
                ann['leaves'].update(result['leaves'])
                for lang in ('he', 'en'):
                    ann[lang].update(result.get(lang, {}))
                for issue in result.get('issues', []):
                    if issue not in ann['issues']:
                        ann['issues'].append(issue)
                write_json(checkpoint, ann)
                for entry in result['he'].values():
                    for part in entry.get('parts', []):
                        if isinstance(part.get('en'), str):
                            translations[part['text']] = part['en']
                print(f'{datetime.now().isoformat(timespec="seconds")} SAVED '
                      f'{len(selected["he"])} he / {len(selected["en"])} en; '
                      f'{time.monotonic() - start:.1f}s; '
                      f'{args.last_usage.get("completion_tokens", "?")} output tokens; '
                      f'{len(response["commands"])} commands', flush=True)
                batches += 1
                if args.max_batches and batches >= args.max_batches:
                    print(f'Saved {batches} batches to {checkpoint}; chunk still incomplete.', flush=True)
                    return
        if args.leaf:
            print(f'Saved selected leaf to {checkpoint}; chunk still incomplete.', flush=True)
            continue
        incomplete = any(leaf['path'] not in ann['leaves'] or any(
            s['id'] not in ann[lang] for lang in ('he', 'en')
            for s in leaf.get(lang, {}).get('segments', [])) for leaf in raw['leaves'])
        if incomplete:
            print(f'INCOMPLETE {relative}: checkpoints preserved; continuing other chunks.', flush=True)
            continue
        # Semantic problems left after the last attempt are issues by now.
        errors = check(raw, ann, relative)
        if errors:
            write_json(CORPUS / 'work' / 'failures' / relative.parent / (checkpoint.stem + '.final.json'),
                       {'chunk': str(relative), 'errors': errors, 'time': datetime.now().isoformat()})
            print(f'DEFERRED final validation {relative}: {errors[:3]}', flush=True)
            continue
        write_json(target, ann)
        print(f'OK: {relative}', flush=True)
        done += 1
        if args.limit and done >= args.limit:
            break
    print(f'Completed {done} new chunks.', flush=True)


def pending_chunks():
    return [str(p.relative_to(CORPUS / 'raw')) for p in sorted((CORPUS / 'raw').glob('*/*.json'))
            if not (CORPUS / 'tagged' / p.relative_to(CORPUS / 'raw')).exists()]


def run_parallel(args, argv):
    """One child process per chunk, so checkpoints never collide; vLLM
    batches the concurrent requests. Child output goes to work/logs/."""
    forward, skip = [], False
    for a in argv:
        if skip:
            skip = False
        elif a in ('--workers', '--passes'):
            skip = True
        elif not a.startswith(('--workers=', '--passes=')):
            forward.append(a)

    def work(relative):
        log = CORPUS / 'work' / 'logs' / relative.replace('.json', '.log')
        log.parent.mkdir(parents=True, exist_ok=True)
        print(f'{datetime.now().isoformat(timespec="seconds")} START {relative}', flush=True)
        with open(log, 'a') as handle:
            code = subprocess.call([sys.executable, __file__, *forward, '--chunk', relative, '--passes', '1'],
                                   stdout=handle, stderr=subprocess.STDOUT)
        state = 'OK' if (CORPUS / 'tagged' / relative).exists() else f'INCOMPLETE (exit {code})'
        print(f'{datetime.now().isoformat(timespec="seconds")} {state} {relative}', flush=True)

    for number in range(max(1, args.passes)):
        todo = pending_chunks()
        print(f'PASS {number + 1}/{args.passes}: {len(todo)} chunks, {args.workers} workers', flush=True)
        if not todo:
            break
        with ThreadPoolExecutor(args.workers) as pool:
            list(pool.map(work, todo))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--model', default='siddur')
    parser.add_argument('--api-key-env', default='VLLM_API_KEY')
    parser.add_argument('--batch-size', type=int, default=48)
    parser.add_argument('--max-tokens', type=int, default=8192)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--retries', type=int, default=2)
    parser.add_argument('--chunk', help='Relative raw chunk path, including nusach/')
    parser.add_argument('--leaf', help='Exact leaf path for a pilot run (checkpoint only)')
    parser.add_argument('--max-batches', type=int, default=0, help='Stop after this many new batches')
    parser.add_argument('--limit', type=int, default=0, help='Maximum new chunks; 0 means all')
    parser.add_argument('--passes', type=int, default=2, help='Full-run passes; later passes retry missing batches')
    parser.add_argument('--workers', type=int, default=1, help='Chunks converted concurrently')
    args = parser.parse_args()
    if args.workers > 1 and not args.chunk:
        run_parallel(args, sys.argv[1:])
        pending = pending_chunks()
        print(f'RUN FINISHED: {len(pending)} chunks still incomplete; see corpus/work/failures.', flush=True)
        sys.exit(0)
    passes = 1 if args.limit or args.max_batches or args.leaf else max(1, args.passes)
    for number in range(passes):
        print(f'PASS {number + 1}/{passes}', flush=True)
        convert(args)
        sources = list((CORPUS / 'raw').glob('*/*.json'))
        if all((CORPUS / 'tagged' / p.relative_to(CORPUS / 'raw')).exists() for p in sources):
            break
    pending = [p for p in (CORPUS / 'raw').glob('*/*.json')
               if not (CORPUS / 'tagged' / p.relative_to(CORPUS / 'raw')).exists()]
    print(f'RUN FINISHED: {len(pending)} chunks still incomplete; see corpus/work/failures.', flush=True)
