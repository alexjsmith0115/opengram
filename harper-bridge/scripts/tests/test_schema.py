"""CLAR-14 / D-12, D-15: every entry has required fields; optional fields omitted when empty."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestSchema(unittest.TestCase):
    """CLAR-14 / D-12, D-15: every entry has required fields; optional fields omitted when empty."""

    def test_required_fields_present(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        for e in parsed["entries"]:
            for key in ("phrase", "replacement", "severity", "sources", "id"):
                self.assertIn(key, e, f"missing {key} in {e}")
            self.assertIsInstance(e["sources"], list)
            self.assertGreater(len(e["sources"]), 0)

    def test_dialects_omitted_when_universal(self):
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml").decode()
        # abundance has no dialects override → dialects key must not appear in its block.
        abundance_block = out.split('phrase = "abundance"')[1].split("[[entries]]")[0]
        self.assertNotIn("dialects", abundance_block)

    def test_note_omitted_when_empty(self):
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml").decode()
        abundance_block = out.split('phrase = "abundance"')[1].split("[[entries]]")[0]
        self.assertNotIn("note", abundance_block)


if __name__ == "__main__":
    unittest.main()
