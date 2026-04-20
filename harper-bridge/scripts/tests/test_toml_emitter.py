"""CLAR-14: hand-rolled emitter produces tomllib-parseable output with D-12 field order."""
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import build_wordy_phrases as bwp  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


class TestTomlEmitter(unittest.TestCase):
    """CLAR-14: hand-rolled emitter produces tomllib-parseable output with D-12 field order."""

    def test_basic_escape_quote(self):
        self.assertEqual(bwp._escape_basic('hi "there"'), '"hi \\"there\\""')

    def test_basic_escape_backslash(self):
        self.assertEqual(bwp._escape_basic("a\\b"), '"a\\\\b"')

    def test_basic_escape_control(self):
        self.assertEqual(bwp._escape_basic("a\nb"), '"a\\nb"')

    def test_output_is_tomllib_parseable(self):
        import tomllib
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml")
        parsed = tomllib.loads(out.decode("utf-8"))
        self.assertIn("entries", parsed)

    def test_field_order_matches_d12(self):
        # Parse emitted text manually to check raw field order per entry block.
        out = bwp.build(FIXTURES, FIXTURES / "tiny-overrides.toml").decode()
        # Find first [[entries]] block.
        block = out.split("[[entries]]")[1].split("[[entries]]")[0]
        order = [l.split(" = ")[0].strip() for l in block.strip().splitlines() if " = " in l]
        expected_prefix = ["phrase", "replacement", "severity", "sources"]
        self.assertEqual(order[:4], expected_prefix, f"Field order violation: {order}")
        self.assertEqual(order[-1], "id", "id must be last field per D-12")


if __name__ == "__main__":
    unittest.main()
