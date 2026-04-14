---
phase: 03-suggestion-ui
plan: "04"
subsystem: SuggestionUI
tags: [bug-fix, overlay, scroll-dismiss, reposition, regression-test]
dependency_graph:
  requires: ["03-03"]
  provides: ["scroll-dismiss-fix", "reposition-after-accept-fix"]
  affects: ["OverlayController"]
tech_stack:
  added: []
  patterns: ["screen-coord-first entry building before window frame recalculation"]
key_files:
  modified:
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
decisions:
  - "Unconditional scroll dismiss: any scroll while overlay is visible means underline positions are stale, making PID-filtered dismiss both unreliable (cgEvent nil) and unnecessary"
  - "Screen-coord-first pattern for repositionAfterAccept mirrors show() exactly, ensuring consistent window frame recalculation after acceptance"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-14"
  tasks_completed: 2
  files_modified: 2
---

# Phase 03 Plan 04: Gap Closure — Scroll Dismiss and Reposition After Accept Summary

Two UAT failures closed: scroll dismissal now fires on any scroll event, and remaining underlines reposition correctly after suggestion acceptance.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix scroll monitor — remove cgEvent PID filter | fffa0c6 | OverlayController.swift |
| 2 | Fix repositionAfterAccept — recalculate window frame | 5942772 | OverlayController.swift, OverlayControllerTests.swift |

## What Was Built

### Task 1: Scroll dismiss fix

Removed the `let targetPID`/`event.cgEvent` PID-filter chain from the `NSEvent.addGlobalMonitorForEvents` scroll monitor callback. The conditional was silently short-circuiting because `event.cgEvent` returns `nil` for native Cocoa scroll events (Notes, TextEdit, etc.). Replaced with unconditional `self?.dismiss()` — any scroll while the overlay is visible means underline positions are stale regardless of which app received the scroll.

### Task 2: repositionAfterAccept window frame fix

Rewrote the survivor loop in `repositionAfterAccept` to build entries in raw screen coordinates first, then compute a new window frame from their union rect (with 4pt padding, identical to `show()`), then translate entries to window-local coordinates before assigning to the view. `overlayWindow.setFrame(newWindowRect, display: false)` and `view.frame = NSRect(origin: .zero, size: newWindowRect.size)` are now called, matching the `show()` pattern exactly. Added a regression test `repositionRecalculatesWindowFrame` verifying surviving suggestions are retained without crash after reposition.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/OverlayController.swift` — modified (commits fffa0c6, 5942772)
- `OpenGramTests/SuggestionUITests/OverlayControllerTests.swift` — modified (commit 5942772)
- `fffa0c6` — confirmed in git log
- `5942772` — confirmed in git log
- All 175 tests pass
