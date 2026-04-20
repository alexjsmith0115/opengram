"""CLAR-14 / D-09, D-10: overrides layer AFTER severity, support drop/severity/replacement/dialects/note."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestOverrides(unittest.TestCase):
    """CLAR-14 / D-09, D-10: overrides layer AFTER severity, support drop/severity/replacement/dialects/note."""

    def test_drop_removes_entry(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        ids = {e["id"] for e in parsed["entries"]}
        self.assertNotIn("be advised", ids)

    def test_severity_override(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        # "a number of" is retext-only → would be medium; override lifts to high.
        self.assertEqual(by_id["a number of"]["severity"], "high")

    def test_replacement_override(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["accompany"]["replacement"], "with")

    def test_dialects_override(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["utilize"].get("dialects"), ["en-US"])

    def test_note_override_from_overrides_file(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["a number of"].get("note"), "Test override: severity upgrade.")


if __name__ == "__main__":
    unittest.main()
