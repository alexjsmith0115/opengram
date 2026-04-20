---
phase: 08-dataset-pipeline
plan: "01"
subsystem: dataset-pipeline
tags: [python, dataset, testing, fixtures, tdd]
dependency_graph:
  requires: []
  provides:
    - harper-bridge/scripts/tests/ (unittest package with 10 RED-state test modules)
    - harper-bridge/scripts/tests/fixtures/ (8 synthetic fixture files)
  affects: []
tech_stack:
  added: []
  patterns:
    - Python stdlib unittest discover under harper-bridge/scripts/tests/
    - Tempdir staging for fixture isolation (W6 pattern, test_omit_handling.py)
    - SHA256 manifest format — two-space separator, shasum-compatible
key_files:
  created:
    - harper-bridge/scripts/tests/__init__.py
    - harper-bridge/scripts/tests/fixtures/__init__.py
    - harper-bridge/scripts/tests/fixtures/tiny-retext.js
    - harper-bridge/scripts/tests/fixtures/tiny-plainlang.md
    - harper-bridge/scripts/tests/fixtures/tiny-overrides.toml
    - harper-bridge/scripts/tests/fixtures/tiny-sources.sha256
    - harper-bridge/scripts/tests/fixtures/tiny-sources.bad.sha256
    - harper-bridge/scripts/tests/fixtures/expected_wordy_phrases.toml
    - harper-bridge/scripts/tests/test_nfc.py
    - harper-bridge/scripts/tests/test_toml_emitter.py
    - harper-bridge/scripts/tests/test_sha256.py
    - harper-bridge/scripts/tests/test_dedup.py
    - harper-bridge/scripts/tests/test_severity.py
    - harper-bridge/scripts/tests/test_overrides.py
    - harper-bridge/scripts/tests/test_omit_handling.py
    - harper-bridge/scripts/tests/test_byte_determinism.py
    - harper-bridge/scripts/tests/test_typography.py
    - harper-bridge/scripts/tests/test_schema.py
  modified:
    - .gitignore (added __pycache__/ + *.pyc)
decisions:
  - "Curly apostrophes (U+2019) added to tiny-plainlang.md fixture to exercise P-1 typography flatten — plain ASCII would not trigger the test_typography path"
  - "expected_wordy_phrases.toml golden uses straight apostrophe in don't (post-normalize) as required by D-13 id derivation"
  - "be advised dropped in golden because tiny-overrides.toml carries drop=true for it per D-10"
metrics:
  duration: "~4 min"
  completed: "2026-04-20T15:56:40Z"
  tasks_completed: 2
  files_created: 20
---

# Phase 08 Plan 01: TDD Scaffold — Test Fixtures + RED-State Unittest Tree Summary

Wave 0 TDD scaffold: 8 synthetic fixtures + 10 RED-state unittest modules covering byte-determinism, NFC, severity, override, omit, SHA invariants for the dataset pipeline build script.

## Fixture Files Created

| File | Size | Edge Cases Covered |
|------|------|--------------------|
| tiny-retext.js | 282 B | omit:true (D-24), multi-replace (D-22), bare identifier key, quoted-string key |
| tiny-plainlang.md | 272 B | dirty-dozen bold (D-23), compound split (P-8), curly apostrophe U+2019 (P-1) |
| tiny-overrides.toml | 254 B | all five D-10 ops: drop, severity, replacement, dialects, note |
| tiny-sources.sha256 | 165 B | correct SHA256 manifest (computed via shasum -a 256) |
| tiny-sources.bad.sha256 | 165 B | zero-hash manifest for SHA mismatch negative test (D-02) |
| expected_wordy_phrases.toml | 1221 B | golden output: 8 entries, be-advised dropped, don't straightened, 4 high severity |

SHA manifest verified: `shasum -a 256 -c tiny-sources.sha256` exits 0.
Golden TOML parses: `python3 -c "import tomllib; tomllib.load(...)"` exits 0.

## Test Modules Created

| File | Requirement | Behaviors Tested |
|------|-------------|-----------------|
| test_nfc.py | CLAR-N4 | normalize_text idempotency, derive_id lowercase+NFC, output bytes NFC |
| test_toml_emitter.py | CLAR-14 | _escape_basic (quote/backslash/control), tomllib round-trip, D-12 field order |
| test_sha256.py | CLAR-14 / D-02 | good manifest passes, bad manifest SystemExit with "SHA256 mismatch"/"expected"/"got" |
| test_dedup.py | CLAR-14 / D-05 | inflected forms retained, cross-source dedup, id uniqueness assertion |
| test_severity.py | CLAR-14 / D-07, D-23 | both-sources→high, single-source→medium, dirty-dozen single-source→high |
| test_overrides.py | CLAR-14 / D-09, D-10 | drop, severity upgrade, replacement override, dialects, note |
| test_omit_handling.py | CLAR-14 / D-24 | omit:true→first replacement + "Upstream also supports deletion." note; tempdir staging |
| test_byte_determinism.py | CLAR-14 SC-1 | two runs identical bytes, matches golden fixture byte-for-byte |
| test_typography.py | CLAR-N4 / P-1 | curly apostrophe/double/em-dash/nbsp flattened; output has no curly chars |
| test_schema.py | CLAR-14 / D-12, D-15 | required fields present, dialects omitted when universal, note omitted when empty |

## RED-State Confirmation

```
python3 -m unittest discover harper-bridge/scripts/tests -v
FAILED (errors=10)
ImportError count: 10
```

All 10 test modules fail with `ModuleNotFoundError: No module named 'build_wordy_phrases'`. Intended pre-implementation posture — Plan 02 creates the module.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing coverage] Added curly apostrophes to tiny-plainlang.md**
- **Found during:** Task 1 — plan spec says "row 3 uses curly apostrophe U+2019" but exact content block showed straight apostrophe
- **Fix:** Wrote file via Python with explicit `\u2019` in `don't`, `Don't say` header, and `you're` body text
- **Files modified:** harper-bridge/scripts/tests/fixtures/tiny-plainlang.md, tiny-sources.sha256 (rehashed after content change)
- **Effect:** test_typography.py `test_output_has_no_curly` now has real curly-quote input to flatten; SHA manifest recomputed post-change

**2. [Rule 2 - Missing gitignore] Added __pycache__ to .gitignore**
- **Found during:** Task 2 post-commit check — unittest discover produced __pycache__ dirs left untracked
- **Fix:** Added `__pycache__/` and `*.pyc` to .gitignore
- **Files modified:** .gitignore

## Hand-off: Plan 02

Plan 02 must create `harper-bridge/scripts/build_wordy_phrases.py` with the following public API (contracts locked):

```python
def normalize_text(s: str) -> str          # NFC + typography map (P-1)
def derive_id(phrase: str) -> str          # nfc(lowercase(phrase))
def verify_sha256(manifest_path, sources_dir) -> None  # raises SystemExit("...SHA256 mismatch: expected <e>, got <g>")
def parse_retext_js(text: str) -> list[dict]
def parse_plainlang_md(text: str) -> list[dict]
def merge_and_dedup(entries) -> list[dict]
def tag_severity(entries) -> list[dict]
def flag_judgment_calls(entries) -> list[dict]
def apply_overrides(entries, overrides) -> list[dict]
def emit_toml(entries, header) -> bytes
def _escape_basic(s: str) -> str
def build(sources_dir, overrides_path, data_dir=None) -> bytes
```

The golden fixture `expected_wordy_phrases.toml` (8 entries) is the byte-for-byte contract `test_byte_determinism.test_matches_golden` validates against.

## Self-Check: PASSED

- harper-bridge/scripts/tests/__init__.py: FOUND
- harper-bridge/scripts/tests/test_nfc.py: FOUND
- harper-bridge/scripts/tests/fixtures/expected_wordy_phrases.toml: FOUND
- Commit bbfafeb (fixtures): FOUND
- Commit 5b0d8f3 (test modules): FOUND
