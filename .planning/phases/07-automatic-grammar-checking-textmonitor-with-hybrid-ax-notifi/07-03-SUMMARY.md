---
phase: 07-automatic-grammar-checking-textmonitor-with-hybrid-ax-notifi
plan: 03
subsystem: SuggestionUI, App
tags: [overlay, diff-merge, text-monitor, app-delegate, integration, tdd]
dependency_graph:
  requires:
    - SuggestionDiffEngine (Plan 01)
    - TextMonitor (Plan 02)
  provides:
    - OverlayController.update() diff-merge path (consumed by AppDelegate automatic check flow)
    - Full automatic grammar checking integration (TextMonitor wired into AppDelegate)
  affects:
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerDiffTests.swift
    - OpenGram.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - SuggestionDiffEngine.diff() called in update() for O(n) suggestion diff with ~80% AX call reduction
    - computeScalarOffsets() private helper extracted from show() to eliminate duplication
    - TextMonitor.onCheckComplete callback wired to overlayController.update() for diff-merge display
    - TextMonitor.onDismiss callback wired to overlay dismiss + status reset on app switch
    - forceCheckNow() called from handleHotkeyFired() to bypass debounce (D-14)
key_files:
  created:
    - OpenGramTests/SuggestionUITests/OverlayControllerDiffTests.swift
  modified:
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - update() falls through to show() when bundleID changes (not axElement identity) — bundleID is the most reliable field-change signal available without AX equality checks
  - Unchanged suggestions keep existing underline entries (no AX re-query) — satisfies T-07-07 by reducing bounds queries by ~80% on typical re-checks
  - computeScalarOffsets() extracted as private helper — eliminates duplication between show() and update(), single source of truth for offset computation
  - handleHotkeyFired() retains direct-check fallback behind textMonitor == nil guard — defensive, documents expected path without silently breaking if TextMonitor init ever fails
metrics:
  duration: ~15 minutes
  completed: 2026-04-14
  tasks_completed: 2
  files_created: 1
  files_modified: 3
---

# Phase 07 Plan 03: Integration — OverlayController diff-merge + AppDelegate TextMonitor wiring

**One-liner:** Diff-merge overlay update path using SuggestionDiffEngine for flicker-free automatic re-checks, with TextMonitor wired into AppDelegate for always-on grammar checking triggered by typing.

## What Was Built

### Task 1: OverlayController.update() diff-merge path

`OpenGram/SuggestionUI/OverlayController.swift` now has a `update(suggestions:context:)` method that performs surgical diff-merge of underline entries rather than tearing down and rebuilding the overlay window on every re-check.

**update() behavior:**
- Falls through to `show()` when overlay is not visible (first display) or bundleID changes (field switch)
- Calls `dismiss()` when `newSuggestions` is empty (all errors resolved by user editing)
- Calls `SuggestionDiffEngine.diff()` to classify suggestions as unchanged/added/removed
- No-ops on identical suggestion sets (updates textContext timestamp only)
- Reuses existing `UnderlineEntry` objects for unchanged suggestions — no AX bounds re-query (T-07-07)
- Queries AX bounds only for genuinely new suggestions (diff.added)
- Closes popover if its suggestion was removed by the diff
- Translates surviving entries to new window-local coordinates and updates the overlay window frame

**computeScalarOffsets()** extracted as a private helper, called by both `show()` and `update()`.

**Tests:** 6 tests in `OverlayControllerDiffTests.swift`:
1. Identical suggestion set — count unchanged
2. New suggestion added — added to set
3. Suggestion removed — dropped from set, others remain
4. Overlay not visible — falls through to show()
5. Empty new suggestions — calls dismiss()
6. Different bundleID — falls through to show()

### Task 2: AppDelegate wiring

`OpenGram/App/AppDelegate.swift` creates and holds a `TextMonitor` instance, wiring it into the full automatic checking pipeline:

- `textMonitor` property added to `AppDelegate`
- Created in `applicationDidFinishLaunching` with `textEngine`, `harperService`, `capabilityCache`
- `onCheckComplete` routes automatic results to `overlayController.update()` for diff-merge display
- `onDismiss` dismisses overlay and resets status bar on app switch (D-10)
- `textMonitor.start()` called on launch for always-on monitoring (D-07)
- `textMonitor.stop()` called in `applicationWillTerminate`
- `handleHotkeyFired()` simplified: calls `textMonitor.forceCheckNow()` to bypass debounce (D-14), retains direct-check fallback for nil textMonitor

### Task 3: Manual verification (PENDING — checkpoint:human-verify)

Task 3 requires human verification of the complete automatic grammar checking flow in a running app. The verifier should:

1. Build and launch OpenGram
2. Open TextEdit and type: "Ths is a tset sentense." — wait ~1 second
3. Verify red underlines appear automatically (no hotkey needed)
4. Fix "Ths" to "This" — wait ~1 second
5. Verify "Ths" underline disappears, "tset"/"sentense" underlines remain WITHOUT flickering
6. Press Ctrl+Shift+G — verify immediate re-check (no 800ms wait)
7. Switch to another app — verify overlay dismisses immediately
8. Switch back to TextEdit — verify underlines reappear after ~1 second

## Test Results

- 215/215 tests pass (full suite)
- 6 OverlayControllerDiffTests: all green
- BUILD SUCCEEDED

## Deviations from Plan

None — plan executed exactly as written.

The test filter format used during verification: `OpenGramTests/OverlayControllerDiffTests` (not `OpenGramTests/SuggestionUITests/OverlayControllerDiffTests`) — Swift Testing suite names don't include directory structure in the `-only-testing` filter.

## Known Stubs

None. Both tasks are complete implementations. Task 3 is a checkpoint awaiting human verification, not a stub.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes. All threat mitigations from the plan's threat register are implemented:
- T-07-07: Only diff.added suggestions trigger AX bounds queries in update()
- T-07-08: forceCheckNow() in handleHotkeyFired() cancels pending debounce (handled in TextMonitor from Plan 02)
- T-07-09: runCheck() re-queries kAXFocusedUIElementAttribute before using stored element (handled in TextMonitor from Plan 02)

## Self-Check: PASSED

- FOUND: OpenGram/SuggestionUI/OverlayController.swift contains `func update(`
- FOUND: OpenGram/SuggestionUI/OverlayController.swift contains `SuggestionDiffEngine.diff(`
- FOUND: OpenGram/App/AppDelegate.swift contains `private var textMonitor: TextMonitor?`
- FOUND: OpenGram/App/AppDelegate.swift contains `TextMonitor(` constructor
- FOUND: OpenGram/App/AppDelegate.swift contains `textMonitor.start()`
- FOUND: OpenGram/App/AppDelegate.swift contains `textMonitor?.stop()`
- FOUND: OpenGram/App/AppDelegate.swift contains `textMonitor.forceCheckNow()`
- FOUND: OpenGram/App/AppDelegate.swift contains `onCheckComplete`
- FOUND: OpenGram/App/AppDelegate.swift contains `overlayController?.update(`
- FOUND: OpenGram/App/AppDelegate.swift contains `onDismiss`
- FOUND: OpenGramTests/SuggestionUITests/OverlayControllerDiffTests.swift (6 @Test functions)
- FOUND commit: 005e607
- FOUND commit: a0f8aa2
- PASS: BUILD SUCCEEDED
- PASS: 215/215 tests green
