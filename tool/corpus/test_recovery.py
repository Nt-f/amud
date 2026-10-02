import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import convert


class RecoveryTests(unittest.TestCase):
    def test_failed_batch_is_deferred_and_resume_finishes_chunk(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory)
            for filename, text in [('SCHEMA.md', 'Test schema'), ('variables.json', '{}'), ('nodes.json', '{}')]:
                (corpus / filename).write_text(text)
            raw = {'nusach': 'ashkenaz', 'chunk': 'Test', 'leaves': [
                {'path': name, 'he': {'segments': [{'id': f'he:{name}:1', 'html': 'שָׁלוֹם'}]}}
                for name in ('Bad', 'Good')]}
            convert.write_json(corpus / 'raw/ashkenaz/test.json', raw)
            args = SimpleNamespace(chunk=None, leaf=None, batch_size=48, retries=0,
                                   max_batches=0, limit=0, last_usage={}, max_tokens=8192)
            success = {'commands': [['leaf', {'node': 'morning.modeh_ani'}]], 'reviewed': ['h1']}

            def partial_success(args, messages, schema=None, max_tokens=None):
                if '"leaf_path":"Bad"' in messages[1]['content']:
                    raise ValueError('Invalid model response')
                return success

            with patch.object(convert, 'CORPUS', corpus), contextlib.redirect_stdout(io.StringIO()):
                with patch.object(convert, 'request', partial_success):
                    convert.convert(args)
                checkpoint = json.loads((corpus / 'work/ashkenaz/test.json').read_text())
                self.assertEqual(set(checkpoint['he']), {'he:Good:1'})
                self.assertFalse((corpus / 'tagged/ashkenaz/test.json').exists())
                self.assertEqual(len(list((corpus / 'work/failures').rglob('*.json'))), 1)
                with patch.object(convert, 'request', return_value=success):
                    convert.convert(args)
                final = json.loads((corpus / 'tagged/ashkenaz/test.json').read_text())
                self.assertEqual(set(final['he']), {'he:Good:1', 'he:Bad:1'})
                self.assertEqual(len(list((corpus / 'work/failures').rglob('*.json'))), 0)


if __name__ == '__main__':
    unittest.main()
