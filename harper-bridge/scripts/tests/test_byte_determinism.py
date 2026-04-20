"""CLAR-14 SC-1: same inputs → identical output bytes across repeated runs."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestByteDeterminism(unittest.TestCase):
    """CLAR-14 SC-1: same inputs → identical output bytes across repeated runs."""

    def test_two_runs_same_bytes(self):
        out1 = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        out2 = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        self.assertEqual(out1, out2, "byte-determinism violated (CLAR-14 / D-17)")

    def test_matches_golden(self):
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        golden = (FIXTURES / "expected_wordy_phrases.toml").read_bytes()
        # Compare byte-for-byte; mismatch shows full diff.
        self.assertEqual(out, golden, "output drifted from golden fixture")


if __name__ == "__main__":
    unittest.main()
