#!/usr/bin/env python3
"""Generate harper-bridge/data/wordy_phrases.toml from vendored sources.

Invoke manually. Reads harper-bridge/scripts/sources/ (vendored retext-simplify
JSON + plainlanguage.gov markdown + SOURCES.sha256) and
harper-bridge/scripts/overrides.toml, writes harper-bridge/data/wordy_phrases.toml.

Python stdlib only — no pip, no venv, no requirements.txt.

Refresh workflow (manual, per D-03):
  1. Fetch new upstream file with curl/wget into sources/<new-sha>.{json,md}
  2. Update SOURCES.sha256 via `shasum -a 256 sources/<new-sha>.*`
  3. Re-run this script
  4. Commit sources/ + SOURCES.sha256 + regenerated data/wordy_phrases.toml
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
import tomllib
import unicodedata
from pathlib import Path

if sys.version_info < (3, 11):
    raise SystemExit("Python 3.11+ required (tomllib dependency)")

# ---- Paths ------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
CRATE_DIR = SCRIPT_DIR.parent
REPO_ROOT = CRATE_DIR.parent
SOURCES_DIR = SCRIPT_DIR / "sources"
DATA_DIR = CRATE_DIR / "data"
OUT_PATH = DATA_DIR / "wordy_phrases.toml"
MANIFEST_PATH = SOURCES_DIR / "SOURCES.sha256"
OVERRIDES_PATH = SCRIPT_DIR / "overrides.toml"

# ---- Normalization ----------------------------------------------------------

# P-1: NFC does not flatten curly quotes. Explicit typography pass after NFC.
SMART_QUOTE_MAP = str.maketrans({
    "\u2018": "'",   # LEFT SINGLE QUOTATION MARK
    "\u2019": "'",   # RIGHT SINGLE QUOTATION MARK
    "\u201C": '"',   # LEFT DOUBLE QUOTATION MARK
    "\u201D": '"',   # RIGHT DOUBLE QUOTATION MARK
    "\u2013": "-",   # EN DASH
    "\u2014": "--",  # EM DASH
    "\u00A0": " ",   # NO-BREAK SPACE
})


def normalize_text(s: str) -> str:
    """NFC-normalize then flatten typographic punctuation to ASCII (P-1 / CLAR-N4)."""
    return unicodedata.normalize("NFC", s).translate(SMART_QUOTE_MAP)


def derive_id(phrase: str) -> str:
    """id = nfc(lowercase(phrase)) per D-13."""
    return unicodedata.normalize("NFC", phrase.lower())


# ---- SHA256 manifest verification ------------------------------------------

def verify_sha256(manifest_path: Path, sources_dir: Path) -> None:
    """Verify every filename in sha256sum-format manifest against on-disk bytes.

    Manifest format per D-02 / Pitfall P-7: `<64-hex>  <filename>\\n`, two-space
    separator, no asterisk binary-mode marker. Compatible with `shasum -a 256 -c`
    and GNU `sha256sum -c`.

    Raises SystemExit on mismatch with exact message per D-02.
    """
    text = manifest_path.read_text(encoding="utf-8")
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2:
            raise SystemExit(f"Malformed manifest line: {line!r}")
        expected, filename = parts
        # Path-traversal guard (V4 / V12): reject absolute paths, `..`, null bytes.
        if "/" in filename or ".." in filename or "\x00" in filename:
            raise SystemExit(f"Unsafe filename in manifest: {filename!r}")
        source_path = (sources_dir / filename).resolve()
        if not source_path.is_relative_to(sources_dir.resolve()):
            raise SystemExit(f"Path traversal blocked: {filename!r}")
        actual = hashlib.sha256(source_path.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(
                f"Source file {filename} SHA256 mismatch: expected {expected}, got {actual}"
            )


# ---- TOML emitter primitives (hand-rolled per D-16 / CLAR-14 — stdlib-only) -

_BASIC_ESCAPES = {
    ord('"'):  '\\"',
    ord('\\'): '\\\\',
    ord('\b'): '\\b',
    ord('\t'): '\\t',
    ord('\n'): '\\n',
    ord('\f'): '\\f',
    ord('\r'): '\\r',
}


def _escape_basic(s: str) -> str:
    """Escape a string for a TOML basic (double-quoted) string per TOML v1.0.0.

    Printable Unicode above U+007F is emitted raw (basic strings accept it).
    Control chars (U+0000..U+001F, U+007F) not in _BASIC_ESCAPES emit as \\uXXXX.
    """
    out: list[str] = []
    for ch in s:
        cp = ord(ch)
        if cp in _BASIC_ESCAPES:
            out.append(_BASIC_ESCAPES[cp])
        elif cp < 0x20 or cp == 0x7F:
            out.append(f"\\u{cp:04X}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _emit_array(values: list[str]) -> str:
    return "[" + ", ".join(_escape_basic(v) for v in values) + "]"


def _emit_entry(e: dict) -> str:
    """Emit one [[entries]] block with D-12 field order: phrase, replacement,
    severity, sources, dialects?, note?, id. Optional fields omitted when empty.
    """
    # Assert NFC at emit boundary (CLAR-N4 invariant enforcement per D-17c).
    for field in ("phrase", "replacement", "id"):
        v = e[field]
        assert unicodedata.is_normalized("NFC", v), f"non-NFC {field}: {v!r}"
    lines = ["[[entries]]"]
    lines.append(f"phrase = {_escape_basic(e['phrase'])}")
    lines.append(f"replacement = {_escape_basic(e['replacement'])}")
    lines.append(f'severity = "{e["severity"]}"')
    lines.append(f"sources = {_emit_array(e['sources'])}")
    if e.get("dialects"):
        lines.append(f"dialects = {_emit_array(e['dialects'])}")
    if e.get("note"):
        lines.append(f"note = {_escape_basic(e['note'])}")
    lines.append(f"id = {_escape_basic(e['id'])}")
    return "\n".join(lines)


def emit_toml(entries: list[dict], header: str) -> bytes:
    """Emit full TOML document. `header` must already contain trailing newline.

    Byte-determinism invariants (D-17):
      - Entries sorted by `id` (codepoint sort) before call; we do not re-sort here.
      - Stable field order per _emit_entry.
      - Exactly one blank line between entries.
      - Trailing newline at EOF.
      - Explicit \\n (never CRLF). Output encoded utf-8.
    """
    body = "\n\n".join(_emit_entry(e) for e in entries)
    doc = header + ("\n" + body + "\n" if entries else "")
    return doc.encode("utf-8")
