---
phase: 10-matcher-implementation
plan: 04
subsystem: clarity
tags: [rust, harper-bridge, clarity, gate-tests, tr-locale, dialect-filter]

requires:
  - phase: 10-matcher-implementation
    plan: 01
    provides: PhraseEntry + CORPUS + WordyPhrasesLinter at module scope
  - phase: 10-matcher-implementation
    plan: 02
    provides: 4 promoted test helpers (make_merged_dict, primary_replacement, title_case, sentence_start)
  - phase: 10-matcher-implementation
    plan: 03
    provides: build_lint_group dialect-filtered registration; HarperChecker public surface stable
provides:
  - 3 new clarity.rs gate tests (proper-noun, word-boundary, tr_TR locale)
  - 1 new lib.rs gate test (dialect-filter end-to-end)
  - 11-test cargo --lib green baseline closing Phase 10 acceptance gates
affects: [10-05-phase-gate, 11-dataset-integration]

tech-stack:
  added: []
  patterns:
    - "Manual env-var save/restore around tr_TR set_var (no serial_test dep) per D-08"
    - "Dialect-filter contract test via HarperChecker('US') vs HarperChecker('GB') exercising build_lint_group filter end-to-end"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs

key-decisions:
  - "Edition 2021 keeps std::env::set_var safe — no unsafe block needed in tr_TR test. If Cargo.toml moves to 2024 edition this test must wrap set_var in unsafe per RESEARCH Pitfall 3."
  - "Synthetic 'forthwith' CORPUS entry (Plan 01, dialects: Some(&[American])) is intentionally NOT in wordy_phrases.toml so Phase 11 TOML wire-up cannot override its dialect tag — preserves dialect-filter test integrity across phase boundaries."
  - "Dialect-filter test counts on primary_replacement == Some('at once') to isolate the synthetic entry from any harper-core curated lint that may co-fire on 'Please forthwith now.'"

patterns-established:
  - "Phase 10 gate-test set covers CLAR-01/CLAR-03/CLAR-04/CLAR-05/CLAR-06/CLAR-15/CLAR-N4 via 11 cargo tests"

requirements-completed: [CLAR-03, CLAR-05, CLAR-06]

duration: ~3min
completed: 2026-04-25
---

# Phase 10 Plan 04: Gate Tests Against Wired WordyPhrasesLinter Summary

**4 gate tests added (3 clarity.rs, 1 lib.rs) covering proper-noun non-trigger, mid-word boundary safety, tr_TR locale ASCII preservation, and dialect-filter end-to-end. cargo test --lib 11/11 green.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-25 (resume after first commit)
- **Completed:** 2026-04-25
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `proper_noun_iphone_does_not_trigger` (clarity.rs) — asserts "iPhone is great." emits zero clarity lints (CLAR-03 token-shape contract)
- `word_boundary_no_midword_match` (clarity.rs) — asserts "The unaccompanied luggage arrived." emits zero clarity lints despite CORPUS entry "accompany" appearing as substring (CLAR-05 SC-3 token-window contract)
- `case_preservation_under_tr_locale` (clarity.rs) — sets LANG/LC_ALL = tr_TR.UTF-8, runs UPPER CASE regime over 21-entry CORPUS, asserts ASCII-correct replacements (no İ/ı drift), restores env vars on exit (CLAR-N4 / Phase 10 SC-6)
- `dialect_filter_drops_non_matching` (lib.rs) — HarperChecker("US") fires synthetic "forthwith → at once" exactly once; HarperChecker("GB") emits zero matches (CLAR-15 / D-05 build_lint_group dialect-filter end-to-end)
- `cargo test --lib` 11/11 green: 8 clarity.rs mod tests + 3 lib.rs mod tests
- No new dependencies added (no `serial_test` per D-08; no `unsafe` per edition 2021)

## Task Commits

1. **Task 1: Add proper_noun_iphone_does_not_trigger + word_boundary_no_midword_match** — `f318856` (test)
2. **Task 2: Add case_preservation_under_tr_locale** — `0c57eb7` (test)
3. **Task 3: Add dialect_filter_drops_non_matching** — `530287b` (test)

## Files Created/Modified

- `harper-bridge/src/clarity.rs` — +51 LoC across two commits: 3 new gate tests inside `mod tests`
- `harper-bridge/src/lib.rs` — +26 LoC: 1 new gate test inside `mod tests`

## Decisions Made

- **Followed plan verbatim** — every test body matches the plan's `<action>` block byte-for-byte after copy-paste.
- **No carrier-sentence substitution needed** — `word_boundary_no_midword_match` passed first try; harper-core PlainEnglish tokenizer treats "unaccompanied" as a single Word token, MapPhraseLinter token-window matcher correctly skips it.
- **No `serial_test` dep** — per D-08, no other tests in `harper-bridge` read LANG/LC_ALL, so manual save/restore inside `case_preservation_under_tr_locale` is sufficient.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Plan 05 (phase gate D-35) can now run final Phase 10 verification: cargo green + xcodebuild green + ClarityFFI parity + build-harper.sh idempotency check.
- Phase 11 (dataset integration) can replace CORPUS const with TOML-parsed `Vec<PhraseEntry>` without touching gate tests — they read CORPUS via const slice import which will become a `static OnceLock` reference in Phase 11.
- All Phase 10 ROADMAP success criteria (SC1–SC6) covered by the 11-test gate set.

## Self-Check: PASSED

**Files verified to exist:**
- `harper-bridge/src/clarity.rs` — FOUND (modified)
- `harper-bridge/src/lib.rs` — FOUND (modified)
- `.planning/phases/10-matcher-implementation/10-04-SUMMARY.md` — FOUND (this file)

**Commits verified to exist in git log:**
- `f318856` (Task 1: test) — FOUND
- `0c57eb7` (Task 2: test) — FOUND
- `530287b` (Task 3: test) — FOUND

**Acceptance criteria final state:**
- `fn proper_noun_iphone_does_not_trigger` count in clarity.rs: 1 ✓
- `fn word_boundary_no_midword_match` count in clarity.rs: 1 ✓
- `fn case_preservation_under_tr_locale` count in clarity.rs: 1 ✓
- `fn dialect_filter_drops_non_matching` count in lib.rs: 1 ✓
- `set_var("LANG"` count in clarity.rs: 2 (set + reset) ✓
- `set_var("LC_ALL"` count in clarity.rs: 2 ✓
- `remove_var(` count in clarity.rs: 2 ✓
- `HarperChecker::new("GB"` count in lib.rs: 1 ✓
- `forthwith` count in lib.rs: 1 ✓
- No `unsafe` block in clarity.rs ✓
- `cargo test --lib`: 11 passed; 0 failed ✓

---
*Phase: 10-matcher-implementation*
*Completed: 2026-04-25*
