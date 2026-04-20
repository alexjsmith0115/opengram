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
        m = re.match(r"retext-simplify-([0-9a-f]+)\.(js|json)$", f.name)
        if m:
            retext_sha = m.group(1)
        m = re.match(r"plainlanguage-([0-9a-f]+)\.md$", f.name)
        if m:
            plainlang_sha = m.group(1)
    return retext_sha, plainlang_sha


def build(sources_dir: Path, overrides_path: Path, data_dir: Path | None = None) -> bytes:
    """Full pipeline: verify → parse → merge → tag → flag → apply → sort → emit → write."""
    # 1. Verify SHA256 manifest (fixture fallback for tests).
    manifest = sources_dir / "tiny-sources.sha256"
    if not manifest.exists():
        manifest = sources_dir / "SOURCES.sha256"
    if manifest.exists():
        verify_sha256(manifest, sources_dir)

    # 2. Parse sources.
    retext_file = None
    plainlang_file = None
    for f in sources_dir.iterdir():
        if f.suffix == ".js" and (f.name.startswith("retext-simplify-") or f.name.startswith("tiny-retext")):
            retext_file = f
        elif f.suffix == ".md" and (f.name.startswith("plainlanguage-") or f.name.startswith("tiny-plainlang")):
            plainlang_file = f

    retext_entries = parse_retext_js(retext_file.read_text(encoding="utf-8")) if retext_file else []
    plainlang_entries = parse_plainlang_md(plainlang_file.read_text(encoding="utf-8")) if plainlang_file else []

    # 3. Merge + dedup (retext first so first-seen identity is retext when present).
    merged = merge_and_dedup(retext_entries + plainlang_entries)

    # 4. Tag severity.
    tagged = tag_severity(merged)

    # 5. Flag judgment calls (rules 2 + 3 only per D-21).
    flagged = flag_judgment_calls(tagged)

    # 6. Load + apply overrides (W5: clears _judgment_reason on any override op).
    overrides = load_overrides(overrides_path)
    after_override = apply_overrides(flagged, overrides)

    # 7. Sort by id (codepoint stable per D-17).
    after_override.sort(key=lambda e: e["id"])

    # 8. Strip internal keys; keep _judgment_reason for emitter; drop dirty_dozen + _omit + _all_replacements.
    cleaned: list[dict] = []
    for e in after_override:
        c = {}
        for k, v in e.items():
            if k in ("_omit", "_all_replacements", "dirty_dozen"):
                continue
            if v is None:
                continue
            if k in ("dialects", "note") and (v == [] or v == ""):
                continue
            c[k] = v
        cleaned.append(c)

    # 9. Emit with judgment comments + header.
    date = "2026-04-20"
    retext_sha, plainlang_sha = _discover_source_shas(sources_dir)
    header = HEADER_TEMPLATE.format(retext_sha=retext_sha, plainlang_sha=plainlang_sha, date=date)
    out = emit_toml_with_judgment(cleaned, header)

    # 10. Atomic write if data_dir provided.
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


# ---- Merge + dedup ---------------------------------------------------------

def merge_and_dedup(entries: list[dict]) -> list[dict]:
    """Dedup by `id`; union `sources`; retext wins replacement conflicts (D-06).

    Order-independent retext-wins rule: identify which side is retext from the
    pre-mutation single-source `sources` arrays on `existing` and `e`. The
    conflict branch runs FIRST, using those untouched arrays; only then is
    `existing["sources"]` overwritten to the union.

    Stderr emits `[CONFLICT] <phrase>: retext=<x>, plainlanguage=<y> — using retext`
    per D-08. Dirty-dozen flag preserved (any True → True).
    """
    by_id: dict[str, dict] = {}
    for e in entries:
        eid = e["id"]
        if eid not in by_id:
            by_id[eid] = dict(e)  # shallow copy — first-seen wins identity
            continue

        existing = by_id[eid]

        # W3 fix: membership determined from PRE-union sources arrays.
        # Parsers emit single-source entries, so exactly one of these is True
        # per side (or False if source label is unexpected).
        existing_is_retext = "retext-simplify" in existing["sources"]
        incoming_is_retext = "retext-simplify" in e["sources"]

        # Conflict resolution — retext's replacement wins (D-06).
        if existing["replacement"] != e["replacement"]:
            if existing_is_retext and not incoming_is_retext:
                retext_repl = existing["replacement"]
                plainlang_repl = e["replacement"]
            elif incoming_is_retext and not existing_is_retext:
                retext_repl = e["replacement"]
                plainlang_repl = existing["replacement"]
            else:
                # Same-source duplicates are rejected by parsers. Guard only.
                retext_repl = existing["replacement"]
                plainlang_repl = e["replacement"]
            print(
                f"[CONFLICT] {existing['phrase']}: retext={retext_repl}, plainlanguage={plainlang_repl} — using retext",
                file=sys.stderr,
            )
            existing["replacement"] = retext_repl

        # AFTER conflict resolution, union the sources arrays in canonical order.
        merged_sources: list[str] = []
        for src in ("retext-simplify", "plainlanguage.gov"):
            if src in existing["sources"] or src in e["sources"]:
                merged_sources.append(src)
        existing["sources"] = merged_sources

        # Preserve dirty_dozen=True if either side flags.
        existing["dirty_dozen"] = existing.get("dirty_dozen", False) or e.get("dirty_dozen", False)

        # Preserve note from whichever side had one (retext omit note or override-planted).
        if not existing.get("note") and e.get("note"):
            existing["note"] = e["note"]

    return list(by_id.values())


# ---- Severity tagging ------------------------------------------------------

def tag_severity(entries: list[dict]) -> list[dict]:
    """Apply D-07 + D-23 severity rules.

    both-sources → high; single-source + dirty_dozen → high; single-source → medium.
    Judgment-flagged entries get severity="low" in flag_judgment_calls (runs after this).
    """
    for e in entries:
        if len(e["sources"]) >= 2:
            e["severity"] = "high"
        elif e.get("dirty_dozen"):
            e["severity"] = "high"
        else:
            e["severity"] = "medium"
    return entries


# ---- Judgment-call flagging (D-11 rules 2 + 3; rule 1 deleted per D-21) ----

_ADVERB_INTENSIFIERS = {"very", "really", "just", "quite", "rather", "simply", "basically"}


def flag_judgment_calls(entries: list[dict]) -> list[dict]:
    """Flag entries per D-11 rules 2 + 3 (D-21: rule 1 deleted — retext has no note/condition).

    Rule 2: replacement shorter than phrase by >3 tokens → flag.
    Rule 3: phrase is only adverb/intensifier tokens → flag.
    Flagged entries: severity downgraded to "low"; `_judgment_reason` attached for emitter.
    """
    for e in entries:
        phrase_tokens = e["phrase"].split()
        replacement_tokens = e["replacement"].split()

        # Rule 2: replacement >3 tokens shorter than phrase.
        if len(phrase_tokens) - len(replacement_tokens) > 3:
            e["_judgment_reason"] = f"replacement >3 tokens shorter than phrase (phrase={len(phrase_tokens)}, replacement={len(replacement_tokens)})"
            e["severity"] = "low"
            continue

        # Rule 3: phrase is adverb/intensifier-only.
        if all(tok in _ADVERB_INTENSIFIERS for tok in phrase_tokens) and phrase_tokens:
            e["_judgment_reason"] = "phrase is adverb/intensifier only"
            e["severity"] = "low"
            continue

    return entries


# ---- Overrides -------------------------------------------------------------

_VALID_OVERRIDE_KEYS = {"drop", "severity", "replacement", "dialects", "note", "add", "phrase", "sources"}


def load_overrides(path: Path) -> dict:
    """Parse overrides.toml via tomllib (read-only, stdlib 3.11+). Missing/empty → {}.

    Shape: `[overrides."<id>"]` tables containing any of D-10 ops.
    Rejects unknown keys per V5 input validation.
    """
    if not path.exists() or not path.read_bytes().strip():
        return {}
    with path.open("rb") as f:
        data = tomllib.load(f)
    overrides = data.get("overrides", {})
    for eid, ops in overrides.items():
        unknown = set(ops.keys()) - _VALID_OVERRIDE_KEYS
        if unknown:
            raise SystemExit(f"Unknown override keys for id={eid!r}: {sorted(unknown)}")
        if ops.get("add") is True:
            # Add-op requires phrase + replacement + sources (non-empty).
            for req in ("phrase", "replacement", "sources"):
                if req not in ops:
                    raise SystemExit(f"Add-op override id={eid!r} missing required key: {req!r}")
            if not isinstance(ops["sources"], list) or not ops["sources"]:
                raise SystemExit(f"Add-op override id={eid!r}: sources must be non-empty list")
            # phrase must derive to the keyed id (prevents key/phrase drift).
            derived = derive_id(normalize_text(ops["phrase"]))
            if derived != eid:
                raise SystemExit(
                    f"Add-op override id={eid!r}: derived id from phrase ({derived!r}) does not match key"
                )
        else:
            # Mutate-op rows must NOT carry `phrase`/`sources`.
            for forbidden in ("phrase", "sources"):
                if forbidden in ops:
                    raise SystemExit(
                        f"Override id={eid!r}: {forbidden!r} only allowed on add-op rows (add = true)"
                    )
    return overrides


def apply_overrides(entries: list[dict], overrides: dict) -> list[dict]:
    """D-09: apply AFTER severity tagging, BEFORE emit. D-10 ops + `add` op.

    Mutate/drop: existing ops (drop, severity, replacement, dialects, note).
    Add: synthesizes new PhraseEntry from override row; severity defaults to "medium"
    per D-07 single-source default (manual entries are single-source by definition);
    dialects/note optional; id derived per D-13.
    W5: ANY mutate op clears `_judgment_reason`.
    Post-apply id-uniqueness re-check (P-6 collision guard — catches add colliding with existing).
    """
    out: list[dict] = []
    add_rows: list[tuple[str, dict]] = []
    for eid, ops in overrides.items():
        if ops.get("add") is True:
            add_rows.append((eid, ops))

    for e in entries:
        ov = overrides.get(e["id"])
        if ov and ov.get("add") is not True:
            if ov.get("drop") is True:
                continue
            for k in ("severity", "replacement", "dialects", "note"):
                if k in ov:
                    e[k] = normalize_text(ov[k]) if isinstance(ov[k], str) else ov[k]
            # W5: curator override supersedes automated judgment flag.
            if "_judgment_reason" in e:
                del e["_judgment_reason"]
        out.append(e)

    # Synthesize add-op entries (D-05 inflected-form-as-own-entry path).
    for eid, ops in add_rows:
        phrase = normalize_text(ops["phrase"])
        replacement = normalize_text(ops["replacement"])
        new_entry: dict = {
            "phrase": phrase,
            "replacement": replacement,
            "severity": ops.get("severity", "medium"),  # D-07 default: single-source = medium
            "sources": list(ops["sources"]),
            "id": derive_id(phrase),
        }
        if "dialects" in ops:
            new_entry["dialects"] = list(ops["dialects"])
        if "note" in ops:
            new_entry["note"] = normalize_text(ops["note"])
        out.append(new_entry)

    # P-6: id uniqueness (catches add colliding with sourced entry).
    seen: set[str] = set()
    for e in out:
        if e["id"] in seen:
            raise SystemExit(f"Duplicate id after override apply: {e['id']!r}")
        seen.add(e["id"])
    return out


# ---- Emit with judgment comments ------------------------------------------

def _emit_entry_with_judgment(e: dict) -> str:
    """Emit [[entries]] block, prefixed with `# JUDGMENT: <reason>` when flagged."""
    prefix = ""
    if e.get("_judgment_reason"):
        prefix = f"# JUDGMENT: {e['_judgment_reason']}\n"
    return prefix + _emit_entry(e)


def emit_toml_with_judgment(entries: list[dict], header: str) -> bytes:
    body = "\n\n".join(_emit_entry_with_judgment(e) for e in entries)
    doc = header + ("\n" + body + "\n" if entries else "")
    return doc.encode("utf-8")


# ---- CLI --------------------------------------------------------------------

def _main() -> None:
    print("[1/12] Verifying SHA256 manifest...", file=sys.stderr)
    # Real run uses SOURCES_DIR + OVERRIDES_PATH; emit to OUT_PATH atomically.
    out = build(SOURCES_DIR, OVERRIDES_PATH, DATA_DIR)
    print(f"[12/12] Wrote {len(out)} bytes to {OUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    _main()
