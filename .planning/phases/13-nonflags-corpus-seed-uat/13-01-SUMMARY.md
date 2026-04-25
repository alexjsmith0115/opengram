---
phase: 13-nonflags-corpus-seed-uat
plan: 01
subsystem: testing
tags: [rust, cargo-integration-test, include_str, harper, wordy-phrases-linter, fixture-harness, regression-corpus]

# Dependency graph
requires:
  - phase: 11-dataset-integration-fixture-harness
    provides: "WordyPhrasesLinter::new_from_parsed + get_corpus + fixture_harness.rs aggregate-failure pattern"
  - phase: 12-settings-ui-severity-filter-acknowledgements
    provides: "Severity filter wired in HarperService; clarity surface stable for regression corpus"
provides:
  - "Empty NonFlags Rust integration test harness (4 per-category test fns) — locked API + filter logic before fixture content lands"
  - "4 placeholder .txt fixture files (header-only) ready for incremental seeding (Wave 2)"
  - "Compile-time include_str! wiring for nonflags/*.txt"
affects: [phase-13-wave-2-fixture-seeding, phase-13-llm-clarity-regression-test, phase-13-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Aggregate-failure assertion (Vec<String> + single final assert) per fixture_harness.rs precedent"
    - "include_str! for compile-time fixture embed (zero-IO; honors CLAR-N3)"
    - "Linter constructed once per test fn (perf budget <5s for ≥100 fixtures)"
    - "Comment + blank-line filter via parse_fixture_file helper"

key-files:
  created:
    - "harper-bridge/tests/nonflags_corpus.rs (130 lines, 4 test fns, parse_fixture_file + run_zero_lint_check helpers)"
    - "harper-bridge/tests/nonflags/proper_nouns.txt (header-only)"
    - "harper-bridge/tests/nonflags/quoted_code.txt (header-only)"
    - "harper-bridge/tests/nonflags/domain_terms.txt (header-only)"
    - "harper-bridge/tests/nonflags/retext_issues.txt (header-only)"
  modified: []

key-decisions:
  - "Mirror fixture_harness.rs aggregate-failure pattern verbatim — Vec<String> + single final assert per category test fn"
  - "Linter constructed ONCE per test fn (not globally) — avoids parallel-test data race on &mut self lint() while keeping <5s perf budget via OnceLock-cached corpus"
  - "include_str! paths relative to source file (tests/nonflags_corpus.rs) — Pitfall 1 honored: nonflags/proper_nouns.txt resolves correctly"
  - "Per-category test fn (vs aggregated single fn) — Cargo's runner reports per-category pass/fail granularity"

patterns-established:
  - "NonFlags fixture format: plain .txt, one sentence per line, # comments + blank lines stripped"
  - "Failure message format: '<file> L<n>: <sentence> produced N lint(s): →replacement1, →replacement2'"
  - "Provenance comments in retext_issues.txt: '# Source: <issue-ref>' or '# Source: hand-curated'"

requirements-completed: [CLAR-21]

# Metrics
duration: ~10min
completed: 2026-04-25
---

# Phase 13 Plan 01: NonFlags Empty Harness Summary

**Empty Rust integration test harness `nonflags_corpus.rs` mirroring `fixture_harness.rs` aggregate-failure pattern, plus 4 placeholder .txt fixture files — `cargo test --test nonflags_corpus` reports 4 passing tests in 2.59s with zero fixtures iterated.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-25T15:10:14Z
- **Completed:** 2026-04-25T15:20Z
- **Tasks:** 2/2
- **Files created:** 5
- **Files modified:** 0

## Accomplishments

- Wired empty NonFlags corpus harness ahead of fixture seeding — locks harness API + filter logic before fixture content lands per CONTEXT decision (test wiring order: empty harness FIRST → 25 lines → ≥100)
- 4 per-category #[test] functions (`nonflags_proper_nouns`, `nonflags_quoted_code`, `nonflags_domain_terms`, `nonflags_retext_issues`) — Cargo runner reports per-category pass/fail granularity
- `parse_fixture_file` helper strips comments + blank lines (1-indexed line numbers preserved for failure reporting)
- `run_zero_lint_check` constructs `WordyPhrasesLinter::new_from_parsed(get_corpus())` ONCE per call to honor <5s perf budget while avoiding parallel-test data race on `&mut self lint()`
- `cargo test --test nonflags_corpus` exits 0 with `4 passed` in 2.59s (well under 5s budget); xcodebuild app build green

## Task Commits

1. **Task 1: Create 4 empty placeholder fixture files** — `8cdfbd9` (test)
2. **Task 2: Write empty harness nonflags_corpus.rs** — `c91d07c` (test)

## Files Created/Modified

- `harper-bridge/tests/nonflags_corpus.rs` (NEW, 130 lines) — 4 #[test] fns + `parse_fixture_file` + `run_zero_lint_check` + `make_merged_dict` + `primary_replacement` helpers. Uses `include_str!("nonflags/<file>.txt")` ×4.
- `harper-bridge/tests/nonflags/proper_nouns.txt` (NEW) — header-only; flagged-substring proper nouns category
- `harper-bridge/tests/nonflags/quoted_code.txt` (NEW) — header-only; backtick/quoted code/path/idiom category
- `harper-bridge/tests/nonflags/domain_terms.txt` (NEW) — header-only; domain-specific / RFC normative usage category
- `harper-bridge/tests/nonflags/retext_issues.txt` (NEW) — header-only; overflow + scraped upstream issues category (provenance comment format documented in header)

## Decisions Made

- **Linter construction scope**: Once per test fn (4 total constructions per `cargo test` invocation), not globally `static mut`. `WordyPhrasesLinter::lint(&mut self, …)` requires unique mutable access; `OnceLock`-cached `get_corpus()` already amortizes the parse cost (Phase 11 precedent). Verified harness compiles + 4 passes in 2.59s.
- **Per-category test fn split**: 4 separate `#[test]` fns (one per fixture file) rather than a single iterator over a directory. Reason: Cargo's runner reports per-category pass/fail; failure isolation is clearer when a single category breaks.
- **Failure message format**: `"<file> L<n>: '<sentence>' produced N lint(s): →repl1, →repl2"`. Includes filename + 1-indexed line number + offending sentence + count + primary replacements per lint. Mirrors `fixture_harness.rs:108-146` aggregate-failure pattern.
- **No `nonflags_meta_corpus_size` ≥100 line assertion in this plan**: deferred to Wave 2 when actual fixtures land — no value asserting ≥100 against an empty corpus.

## Deviations from Plan

None - plan executed exactly as written.

The cargo binary was reachable at `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` per RESEARCH §Pitfall 8, but `rustc` lookup required prepending the same path to `$PATH` for the cargo subprocess (rustc invoked indirectly). Resolved by `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"` before `cargo test`. Not a deviation — RESEARCH explicitly listed this fallback.

## Issues Encountered

- **Initial `cargo test` invocation failed** with `error: could not execute process 'rustc -vV' (never executed)` — rustc not found despite cargo binary path being correct. Cargo subprocesses rustc by command name, and `rustc` was not on `$PATH`. Resolved by exporting full toolchain bin dir to `$PATH` per RESEARCH §Pitfall 8 fallback. Test then ran clean.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary changes. Plan adds Rust integration tests + plain-text placeholder fixtures only.

## Self-Check: PASSED

Verified:
- `harper-bridge/tests/nonflags_corpus.rs` exists (FOUND)
- `harper-bridge/tests/nonflags/proper_nouns.txt` exists (FOUND)
- `harper-bridge/tests/nonflags/quoted_code.txt` exists (FOUND)
- `harper-bridge/tests/nonflags/domain_terms.txt` exists (FOUND)
- `harper-bridge/tests/nonflags/retext_issues.txt` exists (FOUND)
- Commit `8cdfbd9` exists in `git log` (FOUND)
- Commit `c91d07c` exists in `git log` (FOUND)
- `cargo test --test nonflags_corpus` exits 0 with `4 passed` in 2.59s (VERIFIED)
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → BUILD SUCCEEDED (VERIFIED)
- No `Phase` ref in source files (VERIFIED via `grep -L "Phase"`)
- `CLAR-21` reference present in harness + each fixture (VERIFIED)

## Next Phase Readiness

- Plan 13-02 (Wave 2: incremental fixture seed → 25 lines) ready to start — harness API locked.
- Plan 13-03+ (≥100 lines, LLM regression test, CONTRIBUTING.md, PR template, UAT) unblocked once seeding complete.
- No blockers. CLAR-21 progress: 0/100 fixture lines (harness in place; seeding next).

---
*Phase: 13-nonflags-corpus-seed-uat*
*Completed: 2026-04-25*
