---
phase: 12-settings-ui-severity-filter-acknowledgements
plan: 02
subsystem: check-engine
tags: [harper, severity-filter, swift-actor, userdefaults, swift-testing, ffi]

requires:
  - phase: 11-dataset-integration-fixture-harness
    provides: HarperBridge.WordyPhrases rule + Severity enum (.high/.medium/.low) emitted by Rust crate
provides:
  - "HarperService.shouldDropClarityLow(_:opinionatedEnabled:) — nonisolated static predicate"
  - "HarperService.check(text:) post-processing filter for clarity .low when opinionated flag off"
  - "HarperService.init(... defaults: UserDefaults = .standard) — DI for testing"
  - "5 new HarperServiceTests: 4 severity-filter unit + 1 ruleTogglingWordyPhrases integration"
affects: [12-03 (settings UI writes clarityOpinionatedEnabled), 12-04 (acknowledgements layer reads filtered output)]

tech-stack:
  added: []
  patterns:
    - "Swift-side post-processing filter on actor — keeps Rust crate stateless (CLAR-18)"
    - "Pre-read UserDefaults into local before filter closure — avoids @Sendable capture rejection under Swift 6 strict concurrency"
    - "nonisolated static predicate on actor for unit-testable pure logic without actor hop"

key-files:
  created: []
  modified:
    - OpenGram/CheckEngine/Harper/HarperService.swift
    - OpenGramTests/HarperServiceTests.swift

key-decisions:
  - "Filter lives in Swift, not Rust — preserves CLAR-18 contract (Rust stays stateless)"
  - "UserDefaults injected via init with .standard default — AppDelegate call site untouched, source-compatible"
  - "Predicate guards source==.harper && category==.clarity && severity==.low — never drops non-clarity, never drops .high/.medium"
  - "Live UserDefaults read on each check() invocation — toggle takes effect on next check, no restart, no caching"

patterns-established:
  - "Severity-filter pattern: read flag → filter mapped suggestions → return; predicate is nonisolated static for testing"

requirements-completed: [CLAR-08, CLAR-18, CLAR-07]

duration: 6min
completed: 2026-04-25
---

# Phase 12 Plan 02: Harper Severity Filter Summary

**Swift-side severity filter on HarperService.check() drops clarity .low suggestions when opinionated flag off; Rust crate untouched (CLAR-18); 5 new tests including WordyPhrases FFI integration.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-25T06:13:00Z
- **Completed:** 2026-04-25T10:18:41Z
- **Tasks:** 2 (both TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- `nonisolated static shouldDropClarityLow` predicate on HarperService — testable without actor hop, guards all 3 conditions explicitly (CLAR-08, CLAR-18)
- `check(text:)` reads `clarityOpinionatedEnabled` from `defaults` pre-filter; live read so toggle takes effect on next check without restart
- `UserDefaults` constructor injection with `.standard` default — AppDelegate call site source-compatible (no edit needed)
- 5 new Swift Testing tests: 4 unit (drops/keeps low, preserves high/medium, never touches non-clarity) + 1 integration (`ruleTogglingWordyPhrases` mirrors `ruleTogglingSpellCheck` for CLAR-07 FFI verification)
- Rust crate untouched — filter is pure Swift post-processing, honors CLAR-18

## Task Commits

Each task committed atomically per TDD gate sequence:

1. **Task 1: Add severity-filter unit tests (RED)** — `fdee2a0` (test)
2. **Task 2: Implement severity filter + UserDefaults injection (GREEN)** — `3e50feb` (feat)

## Files Created/Modified

- `OpenGram/CheckEngine/Harper/HarperService.swift` — added `import Foundation`, `defaults` private + init param, pre-filter UserDefaults read, `nonisolated static shouldDropClarityLow` predicate
- `OpenGramTests/HarperServiceTests.swift` — appended `makeClaritySuggestion`/`makeSpellingSuggestion` helpers + 5 new `@Test` funcs

## Verification

- `xcodebuild test -only-testing:OpenGramTests/HarperServiceTests`: **15/15 PASS** (5 new + 10 existing)
- `xcodebuild build`: **SUCCEEDED**
- All acceptance grep checks pass (predicate signature, defaults storage, key string, filter call site, guard expression, Foundation import)
- `grep -rn "GSD\|Phase 12\|Plan 0" OpenGram/CheckEngine/Harper/HarperService.swift` → 0 matches (no GSD refs in source)
- `grep -rn "clarityOpinionatedEnabled" OpenGram/` → 1 match (HarperService read site; Plan 03 will add @AppStorage write site)
- AppDelegate.swift line 18 (`HarperService(dictionaryStore:dialect:)` call) UNCHANGED — default-param compat works as designed

## Decisions Made

- Used integration-grade live UserDefaults read inside `check()` rather than caching — phase goal explicitly requires toggle to take effect on next check without restart; caching would defeat that
- Predicate placed as `nonisolated static` on `HarperService` (not free function) for namespace cohesion + future-proofing if predicate gains additional dependencies on actor-internal state

## Deviations from Plan

None — plan executed exactly as written. Both tasks completed in spec'd order with intended RED→GREEN TDD progression.

## Issues Encountered

**Worktree environment setup:**
- Worktree was missing `.planning/phases/12-settings-ui-severity-filter-acknowledgements/` (Plan 12 artifacts not yet propagated from main). Resolved by copying the entire phase directory from main `.planning/`. Not a code change.
- Worktree was missing `HarperBridge.xcframework` (gitignored binary, lives only in main checkout). Resolved by copying the framework into the worktree. Symlink first attempted but xcodebuild does not resolve framework symlinks; hard copy required. xcframework remains gitignored — not committed.
- Build cache from main checkout pointed at main paths; resolved by passing `-derivedDataPath /tmp/opengram-worktree-derived` to isolate worktree build state.

**Pre-existing test failures (out-of-scope):**
- Full-suite `xcodebuild test` produced 6 failures in unrelated subsystems (AXCallWatchdog timing, ScrollTracker timing, OverlayController scroll mode alpha, LLMService localhost timeouts). All 6 are pre-existing on base commit `6b1f45e`, none touch HarperService. Logged in `deferred-items.md` per execute-plan.md scope-boundary rules.

## TDD Gate Compliance

- RED gate (`fdee2a0` test): commit precedes implementation; verified with `xcodebuild test` showing `Type 'HarperService' has no member 'shouldDropClarityLow'` (5 occurrences, one per new test)
- GREEN gate (`3e50feb` feat): commit follows RED; verified with `xcodebuild test` showing all 15 HarperServiceTests pass
- REFACTOR gate: not exercised — implementation already minimal and SRP-clean per plan spec

## User Setup Required

None — no external service configuration. UserDefaults key `clarityOpinionatedEnabled` defaults to `false`, which is the intended out-of-box behavior (Low clarity suggestions hidden by default per CLAR-08). Plan 03 will add the @AppStorage write site in the settings UI.

## Threat Flags

None — Plan 12-02's STRIDE register (T-12-02-01..03) covered all introduced surface. No new boundaries: filter is pure local Swift, no FFI calls beyond pre-existing setRuleEnabled, no network, no secrets.

## Next Plan Readiness

- Plan 12-03 (Settings UI) can now wire `@AppStorage("clarityOpinionatedEnabled")` toggle — HarperService will pick it up on the next `check()` automatically
- Plan 12-04 (Acknowledgements) gets pre-filtered Suggestion array; doesn't need to re-implement severity gating
- Wave 1 parallel-safe contract held: only `HarperService.swift` + `HarperServiceTests.swift` modified; zero overlap with Plan 01 or Plan 04 file sets

## Self-Check: PASSED

Files exist:
- FOUND: OpenGram/CheckEngine/Harper/HarperService.swift
- FOUND: OpenGramTests/HarperServiceTests.swift
- FOUND: .planning/phases/12-settings-ui-severity-filter-acknowledgements/12-02-SUMMARY.md

Commits exist:
- FOUND: fdee2a0 (test RED)
- FOUND: 3e50feb (feat GREEN)

---
*Phase: 12-settings-ui-severity-filter-acknowledgements*
*Plan: 02*
*Completed: 2026-04-25*
