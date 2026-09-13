# SPDX-License-Identifier: GPL-2.0
from pathlib import Path
import tempfile
import unittest
from lint_trusted import violations


class TrustBoundary(unittest.TestCase):
    def test_only_explicit_directories_are_exempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ('trusted', 'loader', 'policy/trusted'):
                (root / directory).mkdir(parents=True)
                (root / directory / 'lib.rs').write_text('unsafe {}\n#[verifier::external_body]\n')
            hits = list(violations(root, [root / 'trusted'], [root / 'loader']))
            self.assertEqual(len(hits), 3)
            self.assertEqual(sum('/loader/' in hit for hit in hits), 1)
            self.assertEqual(sum('/policy/trusted/' in hit for hit in hits), 2)

    def test_missing_source_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                list(violations(Path(tmp) / 'missing'))
