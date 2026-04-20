"""CLAR-N4: every emitted string field equals nfc(field)."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestNFCInvariant(unittest.TestCase):
    """CLAR-N4: every emitted string field equals nfc(field)."""

    def test_normalize_text_is_idempotent(self):
        import unicodedata
        s = "café"
        self.assertEqual(bwp.normalize_text(s), unicodedata.normalize("NFC", bwp.normalize_text(s)))

    def test_derive_id_lowercases_and_nfc(self):
        self.assertEqual(bwp.derive_id("In Order To"), "in order to")

    def test_output_bytes_are_nfc(self):
        import unicodedata
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        text = out.decode("utf-8")
        self.assertEqual(text, unicodedata.normalize("NFC", text))


if __name__ == "__main__":
    unittest.main()
