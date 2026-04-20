"""CLAR-14 / D-24: retext omit:true → first non-empty replace[] as replacement + note."""
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestOmitHandling(unittest.TestCase):
    """CLAR-14 / D-24: retext omit:true → first non-empty replace[] as replacement + note.

    Uses a temp staging dir so FIXTURES stays pristine. Staging contains:
      tiny-retext.js, tiny-plainlang.md, tiny-sources.sha256 (copied from FIXTURES)
      empty-overrides.toml (fresh, zero bytes)
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="opengram-omit-"))
        for name in ("tiny-retext.js", "tiny-plainlang.md", "tiny-sources.sha256"):
            shutil.copy(FIXTURES / name, self.tmp / name)
        self.empty_overrides = self.tmp / "empty-overrides.toml"
        self.empty_overrides.write_bytes(b"")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_omit_entry_uses_first_replace(self):
        # `be advised` is omit:true in fixture. With empty overrides, entry survives and
        # carries the D-24 note + first non-empty replacement.
        import tomllib
        out = bwp.build(self.tmp, self.empty_overrides)
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertIn("be advised", by_id)
        self.assertEqual(by_id["be advised"]["replacement"], "please")
        self.assertEqual(by_id["be advised"].get("note"), "Upstream also supports deletion.")


if __name__ == "__main__":
    unittest.main()
