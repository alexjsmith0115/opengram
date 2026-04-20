"""CLAR-N4 / P-1: NFC does not flatten curly quotes — explicit map required."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestTypography(unittest.TestCase):
    """CLAR-N4 / P-1: NFC does not flatten curly quotes — explicit map required."""

    def test_curly_apostrophe_flattened(self):
        self.assertEqual(bwp.normalize_text("don\u2019t"), "don't")

    def test_curly_double_flattened(self):
        self.assertEqual(bwp.normalize_text("\u201Chi\u201D"), '"hi"')

    def test_em_dash_flattened(self):
        self.assertEqual(bwp.normalize_text("a\u2014b"), "a--b")

    def test_nbsp_flattened(self):
        self.assertEqual(bwp.normalize_text("a\u00A0b"), "a b")

    def test_output_has_no_curly(self):
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml").decode()
        self.assertNotIn("\u2019", out)
        self.assertNotIn("\u201C", out)
        self.assertNotIn("\u201D", out)


if __name__ == "__main__":
    unittest.main()
