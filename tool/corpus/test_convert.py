"""Regression checks for exact source recovery and pilot rubric failures."""
import unittest

import convert


class ConversionTests(unittest.TestCase):
    def raw(self, text):
        return {'leaves': [{'path': 'Berachot/Birkat HaMazon',
                           'he': {'segments': [{'id': 'he:test:1', 'html': text}]}}]}

    def test_split_recovers_exact_vowels_and_html(self):
        text = '<small>בעשרה</small> אֱלֹהֵינוּ'
        annotation = {'he': {'he:test:1': {'parts': [
            {'text': '<small>בעשרה</small>', 'kind': 'instruction', 'en': 'With ten'},
            {'text': ' אֱלֻהֵינוּ', 'kind': 'prayer'}]}}}
        convert.anchor_parts(self.raw(text), annotation)
        parts = annotation['he']['he:test:1']['parts']
        self.assertEqual(''.join(p['text'] for p in parts), text)
        self.assertIn('אֱלֹהֵינוּ', parts[1]['text'])

    def test_changed_letters_are_not_accepted_as_boundaries(self):
        annotation = {'he': {'he:test:1': {'parts': [
            {'text': 'שלום', 'kind': 'prayer'}, {'text': ' זר', 'kind': 'prayer'}]}}}
        convert.anchor_parts(self.raw('שלום עולם'), annotation)
        self.assertEqual(annotation['he']['he:test:1']['parts'][1]['text'], ' זר')
        # The original validator will reject this unchanged bad proposal.
        errors = []
        convert.validate.check_segment('he:test:1', 'שלום עולם',
                                       annotation['he']['he:test:1'], errors)
        self.assertTrue(errors)

    def test_omitted_parentheses_are_recovered_from_source(self):
        text = 'ברוך (<small>בעשרה</small> אלהינו) שאכלנו'
        annotation = {'he': {'he:test:1': {'parts': [
            {'text': 'ברוך ', 'kind': 'prayer'},
            {'text': '<small>בעשרה</small>', 'kind': 'instruction', 'en': 'With ten'},
            {'text': ' אלהינו ', 'kind': 'prayer'},
            {'text': 'שאכלנו', 'kind': 'prayer'}]}}}
        convert.anchor_parts(self.raw(text), annotation)
        self.assertEqual(''.join(p['text'] for p in annotation['he']['he:test:1']['parts']), text)

    def test_mixed_instruction_cannot_hide_spoken_words(self):
        annotation = {'he': {'he:test:1': {'kind': 'instruction', 'en': 'Some add'}}}
        self.assertTrue(convert.semantic_errors(
            self.raw('<small>ויש המוסיפים:</small> ברוך הוא'), annotation))

    def test_ten_diners_is_not_prayer_minyan(self):
        annotation = {'he': {'he:test:1': {'kind': 'prayer', 'when': 'minyan'}}}
        errors = convert.semantic_errors(self.raw('אלהינו'), annotation)
        self.assertTrue(any('ten diners' in e for e in errors))

    def test_seasonal_alternative_cannot_leave_default_unconditional(self):
        raw = self.raw('מגדיל (<small>בשבת:</small> מגדול)')
        annotation = {'he': {'he:test:1': {'parts': [
            {'text': 'מגדיל', 'kind': 'prayer'},
            {'text': ' (<small>בשבת:</small>', 'kind': 'instruction', 'en': 'On Shabbat:'},
            {'text': ' מגדול)', 'kind': 'prayer', 'when': 'shabbat'}]}}}
        self.assertTrue(any('mutually exclusive' in e for e in convert.semantic_errors(raw, annotation)))
        parts = annotation['he']['he:test:1']['parts']
        parts[0].update(when='!shabbat', alt='magdil')
        parts[2]['alt'] = 'magdil'
        self.assertFalse(convert.semantic_errors(raw, annotation))


if __name__ == '__main__':
    unittest.main()
