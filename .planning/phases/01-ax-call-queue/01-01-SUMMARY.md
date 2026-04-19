---
phase: 01-ax-call-queue
plan: "01"
subsystem: accessibility
tags: [swift, axcallwatchdog, performance, testing]

requires: []
provides:
  - "AXCallWatchdog.shouldSkip gates only on blocklist; busy-guard branch removed"
  - "Watchdog test suite locked to new non-skip-during-in-flight contract (5 tests)"
affects:
  - 01-ax-call-queue/01-02 (AXCallQueue actor — relies on shouldSkip not blocking concurrent calls)

tech-stack:
  added: []
  patterns:
    - "shouldSkip is blocklist-only; call serialization delegated to AXCallQueue actor"

key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Accessibility/AXCallWatchdog.swift
    - OpenGramTests/SuggestionUITests/AXCallWatchdogTests.swift

key-decisions:
  - "Busy-guard branch deleted from shouldSkip; activeCall/beginCall/endCall/checkForHang preserved byte-identical — hang detection still runs"
  - "Pre-existing TextMonitorStoreIntegrationTests timing flake confirmed as pre-existing (passes in isolation, flaky under parallel full-suite load)"

patterns-established:
  - "AXCallWatchdog.shouldSkip: blocklist-only gating pattern for PERF-02 compliance"

requirements-completed: [PERF-02]

duration: 4min
completed: "2026-04-18"
---

# Phase 1 Plan 01: Remove AXCallWatchdog Busy-Guard Summary

**Busy-guard branch deleted from AXCallWatchdog.shouldSkip; blocklist-only gating established; test contract locked via replacement Swift Testing test**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-18T21:02:57Z
- **Completed:** 2026-04-18T21:07:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Deleted `if let call = activeCall` busy-guard block from `shouldSkip(for:)` — method now returns `true` only for blocklisted bundles
- `activeCall`, `beginCall`, `endCall`, `checkForHang`, hang timer all preserved byte-identical — hang-to-blocklist path unaffected
- Replaced `busyGuardSkipsWhileCallInFlight` test with `shouldSkipReturnsFalseDuringInFlightCall` — both the in-flight bundle and other bundles assert `false`; 5/5 watchdog tests green

## Task Commits

1. **Task 1: Remove busy-guard branch** - `c47e6b1` (refactor)
2. **Task 2: Swap busy-guard test** - `fe8f26a` (test)

## Files Created/Modified
- `OpenGram/SuggestionUI/Accessibility/AXCallWatchdog.swift` — shouldSkip reduced to blocklist-only; doc comment updated
- `OpenGramTests/SuggestionUITests/AXCallWatchdogTests.swift` — busyGuardSkipsWhileCallInFlight deleted; shouldSkipReturnsFalseDuringInFlightCall added

## Decisions Made
- Preserved `activeCall` and all hang-detection code unchanged — Plan 01-02 AXCallQueue still needs `shouldSkip` to check blocklist before dispatching, and hang detection feeds that blocklist
- Pre-existing `TextMonitorStoreIntegrationTests` timing flake (debounce test, fails under parallel load, passes in isolation) is out of scope — noted in deferred items

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- CodeSign failure on first `xcodebuild test` invocation — transient Xcode signing state; resolved with `CODE_SIGNING_ALLOWED=NO` (standard for test runs in this project)
- `TextMonitorStoreIntegrationTests.keystroke schedules debounced reconcile` failed in full parallel suite run — confirmed pre-existing flake by running in isolation (passes) and checking git log (last touched in edec49c before this plan)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `AXCallWatchdog.shouldSkip` unblocked for Plan 01-02: concurrent AX calls from `AXCallQueue` will not be dropped as "busy"
- No blockers

---
*Phase: 01-ax-call-queue*
*Completed: 2026-04-18*
