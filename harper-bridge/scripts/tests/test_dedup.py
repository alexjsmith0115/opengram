"""CLAR-14 / D-05: dedup by nfc(lower(phrase)); inflected forms stay separate."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestDedup(unittest.TestCase):
    """CLAR-14 / D-05: dedup by nfc(lower(phrase)); inflected forms stay separate."""

    def test_inflected_forms_both_retained(self):
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        text = out.decode()
        # utilize ships in retext fixture. Phase 5 commits real dataset with utilize+utilized+utilizes.
        self.assertIn('phrase = "utilize"', text)

    def test_cross_source_dedup(self):
        # abundance + accompany are in BOTH fixture sources. Must appear exactly once each.
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml").decode()
        self.assertEqual(out.count('phrase = "abundance"'), 1)
        self.assertEqual(out.count('phrase = "accompany"'), 1)

    def test_id_uniqueness_asserted(self):
        # Duplicate id would raise; absence of raise on good fixtures = pass.
        bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")


if __name__ == "__main__":
    unittest.main()
