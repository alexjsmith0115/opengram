---
phase: 09-rust-foundation-mapphraselinter-spike
plan: "01"
subsystem: harper-bridge/rust + OpenGramTests
tags: [tdd, red-gate, clarity, ffi, rust, swift]
dependency_graph:
  requires: []
  provides: [clarity-rs-scaffolding, ffi-test-stubs, swift-clarity-test]
  affects: [harper-bridge/src/lib.rs, OpenGramTests]
tech_stack:
  added: []
  patterns: [cfg(test)-mod-tests, swift-testing-suite]
key_files:
  created:
    - harper-bridge/src/clarity.rs
    - OpenGramTests/ClarityFFITests.swift
  modified:
    - harper-bridge/src/lib.rs
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Plan 01 ships test scaffolding only — no impl. RED state is the goal."
  - "clarity.rs uses mod clarity; declared from lib.rs after setup_scaffolding!()"
  - "ClarityFFITests.swift registered with UUIDs B2...0015 (ref) + B1...0015 (build file)"
metrics:
  duration: "~10min"
  completed: "2026-04-24T22:58:35Z"
  tasks_completed: 3
  files_changed: 4
requirements: [CLAR-11, CLAR-12, CLAR-13]
---

# Phase 9 Plan 01: Failing Test Scaffolding (RED Gate) Summary

**One-liner:** RED-gate test scaffolding for Severity FFI round-trip + stub-fires + dict-add-cycle + spike hard gates, compile-failing until Wave 1 impl lands.

## What Was Built

Wave 0. Locked behavior contract via failing test stubs before any implementation. All tests compile-error on missing symbols — intentional TDD RED state.

### Files Created

**`harper-bridge/src/clarity.rs`** — New module containing ONLY test scaffolding:
- `#[cfg(test)] mod tests`: `severity_enum` + `severity_round_trip` tests referencing unimplemented `Severity`, `PRIORITY_*`, `severity_to_priority`, `severity_from_priority`
- `#[cfg(test)] mod spike`: `case_preservation_five_regimes` + `priority_rewrite_no_default_leak` stubs (assert false, plan 06 fills)

**`OpenGramTests/ClarityFFITests.swift`** — Swift test file:
- `@Suite("Clarity FFI Surface")` with `stubRoundTrip` asserting `FLAG_ME` → `.clarity` + `.medium` + `"FLAGGED"` through full FFI stack
- Compile-RED: `value of type 'Suggestion' has no member 'severity'`

### Files Modified

**`harper-bridge/src/lib.rs`** — Two changes:
1. Added `mod clarity;` after `uniffi::setup_scaffolding!()`
2. Appended `#[cfg(test)] mod tests` block with `stub_fires_flag_me` + `clarity_linter_survives_dict_add_cycle`

**`OpenGram.xcodeproj/project.pbxproj`** — Three additions:
- PBXBuildFile `B10000010000000000000015` for ClarityFFITests.swift
- PBXFileReference `B20000010000000000000015` for ClarityFFITests.swift
- Entry in OpenGramTests group + Sources build phase

## RED State Proof

### Rust (`cargo test -p harper-bridge`)

```
error[E0432]: unresolved import `crate::clarity::Severity`
error[E0425]: cannot find value `PRIORITY_HIGH` in this scope
error[E0425]: cannot find value `PRIORITY_MEDIUM` in this scope
error[E0425]: cannot find value `PRIORITY_LOW` in this scope
error[E0425]: cannot find function `severity_to_priority` in this scope
error[E0425]: cannot find function `severity_from_priority` in this scope
error[E0433]: failed to resolve: use of undeclared type `Severity`
... (28 total compile errors)
error: could not compile `harper-bridge` (lib test) due to 24 previous errors
```

28 errors across clarity.rs and lib.rs tests. All reference symbols absent until plan 02.

### Swift (`xcodebuild build-for-testing`)

```
/Users/alex/Dev/opengram/OpenGramTests/ClarityFFITests.swift:19:32:
error: value of type 'Suggestion' has no member 'severity'
    #expect(clarity.first?.severity == .medium, "severity must round-trip as .medium")
```

Confirmed: ClarityFFITests.swift is compiled by the test target, registered correctly in pbxproj, and produces the exact expected RED error.

### Lib build passes (expected)

`cargo build --lib` succeeds — `#[cfg(test)]` blocks excluded from lib compilation. RED only manifests under `cargo test`.

## No Impl Written

Confirmed: `clarity.rs` contains zero impl code. All functions/types referenced in tests are absent. `lib.rs` tests module references `SuggestionCategory::Clarity` and `severity` field which don't exist in the FFI structs yet.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

### Files Exist
- [x] `harper-bridge/src/clarity.rs` — FOUND
- [x] `OpenGramTests/ClarityFFITests.swift` — FOUND

### Commits Exist
- [x] `8a4d6ca` — test(09-01): add failing clarity.rs test scaffolding (RED gate)
- [x] `346520b` — test(09-01): add failing CLAR-11/CLAR-12 regression tests in lib.rs (RED gate)
- [x] `fd5b729` — test(09-01): add ClarityFFITests.swift + pbxproj registration (RED gate)

## Self-Check: PASSED
