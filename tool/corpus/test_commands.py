import copy
import unittest

import commands


class CommandTests(unittest.TestCase):
    def prepare(self):
        leaf = {'path': 'Test', 'he': {'segments': [
            {'id': 'he:Test:1', 'html': 'בָּרוּךְ'},
            {'id': 'he:Test:2', 'html': '<small>בראש חודש:</small>'},
            {'id': 'he:Test:3', 'html': 'ברוך (<small>בעשרה</small> אֱלֹהֵינוּ) שאכלנו'}]},
            'en': {'segments': [{'id': 'en:Test:1', 'html': 'Blessed'},
                                 {'id': 'en:Test:2', 'html': '<i>On Rosh Chodesh:</i>'}]}}
        raw = {'nusach': 'ashkenaz', 'chunk': 'Test', 'leaves': [leaf]}
        selected = {lang: leaf[lang]['segments'] for lang in ('he', 'en')}
        return commands.prepare(raw, leaf, selected, {'node': 'morning.modeh_ani'})

    def response(self):
        return {'commands': [
            ['tag', 'h2', {'en': 'On Rosh Chodesh:', 'when': 'roshChodesh'}],
            ['tag', 'h3.1', {'en': 'With ten:', 'when': 'x_zimunTen'}],
            ['align_range', 'e1-e2', 'h1-h2']],
            'reviewed': ['h1-h3', 'e1-e2']}

    def test_compact_tools_cover_and_preserve_originals(self):
        prepared = self.prepare()
        result = commands.apply(prepared, self.response())
        self.assertEqual(set(result['he']), {'he:Test:1', 'he:Test:2', 'he:Test:3'})
        self.assertEqual(result['en']['en:Test:2']['he'], ['he:Test:2'])
        self.assertEqual(''.join(p['text'] for p in result['he']['he:Test:3']['parts']),
                         prepared['originals']['h3'])

    def test_markers_split_without_copying_hebrew(self):
        prepared = self.prepare()
        response = self.response()
        response['commands'].insert(0, ['split', 'h3', ['בעשרה', 'אלהינו', 'שאכלנו'], [
            {'kind': 'prayer'}, {'kind': 'instruction', 'en': 'With ten:'},
            {'kind': 'prayer', 'when': 'x_zimunTen'}, {'kind': 'prayer'}]])
        response['commands'].pop(2)  # Remove old pre-split part metadata.
        result = commands.apply(prepared, response)
        self.assertEqual(''.join(p['text'] for p in result['he']['he:Test:3']['parts']),
                         prepared['originals']['h3'])

    def test_unreviewed_defaults_are_rejected(self):
        response = self.response(); response['reviewed'] = ['h1-h2', 'e1-e2']
        with self.assertRaisesRegex(ValueError, 'Review coverage'):
            commands.apply(self.prepare(), response)

    def test_extra_command_array_wrapper_is_harmless(self):
        response = self.response()
        response['commands'] = [response['commands']]
        result = commands.apply(self.prepare(), response)
        self.assertEqual(result['en']['en:Test:2']['he'], ['he:Test:2'])

    def test_part_issue_is_resolved_to_stable_segment_id(self):
        response = self.response()
        response['commands'].append(['issue', {'id': 'h3.1', 'type': 'ambiguous', 'detail': 'Review condition'}])
        result = commands.apply(self.prepare(), response)
        self.assertEqual(result['issues'][0]['id'], 'he:Test:3')
        self.assertEqual(result['issues'][0]['detail'], 'Part 2: Review condition')

    def test_missing_alignment_is_rejected(self):
        response = self.response(); response['commands'].pop()
        with self.assertRaisesRegex(ValueError, 'alignments missing'):
            commands.apply(self.prepare(), response)

    def test_source_rewriting_and_shell_commands_are_rejected(self):
        for command in [['tag', 'h1', {'text': 'changed'}], ['shell', 'echo bad']]:
            response = self.response(); response['commands'].insert(0, command)
            with self.assertRaises(ValueError):
                commands.apply(self.prepare(), response)

    def test_last_attempt_salvages_a_flawed_response(self):
        response = {'commands': [['split', 'h3', ['nonexistent'], [{'kind': 'prayer'}]],
                                 ['tag', 'h2', {'en': 'On Rosh Chodesh:', 'when': 'roshChodesh'}]],
                    'reviewed': ['h1']}
        with self.assertRaises(ValueError):
            commands.apply(self.prepare(), response)
        result = commands.apply(self.prepare(), response, lenient=True)
        self.assertEqual(result['he']['he:Test:2']['when'], 'roshChodesh')
        self.assertEqual(result['en']['en:Test:1']['he'], [])
        self.assertTrue(any(i['type'] == 'alignment' for i in result['issues']))
        prepared = self.prepare()
        self.assertEqual(''.join(p['text'] for p in result['he']['he:Test:3']['parts']), prepared['originals']['h3'])

    def test_context_only_mutations_are_skipped(self):
        prepared = self.prepare(); prepared['draft'].pop('h3'); prepared['required'].remove('h3')
        response = self.response(); response['reviewed'] = ['h1-h2', 'e1-e2']
        result = commands.apply(prepared, response)
        self.assertNotIn('he:Test:3', result['he'])

    def test_ambiguous_marker_requires_occurrence(self):
        with self.assertRaisesRegex(ValueError, 'unique'):
            commands.marker_boundaries('אחד שני אחד שלישי', ['אחד'])
        bounds = commands.marker_boundaries('אחד שני אחד שלישי', [{'before': 'אחד', 'occurrence': 2}])
        self.assertEqual(bounds, [0, 8, 17])


if __name__ == '__main__':
    unittest.main()
