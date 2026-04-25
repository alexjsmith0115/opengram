---
phase: 13-nonflags-corpus-seed-uat
plan: 04
subsystem: testing
tags: [clarity, nonflags, regression-corpus, harper, wordy-phrases, meta-test, fail-fast]

requires:
  - phase: 13-nonflags-corpus-seed-uat
    provides: "105-line corpus across 4 fixture files (from 13-03); parse_fixture_file helper (from 13-01)"
provides:
  - "Fail-fast guard test against accidental fixture deletion below 100-line launch threshold"
  - "5th test fn in nonflags_corpus binary (4 per-category + 1 meta)"
affects: [13-07]

tech-stack:
  added: []
  patterns:
    - "Meta-test pattern reusing per-category helper for aggregate corpus assertions"
    - "Per-category line counts surfaced in failure message for fast triage"

key-files:
  created:
    - ".planning/phases/13-nonflags-corpus-seed-uat/13-04-SUMMARY.md"
  modified:
    - "harper-bridge/tests/nonflags_corpus.rs (+19 lines: nonflags_meta_corpus_size fn)"

key-decisions:
  - "Per-category counts surfaced in failure message (not just total) — caller sees which file shrunk for fast triage"
  - "Reused parse_fixture_file helper directly via .len() — no new helper added; honors plan constraint"

patterns-established:
  - "Meta-test colocated with per-category tests in same binary — single cargo test invocation covers both per-file zero-lint and aggregate-size guards"

requirements-completed: [CLAR-21]

duration: 1min
completed: 2026-04-25
---

# Phase 13 Plan 04: NonFlags Corpus Meta Guard Summary

**Added `nonflags_meta_corpus_size` fail-fast test asserting total non-comment lines across all 4 fixture files ≥100; current corpus passes at 105 lines; CLAR-21 corpus now self-protected against accidental fixture deletion.**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-25T15:45:07Z
- **Tasks:** 1
- **Files modified:** 1
- **Cargo test runtime:** 3.03s (<5s perf budget)

## Accomplishments

- Appended `nonflags_meta_corpus_size` test fn to `harper-bridge/tests/nonflags_corpus.rs` (+19 lines)
- Test sums `parse_fixture_file(...).len()` across all 4 fixture files via `include_str!` and asserts ≥100 threshold
- Failure message lists per-category counts (proper_nouns / quoted_code / domain_terms / retext_issues) for fast triage on regression
- Reused existing `parse_fixture_file` helper — zero new helpers; honors plan constraint
- All 5 `nonflags_corpus` tests green: `nonflags_proper_nouns`, `nonflags_quoted_code`, `nonflags_domain_terms`, `nonflags_retext_issues`, `nonflags_meta_corpus_size`
- xcodebuild app target BUILD SUCCEEDED

## Task Commits

1. **Task 1: Add nonflags_meta_corpus_size test fn** — `48a02ef` (test)

## Files Created/Modified

- `harper-bridge/tests/nonflags_corpus.rs` — +19 lines (5th test fn + comment)
- `.planning/phases/13-nonflags-corpus-seed-uat/13-04-SUMMARY.md` — created

## Decisions Made

- **Per-category counts in failure message:** Plan suggested only total in error string; expanded to per-category to make triage trivial when a future regression shrinks the corpus. Caller sees exactly which fixture file lost lines without needing to manually re-count.
- **Direct `.len()` on parse_fixture_file:** Helper returns `Vec<(usize, String)>` whose len equals non-comment-non-blank-line count. No need for a new line-count helper — direct `.len()` is the cheapest reuse.

## Deviations from Plan

None — plan executed as written. Per-category counts in failure message is a refinement (not a deviation) since plan said "list per-category counts for debugging" in the key_mandates.

## Issues Encountered

- `cargo` not on default PATH (recurring from 13-02/03) — required `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"`. Per-invocation; no project fix needed.

## Build Validation

- `cargo test --test nonflags_corpus` — 5 passed, 0 failed, 3.03s
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — BUILD SUCCEEDED

## Verification Results

| Acceptance criterion | Status |
|---|---|
| `grep -c "fn nonflags_meta_corpus_size" nonflags_corpus.rs` returns 1 | 1 ✓ |
| `grep -c "total >= 100" nonflags_corpus.rs` returns 1 | 1 ✓ |
| `cargo test --test nonflags_corpus` exits 0 with 5 passed | 5/5 passed ✓ |
| File contains no `Phase` reference | confirmed ✓ |
| Total runtime <5s | 3.03s ✓ |
| xcodebuild BUILD SUCCEEDED | confirmed ✓ |

## Next Phase Readiness

- CLAR-21 corpus self-protected against accidental fixture deletion
- Phase 13-07 (UAT close-out) ready to proceed
- No blockers

## Self-Check: PASSED

- File `harper-bridge/tests/nonflags_corpus.rs`: FOUND
- Commit `48a02ef`: FOUND
- Test fn `nonflags_meta_corpus_size`: present (1 occurrence)
- Threshold `total >= 100`: present (1 occurrence)
- 5 tests pass in 3.03s
- No `Phase` literal in test file

---
*Phase: 13-nonflags-corpus-seed-uat*
*Completed: 2026-04-25*
