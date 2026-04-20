"""CLAR-14 / D-07, D-23: severity derived from cross-source confirmation + dirty-dozen."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestSeverity(unittest.TestCase):
    """CLAR-14 / D-07, D-23: severity derived from cross-source confirmation + dirty-dozen."""

    def test_both_sources_high(self):
        # abundance + accompany both in retext + plainlang.
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["abundance"]["severity"], "high")
        self.assertEqual(by_id["accompany"]["severity"], "high")

    def test_single_source_medium(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        # utilize only in retext fixture → medium (override does NOT change severity).
        self.assertEqual(by_id["utilize"]["severity"], "medium")

    def test_dirty_dozen_single_source_high(self):
        """D-23: plainlang bold → high even single-source."""
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["addressees"]["severity"], "high")
        self.assertEqual(by_id["addressees"]["sources"], ["plainlanguage.gov"])


if __name__ == "__main__":
    unittest.main()
