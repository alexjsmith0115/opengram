---
phase: 10-matcher-implementation
plan: 02
subsystem: clarity
tags: [rust, harper-bridge, clarity, test-promotion, spike-promotion]

requires:
  - phase: 10-matcher-implementation
    plan: 01
    provides: PhraseEntry struct + CORPUS const + WordyPhrasesLinter::new at module scope
provides:
  - 4 test helpers (make_merged_dict, title_case, sentence_start, primary_replacement) inside top-level mod tests
  - case_preservation_five_regimes test against production WordyPhrasesLinter::new(CORPUS)
  - priority_rewrite_no_default_leak test against production WordyPhrasesLinter::new(CORPUS)
affects: [10-03-registration-swap, 10-04-gate-tests]

tech-stack:
  added: []
  patterns:
    - "Test helpers + tests duplicated across mod tests + mod spike (temporary; Plan 03 deletes spike)"
    - "CORPUS iteration via PhraseEntry field access (entry.phrase, entry.replacement)"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs

key-decisions:
  - "Promoted tests run against PRODUCTION WordyPhrasesLinter::new(CORPUS) — bypasses build_lint_group dialect filter so all 21 entries (incl. synthetic 'forthwith') are exercised"
  - "Inline use harper_core::linting::Suggestion in mod tests resolves Suggestion type for primary_replacement helper without re-importing in each test"
  - "Spike copies of helpers + tests left intact — Plan 03 deletes mod spike wholesale; promotion-before-deletion ordering guards against compile breakage"

patterns-established:
  - "Test promotion pattern: helpers first (Task 1), tests second (Task 2), spike deletion last (Plan 03) — RESEARCH §Pitfall 2 ordering requirement"

requirements-completed: [CLAR-03, CLAR-04]

duration: 81s
completed: 2026-04-25
---

# Phase 10 Plan 02: Spike Test Promotion Summary

**4 test helpers + 2 spike gate tests promoted to top-level `mod tests` in clarity.rs; promoted tests run against production `WordyPhrasesLinter::new(CORPUS)` with `PhraseEntry` field access; 9 cargo tests green (7 baseline + 2 newly promoted).**

## Performance

- **Duration:** ~1m 21s
- **Started:** 2026-04-25T01:04:19Z
- **Completed:** 2026-04-25T01:05:40Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- 4 test helpers (`make_merged_dict`, `title_case`, `sentence_start`, `primary_replacement`) added to top-level `#[cfg(test)] mod tests`
- Module-level test imports added (`Document`, `Lint`, `Suggestion`, `PlainEnglish`, `FstDictionary`, `MergedDictionary`, `Arc`)
- `case_preservation_five_regimes` promoted — runs 5 regimes × 21 CORPUS entries = 105 assertions against production `WordyPhrasesLinter::new(CORPUS)`
- `priority_rewrite_no_default_leak` promoted — asserts `lint.priority ∈ {200, 220, 240}` for every emitted lint; zero leakage of MapPhraseLinter's hardcoded 31
- Iteration adapted from tuple destructuring `(phrase, replacement, _prio)` to `PhraseEntry` field access (`entry.phrase`, `entry.replacement`)
- Spike module untouched (Plan 03 deletes wholesale)
- `cargo test --lib` 9/9 green (5 baseline mod tests + 2 mod spike + 2 newly promoted)

## Task Commits

1. **Task 1: Promote 4 test helpers to top-level mod tests** — `a9e27c0` (test)
2. **Task 2: Promote case_preservation_five_regimes + priority_rewrite_no_default_leak** — `f5a6125` (test)

## Files Created/Modified
- `harper-bridge/src/clarity.rs` — +125 lines: 7 new module-level imports, 4 helpers, 2 promoted tests inside `#[cfg(test)] mod tests`

## Decisions Made
- Followed plan verbatim. No deviations from action steps.
- Synthetic `forthwith` entry exercises correctly under linter-level test (D-04 from CONTEXT). MapPhraseLinter matches by token windows independent of Dialect, so the entry fires regardless of `Document` setup. 105 assertions (21 entries × 5 regimes) all pass.

## Deviations from Plan

None. Plan executed exactly as written.

### Intermediate dead-code warnings (expected)

Cargo emits 1 dead-code warning on `PhraseEntry`'s derived `Clone` impl (`#[derive(Clone, Copy)]` ignored during dead-code analysis per Rust note). This is the same kind of intermediate warning Plan 01 documented — Plan 03 wires `CORPUS` through `build_lint_group` in `lib.rs`, removing the warning. Build status: `cargo test --lib` exits 0; all 9 tests pass.

## Issues Encountered

None.

## Next Phase Readiness
- Plan 03 atomic registration swap can now proceed safely: `mod spike` deletion will not break test compilation because helpers + 2 spike tests already live in `mod tests` against production `WordyPhrasesLinter`.
- Promoted tests prove production `WordyPhrasesLinter::new(CORPUS)` constructs correctly, lints correctly across all 5 case regimes, and rewrites priority cleanly.
- Plan 04 gate tests (`proper_noun_iphone_does_not_trigger`, `word_boundary_no_midword_match`, `case_preservation_under_tr_locale`, `dialect_filter_drops_non_matching`) can reuse the 4 promoted helpers verbatim.

## Self-Check: PASSED

**Files verified to exist:**
- `harper-bridge/src/clarity.rs` — FOUND (modified)
- `.planning/phases/10-matcher-implementation/10-02-SUMMARY.md` — FOUND (this file)

**Commits verified to exist in git log:**
- `a9e27c0` (Task 1) — FOUND
- `f5a6125` (Task 2) — FOUND

**Acceptance criteria final state:**
- `fn make_merged_dict` count inside top-level mod tests: 1 (via awk between `#[cfg(test)]` and `mod spike`) ✓
- `fn title_case` total count: 2 (mod tests + mod spike) ✓
- `fn sentence_start` total count: 2 ✓
- `fn primary_replacement` total count: 2 ✓
- `fn case_preservation_five_regimes` total count: 2 ✓
- `fn priority_rewrite_no_default_leak` total count: 2 ✓
- `WordyPhrasesLinter::new(CORPUS)` count: 2 (one per promoted test) ✓
- `cargo test --lib`: 9 passed; 0 failed ✓

---
*Phase: 10-matcher-implementation*
*Completed: 2026-04-25*
