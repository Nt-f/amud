"""Deterministic preprocessing and bounded annotation commands; never shell code."""
import copy
import json
import re
import unicodedata

import validate

_POINTING = re.compile('[\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7]')

def _schema():
    """Grammar for guided decoding: each command's shape is fixed, so the
    model cannot emit malformed arrays or text fields."""
    meta = {'type': 'object', 'additionalProperties': False, 'properties': {
        'kind': {'enum': sorted(validate.KINDS)}, 'when': {'type': 'string'}, 'alt': {'type': 'string'},
        'node': {'type': 'string'}, 'role': {'enum': sorted(validate.ROLES)},
        'voice': {'enum': sorted(validate.VOICES)}, 'amidah': {'enum': sorted(validate.AMIDAH)},
        'minyan': {'const': True}, 'gestures': {'type': 'array', 'items': {'enum': sorted(validate.GESTURES)}},
        'repeat': {'type': 'integer', 'minimum': 2}, 'clean': {'type': 'string'}, 'en': {'type': 'string'},
        'cite': {'type': 'string'}, 'gloss': {'type': 'string'}, 'forgot': {'const': True}}}
    alias = {'type': 'string', 'pattern': r'^[he][0-9]+(\.[0-9]+)?(-[he][0-9]+)?$'}
    aliases = {'anyOf': [alias, {'type': 'array', 'items': alias}]}
    marker = {'anyOf': [{'type': 'string'}, {'type': 'object', 'additionalProperties': False,
                                            'required': ['before', 'occurrence'],
                                            'properties': {'before': {'type': 'string'},
                                                           'occurrence': {'type': 'integer', 'minimum': 1}}}]}
    leaf = {'type': 'object', 'additionalProperties': False, 'required': ['node'], 'properties': {
        'node': {'type': 'string'}, 'service': {'enum': sorted(validate.SERVICES)}, 'when': {'type': 'string'}}}
    issue = {'type': 'object', 'additionalProperties': False, 'required': ['id', 'type', 'detail'], 'properties': {
        'id': alias, 'type': {'enum': sorted(validate.ISSUE_TYPES)}, 'detail': {'type': 'string'}}}
    unsettable = sorted(validate.PART_FIELDS - {'text', 'kind', 'he'})

    def command(op, *args):
        return {'type': 'array', 'prefixItems': [{'const': op}, *args], 'items': False,
                'minItems': len(args) + 1, 'maxItems': len(args) + 1}

    return {'type': 'object', 'additionalProperties': False, 'required': ['commands', 'reviewed'],
            'properties': {
                'commands': {'type': 'array', 'items': {'anyOf': [
                    command('leaf', leaf),
                    command('tag', aliases, meta),
                    command('unset', aliases, {'type': 'array', 'items': {'enum': unsettable}}),
                    command('align', alias, {'type': 'array', 'items': alias}),
                    command('align_range', alias, alias),
                    command('split', alias, {'type': 'array', 'items': marker}, {'type': 'array', 'items': meta}),
                    command('issue', issue)]}},
                'reviewed': {'type': 'array', 'items': alias}}}


RESPONSE_SCHEMA = _schema()


def response_schema(prepared):
    """Per-batch grammar. Bounded arrays stop the model looping until it
    runs out of tokens; a new leaf must get its defaults, so "leaf" is
    required when there is no prior."""
    schema = copy.deepcopy(RESPONSE_SCHEMA)
    n = len(prepared['required'])
    schema['properties']['commands']['maxItems'] = 3 * n + 10
    schema['properties']['reviewed']['maxItems'] = n + 4
    if prepared['prior'] is None:
        schema['properties']['leaf'] = schema['properties']['commands']['items']['anyOf'][0]['prefixItems'][1]
        schema['required'] = ['leaf', 'commands', 'reviewed']
    return schema


PROTOCOL = '''Return only {"commands":[...], "reviewed":[...]}. When leaf_default is null,
also give "leaf": {"node":"...", "service":"...", "when":"..."} (node required).
Commands are typed annotation tools, NOT shell commands:
 ["leaf", {"node":"...", "service":"...", "when":"..."}]
 ["tag", "h12", {"kind":"note", "en":"..."}]
 ["tag", ["h12.0","h14.0"], {"kind":"instruction","en":"With ten:","when":"x_zimunTen"}]
 ["tag", "h12-h20", {"role":"chazzan","voice":"aloud"}]
 ["align", "e12", ["h13"]]
 ["align_range", "e1-e8", "h1-h8"]  // ONLY after checking each correspondence!
 ["split", "h12", ["short unvocalized start phrase", {"before":"phrase","occurrence":2}],
   [{"kind":"prayer"},{"kind":"instruction","en":"..."},{"kind":"prayer","when":"..."}]]
 ["issue", {"id":"h12", "type":"ambiguous", "detail":"..."}]
 ["unset", "h12", ["when"]]

Tag targets are selected segment aliases, inclusive ranges, or existing part addresses h12.0.
Source fragments are mechanically pre-split at small/italic formatting spans. These are
TENTATIVE classifications, not expert annotations. Inspect ALL selected text and ALL
its fragments; override any incorrect kind. Put conditions/roles on the relevant parts.
Alternatives need the SAME alt ID and mutually exclusive when conditions on BOTH
forms, including the default form. For Magdil/Migdol, Magdil has !shabbat && !yomTov
and Migdol has shabbat || yomTov; both share an alt ID. Do not leave Magdil unconditional.
Rules for forgetting are tagged forgot:true, including the associated corrective
prayers. Hebrew instructions, notes, headings and speaker labels ALWAYS need en
renderings unless an exact-text rendering was already supplied in the draft.
English rubrics often correspond to Hebrew rubrics even when English is more verbose;
do not use align [] just because the wording differs.
No need to output unchanged prayer defaults. NEVER output text, full IDs, copied prayers,
HTML, parts arrays containing text, nusach, chunk, leaves, he/en output objects, or paths.
For new leaf defaults use leaf; otherwise omit it and preserve the supplied leaf default.
For additional splits use short phrase markers; Python finds them ignoring vowels/HTML
and slices the original source EXACTLY. A split replaces any pre-split parts, so give all
resulting part metadata. Ambiguous markers require a one-based occurrence number.
Every selected English segment MUST receive align or align_range, even align [] if no
counterpart. Alignments may reference Hebrew aliases visible in the context. Empty
alignments require an alignment issue when a counterpart may exist outside the context.
Every selected segment MUST appear in reviewed (ranges allowed), including unchanged
prayers and English. reviewed confirms you read every segment, not permission to mass
accept unchecked defaults. Do NOT review/tag context-only segments. Example:
 {"commands":[["tag","h3.0",{"en":"On Rosh Chodesh:","when":"roshChodesh"}],
 ["tag","h3.1",{"when":"roshChodesh"}], ["align","e3",["h3"]]],
 "reviewed":["h3","e3"]}
'''


def _pointed(text):
    letters = [c for c in validate.comparable(text) if '\u05d0' <= c <= '\u05ea']
    return bool(letters) and len(_POINTING.findall(text)) >= len(letters) / 2


def _rubric_pieces(span):
    """A small span is usually a rubric, but congregational responses are
    often printed small too: "<em>ועונים:</em> אָמֵן" is a label then a
    spoken response, and a pointed span with no label is likely spoken."""
    label = re.search(r'</em>', span)
    if label and _pointed(span[label.end():]):
        return [{'text': span[:label.end()], 'kind': 'instruction'},
                {'text': span[label.end():], 'kind': 'prayer'}]
    return [{'text': span, 'kind': 'prayer' if _pointed(span) else 'instruction'}]


def fragments(text, lang):
    """Suggest boundaries only; semantic approval is still required."""
    tag = 'small' if lang == 'he' else 'i'
    matches = list(re.finditer(rf'<{tag}(?:\s[^>]*)?>.*?</{tag}>', text, re.S | re.I))
    if not matches:
        return [{'text': text, 'kind': 'prayer'}]
    pieces, end = [], 0
    for match in matches:
        before = text[end:match.start()]
        if validate.comparable(before):
            pieces.append({'text': before, 'kind': 'prayer'})
            before = ''
        pieces.extend(_rubric_pieces(before + match.group()))
        end = match.end()
    tail = text[end:]
    if validate.comparable(tail):
        pieces.append({'text': tail, 'kind': 'prayer'})
    elif pieces:
        pieces[-1]['text'] += tail
    else:
        pieces.append({'text': tail, 'kind': 'prayer'})
    # In mixed rubric/prayer passages, punctuation gives cheap candidate
    # clause boundaries (e.g. the two seasonal forms in Birkat HaMazon).
    # These have no calendar semantics until the model reviews them.
    expanded = []
    for piece in pieces:
        value = piece['text']
        if piece['kind'] != 'prayer' or len(pieces) == 1:
            expanded.append(piece)
            continue
        boundaries = [0]
        for token in re.finditer(r'<[^>]*>|&[^;\s]+;|[^<&]|[<&]', value):
            if token.group() in (',', ';'):
                boundaries.append(token.end())
        boundaries.append(len(value))
        for start, finish in zip(boundaries, boundaries[1:]):
            if finish > start:
                expanded.append({'text': value[start:finish], 'kind': 'prayer'})
    pieces = []
    for piece in expanded:
        if not validate.comparable(piece['text']) and pieces:
            pieces[-1]['text'] += piece['text']
        else:
            pieces.append(piece)
    assert ''.join(p['text'] for p in pieces) == text
    return pieces


def prepare(raw, leaf, selected, prior, translations=None, batch_size=48):
    translations = translations or {}
    aliases, originals, draft, required = {}, {}, {}, set()
    context = []
    for lang in ('he', 'en'):
        rows = leaf.get(lang, {}).get('segments', [])
        chosen = {s['id'] for s in selected[lang]}
        indexes = [i for i, s in enumerate(rows) if s['id'] in chosen]
        if not indexes:
            other = 'en' if lang == 'he' else 'he'
            other_chosen = {s['id'] for s in selected[other]}
            indexes = [i for i, s in enumerate(leaf.get(other, {}).get('segments', []))
                       if s['id'] in other_chosen]
        low = max(0, min(indexes, default=0) - 4)
        high = min(len(rows), max(indexes, default=-1) + 5)
        for i, segment in enumerate(rows):
            alias = ('h' if lang == 'he' else 'e') + str(i + 1)
            aliases[alias] = segment['id']
            originals[alias] = segment['html']
            if segment['id'] in chosen:
                required.add(alias)
                parts = fragments(segment['html'], lang)
                for part in parts:
                    if lang == 'he' and part['kind'] == 'instruction' and part['text'] in translations:
                        part['en'] = translations[part['text']]
                if len(parts) > 1:
                    entry = {'parts': parts}
                elif lang == 'he':
                    entry = {k: v for k, v in parts[0].items() if k != 'text'}
                else:
                    entry = {}
                if lang == 'en':
                    entry['he'] = []
                draft[alias] = entry
                context.append({'id': alias, 'selected': True,
                                'draft': entry, 'source': segment['html'] if 'parts' not in entry else None})
            elif low <= i < high:
                context.append({'id': alias, 'selected': False, 'source': segment['html']})
    return {'raw': raw, 'leaf': leaf, 'prior': prior, 'aliases': aliases,
            'originals': originals, 'draft': draft, 'required': required, 'context': context}


def expand(target):
    if isinstance(target, list):
        return [item for value in target for item in expand(value)]
    if not isinstance(target, str):
        raise ValueError('Target must be alias, range, or list')
    match = re.fullmatch(r'([he])(\d+)-\1(\d+)', target)
    if match:
        start, end = int(match[2]), int(match[3])
        if end < start or end - start > 10000:
            raise ValueError('Invalid alias range')
        return [match[1] + str(i) for i in range(start, end + 1)]
    if not re.fullmatch(r'[he]\d+(?:\.\d+)?', target):
        raise ValueError('Invalid alias: ' + target)
    return [target]


def _letters(text):
    return ''.join(c.lower() for c in unicodedata.normalize('NFD', validate.comparable(text))
                   if c.isalnum() and unicodedata.category(c) != 'Mn')


def marker_boundaries(text, markers):
    letters, positions = [], []
    for token in re.finditer(r'<[^>]*>|&[^;\s]+;|[^<&]|[<&]', text):
        if token.group().startswith(('<', '&')):
            continue
        for char in unicodedata.normalize('NFD', token.group()):
            if char.isalnum() and unicodedata.category(char) != 'Mn':
                letters.append(char.lower()); positions.append(token.start())
    normalized = ''.join(letters)
    boundaries = [0]
    for marker in markers:
        phrase = marker if isinstance(marker, str) else marker['before']
        key = ''.join(c.lower() for c in unicodedata.normalize('NFD', validate.comparable(phrase))
                      if c.isalnum() and unicodedata.category(c) != 'Mn')
        if not key:
            raise ValueError('Empty split marker')
        hits = [positions[m.start()] for m in re.finditer(f'(?={re.escape(key)})', normalized)]
        occurrence = marker.get('occurrence') if isinstance(marker, dict) else None
        if occurrence is not None:
            if not isinstance(occurrence, int) or not 1 <= occurrence <= len(hits):
                raise ValueError(f'Invalid marker occurrence: {marker}')
            hits = [hits[occurrence - 1]]
        # An opening tag right before the marker belongs to the new part.
        for n, hit in enumerate(hits):
            while (m := re.search(r'<(?!/)[^>]*>\s*$', text[:hit])) and m.start() > boundaries[-1]:
                hit = m.start()
            hits[n] = hit
        if len(hits) != 1 or hits[0] <= boundaries[-1]:
            raise ValueError(f'Marker needs a unique increasing boundary or occurrence: {marker}; '
                             f'found positions {hits}, previous boundary {boundaries[-1]}')
        boundaries.append(hits[0])
    return boundaries + [len(text)]


def apply(prepared, response, lenient=False):
    """Interpret metadata tools in memory. No arbitrary execution or file access.

    With [lenient] (a batch's last attempt), a malformed command is skipped
    rather than failing the batch, unreviewed segments keep their drafts and
    unaligned English is left unaligned with an issue: the source text stays
    exact either way, only some annotation is lost."""
    if isinstance(response, dict) and 'leaf' in response:
        response = dict(response)
        response['commands'] = [['leaf', response.pop('leaf')]] + list(response.get('commands', []))
    if not isinstance(response, dict) or set(response) != {'commands', 'reviewed'}:
        keys = list(response) if isinstance(response, dict) else type(response).__name__
        raise ValueError(f'Return exactly commands and reviewed; received {keys}')
    # Extra context aliases in reviewed are harmless; only omissions matter.
    try:
        reviewed = set(expand(response['reviewed']))
    except ValueError:
        if not lenient:
            raise
        reviewed = set(prepared['required'])
    missing = prepared['required'] - reviewed
    if missing and not lenient:
        raise ValueError(f'Review coverage missing {sorted(missing)}; '
                         'list every selected alias in reviewed (ranges allowed)')
    draft = copy.deepcopy(prepared['draft'])
    leaf = copy.deepcopy(prepared['prior'])
    issues, aligned = [], set()

    skipped = []

    def targets(value, strict=False):
        """Yields (alias, entry) per address. A retry costs a whole request,
        so tag/unset skip addresses that are context-only or don't exist
        (the review check still covers every selected segment)."""
        try:
            addresses = expand(value)
        except ValueError:
            if strict:
                raise
            skipped.append(str(value))
            return
        for address in addresses:
            alias, _, index = address.partition('.')
            entry = draft.get(alias)
            if entry is not None and index and not ('parts' not in entry and index == '0'):
                parts = entry.get('parts', [])
                entry = parts[int(index)] if int(index) < len(parts) else None
            if entry is None:
                if strict:
                    raise ValueError(f'Unknown or context-only address: {address}')
                skipped.append(address)
                continue
            yield alias, entry

    def fields(value):
        if not isinstance(value, dict) or set(value) - (validate.PART_FIELDS - {'text', 'he'}):
            raise ValueError('Only annotation metadata allowed; never text/parts/he')
        return value

    def align(english, hebrew):
        if english.startswith('e') and english in prepared['aliases'] and english not in draft:
            return  # Context-only English: aligned in its own batch.
        if english not in draft or not english.startswith('e'):
            raise ValueError('Alignment needs a selected English alias')
        hebrew = expand(hebrew)
        if any(h not in prepared['aliases'] or not h.startswith('h') or '.' in h for h in hebrew):
            raise ValueError('Alignment needs known Hebrew segment aliases')
        draft[english]['he'] = [prepared['aliases'][h] for h in hebrew]
        aligned.add(english)

    def flatten(items):
        for item in items:
            if isinstance(item, list) and item and isinstance(item[0], list):
                yield from flatten(item)
            else:
                yield item

    for command in flatten(response['commands']):
        try:
            if not isinstance(command, list) or not command:
                raise ValueError('Each command must be a nonempty array')
            op, *args = command
            if op == 'leaf' and len(args) == 1:
                if prepared['prior'] is not None and args[0] != prepared['prior']:
                    raise ValueError('Preserve existing leaf defaults')
                leaf = args[0]
            elif op == 'tag' and len(args) == 2:
                metadata = fields(args[1])
                for alias, entry in targets(args[0]):
                    if 'parts' in entry:
                        for part in entry['parts']:
                            part.update(metadata)
                    else:
                        entry.update(metadata)
            elif op == 'unset' and len(args) == 2:
                if any(k not in validate.PART_FIELDS - {'text', 'kind', 'he'} for k in args[1]):
                    raise ValueError('Cannot unset structural fields')
                for alias, entry in targets(args[0]):
                    for part in entry.get('parts', [entry]):
                        for key in args[1]:
                            part.pop(key, None)
            elif op == 'align' and len(args) == 2:
                align(args[0], args[1])
            elif op == 'align_range' and len(args) == 2:
                english, hebrew = expand(args[0]), expand(args[1])
                if len(english) != len(hebrew):
                    raise ValueError('Alignment ranges must have equal lengths')
                for e, h in zip(english, hebrew):
                    align(e, [h])
            elif op == 'split' and len(args) == 3:
                alias, markers, metadata = args
                if alias not in draft or '.' in alias:
                    raise ValueError('Split needs a selected segment alias')
                text = prepared['originals'][alias]
                if len(markers) == len(metadata) and markers:
                    # One marker per part: the first marks where part 1 starts.
                    if _letters(text).startswith(_letters(markers[0] if isinstance(markers[0], str)
                                                          else markers[0].get('before', '')) or '\0'):
                        markers = markers[1:]
                bounds = marker_boundaries(text, markers)
                if len(metadata) != len(bounds) - 1 or len(metadata) < 2:
                    raise ValueError('Split needs one metadata object per resulting part')
                parts = [dict(fields(meta), text=text[start:end])
                         for meta, start, end in zip(metadata, bounds, bounds[1:])]
                alignment = draft[alias].get('he') if alias.startswith('e') else None
                draft[alias] = {'parts': parts}
                if alignment is not None:
                    draft[alias]['he'] = alignment
            elif op == 'issue' and len(args) == 1:
                issue = copy.deepcopy(args[0])
                address = issue.get('id', '')
                alias, _, index = address.partition('.')
                if alias not in prepared['aliases']:
                    raise ValueError('Issue needs a known segment alias')
                if index:
                    list(targets(address, strict=True))  # Check that the referenced part exists.
                    issue['detail'] = f'Part {int(index) + 1}: ' + issue.get('detail', '')
                issue['id'] = prepared['aliases'][alias]
                issues.append(issue)
            else:
                raise ValueError('Unknown command or argument count: ' + str(op))
        except ValueError as e:
            if not lenient:
                raise
            skipped.append(str(e))
    missing = {a for a in draft if a.startswith('e')} - aligned
    if missing and not lenient:
        raise ValueError('English alignments missing: ' + ','.join(sorted(missing)))
    for alias in sorted(missing):
        issues.append({'id': prepared['aliases'][alias], 'type': 'alignment',
                       'detail': 'Not aligned by the tagger (left unaligned on its last attempt).'})
    if skipped:
        issues.append({'id': prepared['aliases'][sorted(prepared['required'])[0]], 'type': 'engine_bug_risk',
                       'detail': 'Tagger commands skipped on the last attempt: ' + '; '.join(skipped[:5])})
    if leaf is None:
        raise ValueError('New leaf needs leaf command with canonical node')
    for alias, entry in draft.items():
        if 'parts' in entry and ''.join(p['text'] for p in entry['parts']) != prepared['originals'][alias]:
            raise ValueError('Internal error: split did not preserve exact source')
    result = {'nusach': prepared['raw']['nusach'], 'chunk': prepared['raw']['chunk'],
              'leaves': {prepared['leaf']['path']: leaf}, 'he': {}, 'en': {}, 'issues': issues}
    for alias, entry in draft.items():
        result['he' if alias.startswith('h') else 'en'][prepared['aliases'][alias]] = entry
    return result


def bare(value):
    """Niqqud and cantillation cost the model most of its prompt tokens and
    say nothing about tagging; split markers ignore them anyway. Python
    keeps slicing the pointed original."""
    if isinstance(value, str):
        return _POINTING.sub('', value)
    if isinstance(value, list):
        return [bare(v) for v in value]
    if isinstance(value, dict):
        return {k: bare(v) for k, v in value.items()}
    return value


def prompt(prepared):
    return json.dumps({'leaf_path': prepared['leaf']['path'],
                       'leaf_default': prepared['prior'], 'segments': bare(prepared['context']),
                       'required_review': sorted(prepared['required'])}, ensure_ascii=False,
                      separators=(',', ':'))
