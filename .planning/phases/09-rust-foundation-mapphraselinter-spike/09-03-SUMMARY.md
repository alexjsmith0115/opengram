---
phase: 09-rust-foundation-mapphraselinter-spike
plan: 03
subsystem: rust
tags: [harper-core, uniffi, lint-group, clarity, wordy-phrases]

requires:
  - phase: 09-rust-foundation-mapphraselinter-spike/plan-02
    provides: "Severity FFI enum, priority constants (200/220/240), severity_from_priority helper"

provides:
  - "build_lint_group(merged, dialect) module-level fn — single source of LintGroup construction"
  - "WordyPhrasesStubLinter type with empty Linter impl in clarity.rs"
  - "Clarity linter registered under key WordyPhrases at construction time — survives dict-add by design"

affects: [09-04, 09-plan-04, matcher-implementation]

tech-stack:
  added: []
  patterns:
    - "build_lint_group mirrors build_merged_dict style: module-level pure fn, owned args, returns owned type"
    - "LintGroup construction centralized — never call LintGroup::new_curated directly from HarperChecker methods"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs

key-decisions:
  - "Single build_lint_group call site for LintGroup::new_curated — both HarperChecker::new and add_to_dictionary delegate to helper (D-23)"
  - "WordyPhrasesStubLinter.lint() returns Vec::new() — match logic intentionally deferred to plan 04"
  - "Stub description string neutral (no GSD phase refs) per global instruction"

patterns-established:
  - "LintGroup construction pattern: always via build_lint_group; never inline new_curated calls in impl blocks"

requirements-completed: [CLAR-12]

duration: 8min
completed: 2026-04-24
---

# Phase 9 Plan 03: build_lint_group Helper + WordyPhrasesStubLinter Skeleton Summary

**Single-source LintGroup construction: build_lint_group helper extracts twin new_curated call sites; WordyPhrasesStubLinter skeleton registered under key "WordyPhrases" — CLAR-12 clarity-survives-dict-add guaranteed by construction.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-24T23:11:00Z
- **Completed:** 2026-04-24T23:19:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `WordyPhrasesStubLinter` declared pub in clarity.rs with empty `Linter` impl (`lint()` → `Vec::new()`)
- `build_lint_group(merged, dialect) -> LintGroup` module-level fn added to lib.rs; registers stub under key `"WordyPhrases"`
- Twin `LintGroup::new_curated` call sites at `HarperChecker::new` (line 75) and `add_to_dictionary` (line 137) replaced with `build_lint_group` calls
- `LintGroup::new_curated` count in lib.rs: 2 → 1 (only inside helper body)
- `clarity_linter_survives_dict_add_cycle` and `stub_fires_flag_me` tests stay RED as designed — plan 04 fills match logic

## Task Commits

1. **Task 1: WordyPhrasesStubLinter skeleton** - `0b06580` (feat)
2. **Task 2: build_lint_group helper + twin call-site replacement** - `7555b3c` (feat)

## Files Created/Modified

- `harper-bridge/src/clarity.rs` — Added `WordyPhrasesStubLinter` struct + `Linter` impl (empty lint body)
- `harper-bridge/src/lib.rs` — Added `build_lint_group` fn; updated clarity import; replaced both `LintGroup::new_curated` call sites

## Decisions Made

- Stub `description()` uses neutral string with no GSD phase/plan refs per global CLAUDE.md instruction
- `Default` impl added alongside `new()` for idiomatic Rust (zero cost, enables `..Default::default()` patterns)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Plan 04 can import `WordyPhrasesStubLinter` from clarity and fill `lint()` with FLAG_ME token scan + Lint emission
- `build_lint_group` is the single wiring point — plan 04 only needs to change clarity.rs
- `stub_fires_flag_me` and `clarity_linter_survives_dict_add_cycle` tests pre-wired in lib.rs; flip GREEN when stub emits on FLAG_ME

---
*Phase: 09-rust-foundation-mapphraselinter-spike*
*Completed: 2026-04-24*
