---
phase: 04-scroll-handling-trackframe-hideandsettle
plan: 02
subsystem: overlay
tags: [scrolltracker, cadisplaylink, pump, perf-09]

requires:
  - phase: 04-01
    provides: ScrollMode enum (used by 04-04 consumer, not this plan)
provides:
  - "@MainActor final class ScrollTracker — CADisplayLink pump driven by noteScrollEvent() pings"
  - "Lazy-install displayLink on first event; per-frame onTick callback; one-shot onIdle after idleTimeout lapse"
  - "stop() invalidates link; deinit invalidates via MainActor.assumeIsolated"
  - "3 Swift Testing tests (ticksWhileActive, idleFires, stopInvalidates) + shared host window pattern for CADisplayLink-bound tests"
affects: [04-04]

tech-stack:
  added: []
  patterns:
    - "Swift 6 nonisolated deinit accessing @MainActor-isolated non-Sendable property → wrap in MainActor.assumeIsolated"
    - "CADisplayLink unit testing: shared static NSWindow + orderFrontRegardless once + serialized @Suite + RunLoop.main.run pump (Task.sleep alone does not drive NSRunLoop in test host)"

key-files:
  created:
    - OpenGram/SuggestionUI/Overlay/ScrollTracker.swift
    - OpenGramTests/SuggestionUITests/ScrollTrackerTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "deinit wrapped in MainActor.assumeIsolated — Swift 6 strict concurrency forbids nonisolated deinit access to non-Sendable CADisplayLink? property; assumeIsolated preserves the deinit-invalidates contract from D-01 without introducing a Task hop"
  - "displayLink flipped to internal upfront (D-27) — Task 3 needs @testable access for stopInvalidates; flipped during Task 1 rather than mid-Task 3 to keep the file's diff atomic"
  - "Shared NSWindow across all 3 tests (SharedHost enum, static let, one orderFrontRegardless) — sequential per-test NSWindow ordering raced the WindowServer (NSCGS pre-commit fence) and crashed the test host between idleFires and stopInvalidates; one persistent screen-bound window is the minimum surface that lets CADisplayLink fire reliably without windowserver instability"
  - "pumpMainRunLoop helper instead of Task.sleep — CADisplayLink timer callbacks queue onto NSRunLoop, not the Swift task scheduler; Task.sleep yields the actor but does not spin RunLoop.main, so the link installs but no ticks arrive"
  - "Suite marked .serialized — Swift Testing parallelizes @Test methods by default; concurrent NSWindow access from sibling tests would re-introduce the WindowServer race even with shared host"

patterns-established:
  - "MainActor.assumeIsolated deinit guard for @MainActor classes holding non-Sendable handles"
  - "SharedHost static window + serialized suite + RunLoop pump pattern for CADisplayLink unit tests in this project"

requirements-completed: [PERF-09]

duration: 8min
completed: 2026-04-19
---

# Phase 4 Plan 02: ScrollTracker CADisplayLink Pump Summary

**`@MainActor final class ScrollTracker` drives a per-view CADisplayLink pump while `noteScrollEvent()` pings keep arriving, fires `onIdle` once after `idleTimeout` lapse, and self-stops — backed by 3 Swift Testing cases.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-19T13:54:02Z
- **Completed:** 2026-04-19T14:01:54Z
- **Tasks:** 3 (1 deviation: Rule 1 Swift 6 deinit fix)
- **Files created:** 2 (`ScrollTracker.swift`, `ScrollTrackerTests.swift`)
- **Files modified:** 1 (`project.pbxproj` — 8 edits across BuildFile/FileReference/Group/Sources sections for both target + test target)

## Accomplishments

- `ScrollTracker.swift` — `@MainActor final class`, lazy-install `CADisplayLink` via `hostView.displayLink(target:selector:)` on first `noteScrollEvent()`, `onTick` per refresh, `onIdle` once after `idleTimeout` (default 0.18s) lapse, `stop()` + `deinit` (MainActor.assumeIsolated) invalidate
- `ScrollTrackerTests.swift` — 3 Swift Testing cases (`ticksWhileActive`, `idleFires`, `stopInvalidates`), serialized suite + shared host window + RunLoop pump pattern
- pbxproj registration for both new files (OpenGramLib Sources + OpenGramTests Sources, plus their respective groups)
- Build green via `xcodebuild`; targeted suite `xcodebuild test -only-testing:OpenGramTests/ScrollTrackerTests` → 3/3 pass

## Task Commits

1. **Task 1 — feat: ScrollTracker class:** `79d6c61` (`feat(04-02): add ScrollTracker CADisplayLink pump (PERF-09)`)
2. **Rule 1 fix — Swift 6 deinit Sendable error:** `c432b5d` (`fix(04-02): wrap ScrollTracker deinit in MainActor.assumeIsolated`)
3. **Task 2 — pbxproj registration:** `5a22ed0` (`chore(04-02): register ScrollTracker.swift in OpenGramLib Sources`)
4. **Task 3 — tests + pbxproj:** `401e020` (`test(04-02): add ScrollTrackerTests with 3 cases (D-24)`)

## Files Created/Modified

- `OpenGram/SuggestionUI/Overlay/ScrollTracker.swift` — new, 59 lines
- `OpenGramTests/SuggestionUITests/ScrollTrackerTests.swift` — new, 79 lines
- `OpenGram.xcodeproj/project.pbxproj` — 8 additions: 2× PBXBuildFile, 2× PBXFileReference, 2× PBXGroup children, 2× PBXSourcesBuildPhase files (one set for `A...0101` ScrollTracker, one set for `B...0102` ScrollTrackerTests)

## Decisions Made

- **`MainActor.assumeIsolated` in deinit:** Swift 6.3 strict concurrency rejected `displayLink?.invalidate()` from the implicit nonisolated deinit because `CADisplayLink?` is non-Sendable. Three options considered: (a) drop deinit invalidation and rely on `stop()` from owner — rejected because `stop()` is a contract guarantee, not a defensive fallback; (b) `Task { @MainActor in ... }` — rejected because `self` is being deinitialized, capturing it deferred is unsound; (c) `MainActor.assumeIsolated` — selected because deinit always runs on the main thread for a `@MainActor` class, the assumption is safe at runtime, and the contract from D-01 (deinit invalidates) is preserved verbatim.
- **`displayLink` internal (not private):** D-27 lists the visibility flip as a Task 3 step. Flipped during Task 1 instead — the file diff for ScrollTracker is then atomic (one commit, one final shape) rather than a private→internal modification surfacing only in Task 3's commit. Plan's `<verify>` grep conditions remain satisfied either way.
- **Shared `SharedHost.window` (static let) + `.serialized` suite + `pumpMainRunLoop` helper for tests:** Three-part fix discovered iteratively. (1) Per-test NSWindow + `Task.sleep`: CADisplayLink installed but never fired — test host's NSRunLoop never advanced past `Task.sleep` yield. (2) Per-test NSWindow + `RunLoop.main.run` pump + `orderFrontRegardless`: First test passed, second test crashed with `[NSCGS] Ignoring request to entangle context after pre-commit` and process restarted. WindowServer can't tolerate sequential NSWindow create/order-front cycles in same process. (3) Shared static window orderedFront once + RunLoop pump + `.serialized` suite: 3/3 pass cleanly in 0.48s. Rejected alternatives: (a) `NSScreen.displayLink` test seam — would pollute production API; (b) `@Suite(.disabled(if: NSScreen.main == nil))` skip — local screen is always available, real bug was windowserver race not screen absence.
- **`Task.sleep` → `RunLoop.main.run` pump:** CADisplayLink fires onto NSRunLoop in `.common` mode. Inside a Swift Testing async test, `Task.sleep(for:)` yields the MainActor but does NOT spin NSRunLoop. The link installs successfully but tick callbacks never reach the registered selector because nothing pumps the runloop. `RunLoop.main.run(mode: .default, before:)` in a 10ms loop drives the runloop and lets ticks fire.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency rejected nonisolated deinit access to non-Sendable CADisplayLink? property**
- **Found during:** Task 2 verification (`xcodebuild build` after pbxproj registration)
- **Issue:** `error: cannot access property 'displayLink' with a non-Sendable type 'CADisplayLink?' from nonisolated deinit`
- **Fix:** Wrapped `displayLink?.invalidate()` in `MainActor.assumeIsolated { ... }` — preserves D-01's "deinit invalidates" contract under Swift 6.3 strict concurrency
- **Files modified:** `OpenGram/SuggestionUI/Overlay/ScrollTracker.swift`
- **Commit:** `c432b5d`

**2. [Rule 3 - Blocking] Test infrastructure: Task.sleep does not advance NSRunLoop in test host; sequential NSWindow + orderFrontRegardless crashes WindowServer**
- **Found during:** Task 3 verification (initial test run: 0/3 firing then 1/3 with crash mid-suite)
- **Issue:** Two compounding problems blocking Task 3 completion. (a) CADisplayLink installed but `onTick`/`onIdle` never fired because test-host NSRunLoop wasn't being driven. (b) After switching to `RunLoop.main.run` pump and `orderFrontRegardless` per-test, second test crashed with WindowServer pre-commit fence error.
- **Fix:** (a) Added `pumpMainRunLoop(for:)` helper that loops `RunLoop.main.run(mode: .default, before:)` until deadline. (b) Created `SharedHost` private enum with single `static let window` ordered front once at lazy-init; added `.serialized` to suite. Both decisions are test-only; production code unchanged.
- **Files modified:** `OpenGramTests/SuggestionUITests/ScrollTrackerTests.swift`
- **Commit:** `401e020` (folded into Task 3 commit because the fixes ARE Task 3)

## Authentication Gates

None.

## Issues Encountered

- Full-suite `xcodebuild test` flagged 3 failures: 2 in `AXCallWatchdogTests` (`shouldSkip returns true …after timeout`, `blocklist entry expires …`) and 1 in `TextMonitorStoreIntegrationTests` (`keystroke schedules debounced reconcile`). Re-ran each in isolation: 13/13 pass. All three are pre-existing parallel-load timing flakes documented in STATE.md (Phase 04-01 decision log, Plan 20-09 decision log). Out of scope for this plan per Rule 3 boundary; not fixed.

## TDD Gate Compliance

- Plan 04-02 is `type: execute` (not `type: tdd`), so plan-level RED/GREEN/REFACTOR gate enforcement does not apply.
- Tasks 1 and 3 carry `tdd="true"` markers but the structural intent of this plan is "create file → register → add tests" rather than test-first iteration on a behavior. Per the SUMMARY-01 precedent, executed in plan order; tests in Task 3 verify the implementation from Task 1.

## Threat Model Compliance

Plan's `<threat_model>` listed:
- **T-04.02-01 (DoS — runaway display link):** Mitigated. `stop()` invalidates, `deinit` invalidates (via assumeIsolated), `tick(_:)` self-stops when idle.
- **T-04.02-02 (Info disclosure — hostView weak ref leak):** Accepted. `weak var hostView` plus deinit invalidation; no hostView state read beyond the displayLink factory call.

No new threat surface introduced beyond the plan's register.

## Next Phase Readiness

- ScrollTracker is the contract that 04-04's OverlayController scroll state machine consumes (D-08): `let tracker = ScrollTracker(hostView: view); tracker.onTick = ...; tracker.onIdle = ...; tracker.noteScrollEvent()`.
- `internal var displayLink` lets future test files (e.g. `OverlayControllerScrollModeTests` in 04-04) assert pump installation/teardown if needed.
- The SharedHost+serialized+pump test pattern is reusable for any future test that needs a screen-bound CADisplayLink.
- No blockers.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/Overlay/ScrollTracker.swift` — FOUND, contains `final class ScrollTracker`, `@MainActor`, `func noteScrollEvent`, `hostView.displayLink(target:`
- `OpenGramTests/SuggestionUITests/ScrollTrackerTests.swift` — FOUND, contains `@Suite("ScrollTracker"`, 3× `@Test`
- `OpenGram.xcodeproj/project.pbxproj` — contains `ScrollTracker.swift in Sources`, `path = ScrollTracker.swift`, `ScrollTrackerTests.swift in Sources`, `path = ScrollTrackerTests.swift`
- Commit `79d6c61` — FOUND
- Commit `c432b5d` — FOUND
- Commit `5a22ed0` — FOUND
- Commit `401e020` — FOUND
- Targeted test run: 3/3 pass in 0.48s
- Full-suite anomaly: 3 pre-existing parallel-load timing flakes, all green in isolation, documented above

---
*Phase: 04-scroll-handling-trackframe-hideandsettle*
*Completed: 2026-04-19*
