---
phase: 01-ax-call-queue
plan: "02"
subsystem: accessibility
tags: [swift, actor, concurrency, axcallqueue, performance, testing]

requires:
  - phase: 01-ax-call-queue/01-01
    provides: "AXCallWatchdog.shouldSkip is blocklist-only — no busy-guard to block concurrent queue calls"

provides:
  - "AXCallQueue actor serializes AX reads off main actor via FIFO isolation"
  - "bounds/boundsBatch/elementBounds async throws entry points with cooperative cancellation"
  - "TextEngineTests group in OpenGramTests target for future TextEngine test files"

affects:
  - 01-ax-call-queue/01-03 (OverlayController init — will inject AXCallQueue via defaulted param)

tech-stack:
  added: []
  patterns:
    - "Actor-isolated AX serialization: AXCallQueue actor provides FIFO ordering without a busy-guard"
    - "boundsBatch: Task.checkCancellation() + Task.yield() per item for cooperative cancellation and fair scheduling"
    - "elementBounds: watchdog.beginCall/endCall wraps each raw AX read for hang detection coverage (D-06)"

key-files:
  created:
    - OpenGram/TextEngine/AXCallQueue.swift
    - OpenGramTests/TextEngineTests/AXCallQueueTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "makeSuggestion/makeAXRectValue helpers inlined in test file per D-10 — OverlayControllerTests versions are private"
  - "Suggestion.primaryReplacement is String? and priority is UInt8 — test helper adjusted from plan template accordingly"

patterns-established:
  - "AXCallQueue init DI pattern: accessor/validator/watchdog all defaulted to shared singletons, overridable in tests"
  - "TextEngineTests PBXGroup established as home for future TextEngine-layer test files"

requirements-completed: [PERF-01]

duration: 15min
completed: "2026-04-18"
---

# Phase 1 Plan 02: AXCallQueue Actor Summary

**AXCallQueue Swift actor serializes AX bounds reads off main via FIFO isolation with cooperative cancellation; 4 Swift Testing cases green (PERF-01)**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-18T21:08:00Z
- **Completed:** 2026-04-18T21:23:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- `actor AXCallQueue` with `bounds`, `boundsBatch`, `elementBounds` — all `async throws` with `Task.checkCancellation()` at entry and between iterations
- `elementBounds` wraps both raw AX reads in `watchdog.beginCall/endCall` per D-06; entry-gate via `watchdog.shouldSkip`
- 4 Swift Testing cases: `boundsBatchSuccess`, `boundsBatchCancellation`, `elementBoundsSuccess`, `elementBoundsFailure` — all pass
- `TextEngineTests` PBXGroup created under `OpenGramTests`; both files registered in `project.pbxproj`; `plutil -lint` OK

## Task Commits

1. **Task 1: Create AXCallQueue actor** - `3e222c4` (feat)
2. **Task 2: Create AXCallQueueTests** - `111dfe7` (test)
3. **Task 3: Register in pbxproj** - `0ce329a` (chore)

## Files Created/Modified
- `OpenGram/TextEngine/AXCallQueue.swift` — actor with 3 async throws entry points; 94 lines
- `OpenGramTests/TextEngineTests/AXCallQueueTests.swift` — @Suite("AXCallQueue") with 4 @Test functions; 109 lines
- `OpenGram.xcodeproj/project.pbxproj` — 2 fileRefs, 2 buildFile entries, TextEngineTests group, 2 Sources build phase entries

## Decisions Made
- `Suggestion.primaryReplacement` is `String?` (not `String`) and `priority` is `UInt8` — plan's test template had wrong types; corrected in implementation
- `makeSuggestion` and `makeAXRectValue` helpers inlined per D-10 since `OverlayControllerTests` counterparts are `private`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected Suggestion init types in test helper**
- **Found during:** Task 2 (AXCallQueueTests creation)
- **Issue:** Plan's `makeSuggestion` template used `primaryReplacement: String` and `priority: Int`; actual `Suggestion` struct declares `primaryReplacement: String?` and `priority: UInt8`
- **Fix:** Updated `makeSuggestion` helper to match actual struct — `primaryReplacement` passed as `String` (implicitly converted to `String?`), `priority: 5` as `UInt8`-compatible literal
- **Files modified:** `OpenGramTests/TextEngineTests/AXCallQueueTests.swift`
- **Verification:** `xcodebuild test` passes; all 4 tests green
- **Committed in:** `111dfe7` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — type mismatch in plan template)
**Impact on plan:** Correctness fix only. No scope change.

## Issues Encountered
- `TextMonitorStoreIntegrationTests` timing flake surfaced again in full parallel suite run (1 test in that suite failed) — confirmed pre-existing by running in isolation (8/8 pass). Documented in 01-01 SUMMARY. Not caused by this plan's changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `AXCallQueue` actor ready for Plan 01-03 to inject into `OverlayController.init` via defaulted `axQueue: AXCallQueue?` parameter
- No blockers

---
*Phase: 01-ax-call-queue*
*Completed: 2026-04-18*
