---
phase: 01-ax-call-queue
plan: "03"
subsystem: accessibility
tags: [swift, actor, overlay, dependency-injection, performance]

requires:
  - phase: 01-ax-call-queue/01-02
    provides: "AXCallQueue actor with bounds/boundsBatch/elementBounds async throws entry points"

provides:
  - "OverlayController.init accepts optional axQueue: AXCallQueue? = nil for DI"
  - "OverlayController stores private let axQueue: AXCallQueue (default-constructed from injected accessor)"

affects:
  - Phase 2 (Cancellable Bounds Queries) — injects AXCallQueue test double and introduces currentRepositionTask

tech-stack:
  added: []
  patterns:
    - "DI seam via trailing defaulted param — axQueue: AXCallQueue? = nil preserves all 27+ existing call sites unchanged"
    - "Default-construct pattern: axQueue ?? AXCallQueue(accessor: accessor) reuses injected accessor, test determinism preserved"

key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift

key-decisions:
  - "axQueue field stored but unused this phase (D-09) — Phase 2 introduces first invocation via currentRepositionTask"

patterns-established:
  - "Trailing defaulted actor DI param: add AXCallQueue? = nil last so all partial-arg call sites compile without modification"

requirements-completed: [PERF-01]

duration: 5min
completed: "2026-04-18"
---

# Phase 1 Plan 03: OverlayController AXCallQueue Init Seam Summary

**`private let axQueue: AXCallQueue` stored in OverlayController via trailing defaulted DI param; all 27+ call sites compile unchanged; D-09 invariant holds (zero self.axQueue. invocations)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-19T01:18:00Z
- **Completed:** 2026-04-19T01:21:17Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Three surgical edits to `OverlayController.swift`: stored property, init param, init body assignment
- D-09 verified: `grep -c "self\.axQueue\."` returns 0 exactly
- All existing call sites compile unchanged (trailing defaulted param, no changes required)
- Build succeeded; AXCallQueue + AXCallWatchdog suites green in isolation (parallel-suite timing flakes pre-existing, documented in 01-02 SUMMARY)

## Task Commits

1. **Task 1: Extend OverlayController init + stored property for axQueue** - `e6f7cec` (refactor)

**Plan metadata:** TBD (docs commit below)

## Files Created/Modified
- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — added `private let axQueue: AXCallQueue` property, `axQueue: AXCallQueue? = nil` init param, `self.axQueue = axQueue ?? AXCallQueue(accessor: accessor)` assignment

## Decisions Made
- No new decisions. Followed D-08/D-09 from 01-CONTEXT exactly: field present, unused this phase.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `AXCallWatchdogTests` + `TextMonitorStoreIntegrationTests` failed in full parallel suite run — confirmed pre-existing timing flakes (identical to 01-02 SUMMARY pattern, both pass in isolation). Not caused by this plan's change.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 complete: AXCallWatchdog busy-guard removed (01-01), AXCallQueue actor created (01-02), OverlayController owns one per instance (01-03)
- Phase 2 (Cancellable Bounds Queries) can now inject test doubles via `axQueue:` param and introduce `currentRepositionTask`
- No blockers

## Self-Check: PASSED

- FOUND: `OpenGram/SuggestionUI/Overlay/OverlayController.swift` (modified)
- FOUND: `private let axQueue: AXCallQueue` in OverlayController
- FOUND: `axQueue: AXCallQueue? = nil` in init signature
- FOUND: `self.axQueue = axQueue ?? AXCallQueue(accessor: accessor)` in init body
- FOUND: D-09 grep returns 0
- FOUND: commit `e6f7cec` (refactor — task 1)

---
*Phase: 01-ax-call-queue*
*Completed: 2026-04-18*
