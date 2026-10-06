#!/usr/bin/env python3
"""Tests for edit.py on a temporary copy of a siddur: python3 tool/corpus/test_edit.py"""
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import edit  # noqa: E402
import source  # noqa: E402


def rd(p):
    with open(p, encoding='utf-8') as fh:
        return fh.read()


def vis(parts):
    return ''.join(edit.visible(p['text']) for p in parts)


class Words(unittest.TestCase):
    def test_tags_do_not_break_words(self):
        html = '<b>בָּרוּךְ</b> אַתָּה<br>יְהוָה&nbsp;אֱלֹהֵינוּ'
        ws = [html[a:b] for a, b in edit.words(html)]
        self.assertEqual(ws, ['בָּרוּךְ', 'אַתָּה', 'יְהוָה', 'אֱלֹהֵינוּ'])

    def test_phrase_ignores_niqqud_and_maqaf(self):
        html = 'זֵֽכֶר רַב־טוּבְ֒ךָ יַבִּֽיעוּ'
        self.assertEqual(edit.phrase_matches(html, 'רב טובך'), [(1, 1)])
        self.assertEqual(edit.phrase_matches(html, 'יביעו'), [(2, 2)])

    def test_pieces_balance_tags(self):
        html = '<b>אחד שנים שלשה</b> ארבעה'
        spans = edit.words(html)
        cut = edit.cut_before(html, spans, 2)
        a, b = edit.pieces(html, [cut])
        self.assertEqual(a, '<b>אחד שנים</b>')
        self.assertEqual(b, '<b> שלשה</b> ארבעה')


class Verses(unittest.TestCase):
    def test_numerals(self):
        self.assertEqual([edit.to_numeral(n) for n in (1, 9, 10, 12, 15, 16, 21, 118)], ['א', 'ט', 'י', 'יב', 'טו', 'טז', 'כא', 'קיח'])
        self.assertEqual(edit.numeral_value('טו'), 15)
        self.assertIsNone(edit.numeral_value('שים'))

    def part(self, html):
        s = edit.Session('x', root='/nonexistent')
        lf = {'path': 'T/p', 'node': 'x', 'he': {'version': 'v', 'segs': [{'ref': '1', 'kind': 'prayer', 'text': html}]}}
        s.docs = {'x': {'f.json': {'book': 'b', 'chunk': 'c', 'leaves': [lf]}}}
        s.orig[('x', 'f.json')] = json.dumps(s.docs['x']['f.json'])
        s.leaf = ('x', 'f.json', lf)
        return s, lf

    def test_bake_spaced_glued_and_sequence(self):
        s, lf = self.part('א הַלְלוּ יָהּ הַלְלוּ. ב יְהִי שֵׁם. יבמָה אָשִׁיב')
        lint = edit.cmd_lint(s, [])
        self.assertIn('verse he:1 w0', lint)
        self.assertIn('verse he:1 w4', lint)
        _, err, _ = edit.run_block(s, ['verse he:1 w4', 'verse he:1 w0'])
        self.assertIsNone(err, err)
        t = lf['he']['segs'][0]['text']
        self.assertTrue(t.startswith('<sup class="verse">א</sup> הַלְלוּ'))
        self.assertIn('<sup class="verse">ב</sup> יְהִי', t)

    def test_ashrei_letters_are_not_verses(self):
        s, lf = self.part('וּגְדָל חָסֶד. טוֹב יְהוָה לַכֹּל. יוֹדוּךָ יְהוָה')
        self.assertEqual(edit.cmd_lint(s, []), 'clean')
        _, err, _ = edit.run_block(s, ['verse he:1 w3 glued n=9'])
        self.assertIsNotNone(err)   # not a numeral followed by a pointed word... or not asserted

    def test_balance_and_tidy(self):
        self.assertEqual(edit.balance_html('<b>אחד</b></i> שנים <small>שלשה'), '<b>אחד</b> שנים <small>שלשה</small>')
        s, lf = self.part('<b>אחד  שנים')
        self.assertIn('balance he:1', edit.cmd_lint(s, []))
        _, err, _ = edit.run_block(s, ['balance he:1', 'tidy he:1'])
        self.assertIsNone(err, err)
        self.assertEqual(lf['he']['segs'][0]['text'], '<b>אחד שנים</b>')


class Ops(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.root = os.path.join(cls.tmp, 'siddur')
        shutil.copytree(os.path.join(source.SIDDUR, 'chabad'), os.path.join(cls.root, 'chabad'))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def session(self):
        s = edit.Session('chabad', root=self.root, work=os.path.join(self.tmp, 'bk'))
        s.load('chabad')
        return s

    def long_leaf(self, s):
        for n, f, lf in s.leaves():
            for seg in lf['he']['segs']:
                if 'parts' not in seg and len(edit.words(seg.get('text', ''))) > 12 and seg.get('kind') == 'prayer':
                    return lf['path'], seg['ref']
        self.fail('no long plain prayer segment')

    def test_tag_range_splits_without_changing_the_words(self):
        s = self.session()
        path, ref = self.long_leaf(s)
        before = next(seg for n, f, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] if seg['ref'] == ref)
        text = before['text']
        out, err, changed = edit.run_block(s, [f'@ {path}', f'tag he:{ref} w3..5 when=roshChodesh voice=undertone'])
        self.assertIsNone(err, err)
        self.assertTrue(changed)
        seg = next(seg for n, f, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] if seg['ref'] == ref)
        self.assertEqual(len(seg['parts']), 3)
        self.assertEqual(edit.visible(text), vis(seg['parts']))
        self.assertEqual([p.get('when') for p in seg['parts']], [None, 'roshChodesh', None])
        self.assertEqual(len(edit.words(seg['parts'][1]['text'])), 3)
        self.assertEqual(edit.validate_touched(s)[0], [])

    def test_whole_range_sets_fields_without_splitting(self):
        s = self.session()
        path, ref = self.long_leaf(s)
        n = len(edit.words(next(seg for _, _, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] if seg['ref'] == ref)['text']))
        out, err, _ = edit.run_block(s, [f'@ {path}', f'tag he:{ref} w0..{n - 1} align=center'])
        self.assertIsNone(err, err)
        seg = next(seg for _, _, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] if seg['ref'] == ref)
        self.assertNotIn('parts', seg)
        self.assertEqual(seg['align'], 'center')

    def test_block_is_atomic(self):
        s = self.session()
        path, ref = self.long_leaf(s)
        out, err, changed = edit.run_block(s, [f'@ {path}', f'set he:{ref} align=center', f'set he:{ref} role=nonsense'])
        self.assertIn('role', err)
        self.assertFalse(changed)
        seg = next(seg for _, _, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] if seg['ref'] == ref)
        self.assertNotIn('align', seg)
        self.assertEqual(s.touched, set())

    def test_errors_say_what_to_do(self):
        s = self.session()
        path, ref = self.long_leaf(s)
        _, err, _ = edit.run_block(s, [f'@ {path}', f'tag he:{ref} w0..9999 voice=aloud'])
        self.assertIn('outside', err)
        _, err, _ = edit.run_block(s, [f'@ {path}', 'set he:zzz voice=aloud'])
        self.assertIn('no he:zzz', err)
        _, err, _ = edit.run_block(s, ['set he:1 voice=aloud'])
        self.assertIn('which leaf', err)

    def test_tagall_tags_the_phrase_only(self):
        s = self.session()
        hit = None
        for n, f, lf in s.leaves():
            for seg in lf['he']['segs']:
                for p in edit.seg_parts(seg):
                    ws = edit.words(p.get('text', ''))
                    if len(ws) > 6:
                        hit = (lf['path'], p['text'], ws)
                        break
                if hit:
                    break
            if hit:
                break
        path, text, ws = hit
        phrase = edit.MARKS.sub('', edit.visible(text[ws[2][0]:ws[3][1]]))
        out, err, _ = edit.run_block(s, [f'@ {path}', f'tagall "~{phrase}" voice=undertone'])
        self.assertIsNone(err, err)
        self.assertIn('place', out[-1])
        tagged = [p for _, _, lf in s.leaves() if lf['path'] == path for seg in lf['he']['segs'] for p in edit.seg_parts(seg) if p.get('voice') == 'undertone']
        self.assertTrue(tagged)
        self.assertTrue(any(edit.norm_word(phrase) in edit.norm_word(p['text']) for p in tagged))

    def test_diff_and_commit_and_undo(self):
        s = self.session()
        path, ref = self.long_leaf(s)
        edit.run_block(s, [f'@ {path}', f'tag he:{ref} w1..2 voice=silent'])
        d = edit.diff_text(s)
        self.assertIn(path, d)
        self.assertIn('- he:' + ref, d)
        self.assertIn('+ he:' + ref + '.2', d)
        f = sorted(s.touched)[0][1]
        disk = os.path.join(self.root, 'chabad', f)
        before = rd(disk)
        self.assertIn('dry run', edit.commit(s, False))
        self.assertEqual(rd(disk), before)
        self.assertIn('applied', edit.commit(s, True))
        self.assertNotEqual(rd(disk), before)
        self.assertIn('restored', edit.undo(root=self.root, work=os.path.join(self.tmp, 'bk')))
        self.assertEqual(rd(disk), before)

    def test_proposal_is_applied_only_when_approved_and_fresh(self):
        old = edit.PROPOSALS
        edit.PROPOSALS = os.path.join(self.tmp, 'props')
        try:
            s = self.session()
            path, ref = self.long_leaf(s)
            edit.run_block(s, [f'@ {path}', f'set he:{ref} voice=silent'])
            prop = edit.make_proposal(s, task='t', ops=['x'])
            f = next(iter(prop['files']))
            disk = os.path.join(self.root, f)
            before = rd(disk)
            self.assertEqual(rd(disk), before)       # nothing written yet
            with self.assertRaises(edit.EditError):                              # file changed under it
                open(disk, 'a').close()
                shutil.copy(disk, disk + '.bak')
                with open(disk, 'w', encoding='utf-8') as fh:
                    fh.write(before.replace('"chunk"', '"chunk" ', 1))
                try:
                    edit.apply_proposal(prop['id'], root=self.root, work=os.path.join(self.tmp, 'bk2'))
                finally:
                    shutil.move(disk + '.bak', disk)
            self.assertIn('applied', edit.apply_proposal(prop['id'], root=self.root, work=os.path.join(self.tmp, 'bk2')))
            self.assertIn('voice": "silent"', rd(disk))
            with self.assertRaises(edit.EditError):
                edit.apply_proposal(prop['id'], root=self.root)
        finally:
            edit.PROPOSALS = old


if __name__ == '__main__':
    unittest.main()
