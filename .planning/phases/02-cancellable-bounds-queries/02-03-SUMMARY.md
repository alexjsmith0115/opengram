---
phase: 02-cancellable-bounds-queries
plan: "03"
subsystem: testing
tags: [testing, overlay, concurrency, cancellation, performance]

dependency_graph:
  requires:
    - phase: 02-01
      provides: currentRepositionTask, applyBoundsCallCount, scheduleReposition, RepositionReason
    - phase: 02-02
      provides: SlowMockAXAccessor test helper
  provides:
    - OverlayControllerRepositionTests (5 cases locking PERF-03 + PERF-04)
  affects: []

tech_stack:
  added: []
  patterns:
    - "await task?.value as deterministic terminal-state gate — works for both completed and cancelled Task<Void, Never>"
    - "applyBoundsCallCount spy counter as cancellation oracle — no wall-clock race, pure state assertion"
    - "SlowMockAXAccessor(delay: .milliseconds(N)) as cancellation window opener — synchronous sleep per AX call"
    - "Inlined private helpers (makeSuggestion, makeAXRectValue, makeTextContext) — file-private originals in OverlayControllerTests.swift not accessible"

key_files:
  created:
    - OpenGramTests/SuggestionUITests/OverlayControllerRepositionTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj

key_decisions:
  - "Used Option C (applyBoundsCallCount spy) for cancellation verification — idiomatic, deterministic, matches OPENGRAM_PERFORMANCE_SPEC template"
  - "scrollPathCancels tests closure body literally (cancel + dismiss) rather than synthesizing NSEvent — global monitors only fire for other-process events, making synthesis unreachable from unit tests"
  - "Inlined helper functions rather than sharing — OverlayControllerTests helpers are file-private; D-10 precedent from prior plan"

metrics:
  duration: 3min
  completed: 2026-04-19T05:18:00Z
  tasks_completed: 3
  files_changed: 2

requirements: [PERF-03, PERF-04]
---

# Phase 02 Plan 03: OverlayControllerRepositionTests Summary

5 Swift Testing cases locking PERF-03 + PERF-04 via `applyBoundsCallCount` spy + `await task?.value` terminal-state gate. `SlowMockAXAccessor(delay: .milliseconds(50))` opens deterministic cancellation windows.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Write OverlayControllerRepositionTests with 5 cases | bbc3df7 | OpenGramTests/SuggestionUITests/OverlayControllerRepositionTests.swift |
| 2 | Register in pbxproj | 2e8883f | OpenGram.xcodeproj/project.pbxproj |
| 3 | Run targeted + full test suite | — | (validation only) |

## Test Results

**Targeted run** (`-only-testing:OpenGramTests/OverlayControllerRepositionTests`): 5/5 passed.

| Test | Duration | Result |
|------|----------|--------|
| cancellation during reposition aborts before bounds are applied | 2.544s | PASS |
| acceptSuggestion cancels currentRepositionTask | 0.321s | PASS |
| dismiss cancels currentRepositionTask | 0.320s | PASS |
| scroll-path dismiss cancels currentRepositionTask | 0.319s | PASS |
| no task leaks across rapid scheduleReposition sequence | 0.815s | PASS |

**Full suite**: 468 tests, 73 suites. 1 pre-existing failure (`TextMonitorStoreIntegrationTests` — LLM localhost:1234 timeout; confirmed pre-existing on clean HEAD, documented in 02-01 and 02-02 summaries).

## pbxproj Registration

4 entries added:
- `PBXBuildFile`: `B10000010000000000000051` (OverlayControllerRepositionTests.swift in Sources)
- `PBXFileReference`: `B20000010000000000000051` (OverlayControllerRepositionTests.swift)
- `PBXGroup` child: `B4000001000000000000000A` (SuggestionUITests — alphabetical after OverlayControllerTests)
- Sources build phase entry in `B60000010000000000000001`

`plutil -lint` exits 0. OverlayControllerRepositionTests.swift appears 4 times in pbxproj.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — test-only code, no production data flows.

## Threat Flags

None — test-only code, no new production surface.

## Self-Check

- [x] `OpenGramTests/SuggestionUITests/OverlayControllerRepositionTests.swift` exists
- [x] Exactly 5 `@Test(` annotations
- [x] `@Suite("OverlayController reposition")` present
- [x] `SlowMockAXAccessor(delay:`, `scheduleReposition(reason:`, `applyBoundsCallCount`, `currentRepositionTask` all referenced
- [x] No "Phase N" / "Plan N" strings in test source
- [x] `plutil -lint` exits 0; file appears 4 times in pbxproj
- [x] Targeted run: 5/5 passed, `** TEST SUCCEEDED **`
- [x] Commits bbc3df7 + 2e8883f exist in git log

## Self-Check: PASSED
