---
phase: 04-scroll-handling-trackframe-hideandsettle
plan: 04
subsystem: overlay
tags: [overlay, scroll-state-machine, fade, demotion, ax-observer, perf-07, perf-08, perf-09, perf-10, perf-11]

requires:
  - phase: 04-01
    provides: ScrollMode enum + AppQuirk.scrollMode field + bundled allowlist
  - phase: 04-02
    provides: ScrollTracker @MainActor class (CADisplayLink pump)
  - phase: 04-03
    provides: ScrollAreaObserver @MainActor class (programmatic-scroll AX observer)
provides:
  - "OverlayController.ScrollState enum (.idle/.scrolling/.faded) — internal"
  - "Stored props: scrollState, scrollTracker, hideSettleTimer, frameBudgetMisses, effectiveScrollMode, scrollAreaObserver — all internal per D-27"
  - "Constants: frameBudget=0.012s, frameBudgetMissLimit=3, hideAndSettleDelay=0.15s"
  - "11 new methods: resolveScrollMode, handleScrollEvent, handleScrollTick, handleScrollIdle, handleScrollEvent_hideAndSettle, resetHideSettleTimer, handleHideAndSettleComplete, recordFrameCost, demoteToHideAndSettle, fadeUnderlines, findScrollAreaAncestor"
  - "show() scroll monitor closure routes via handleScrollEvent (no direct dismiss)"
  - "show() installs ScrollTracker for trackFrame mode + ScrollAreaObserver if ancestor found"
  - "applyBounds fade-in on .scrollSettled when alpha != 1 (idempotent)"
  - "dismiss() full scroll-state teardown before existing body"
  - "reposition() catch split: CancellationError silent, others logged via Self.logger"
  - "underlineView visibility flipped private→internal per D-27"
affects: [04-05]

tech-stack:
  added: []
  patterns:
    - "Per-app scroll mode resolution at show() time via AppQuirksTable lookup; missing entries default hideAndSettle"
    - "Frame-budget demotion with miss decay on good frames (self-healing for transient hitches)"
    - "Timer.scheduledTimer + Task { @MainActor } weak-self chain for hideAndSettle debounce"
    - "10-level cycle-safe AX parent walk for ancestor lookup"

key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift

key-decisions:
  - "Tasks 1+2 merged into single feat commit because the scroll monitor closure (Task 1) calls handleScrollEvent / findScrollAreaAncestor / resolveScrollMode (Task 2) — splitting would create build-broken intermediate commits, violating plan's <verify> gate. Tasks 3, 4, 5 each as separate commits since each extends an existing method with isolated, build-safe hunks."
  - "pid binding already at show() top scope (line 251) — no hoist required; both TargetAppObserver and ScrollAreaObserver installs reach the same pid binding via outer if-let."
  - "All scroll handlers, fade primitive, and ancestor lookup placed in dedicated MARK block between freshElementBounds and rebuildUnderlineEntries — keeps reposition/applyBounds together, scroll machinery cohesive."
  - "Self.logger reused for D-22 (existing private static Logger declared at top of OverlayController) — no new Logger subsystem needed."

patterns-established:
  - "Atomic-commit-per-task plans bend to multi-task commits when hunks have build-time co-dependencies; final commit always builds clean."

requirements-completed: [PERF-07, PERF-08, PERF-09, PERF-10, PERF-11]

duration: 6min
completed: 2026-04-19
---

# Phase 4 Plan 04: OverlayController Scroll State Machine Summary

**OverlayController gains full per-app scroll state machine: trackFrame (CADisplayLink-pumped reposition with frame-budget demotion) and hideAndSettle (fade→debounce→reposition→fade-in) selected via AppQuirks; programmatic-scroll AXObserver catches arrow keys + find-nav + scrollToVisible: that NSEvent monitor misses; full session teardown on dismiss.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-19T14:14:02Z
- **Completed:** 2026-04-19T14:20:24Z
- **Tasks:** 5 (planned) → 4 commits (Tasks 1+2 merged for build-safety)
- **Files modified:** 1 (`OverlayController.swift`)
- **Lines added:** +200 / -9

## Accomplishments

- `ScrollState` enum + 6 stored props + 3 constants added to OverlayController
- `underlineView` flipped from `private var` → `var` per D-27 (test access for alpha assertions)
- `show()` scroll monitor closure replaced: routes through `handleScrollEvent()` instead of direct dismiss
- `show()` installs `ScrollTracker` for trackFrame mode and `ScrollAreaObserver` on nearest `kAXScrollAreaRole` ancestor when found
- 11 new methods covering full state machine: routing (`handleScrollEvent`), trackFrame (`handleScrollTick`/`handleScrollIdle`), hideAndSettle (`handleScrollEvent_hideAndSettle`/`resetHideSettleTimer`/`handleHideAndSettleComplete`), demotion (`recordFrameCost`/`demoteToHideAndSettle`), fade primitive (`fadeUnderlines`), ancestor lookup (`findScrollAreaAncestor`), mode resolution (`resolveScrollMode`)
- `applyBounds` extended with idempotent fade-in branch on `.scrollSettled`
- `dismiss()` extended with full scroll teardown (tracker stop, timer invalidate, observer uninstall, state zeroing)
- `reposition()` catch split: `CancellationError` silent vs other errors logged via existing `Self.logger`
- `xcodebuild build` green at every commit

## Task Commits

1. **Tasks 1+2 — feat: state machine core:** `b13a679` (`feat(04-04): add scroll state machine + handlers + fade + ancestor lookup`)
2. **Task 3 — feat: applyBounds fade-in:** `f879758` (`feat(04-04): applyBounds fade-in branch on .scrollSettled`)
3. **Task 4 — feat: dismiss teardown:** `8958832` (`feat(04-04): dismiss() full scroll-state teardown`)
4. **Task 5 — fix: catch split:** `f078b5b` (`fix(04-04): split reposition() catch — log non-cancellation errors`)

## Files Created/Modified

- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — +200/−9 lines across 4 commits

## Decisions Made

- **Tasks 1+2 merged into one commit:** Plan's Task 1 includes the show() scroll monitor closure replacement that calls `handleScrollEvent()`, `findScrollAreaAncestor()`, and `resolveScrollMode()` — all of which are added in Task 2. Splitting Tasks 1 and 2 would produce a build-broken intermediate commit, violating the plan's own `<verify>` clause requiring `xcodebuild build` succeed at Task 5. Merged as a single `feat` commit covering the foundational state machine. Tasks 3, 4, 5 remained separate because each extends an existing method with a self-contained hunk that builds independently. Precedent: Phase 04-01 SUMMARY documents the same TDD-RED+GREEN merger when two adjacent tasks have build-time co-dependencies.
- **pid binding hoist NOT required:** Plan Task 1 noted the `pid` binding might need hoisting so both observer installs could reach it. Inspection shows the existing `let pid = NSRunningApplication...processIdentifier` is at show() top scope (line 251), well above both observer install sites. Both observer installs use the `if let pid` guard pattern correctly. No hoist needed.
- **Self.logger for D-22:** OverlayController already has a private static `Logger(subsystem: ..., category: "OverlayController")` at line 20. Plan's D-22 said "use existing Logger or add one per convention" — existing one matches; no new logger added.
- **Scroll handler MARK placement:** All 11 new scroll-state methods + resolveScrollMode + fadeUnderlines + findScrollAreaAncestor live in a single dedicated `// MARK: - Scroll state machine (PERF-07/08/09/10/11)` block placed between `freshElementBounds` (cull helper) and `rebuildUnderlineEntries` (existing helper). Keeps reposition/cull/apply cluster intact and groups all scroll machinery cohesively.

## Deviations from Plan

None — plan executed as written. Multi-task commit merger documented above is a build-safety choice, not a deviation from plan content; all hunks landed verbatim per plan specification.

## Authentication Gates

None.

## Issues Encountered

None blocking. Build succeeded at every commit; no test runs invoked this plan per plan's explicit deferral of full-suite gate to Plan 05 Task 3.

## TDD Gate Compliance

Plan 04-04 is `type: execute` (not `type: tdd`); plan-level RED/GREEN/REFACTOR gate enforcement does not apply. Tests for this work land in Plan 05.

## Threat Model Compliance

Plan's `<threat_model>` listed:
- **T-04.04-01 (DoS — runaway trackFrame pump in slow app):** Mitigated. PERF-10 demotion (`recordFrameCost` → `demoteToHideAndSettle` after 3 frames > 12ms) self-heals via good-frame decay (`max(0, frameBudgetMisses - 1)`).
- **T-04.04-02 (DoS — runaway hideSettleTimer after dismiss):** Mitigated. `dismiss()` invalidates timer; Timer callback uses weak-self → `Task { @MainActor in self?.handleHideAndSettleComplete() }`. Nil self short-circuits.
- **T-04.04-03 (Tampering — ScrollAreaObserver from another app):** Accepted. AXObserver is PID-scoped at install; PID sourced from NSRunningApplication with intended bundleID.
- **T-04.04-04 (Info disclosure — reposition error log payload):** Mitigated. Error description logged with `privacy: .public` — non-sensitive failure string only, no PII paths.
- **T-04.04-05 (Elevation — AX element ancestor walk):** Accepted. `findScrollAreaAncestor` depth-capped at 10; cycle-safe; read-only operations.

No new threat surface introduced beyond the plan's register.

## Next Phase Readiness

- Plan 04-05 (tests + manual validation) consumes this plan's full surface: `ScrollState`, `effectiveScrollMode`, `scrollState`, `frameBudgetMisses`, `scrollTracker`, `scrollAreaObserver`, `underlineView` — all internal-visibility per D-27 for @testable assertions.
- Plan 04-05 Task 3 is the canonical full-suite `xcodebuild test` gate for the phase.
- The existing `OverlayControllerTests.scrollPathCancels` test (Phase 2) asserted the literal closure body `self?.dismiss()` — that test will need updating in Plan 05 since the closure now calls `self?.handleScrollEvent()`. Documented in plan's `<verification>` note for Plan 05 to address.
- No blockers.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — FOUND, contains:
  - `enum ScrollState` (line 76)
  - `var scrollState: ScrollState = .idle` (line 84)
  - `var scrollTracker: ScrollTracker?`
  - `var scrollAreaObserver: ScrollAreaObserver?`
  - `var underlineView: UnderlineView?` (no `private` qualifier)
  - `static let frameBudget: TimeInterval = 0.012`
  - `static let frameBudgetMissLimit = 3`
  - `static let hideAndSettleDelay: TimeInterval = 0.15`
  - `func resolveScrollMode(bundleID: String) -> ScrollMode`
  - `func handleScrollEvent()`, `func handleScrollTick()`, `func handleScrollIdle()`
  - `func handleScrollEvent_hideAndSettle()`, `func resetHideSettleTimer()`, `func handleHideAndSettleComplete()`
  - `func recordFrameCost(start: CFTimeInterval)`, `func demoteToHideAndSettle()`
  - `func fadeUnderlines(to alpha: CGFloat, duration: TimeInterval)`
  - `func findScrollAreaAncestor(_ element: AXUIElement) -> AXUIElement?`
  - `self?.handleScrollEvent()` (scroll monitor closure body)
  - `scrollTracker?.stop()` in dismiss()
  - `hideSettleTimer?.invalidate()` in dismiss()
  - `scrollAreaObserver?.uninstall()` in dismiss()
  - `effectiveScrollMode = .hideAndSettle` (dismiss reset)
  - `catch is CancellationError`
  - `Self.logger.error("reposition failed:` ...
  - `if reason == .scrollSettled, underlineView?.alphaValue != 1` (applyBounds fade-in)
  - `fadeUnderlines(to: 1, duration: 0.12)` (applyBounds fade-in body)
- Negative greps confirmed:
  - `! grep -q "private var underlineView"` → 0 matches
  - `! grep -q "scheduleReposition(reason: .initial)"` → 0 matches (show() sync loop untouched, D-23)
  - `! grep -E "Phase [0-9]|Plan [0-9]"` in source → 0 matches (no GSD refs)
- Commit `b13a679` — FOUND
- Commit `f879758` — FOUND
- Commit `8958832` — FOUND
- Commit `f078b5b` — FOUND
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → BUILD SUCCEEDED (verified at every commit)

---
*Phase: 04-scroll-handling-trackframe-hideandsettle*
*Completed: 2026-04-19*
