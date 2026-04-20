---
phase: 08-dataset-pipeline
plan: "04"
subsystem: dataset-pipeline
tags: [python, dataset, merge, dedup, severity, overrides, judgment]
dependency_graph:
  requires:
    - harper-bridge/scripts/build_wordy_phrases.py (Plan 02 infra + Plan 03 parsers)
    - harper-bridge/scripts/tests/fixtures/tiny-overrides.toml
    - harper-bridge/scripts/tests/fixtures/expected_wordy_phrases.toml (golden)
  provides:
    - merge_and_dedup (order-independent retext-wins, sources union, dirty_dozen OR)
    - tag_severity (D-07 + D-23 rules)
    - flag_judgment_calls (D-11 rules 2+3; rule 1 absent per D-21)
    - load_overrides (tomllib, unknown-key rejection)
    - apply_overrides (all 5 D-10 ops, W5 _judgment_reason clear, P-6 uniqueness re-check)
    - emit_toml_with_judgment (# JUDGMENT: comment above flagged entries)
    - build() fully wired end-to-end pipeline
  affects:
    - Plan 05 (vendors real upstream sources, runs script, curates overrides, commits generated TOML)
    - Phase 9 (PhraseEntry struct consumes D-12 schema from generated TOML)
tech_stack:
  added: []
  patterns:
    - W3 fix: pre-mutation sources membership check for order-independent retext-wins in merge_and_dedup
    - W5 fix: any override op deletes _judgment_reason to prevent stale JUDGMENT comments
    - P-6 guard: post-apply id-uniqueness re-check with SystemExit on collision
    - D-21: D-11 rule 1 absent — no retext note/condition keyword scan (confirmed dead code)
    - emit_toml_with_judgment: # JUDGMENT: comment prefix on flagged entries, only when override did not fire
key_files:
  created: []
  modified:
    - harper-bridge/scripts/build_wordy_phrases.py (231 lines added; 396 → 611 total)
decisions:
  - "Both tasks (T1 merge/severity/judgment + T2 overrides/build-wiring) committed atomically — pipeline only meaningful as whole"
  - "build() uses emit_toml_with_judgment not emit_toml — judgment comments flow through by default; no separate path"
  - "Internal fields (_omit, _all_replacements, dirty_dozen) stripped in build() step 8, not in emitter — emitter stays single-purpose"
  - "_judgment_reason retained through sort+clean steps so emitter can prefix # JUDGMENT: comment"
requirements: [CLAR-14, CLAR-15]
metrics:
  duration: "~8 min"
  completed: "2026-04-20T00:00:00Z"
  tasks_completed: 2
  files_created: 0
  files_modified: 1
---

# Phase 08 Plan 04: Pipeline Wiring — merge, severity, overrides, judgment Summary

Full build() pipeline wired: parsers → merge_and_dedup (W3 order-independent retext-wins) → tag_severity (D-07+D-23) → flag_judgment_calls (D-11 rules 2+3) → load/apply_overrides (D-09/D-10, W5 judgment clear) → sort → emit_toml_with_judgment → atomic write. All 32 tests green; fixture build byte-identical to golden.

## Test Suite Results

| Metric | Value |
|--------|-------|
| Modules | 10 |
| Total tests | 32 |
| Passed | 32 |
| Failed | 0 |
| Errors | 0 |

All tests that were RED after Plan 03 are now GREEN:

| Test | Status |
|------|--------|
| test_dedup.TestDedup.test_cross_source_dedup | GREEN |
| test_dedup.TestDedup.test_inflected_forms_both_retained | GREEN |
| test_dedup.TestDedup.test_id_uniqueness_asserted | GREEN |
| test_severity.TestSeverity.test_both_sources_high | GREEN |
| test_severity.TestSeverity.test_single_source_medium | GREEN |
| test_severity.TestSeverity.test_dirty_dozen_single_source_high | GREEN |
| test_overrides.TestOverrides.test_drop_removes_entry | GREEN |
| test_overrides.TestOverrides.test_severity_override | GREEN |
| test_overrides.TestOverrides.test_replacement_override | GREEN |
| test_overrides.TestOverrides.test_dialects_override | GREEN |
| test_overrides.TestOverrides.test_note_override_from_overrides_file | GREEN |
| test_byte_determinism.TestByteDeterminism.test_two_runs_same_bytes | GREEN |
| test_byte_determinism.TestByteDeterminism.test_matches_golden | GREEN |
| test_schema.TestSchema.* (3 tests) | GREEN |
| test_nfc.TestNFCInvariant.test_output_bytes_are_nfc | GREEN |
| test_toml_emitter.TestTomlEmitter.test_output_is_tomllib_parseable | GREEN |
| test_toml_emitter.TestTomlEmitter.test_field_order_matches_d12 | GREEN |
| test_omit_handling.TestOmitHandling.test_omit_entry_uses_first_replace | GREEN |

## Byte-Identical Golden Fixture Match

```
python3 -c "... out1 == golden ... print('GREEN')"
GREEN
```

Two sequential runs against `harper-bridge/scripts/tests/fixtures/` produce identical bytes matching `expected_wordy_phrases.toml` exactly. D-17 byte-determinism invariant holds.

## W3 + W5 Regression Coverage

**W3 (order-independent retext-wins):** `merge_and_dedup` reads `existing_is_retext` and `incoming_is_retext` from PRE-union `sources` arrays BEFORE overwriting them. Conflict branch uses these booleans — no dead code, no stale state. Verified by running `merge_and_dedup([retext, plainlang])` AND `merge_and_dedup([plainlang, retext])` — both resolve `replacement` to the retext value.

**W5 (stale JUDGMENT comment prevention):** `apply_overrides` deletes `_judgment_reason` from any entry where an override op fires (`del e["_judgment_reason"]`). Verified by unit test: entry with `_judgment_reason` set + override `severity=high` → post-apply `_judgment_reason` absent.

## Pipeline Order

```
build()
  1. verify_sha256 (manifest)
  2. parse_retext_js + parse_plainlang_md
  3. merge_and_dedup(retext_entries + plainlang_entries)
  4. tag_severity
  5. flag_judgment_calls
  6. load_overrides + apply_overrides
  7. sort by id (codepoint)
  8. strip _omit / _all_replacements / dirty_dozen
  9. emit_toml_with_judgment (# JUDGMENT: prefix on flagged entries)
  10. write_atomic (if data_dir set)
```

## D-21 Enforcement

`grep -c "note.*condition.*careful\|careful.*sometimes.*context" build_wordy_phrases.py` → `0`. D-11 rule 1 (retext note/condition keyword scan) is confirmed absent. Rules 2 and 3 only.

## Security Mitigations Implemented

| Threat ID | Mitigation | Verified |
|-----------|-----------|---------|
| T-8-02 | `_VALID_OVERRIDE_KEYS` allowlist in `load_overrides` → SystemExit on unknown key | grep confirmed |
| T-8-07 | Post-apply id-uniqueness re-check in `apply_overrides` → SystemExit on collision | code present |
| T-8-08 | W5: `del e["_judgment_reason"]` on any override op | unit test verified |

## Deviations from Plan

None — plan executed exactly as written. Both tasks implemented as specified; all acceptance criteria met on first attempt.

## Hand-off: Plan 05

Plan 05 vendors real upstream sources (retext-simplify + plainlanguage.gov), runs `build_wordy_phrases.py` against them, curates `overrides.toml`, and commits the generated `harper-bridge/data/wordy_phrases.toml`. The script is now fully correct — Plan 05 is pure data work, no script changes expected.

## Self-Check: PASSED

- harper-bridge/scripts/build_wordy_phrases.py: FOUND (611 lines)
- Commit f0abee2: FOUND
- All 32 tests: GREEN
- Golden byte match: PASSED
- D-21 rule 1 absent: CONFIRMED (count=0)
- W3 order-independence: VERIFIED
- W5 judgment clear: VERIFIED
