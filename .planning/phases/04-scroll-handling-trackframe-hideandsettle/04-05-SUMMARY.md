---
phase: 04-scroll-handling-trackframe-hideandsettle
plan: 05
subsystem: overlay
tags: [tests, scrollmode, demotion, fade, perf-07, perf-08, perf-10]

requires:
  - phase: 04-04
    provides: ScrollState enum + internal visibility on scrollState/scrollTracker/hideSettleTimer/frameBudgetMisses/effectiveScrollMode/scrollAreaObserver/underlineView + 11 scroll methods
provides:
  - "recordFrameCost(elapsed:) internal test seam on OverlayController; recordFrameCost(start:) delegates"
  - "OverlayControllerScrollModeTests suite (6 Swift Testing cases) covering PERF-07/08/10"
affects: []

tech-stack:
  added: []
  patterns:
    - "Deterministic demotion tests via recordFrameCost(elapsed:) overload — injects elapsed time, bypasses CACurrentMediaTime wall clock"
    - "Async fade test polls view.alphaValue after NSAnimationContext animator group — model value updates on main run loop, not synchronously"

key-files:
  created:
    - OpenGramTests/SuggestionUITests/OverlayControllerScrollModeTests.swift
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram.xcodeproj/project.pbxproj
    - OpenGram/SuggestionUI/Settings/LLMSettingsView.swift
    - OpenGram/Generated/HarperBridge.swift
    - harper-bridge/src/lib.rs

key-decisions:
  - "Fade test switched from sync alphaValue assertion to async poll — NSAnimationContext's animator proxy updates model alphaValue via main-runloop driver, not synchronously inside runAnimationGroup. Plan's assumption that model value lands sync at group start was incorrect; poll with 1s budget is deterministic and still fast (typical resolution ~60ms for 80ms fade)."
  - "scrollPathCancels test in OverlayControllerRepositionTests NOT updated — it already calls dismiss() directly rather than synthesizing the closure body, so 04-04's closure swap from self?.dismiss() to self?.handleScrollEvent() does not invalidate the test. The 04-04 follow-up note was speculative."
  - "Stale 'Phase N' comments scrubbed from 3 files (LLMSettingsView.swift, HarperBridge.swift, harper-bridge/src/lib.rs) predating Phase 4. Rust source scrubbed alongside generated Swift so next UniFFI regen keeps the file clean. Project convention forbids GSD refs in source (memory: feedback_no_gsd_refs_in_source)."

patterns-established:
  - "Animated Swift AppKit tests poll the model property after the animator call — do not assume synchronous model update."

requirements-completed: [PERF-07, PERF-08, PERF-10]

duration: 4min
completed: 2026-04-19
---

# Phase 4 Plan 05: OverlayController Scroll-Mode Tests Summary

**OverlayController scroll state machine locked under 6 Swift Testing cases: unknown-bundle / com.apple.Notes mode resolution (PERF-07), hideAndSettle fade-to-0 + settle-resets-to-idle (PERF-08), 3-slow-frame trackFrame demotion via recordFrameCost(elapsed:) seam (PERF-10), full dismiss() teardown of tracker/timer/observer/state. recordFrameCost(elapsed:) overload added as deterministic test seam; recordFrameCost(start:) delegates.**

## Performance

- **Duration:** ~4 min
- **Tasks:** 3 (all planned tasks executed)
- **Files touched:** 5 (1 created, 4 modified — 1 controller, 1 pbxproj, 3 comment scrubs)
- **Lines added:** +133 (test file) / +9 (seam overload) / +3 (pbxproj refs) / -3 (comment scrubs)

## Accomplishments

- Added `recordFrameCost(elapsed: TimeInterval)` internal test-seam overload to OverlayController; `recordFrameCost(start: CFTimeInterval)` delegates. Demotion arithmetic now has a single home; tests inject exact elapsed durations without racing a wall clock.
- Created `OverlayControllerScrollModeTests` with exactly 6 `@Test` cases:
  1. `unknown bundle defaults to hideAndSettle` (PERF-07)
  2. `com.apple.Notes resolves to trackFrame` (PERF-07)
  3. `hideAndSettle scroll event fades underlines to 0 and sets .faded` (PERF-08) — poll-based alpha assertion
  4. `handleHideAndSettleComplete returns state to .idle and schedules .scrollSettled` (PERF-08)
  5. `3 consecutive slow frames demote trackFrame session to hideAndSettle` (PERF-10) — uses `recordFrameCost(elapsed:)` seam
  6. `dismiss tears down tracker/timer/observer and resets scroll state`
- Registered the test file in pbxproj with the established 4-hunk pattern (PBXBuildFile + PBXFileReference + group child + Sources build phase entry), using IDs `B10000010000000000000104` / `B20000010000000000000104`.
- Scrubbed 3 stale "Phase N" references predating Phase 4 to meet plan's GSD-ref gate:
  - `OpenGram/SuggestionUI/Settings/LLMSettingsView.swift`: "Phase 5 will embed" → "future work will embed"
  - `OpenGram/Generated/HarperBridge.swift` + `harper-bridge/src/lib.rs`: "Phase 3 can decide presentation" → "callers can decide presentation" (Rust source scrubbed alongside generated Swift so regen stays clean)
- Full `xcodebuild -scheme OpenGram build` green, zero warnings.
- Full `xcodebuild -scheme OpenGram test` run — all 6 new scroll-mode tests pass; pre-existing parallel-load flakes surfaced in 3 tests (see Known Flakes below).

## Task Commits

1. **Task 1 — feat: test seam overload:** `f26e346` (`feat(04-05): add recordFrameCost(elapsed:) test seam overload`)
2. **Task 2 — test: scroll mode tests:** `f98b989` (`test(04-05): add OverlayControllerScrollModeTests (6 cases, PERF-07/08/10)`)
3. **Task 3 — chore: strip GSD refs:** `0edd99a` (`chore(04-05): strip stale GSD phase refs from source comments`)

## Files Created/Modified

- **Created:** `OpenGramTests/SuggestionUITests/OverlayControllerScrollModeTests.swift` (+133 lines, 6 tests)
- **Modified:** `OpenGram/SuggestionUI/Overlay/OverlayController.swift` (+9 / -1 — seam overload)
- **Modified:** `OpenGram.xcodeproj/project.pbxproj` (+4 lines — test registration)
- **Modified:** `OpenGram/SuggestionUI/Settings/LLMSettingsView.swift` (comment scrub)
- **Modified:** `OpenGram/Generated/HarperBridge.swift` (comment scrub)
- **Modified:** `harper-bridge/src/lib.rs` (comment scrub)

## Decisions Made

- **Fade test uses async poll, not sync assertion.** Plan 05 originally specified `#expect(view.alphaValue == 0)` immediately after `handleScrollEvent()`, commenting that the model value lands synchronously at the start of `NSAnimationContext.runAnimationGroup`. That is incorrect — NSAnimationContext's animator proxy defers model writes to the main run loop. First run surfaced the issue: 5/6 pass, fade test failed with `view.alphaValue → 1.0`. Fix: convert the test to `async`, poll `view.alphaValue` with a 1s deadline (production fade duration is 0.08s; real runtime resolution observed at ~60ms). Production code unchanged.
- **`scrollPathCancels` test NOT updated.** 04-04 follow-up noted the test "likely needs update" since the scroll closure now calls `handleScrollEvent()` instead of `dismiss()`. Inspection of the actual test shows it calls `controller.currentRepositionTask?.cancel(); controller.dismiss()` directly on the controller — it does not synthesize the closure body. The assertion (cancelled task → applyBoundsCallCount == 0) remains valid under both closure bodies. No update required.
- **Rust source scrubbed alongside Swift generated file.** `harper-bridge/src/lib.rs` carries the same "Phase 3" comment that UniFFI propagates into `OpenGram/Generated/HarperBridge.swift`. Scrubbing only the Swift file would have been reverted by the next `build-harper.sh` regen. Both sources updated atomically.

## Deviations from Plan

- **[Rule 1 - Bug] Fade test sampling strategy corrected.** Plan specified synchronous `view.alphaValue == 0` assertion based on comment "NSAnimationContext animator sets the layer's presentation value asynchronously; the model value (alphaValue) is set synchronously at the start of the group." Behavior contradicts the comment — model value updates on the main run loop, not synchronously. Test converted to `async` with poll (10ms interval, 1s budget). Production code unchanged. Commit `f98b989`.
- **[Rule 3 - Blocking] Stale Phase N comments scrubbed.** Plan's Task 3 verify gate `! grep -rE "Phase [0-9]+( |:|\.)" OpenGram/ --include='*.swift'` failed on 2 pre-existing Phase refs unrelated to v1.3 Phase 4. Both scrubbed inline (Rust source + generated Swift) to unblock the gate. Commit `0edd99a`.

## Authentication Gates

None.

## Known Flakes (Deferred, Not Caused by This Plan)

Full-suite `xcodebuild test` surfaced 3 pre-existing timing flakes under parallel load. All pass in isolation; all pre-date Plan 05:

| Suite | Test | Status | Reason |
|-------|------|--------|--------|
| AXCallWatchdogTests | `shouldSkip returns true for bundle ID added to blocklist after timeout` | Pass solo / flake parallel | Documented in STATE.md Phase 04-01 decisions as pre-existing timing flake under parallel load |
| AXCallWatchdogTests | `blocklist entry expires after blocklistDuration and shouldSkip returns false` | Pass solo / flake parallel | Same pre-existing timing flake |
| TextMonitorStoreIntegrationTests | `keystroke schedules debounced reconcile — LLM request fires after debounce` | Pass solo / flake parallel | Debounce-window timing; not touched by this plan; lives in scheduler/store code paths post-Phase-20 |

All new Phase 4 tests (5 + 3 + 3 + 6 = 17) pass both solo and in the full suite. Flakes are out of scope per executor SCOPE BOUNDARY — not directly caused by this plan's changes.

## TDD Gate Compliance

Plan 04-05 is `type: execute` (not `type: tdd`); plan-level RED/GREEN/REFACTOR gate enforcement does not apply.

## Threat Model Compliance

Plan's `<threat_model>`:
- **T-04.05-01 (Tampering — test seam leaking to production):** Mitigated. `recordFrameCost(elapsed:)` is `internal`, reachable only via `@testable import`. Production call path is `recordFrameCost(start:)` → `recordFrameCost(elapsed:)` delegation. No attack surface on shipping binary.
- **T-04.05-02 (DoS — timer-backed test leaving runaway timer):** Mitigated. `dismiss_tearsDownScrollState` test assigns a 10s interval timer and immediately invalidates it via `dismiss()`. No runaway risk.

## Self-Check: PASSED

Verified:

- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — contains:
  - `func recordFrameCost(start: CFTimeInterval)` delegating to elapsed overload
  - `func recordFrameCost(elapsed: TimeInterval)` internal test seam
- `OpenGramTests/SuggestionUITests/OverlayControllerScrollModeTests.swift` — FOUND, contains:
  - `@Suite("OverlayController scroll mode")`
  - Exactly 6 `@Test(` occurrences
  - 6 test function signatures matching plan's Test 1-6
- `OpenGram.xcodeproj/project.pbxproj` — contains 4 registrations for `OverlayControllerScrollModeTests.swift`:
  - PBXBuildFile entry (line 62)
  - PBXFileReference entry (line 223)
  - Group child entry (line 697)
  - Sources build phase entry (line 945)
- Commit `f26e346` — FOUND (Task 1)
- Commit `f98b989` — FOUND (Task 2)
- Commit `0edd99a` — FOUND (Task 3)
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → BUILD SUCCEEDED, zero warnings
- `xcodebuild test -only-testing:OpenGramTests/OverlayControllerScrollModeTests` → 6 tests pass in 0.226s
- `! grep -rE "Phase [0-9]+( |:|\.)" OpenGram/ --include='*.swift'` → zero matches

## Next Phase Readiness

Phase 4 complete. All 5 plans shipped:
- 04-01: AppQuirks ScrollMode + allowlist (5 tests)
- 04-02: ScrollTracker CADisplayLink pump (3 tests)
- 04-03: ScrollAreaObserver programmatic-scroll AX observer (3 tests)
- 04-04: OverlayController scroll state machine + fade + demotion + AX observer wiring (0 new tests — this plan's scope)
- 04-05: OverlayController scroll-mode tests (6 tests) — THIS PLAN

PERF-07, PERF-08, PERF-09, PERF-10, PERF-11 all validated. v1.3 Milestone Phase 4 closes; next is Phase 5 (accept-time targeted rect invalidation + session-local mirror improvements per roadmap, or milestone close if Phase 5 was deferred).

---
*Phase: 04-scroll-handling-trackframe-hideandsettle*
*Completed: 2026-04-19*
