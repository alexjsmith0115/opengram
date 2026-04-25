---
phase: 10-matcher-implementation
plan: 03
subsystem: clarity
tags: [rust, harper-bridge, clarity, atomic-swap, stub-deletion, dialect-filter]

requires:
  - phase: 10-matcher-implementation
    plan: 01
    provides: PhraseEntry struct + CORPUS const + WordyPhrasesLinter::new at module scope
  - phase: 10-matcher-implementation
    plan: 02
    provides: 4 promoted test helpers + 2 promoted gate tests inside top-level mod tests (clarity.rs)
provides:
  - WordyPhrasesLinter wired into build_lint_group via dialect-filtered CORPUS slice
  - lib.rs corpus-based regression tests (wordy_phrases_fires_corpus_entry, clarity_linter_survives_dict_add_cycle)
  - Production-only clarity.rs surface — stub gone, spike gone
affects: [10-04-gate-tests, 10-05-phase-gate, 11-dataset-integration]

tech-stack:
  added: []
  patterns:
    - "Build-time dialect filter — CORPUS .iter().filter().copied().collect() into Vec<PhraseEntry>"
    - "Filter-by-replacement test pattern (filter+count on primary_replacement) — survives co-emission of grammar/spelling lints on real corpus text"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs

key-decisions:
  - "Atomic two-task plan honored D-02: Task 1 deletes stub + spike from clarity.rs (build intentionally broken on lib.rs:7); Task 2 swaps lib.rs import + build_lint_group + tests in single coherent change. No coexistence period."
  - "build_lint_group dialect filter: None passes universally; Some(allowed) requires dialect.contains() membership. Per D-15, signature unchanged."
  - "Replaced len-equality assertions with filter+count by primary_replacement — real corpus text emits grammar/spelling co-lints alongside clarity matches; len==1 would race against unrelated harper-core curated rules."

patterns-established:
  - "Atomic stub→production swap: upstream deletion (Task 1) + downstream rewire (Task 2) in single plan"
  - "Corpus-based regression tests filter on primary_replacement field, not output cardinality"

requirements-completed: [CLAR-01, CLAR-04, CLAR-05, CLAR-06]

duration: ~2min
completed: 2026-04-25
---

# Phase 10 Plan 03: Atomic Registration Swap + Stub/Spike Deletion Summary

**WordyPhrasesLinter wired into build_lint_group via dialect-filtered CORPUS slice; WordyPhrasesStubLinter + mod spike + stub-only imports deleted from clarity.rs in same plan; lib.rs regression tests rewritten against real "utilize" → "use" corpus entry; cargo test --lib green with 7 tests passing.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-25T01:08:30Z
- **Completed:** 2026-04-25T01:10:42Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `WordyPhrasesStubLinter` struct + Default impl + Linter impl deleted from `clarity.rs`
- `mod spike` block (PriorityRewritingMapPhraseLinter + duplicate helpers + 2 duplicate tests) deleted from `clarity.rs`
- Stub-only imports (`harper_core::TokenKind`, `Punctuation`) and the duplicate `Suggestion` re-import removed; harper_core imports consolidated into single block
- `clarity.rs` file header doc-comment updated: production WordyPhrasesLinter description replaces "stub" reference
- `lib.rs:7` import: `WordyPhrasesStubLinter` dropped, `WordyPhrasesLinter` + `CORPUS` + `PhraseEntry` added
- `build_lint_group` dialect-filters `CORPUS` (`None` ⇒ universal; `Some(allowed)` ⇒ `allowed.contains(&dialect)`) then registers `WordyPhrasesLinter::new(&applicable)`; signature unchanged per D-15
- `stub_fires_flag_me` replaced with `wordy_phrases_fires_corpus_entry`: asserts `"utilize"` → `"use"` produces a Clarity-category lint with `Severity::High` and priority 200
- `clarity_linter_survives_dict_add_cycle` rewritten to use `"utilize"` corpus entry instead of FLAG_ME; CLAR-12 invariant verified via filter+count on `primary_replacement`
- `cargo test --lib` 7/7 green: 5 clarity.rs mod tests (severity_enum, severity_round_trip, clarity_loses_to_grammar_on_overlap, case_preservation_five_regimes, priority_rewrite_no_default_leak) + 2 lib.rs mod tests (wordy_phrases_fires_corpus_entry, clarity_linter_survives_dict_add_cycle)
- `clarity.rs` shrank from 571 LoC → 305 LoC (266 LoC removed in Task 1)

## Task Commits

1. **Task 1: Delete WordyPhrasesStubLinter + mod spike + stub-only imports from clarity.rs** — `61d0129` (refactor)
2. **Task 2: Update lib.rs import + build_lint_group body + replace stub tests** — `e22478b` (feat)

_Note: Task 1 intentionally leaves the build broken on lib.rs:7 (still imports the now-deleted stub). Task 2 atomically resolves per D-02 — no coexistence period._

## Files Created/Modified
- `harper-bridge/src/clarity.rs` — net −266 LoC: stub block deleted (45 lines), mod spike block deleted (211 lines), stub-only imports consolidated, file header doc-comment refreshed
- `harper-bridge/src/lib.rs` — net +21 LoC: import line swapped, `build_lint_group` body expanded with dialect-filter, both mod tests rewritten to use real CORPUS entries

## Decisions Made

- **Test cardinality changed from `len() == 1` to `filter+count on primary_replacement = 1`** — Plan-anticipated. Stub text "FLAG_ME" was gibberish to harper-core's curated grammar/spelling rules so `out.len() == 1` was safe. Real corpus text "Please utilize this." can co-emit unrelated grammar/spelling lints; filtering by replacement isolates the clarity match.
- **Followed plan verbatim.** No deviations from the plan-specified action steps.

## Deviations from Plan

None — plan executed exactly as written.

### Plan vs cargo test count discrepancy (clarification, not deviation)

- Plan `success_criteria` line states "9 tests pass" (5 baseline + 2 promoted + 2 corpus-based lib.rs).
- Plan `behavior` Test 2 states "7 tests total" (5 clarity.rs + 2 lib.rs).
- The 7-count is correct for the post-deletion state: mod spike held the only "non-promoted" duplicates, and Task 1 deleted them. Final cargo output: `test result: ok. 7 passed; 0 failed`.

## Issues Encountered

None.

## Next Phase Readiness

- Plan 04 gate tests can now consume the production `WordyPhrasesLinter` + `CORPUS` + 4 promoted helpers without any stub-related compile or runtime baggage.
- Plan 05 (phase gate D-35) will validate end-to-end CLAR-01 / CLAR-05 / CLAR-06 against the now-wired build_lint_group.
- Phase 11 (dataset integration) can replace `CORPUS` const with TOML-parsed `Vec<PhraseEntry>` without touching `WordyPhrasesLinter::new` or `build_lint_group` filter logic.

## Self-Check: PASSED

**Files verified to exist:**
- `harper-bridge/src/clarity.rs` — FOUND (modified, 305 LoC)
- `harper-bridge/src/lib.rs` — FOUND (modified)
- `.planning/phases/10-matcher-implementation/10-03-SUMMARY.md` — FOUND (this file)

**Commits verified to exist in git log:**
- `61d0129` (Task 1: refactor) — FOUND
- `e22478b` (Task 2: feat) — FOUND

**Acceptance criteria final state:**
- `WordyPhrasesStubLinter` count in clarity.rs: 0 ✓
- `mod spike` count in clarity.rs: 0 ✓
- `PriorityRewritingMapPhraseLinter` count in clarity.rs: 0 ✓
- `FLAG_ME` count in clarity.rs: 0 ✓
- `TokenKind` count in clarity.rs: 0 ✓
- `Punctuation` count in clarity.rs: 0 ✓
- `use harper_core::linting::{Lint, LintKind, Linter, MapPhraseLinter}` count: 1 ✓
- `pub(crate) struct WordyPhrasesLinter` count: 1 ✓
- `pub(crate) const CORPUS` count: 1 ✓
- `WordyPhrasesStubLinter` count in lib.rs: 0 ✓
- `FLAG_ME` count in lib.rs: 0 ✓
- `FLAGGED` count in lib.rs: 0 ✓
- `stub_fires_flag_me` count in lib.rs: 0 ✓
- `use clarity::{Severity, WordyPhrasesLinter, severity_from_priority, CORPUS, PhraseEntry};` count: 1 ✓
- `fn wordy_phrases_fires_corpus_entry` count: 1 ✓
- `fn clarity_linter_survives_dict_add_cycle` count: 1 ✓
- `applicable: Vec<PhraseEntry>` count: 1 ✓
- `.copied()` count: 1 ✓
- `WordyPhrasesLinter::new(&applicable)` count: 1 ✓
- `cargo test --lib`: 7 passed; 0 failed ✓

---
*Phase: 10-matcher-implementation*
*Completed: 2026-04-25*
