---
phase: 11
plan: "03"
subsystem: harper-bridge
tags: [clarity-engine, fixture-harness, integration-tests, rust, CLAR-20]
dependency_graph:
  requires: [11-02]
  provides: [fixture_harness integration test suite, positive+negative corpus coverage]
  affects:
    - harper-bridge/tests/fixture_harness.rs
    - harper-bridge/Cargo.toml
    - harper-bridge/src/lib.rs
tech_stack:
  added: []
  patterns:
    - aggregate-failure-reporting (Vec<String> + single assert)
    - per-entry linter construction (new_from_parsed + std::slice::from_ref)
    - is_simple_phrase / is_single_word filter guards
key_files:
  created:
    - harper-bridge/tests/fixture_harness.rs
  modified:
    - harper-bridge/Cargo.toml
    - harper-bridge/src/lib.rs
decisions:
  - "rlib added to crate-type (Rule 3): staticlib+cdylib alone does not produce rlib linkage; cargo test --test needs rlib to link harper_bridge in integration tests"
  - "clarity mod promoted pub in lib.rs (Rule 3): integration tests in tests/ cannot access private modules; pub mod clarity required for use harper_bridge::clarity::*"
  - "All tasks written in single atomic file write — both Task 1 (meta+positive) and Task 2 (negative) landed in fixture_harness.rs; committed together"
metrics:
  duration: "20min"
  completed: "2026-04-24"
  tasks: 2
  files: 3
---

# Phase 11 Plan 03: Fixture Harness Summary

One-liner: Auto-generated fixture harness iterating get_corpus() — 330 positive + 207 negative fixtures, 3 meta-tests, aggregate failure reporting.

## Test Count Breakdown

| Test | Type | Status |
|------|------|--------|
| meta_test_generator_detects_known_entry | meta | green |
| meta_test_generator_rejects_replacement_text | meta | green |
| meta_test_generator_rejects_unrelated_text | meta | green |
| meta_test_negative_generator_rejects_midword | meta-negative | green |
| positive_fixtures_lowercase | positive loop | green |
| positive_fixtures_sentence_start | positive loop | green |
| negative_fixtures_midword | negative loop | green |

**Total:** 7 integration tests. All green.

## Tested vs Skipped Counts

| Loop | Tested | Skipped | Failed |
|------|--------|---------|--------|
| positive_fixtures_lowercase | 330 | 8 | 0 |
| positive_fixtures_sentence_start | 330 | 8 | 0 |
| negative_fixtures_midword | 207 | 131 | 0 |

Positive total: 330 + 8 = 338 entries (full corpus).
Negative total: 207 single-word + 131 multi-word/non-simple skipped = 338.

## Triage Log

### Skipped in positive_fixtures (is_simple_phrase = false) — 8 entries

All 8 are **judgment_call** entries: phrases containing punctuation characters
(`/`, `\`, `.`) that cannot appear safely in a fixture sentence template.

| Phrase | Replacement | Reason Skipped |
|--------|-------------|----------------|
| `/ (slash)` | `and` | Contains `/` and `()`  |
| `\_\_\_\_\_\_etc.` | `for example` | Contains `\` and `.` |
| `a and/or b` | `a or b or both` | Contains `/` |
| `and/or` | `… or … or both` | Contains `/` |
| `e.g.` | `for example` | Contains `.` |
| `i.e.` | `as in` | Contains `.` |
| `not later than 10 May` | `by 10 May` | Contains digits (`10`) — `chars().all(alphabetic\|space\|hyphen\|apostrophe)` rejects digit |
| `not later than 1600` | `by 1600` | Contains digits (`1600`) |

None of these entries represent a matcher bug. `MapPhraseLinter` would handle them
correctly at runtime — the skip is purely a fixture-sentence-construction limitation.
The last two (date/time phrases) contain numerals which `is_simple_phrase` correctly
flags as non-alphabetic.

### Skipped in negative_fixtures_midword (is_single_word = false) — 131 entries

All multi-word phrases (contain space) plus the 8 non-simple entries above.
Multi-word phrases cannot be wrapped mid-token (a sentence like "unin order toable"
is not valid text); the negative mid-word strategy is inherently single-word-only.
Positive fixtures cover multi-word entries — no coverage gap.

### Matcher Bug Findings

None. Zero failures in all 3 loops. The `MapPhraseLinter` word-boundary contract
(CLAR-05) held for every tested entry.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added rlib to crate-type**
- **Found during:** Task 1 probe test
- **Issue:** `crate-type = ["staticlib", "cdylib"]` does not emit an rlib; `cargo test --test` integration tests need rlib to link `harper_bridge`
- **Fix:** Added `"rlib"` to `crate-type` array in Cargo.toml
- **Files modified:** harper-bridge/Cargo.toml
- **Commit:** b03ba87

**2. [Rule 3 - Blocking] Promoted clarity module to pub**
- **Found during:** Task 1 probe test
- **Issue:** `mod clarity` (private) blocked `use harper_bridge::clarity::*` from integration test files in `tests/`
- **Fix:** Changed `mod clarity` to `pub mod clarity` in lib.rs
- **Files modified:** harper-bridge/src/lib.rs
- **Commit:** b03ba87

## Self-Check: PASSED

- [x] `harper-bridge/tests/fixture_harness.rs` exists
- [x] 7 test functions confirmed: meta_test_generator_detects_known_entry, meta_test_generator_rejects_replacement_text, meta_test_generator_rejects_unrelated_text, meta_test_negative_generator_rejects_midword, positive_fixtures_lowercase, positive_fixtures_sentence_start, negative_fixtures_midword
- [x] 5 helper functions confirmed: run_positive_check, run_negative_check, is_simple_phrase, is_single_word, make_merged_dict + primary_replacement + sentence_start
- [x] cargo test --test fixture_harness: 7/7 green
- [x] cargo test (full suite): 15 unit + 7 integration = 22 green, 0 failed
- [x] Commit b03ba87 exists in git log
