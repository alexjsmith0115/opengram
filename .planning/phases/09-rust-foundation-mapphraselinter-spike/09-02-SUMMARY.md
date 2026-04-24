---
phase: 09-rust-foundation-mapphraselinter-spike
plan: "02"
subsystem: harper-bridge/rust
tags: [tdd, green-gate, clarity, ffi, rust, severity]
dependency_graph:
  requires: [clarity-rs-scaffolding, ffi-test-stubs]
  provides: [severity-ffi-enum, clarity-category-variant, severity-field-ffi, overlap-priority-test]
  affects: [harper-bridge/src/clarity.rs, harper-bridge/src/lib.rs]
tech_stack:
  added: []
  patterns: [uniffi-enum-derive, uniffi-record-field, priority-range-guard]
key_files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs
decisions:
  - "LintKind::Style + priority∈{200,220,240} is the clarity routing guard (D-32) — belt-and-suspenders prevents harper-core's own Style lints (priority≤127) from being mis-tagged"
  - "severity_to_priority kept public despite dead_code warning — used by Phase 10 production matcher"
  - "Tasks 1+2 committed together — lib.rs test module from plan 01 references both Task 1 and Task 2 symbols; compilation required both to proceed"
metrics:
  duration: "~4min"
  completed: "2026-04-24T23:07:00Z"
  tasks_completed: 3
  files_changed: 2
requirements: [CLAR-11, CLAR-06]
---

# Phase 9 Plan 02: Severity FFI Enum + Priority Constants + Clarity Category Summary

**One-liner:** Severity { High/Medium/Low } UniFFI enum + priority constants (200/220/240) + SuggestionCategory::Clarity variant + GrammarSuggestion.severity field + FFI priority-range routing, with overlap-priority behavioral test proving CLAR-06 grammar-beats-clarity contract.

## What Was Built

Wave 1 GREEN gate. Implements all Rust-side CLAR-11 surface and seeds CLAR-06 behavioral proof.

### Files Modified

**`harper-bridge/src/clarity.rs`** — Three additions:

1. **Severity enum** with `uniffi::Enum` derive + `Clone, Copy, Debug, PartialEq, Eq`:
   ```rust
   #[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
   pub enum Severity { High, Medium, Low }
   ```

2. **Priority constants + helpers**:
   ```rust
   pub const PRIORITY_HIGH: u8 = 200;
   pub const PRIORITY_MEDIUM: u8 = 220;
   pub const PRIORITY_LOW: u8 = 240;
   pub fn severity_to_priority(sev: Severity) -> u8 { ... }
   pub fn severity_from_priority(prio: u8) -> Option<Severity> { ... }
   ```

3. **`clarity_loses_to_grammar_on_overlap` test** (Task 3 / ROADMAP SC-3):
   - Constructs two lints at span 0..7: grammar (priority 127, LintKind::Miscellaneous) + clarity (priority 220, LintKind::Style)
   - Calls `harper_core::remove_overlaps(&mut lints)` directly
   - Asserts `lints.len() == 1` and `lints[0].priority == 127` (grammar survived)
   - Proves CLAR-06 priority contract at the remove_overlaps boundary

**`harper-bridge/src/lib.rs`** — Four additions:

1. **Import**: `use clarity::{Severity, severity_from_priority};`

2. **SuggestionCategory::Clarity variant**:
   ```rust
   pub enum SuggestionCategory { Spelling, GrammarPunctuation, Clarity }
   ```

3. **GrammarSuggestion.severity field**:
   ```rust
   pub severity: Option<Severity>,
   ```

4. **FFI translation block** (replaces single `category` match):
   ```rust
   let (category, severity) = match (lint.lint_kind, severity_from_priority(lint.priority)) {
       (LintKind::Spelling, _) => (SuggestionCategory::Spelling, None),
       (LintKind::Style, Some(sev)) => (SuggestionCategory::Clarity, Some(sev)),
       _ => (SuggestionCategory::GrammarPunctuation, None),
   };
   ```

## Test Results

### GREEN (this plan)

```
running 3 tests
test clarity::tests::clarity_loses_to_grammar_on_overlap ... ok
test clarity::tests::severity_enum ... ok
test clarity::tests::severity_round_trip ... ok

test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured
```

### Still RED (expected — owned by later plans)

- `lib::tests::stub_fires_flag_me` — stub linter not registered yet (plan 04 owns `build_lint_group` + `WordyPhrasesStubLinter`)
- `lib::tests::clarity_linter_survives_dict_add_cycle` — same (plan 04)
- `clarity::spike::case_preservation_five_regimes` — plan 06
- `clarity::spike::priority_rewrite_no_default_leak` — plan 06
- `OpenGramTests/ClarityFFITests::stubRoundTrip` — Swift test (plan 05 after XCFramework rebuild)

### Build

`cargo build --lib` exits 0. One `dead_code` warning on `severity_to_priority` — intentional public API, used by Phase 10 production matcher.

## Deviations from Plan

**1. [Rule 3 - Blocking] Tasks 1+2 committed together instead of separately**
- **Found during:** Task 1 verification
- **Issue:** `lib.rs` test module from plan 01 references `SuggestionCategory::Clarity` (Task 2) and `severity` field (Task 2). Compilation fails until both tasks are done — impossible to run `clarity::tests` in isolation.
- **Fix:** Implemented Task 2 immediately after Task 1, committed both in one `feat(09-02)` commit.
- **Files modified:** `harper-bridge/src/clarity.rs`, `harper-bridge/src/lib.rs`
- **Commit:** `b24d57b`

No other deviations. Plan executed per spec otherwise.

## Known Stubs

None in plan 02 scope. `WordyPhrasesStubLinter` (the stub linter registered via `build_lint_group`) is plan 04's deliverable — not present yet, and its absence is expected/correct at this stage.

## Threat Flags

None — plan 02 is pure Rust enum/constant/helper additions with no new network surface, auth paths, or schema changes at trust boundaries.

## Self-Check

### Files Exist

```
FOUND: harper-bridge/src/clarity.rs
FOUND: harper-bridge/src/lib.rs
```

### Commits Exist

```
b24d57b feat(09-02): implement Severity enum + priority constants + SuggestionCategory::Clarity + severity FFI field
a585683 test(09-02): add clarity_loses_to_grammar_on_overlap behavioral test (ROADMAP SC-3 / CLAR-06)
```

## Self-Check: PASSED
