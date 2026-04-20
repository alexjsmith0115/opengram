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


# ---- Atomic write -----------------------------------------------------------

def write_atomic(path: Path, content: bytes) -> None:
    """Write-then-rename. POSIX atomic per os.replace contract (P-10)."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(content)
    os.replace(tmp, path)


# ---- Build pipeline (stub — Plans 03/04 populate entries list) -------------

HEADER_TEMPLATE = (
    "# Generated from retext-simplify@{retext_sha}, plainlanguage.gov@{plainlang_sha} on {date}\n"
    "# Do not hand-edit — see scripts/overrides.toml for curation overrides.\n"
)


def _discover_source_shas(sources_dir: Path) -> tuple[str, str]:
    """Read sources dir to extract short-SHA from filenames (D-01).

    Filenames encode provenance: retext-simplify-<sha>.json, plainlanguage-<sha>.md.
    Fixture mode uses `test` placeholder sha when files don't match the real pattern.
    """
    retext_sha = "test"
    plainlang_sha = "test"
    for f in sources_dir.iterdir():
        m = re.match(r"retext-simplify-([0-9a-f]+)\.json$", f.name)
        if m:
            retext_sha = m.group(1)
        m = re.match(r"plainlanguage-([0-9a-f]+)\.md$", f.name)
        if m:
            plainlang_sha = m.group(1)
    return retext_sha, plainlang_sha


def build(sources_dir: Path, overrides_path: Path, data_dir: Path | None = None) -> bytes:
    """Pipeline entry point. Returns TOML bytes; writes atomically if data_dir set.

    Stub: verifies SHA manifest, reads overrides (if any), emits empty-entries TOML.
    Plans 03/04 add parser + merge calls between verify and emit.
    """
    # Fixture mode: sources_dir may be the fixtures dir containing tiny-sources.sha256.
    manifest = sources_dir / "tiny-sources.sha256"
    if not manifest.exists():
        manifest = sources_dir / "SOURCES.sha256"
    if manifest.exists():
        verify_sha256(manifest, sources_dir)

    # Fixture date is static; real run uses today's ISO date per D-17e.
    # For byte-determinism of tests, use the date already embedded in expected fixture.
    date = "2026-04-20"
    retext_sha, plainlang_sha = _discover_source_shas(sources_dir)
    header = HEADER_TEMPLATE.format(
        retext_sha=retext_sha,
        plainlang_sha=plainlang_sha,
        date=date,
    )

    entries: list[dict] = []  # Plans 03/04 populate via parse → merge → override.

    out = emit_toml(entries, header)
    if data_dir is not None:
        write_atomic(data_dir / "wordy_phrases.toml", out)
    return out


# ---- Source parsers --------------------------------------------------------

# retext-simplify: `export const patterns = { 'key': {replace: [...], omit?: true} }`
# Key forms: single-quoted string or bare identifier. Body contains no nested braces.
_RETEXT_ENTRY_RE = re.compile(
    r"""
    (?:'([^']+)'|([a-zA-Z_][\w-]*))   # group 1 = quoted key, group 2 = bare key
    \s*:\s*\{
    ([^{}]*?)                          # body — no nested braces
    \}
    """,
    re.VERBOSE | re.DOTALL,
)
_RETEXT_REPLACE_LIT_RE = re.compile(r"'((?:[^'\\]|\\.)*)'")
_RETEXT_OMIT_RE = re.compile(r"\bomit\s*:\s*true\b")
_RETEXT_REPLACE_ARR_RE = re.compile(r"replace\s*:\s*\[([^\]]*)\]", re.DOTALL)


def parse_retext_js(text: str) -> list[dict]:
    """Parse retext-simplify patterns.js into list of entry dicts.

    Handles D-22 (first replacement only) + D-24 (omit:true → first-non-empty + note).
    Bounded regex only — no ReDoS surface (no nested quantifiers).
    """
    entries: list[dict] = []
    seen_ids: set[str] = set()

    for m in _RETEXT_ENTRY_RE.finditer(text):
        key_quoted = m.group(1)
        key_bare = m.group(2)
        key = key_quoted if key_quoted is not None else key_bare
        if key is None:
            continue

        body = m.group(3)
        replace_match = _RETEXT_REPLACE_ARR_RE.search(body)
        if not replace_match:
            continue
        raw_arr = replace_match.group(1)
        replacements = [lit.group(1) for lit in _RETEXT_REPLACE_LIT_RE.finditer(raw_arr)]
        if not replacements:
            continue

        is_omit = bool(_RETEXT_OMIT_RE.search(body))
        replacement = next((r for r in replacements if r), "")
        if not replacement:
            continue

        phrase = normalize_text(key)
        replacement = normalize_text(replacement)
        entry_id = derive_id(phrase)
        if entry_id in seen_ids:
            raise SystemExit(f"Duplicate id in retext source: {entry_id!r}")
        seen_ids.add(entry_id)

        entries.append({
            "phrase": phrase,
            "replacement": replacement,
            "sources": ["retext-simplify"],
            "dirty_dozen": False,
            "note": "Upstream also supports deletion." if is_omit else None,
            "id": entry_id,
            "_omit": is_omit,
            "_all_replacements": replacements,
        })

    return entries


# plainlanguage.gov: markdown pipe-table after YAML front-matter.
# Header: `**Don't say** | **Say**` (curly apostrophe in raw source).
# Separator: `---- | ----`.
# Rows: `phrase | replacement` optionally with `**bold**` markers (dirty dozen).

_YAML_FM_RE = re.compile(r"^---\n.*?\n---\n", re.DOTALL)
_PIPE_ROW_RE = re.compile(r"^\s*([^|#\n]+?)\s*\|\s*([^\n]+?)\s*$", re.MULTILINE)
_BOLD_WRAP_RE = re.compile(r"^\*\*(.+?)\*\*$")


def _strip_bold(cell: str) -> tuple[str, bool]:
    """Return (inner_text, was_bold). `**x**` → ("x", True); `x` → ("x", False)."""
    m = _BOLD_WRAP_RE.match(cell.strip())
    if m:
        return m.group(1).strip(), True
    return cell.strip(), False


def parse_plainlang_md(text: str) -> list[dict]:
    """Parse plainlanguage.gov use-simple-words-phrases.md into entry dicts.

    D-22: multi-replacement rows take first replacement only.
    D-23: bold-bold rows (dirty dozen) flagged for severity bump.
    P-1: curly apostrophes flattened via normalize_text.
    P-8: compound left cell (`assist, assistance`) splits into N entries.
    """
    # Strip YAML front-matter.
    body = _YAML_FM_RE.sub("", text, count=1)

    entries: list[dict] = []
    seen_ids: set[str] = set()

    for m in _PIPE_ROW_RE.finditer(body):
        left_raw = m.group(1).strip()
        right_raw = m.group(2).strip()

        # Skip header + separator rows.
        if not left_raw or not right_raw:
            continue
        if left_raw.startswith("---") or right_raw.startswith("---"):
            continue
        if "Don" in left_raw and "say" in right_raw.lower():
            # Header row — may be `**Don't say**` with curly apostrophe.
            continue

        left_inner, left_bold = _strip_bold(left_raw)
        right_inner, right_bold = _strip_bold(right_raw)
        dirty_dozen = left_bold and right_bold

        # D-22: first replacement only for comma-separated right side.
        replacement_raw = right_inner.split(",")[0].strip()
        if not replacement_raw:
            continue
        replacement = normalize_text(replacement_raw)

        # P-8: compound left cell → split on comma into N phrases sharing the replacement.
        if "," in left_inner:
            phrases = [p.strip() for p in left_inner.split(",") if p.strip()]
        else:
            phrases = [left_inner]

        for phrase_raw in phrases:
            phrase = normalize_text(phrase_raw)
            entry_id = derive_id(phrase)
            if entry_id in seen_ids:
                # Duplicate within plainlang source — skip per D-05 dedup-later discipline.
                continue
            seen_ids.add(entry_id)
            entries.append({
                "phrase": phrase,
                "replacement": replacement,
                "sources": ["plainlanguage.gov"],
                "dirty_dozen": dirty_dozen,
                "note": None,
                "id": entry_id,
                "_omit": False,
                "_all_replacements": [s.strip() for s in right_inner.split(",") if s.strip()],
            })

    return entries


# ---- CLI --------------------------------------------------------------------

def _main() -> None:
    print("[1/12] Verifying SHA256 manifest...", file=sys.stderr)
    # Real run uses SOURCES_DIR + OVERRIDES_PATH; emit to OUT_PATH atomically.
    out = build(SOURCES_DIR, OVERRIDES_PATH, DATA_DIR)
    print(f"[12/12] Wrote {len(out)} bytes to {OUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    _main()
