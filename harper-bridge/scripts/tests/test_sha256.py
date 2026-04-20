"""CLAR-14 / D-02: SHA256 manifest mismatch raises SystemExit with exact message."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestShaVerification(unittest.TestCase):
    """CLAR-14 / D-02: SHA256 manifest mismatch → SystemExit with exact message."""

    def test_good_manifest_passes(self):
        bwp.verify_sha256(FIXTURES / "tiny-sources.sha256", FIXTURES)  # no raise

    def test_bad_manifest_raises(self):
        with self.assertRaises(SystemExit) as cm:
            bwp.verify_sha256(FIXTURES / "tiny-sources.bad.sha256", FIXTURES)
        self.assertIn("SHA256 mismatch", str(cm.exception))
        self.assertIn("expected", str(cm.exception))
        self.assertIn("got", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
