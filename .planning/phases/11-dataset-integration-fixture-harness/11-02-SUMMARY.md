---
phase: 11
plan: "02"
subsystem: harper-bridge
tags: [clarity-engine, dataset-integration, wordy-phrases, rust]
dependency_graph:
  requires: [11-01]
  provides: [WordyPhrasesLinter::new_from_parsed, get_corpus wired in build_lint_group]
  affects: [harper-bridge/src/clarity.rs, harper-bridge/src/lib.rs]
tech_stack:
  added: []
  patterns: [OnceLock single-init, constructor injection, dialect filter via cloned Vec]
key_files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs
decisions:
  - "WordyPhrasesLinter promoted pub(crate)→pub so Plans 03/04/05 integration tests can construct it directly"
  - "dialect_filter_drops_non_matching rewritten to inject synthetic forthwith locally via new_from_parsed; no longer routes through HarperChecker::new which only sees TOML data"
  - ".cloned() not .copied() in build_lint_group because ParsedPhraseEntry contains String (non-Copy)"
  - "match &e.dialects (borrow) not match e.dialects (move) because Vec<Dialect> is not Copy"
metrics:
  duration: "10min"
  completed: "2026-04-25"
  tasks: 2
  files: 2
---

# Phase 11 Plan 02: Wire Production Dataset into build_lint_group Summary

**One-liner:** Switched `build_lint_group` from 21-entry `CORPUS` const to 338-entry `get_corpus()` TOML dataset; added `pub WordyPhrasesLinter::new_from_parsed(&[ParsedPhraseEntry])` constructor; relocated synthetic forthwith dialect test to local injection.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Promote WordyPhrasesLinter to pub; add new_from_parsed | 08d7845 | clarity.rs |
| 2 | Switch build_lint_group to get_corpus(); rewrite dialect test | 4dcdc7c | lib.rs |

## What Changed

### clarity.rs
- `pub(crate) struct WordyPhrasesLinter` → `pub struct WordyPhrasesLinter`
- Added `pub fn new_from_parsed(entries: &[ParsedPhraseEntry]) -> Self` after existing `pub(crate) fn new`
- Added test `new_from_parsed_emits_priority_from_severity` (GREEN on first run after RED compile-error phase)
- Existing `pub(crate) fn new(&[PhraseEntry])` retained — used by in-module clarity.rs tests (CORPUS const)

### lib.rs
- Import line 7: `CORPUS, PhraseEntry` removed; `get_corpus, ParsedPhraseEntry` added
- `build_lint_group`: `CORPUS.iter().copied()` → `get_corpus().iter().cloned()`; `match e.dialects` → `match &e.dialects`; `WordyPhrasesLinter::new` → `WordyPhrasesLinter::new_from_parsed`
- `dialect_filter_drops_non_matching`: rewritten to construct `ParsedPhraseEntry { phrase: "forthwith", ..., dialects: Some(vec![Dialect::American]) }` locally, filter via inline dialect logic, build `WordyPhrasesLinter::new_from_parsed` directly — no HarperChecker involved

## Test Results

```
running 15 tests
test clarity::tests::clarity_loses_to_grammar_on_overlap ... ok
test clarity::tests::parse_wordy_phrases_round_trip ... ok
test clarity::tests::severity_enum ... ok
test clarity::tests::severity_round_trip ... ok
test clarity::tests::parse_wordy_phrases_real_dataset_338_entries ... ok
test clarity::tests::corpus_parsed_exactly_once ... ok
test clarity::tests::new_from_parsed_emits_priority_from_severity ... ok
test clarity::tests::proper_noun_iphone_does_not_trigger ... ok
test clarity::tests::word_boundary_no_midword_match ... ok
test clarity::tests::priority_rewrite_no_default_leak ... ok
test clarity::tests::case_preservation_under_tr_locale ... ok
test clarity::tests::case_preservation_five_regimes ... ok
test tests::wordy_phrases_fires_corpus_entry ... ok
test tests::dialect_filter_drops_non_matching ... ok
test tests::clarity_linter_survives_dict_add_cycle ... ok

test result: ok. 15 passed; 0 failed; 0 ignored; 0 measured
```

`cargo build --release` succeeded (1m 14s; 60KB TOML embedded via `include_str!`).

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. `get_corpus()` returns all 338 parsed entries from production TOML; no placeholder data.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

- `harper-bridge/src/clarity.rs` exists and contains `pub struct WordyPhrasesLinter` + `pub fn new_from_parsed`
- `harper-bridge/src/lib.rs` exists and contains `get_corpus()` in build_lint_group; zero `CORPUS.iter()` matches
- Commits `08d7845` and `4dcdc7c` verified in git log
- All 15 tests green; release build succeeded
