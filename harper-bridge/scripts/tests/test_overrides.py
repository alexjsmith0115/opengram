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


class TestAddOp(unittest.TestCase):
    """Tests for the `add` override op (CLAR-04 inflection contract, D-05)."""

    def test_add_op_creates_new_entry_with_defaults(self):
        import tomllib
        tmp = FIXTURES / "tmp-add-overrides.toml"
        tmp.write_text(
            '[overrides."utilizes"]\n'
            'add = true\n'
            'phrase = "utilizes"\n'
            'replacement = "use"\n'
            'sources = ["manual"]\n'
        )
        try:
            out = bwp.build(FIXTURES, tmp)
            parsed = tomllib.loads(out.decode())
            by_id = {e["id"]: e for e in parsed["entries"]}
            self.assertIn("utilizes", by_id)
            self.assertEqual(by_id["utilizes"]["replacement"], "use")
            self.assertEqual(by_id["utilizes"]["severity"], "medium")
            self.assertEqual(by_id["utilizes"]["sources"], ["manual"])
        finally:
            tmp.unlink(missing_ok=True)

    def test_add_op_explicit_severity_honored(self):
        import tomllib
        tmp = FIXTURES / "tmp-add-sev.toml"
        tmp.write_text(
            '[overrides."utilized"]\n'
            'add = true\n'
            'phrase = "utilized"\n'
            'replacement = "used"\n'
            'severity = "high"\n'
            'sources = ["manual"]\n'
        )
        try:
            out = bwp.build(FIXTURES, tmp)
            parsed = tomllib.loads(out.decode())
            by_id = {e["id"]: e for e in parsed["entries"]}
            self.assertEqual(by_id["utilized"]["severity"], "high")
        finally:
            tmp.unlink(missing_ok=True)

    def test_add_op_id_collision_with_existing_raises(self):
        # "utilize" exists in tiny-retext fixture.
        tmp = FIXTURES / "tmp-add-collision.toml"
        tmp.write_text(
            '[overrides."utilize"]\n'
            'add = true\n'
            'phrase = "utilize"\n'
            'replacement = "other"\n'
            'sources = ["manual"]\n'
        )
        try:
            with self.assertRaises(SystemExit):
                bwp.build(FIXTURES, tmp)
        finally:
            tmp.unlink(missing_ok=True)

    def test_add_op_missing_required_key_raises(self):
        tmp = FIXTURES / "tmp-add-missing.toml"
        tmp.write_text(
            '[overrides."foo"]\n'
            'add = true\n'
            'phrase = "foo"\n'
            # missing replacement + sources
        )
        try:
            with self.assertRaises(SystemExit):
                bwp.build(FIXTURES, tmp)
        finally:
            tmp.unlink(missing_ok=True)

    def test_add_op_phrase_must_match_key(self):
        tmp = FIXTURES / "tmp-add-key-drift.toml"
        tmp.write_text(
            '[overrides."mismatch"]\n'
            'add = true\n'
            'phrase = "different phrase"\n'
            'replacement = "x"\n'
            'sources = ["manual"]\n'
        )
        try:
            with self.assertRaises(SystemExit):
                bwp.build(FIXTURES, tmp)
        finally:
            tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
