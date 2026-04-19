---
phase: 02-cancellable-bounds-queries
plan: "01"
subsystem: ui
tags: [swift, concurrency, task-cancellation, overlay, performance, ax]

requires:
  - phase: 01-ax-call-queue
    provides: AXCallQueue actor with boundsBatch + cooperative cancellation via Task.checkCancellation()

provides:
  - currentRepositionTask (internal) — stored Task<Void, Never>? on OverlayController
  - applyBoundsCallCount (internal) — test-spy counter on OverlayController
  - RepositionReason enum (internal) — 4 cases: initial, scrollDuring, scrollSettled, textChanged
  - scheduleReposition(reason:) (internal) — cancels prior task, spawns new reposition campaign
  - reposition(reason:) async (private) — reads textContext, awaits axQueue.boundsBatch, checks isCancelled
  - suggestionsForReposition (private placeholder) — prefix(maxDisplayedSuggestions)
  - applyBounds (private placeholder) — increments applyBoundsCallCount spy counter
  - clearUnderlines (private helper) — sets underlineView?.entries = []
  - Cancel hooks at: acceptSuggestion first line, dismiss() first line, scrollMonitor closure first line

affects: [02-02, 02-03, 04-scroll-state-machine]

tech-stack:
  added: []
  patterns:
    - "Task { [weak self] in await self?.method() } for @MainActor-isolated async work — matches storeSubscriptionTask pattern"
    - "applyBoundsCallCount as test-spy counter (internal visibility) — enables @testable cancellation assertions without protocol indirection"
    - "scheduleReposition cancel-before-assign — ensures exactly one in-flight reposition task at any time"

key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift

key-decisions:
  - "currentRepositionTask and scheduleReposition are internal (not private) — @testable import does not pierce private; tests in 02-03 need direct access"
  - "applyBounds body is a spy counter only this revision — production rendering wired in later work (D-07)"
  - "show() synchronous bounds loop untouched per D-12 — conversion to async scheduleReposition(.initial) deferred to scroll state machine work"
  - "Silent catch {} in reposition — CancellationError expected; other errors rare until scroll path is production-active (D-05)"
  - "3 cancel sites: accept/dismiss/scroll — scroll cancel precedes dismiss() so no stale task runs after teardown (PERF-04)"

patterns-established:
  - "Cancel-before-assign: currentRepositionTask?.cancel() then assign new Task — prevents task accumulation"
  - "Test spy via internal counter — simpler than protocol/mock indirection for single-assertion use case"

requirements-completed: [PERF-03, PERF-04]

duration: 15min
completed: 2026-04-19
---

# Phase 02 Plan 01: Reposition Infra Summary

**Cancellable reposition campaign infrastructure on OverlayController — Task+enum+5 methods+3 cancel hooks, zero production behavior change**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-19T05:05:00Z
- **Completed:** 2026-04-19T05:20:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Added `currentRepositionTask: Task<Void, Never>?` and `applyBoundsCallCount: Int` as internal stored properties
- Added `RepositionReason` enum with all 4 cases (initial/scrollDuring/scrollSettled/textChanged) for forward-compat
- Added full reposition campaign: `scheduleReposition` → `reposition(async)` → `axQueue.boundsBatch` → `applyBounds`
- Wired `currentRepositionTask?.cancel()` as first statement in `acceptSuggestion`, `dismiss()`, and scroll monitor closure
- Build clean, no new test failures (3 pre-existing flaky timing tests in AXCallWatchdog + TextMonitorStore confirmed pre-existing)

## Task Commits

1. **Task 1: Add reposition infra to OverlayController** — `43a6e0d` (feat)
2. **Task 2: Build + full test suite validation** — no files changed (validation only)

## Files Created/Modified

- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — +90 lines: new MARK Reposition section + 2 stored properties + 3 cancel hooks

## Decisions Made

- Used `internal` (default) visibility for `currentRepositionTask`, `applyBoundsCallCount`, `scheduleReposition`, and `RepositionReason` — `@testable import` exposes `internal` but not `private`; tests in plan 02-03 require direct access
- `applyBounds` body is a spy counter only — avoids wiring unfinished rendering logic; production rendering deferred to viewport culling work
- No `MainActor.run` wrapper in `reposition` — controller is `@MainActor`-bound so all instance methods run on main actor automatically

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - CLAUDE.md compliance] Removed "Plan 02-03" reference from source comment**
- **Found during:** Task 1 post-edit verification
- **Issue:** Comment `/// Plan 02-03 asserts ...` violated `feedback_no_gsd_refs_in_source` memory rule (no Phase N/Plan N in source)
- **Fix:** Replaced with `/// The cancellation test asserts ...`
- **Files modified:** OpenGram/SuggestionUI/Overlay/OverlayController.swift
- **Verification:** `grep -nE "(Phase|Plan)[[:space:]]+[0-9]"` returns no matches
- **Committed in:** 43a6e0d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (CLAUDE.md compliance)
**Impact on plan:** Non-functional comment wording only. No scope change.

## Issues Encountered

3 pre-existing flaky test failures confirmed unrelated to this plan:
- `AXCallWatchdogTests` — 2 timing-sensitive blocklist expiry tests (fail on clean HEAD too)
- `TextMonitorStoreIntegrationTests` — 1 LLM debounce timing test (fails on clean HEAD too)

## Next Phase Readiness

- Plan 02-02 can add `SlowMockAXAccessor` test helper and `OpenGramTests/TestHelpers/` dir
- Plan 02-03 can write `OverlayControllerRepositionTests` — all internal members accessible via `@testable import OpenGramLib`
- `scheduleReposition` has no production caller yet (D-12) — scroll state machine work will wire it

---
*Phase: 02-cancellable-bounds-queries*
*Completed: 2026-04-19*
