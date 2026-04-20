---
phase: 08-dataset-pipeline
plan: "02"
subsystem: dataset-pipeline
tags: [python, dataset, infrastructure, toml-emitter, nfc]
dependency_graph:
  requires:
    - harper-bridge/scripts/tests/ (Plan 01 RED-state test tree)
    - harper-bridge/scripts/tests/fixtures/ (Plan 01 fixtures)
  provides:
    - harper-bridge/scripts/build_wordy_phrases.py (importable module, core infrastructure)
  affects:
    - Plans 03/04 (parsers + merge pipeline consume this module's public API)
tech_stack:
  added: []
  patterns:
    - Python stdlib only (hashlib, unicodedata, re, os, tomllib, pathlib)
    - NFC + explicit typography map (P-1): normalize_text = NFC then SMART_QUOTE_MAP
    - Hand-rolled TOML emitter: _escape_basic + _emit_array + _emit_entry + emit_toml
    - sha256sum-format manifest verification (two-space separator, no asterisk)
    - POSIX atomic write via os.replace (P-10)
key_files:
  created:
    - harper-bridge/scripts/build_wordy_phrases.py
  modified: []
decisions:
  - "build() stub uses static date '2026-04-20' matching expected fixture header for byte-determinism — real run will use today's ISO date (Plans 03/04 can inject date parameter when wiring full pipeline)"
  - "verify_sha256 path-traversal guard rejects filenames containing '/', '..', or null bytes and asserts is_relative_to(sources_dir) after resolve (V12)"
  - "SMART_QUOTE_MAP covers U+2018/2019/201C/201D (quotes), U+2013 (en-dash→-), U+2014 (em-dash→--), U+00A0 (NBSP→space)"
metrics:
  duration: "~4 min"
  completed: "2026-04-20T16:04:26Z"
  tasks_completed: 3
  files_created: 1
---

# Phase 08 Plan 02: Core Infrastructure — build_wordy_phrases.py Summary

stdlib-only Python module with NFC+typography normalization, sha256sum manifest verification, hand-rolled byte-deterministic TOML emitter, atomic write, and stub build pipeline — 245 lines, all core infrastructure tests green.

## Public API Shipped

| Symbol | Type | Purpose |
|--------|------|---------|
| `SCRIPT_DIR`, `CRATE_DIR`, `REPO_ROOT` | `Path` constants | Repo-relative path anchors |
| `SOURCES_DIR`, `DATA_DIR`, `OUT_PATH` | `Path` constants | Source + output locations |
| `MANIFEST_PATH`, `OVERRIDES_PATH` | `Path` constants | Manifest + overrides locations |
| `SMART_QUOTE_MAP` | `dict` | Unicode → ASCII typography map (P-1) |
| `normalize_text(s)` | function | NFC + SMART_QUOTE_MAP |
| `derive_id(phrase)` | function | `nfc(lowercase(phrase))` per D-13 |
| `verify_sha256(manifest, sources_dir)` | function | sha256sum-format verification; SystemExit on mismatch |
| `_BASIC_ESCAPES` | `dict` | TOML v1.0.0 required escape sequences |
| `_escape_basic(s)` | function | TOML basic-string escaping |
| `_emit_array(values)` | function | Inline TOML array |
| `_emit_entry(e)` | function | One `[[entries]]` block in D-12 field order |
| `emit_toml(entries, header)` | function | Full TOML document bytes |
| `HEADER_TEMPLATE` | `str` | Provenance comment template (D-04) |
| `write_atomic(path, content)` | function | POSIX atomic write via os.replace |
| `_discover_source_shas(sources_dir)` | function | SHA-from-filename extraction per D-01 |
| `build(sources_dir, overrides_path, data_dir)` | function | Pipeline entry point (stub) |

## Tests Green vs Plan 01 RED Baseline

| Test Module | Plan 01 State | Plan 02 State | Notes |
|-------------|---------------|---------------|-------|
| test_nfc.py (3 tests) | ERROR (ImportError) | 3/3 PASS | All NFC + derive_id tests green |
| test_typography.py (5 tests) | ERROR (ImportError) | 5/5 PASS | All typography flatten + output tests green |
| test_sha256.py (2 tests) | ERROR (ImportError) | 2/2 PASS | Good manifest + bad manifest SystemExit tests green |
| test_toml_emitter.py (5 tests) | ERROR (ImportError) | 3/5 PASS | Escape tests green; round-trip + field-order tests need parsed entries (Plans 03/04) |

**Total: 13/15 tests green** (from 0/15 in Plan 01)

## test_toml_emitter Deferred Tests

`test_output_is_tomllib_parseable` and `test_field_order_matches_d12` both call `build()` and assert `"entries"` key exists in parsed output. Stub build returns empty-entries TOML (no `[[entries]]` blocks), so these 2 tests remain RED. This is the expected state per Plan 02 task 2 done criteria: "round-trip tests still RED until Task 3 + Plans 03/04."

Both tests will go green once Plans 03/04 wire `parse_retext_js` + `parse_plainlang_md` into the build pipeline and the stub `entries: list[dict] = []` becomes a populated list.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Plan Contradiction Noted (No Action Taken)

The plan's overall success criteria states "`test_toml_emitter.py` green" while task 2's done criteria states "round-trip tests still RED until Task 3 + Plans 03/04." These are contradictory: `test_output_is_tomllib_parseable` and `test_field_order_matches_d12` cannot pass without parsed entries. The 3 escape tests that can pass do pass. This contradiction is inherent to the phased approach — full green requires Plans 03/04.

## Hand-off: Plan 03

Plan 03 adds `parse_retext_js(text: str) -> list[dict]` + `parse_plainlang_md(text: str) -> list[dict]` using the stub `build()` wiring point at:
```python
entries: list[dict] = []  # Plans 03/04 populate via parse → merge → override.
```

The two deferred test_toml_emitter tests will go green once Plans 03/04 replace the empty list with real parsed entries.

## Self-Check: PASSED

- harper-bridge/scripts/build_wordy_phrases.py: FOUND
- Commit 146667b (Task 1 — preamble + normalize + SHA): FOUND
- Commit 5a8a56e (Task 2 — TOML emitter primitives): FOUND
- Commit 21f7b0e (Task 3 — atomic write + stub build + CLI): FOUND
