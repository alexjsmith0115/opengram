---
phase: 01-shell-hotkey-text-extraction
plan: 03
subsystem: hotkey
tags: [cgeventtap, hotkey, health-check, swift6-concurrency]

dependency_graph:
  requires: ["01-01"]
  provides: ["HotkeyManager", "EventTapBridge", "HealthCheckLoop"]
  affects: ["01-05"]

tech_stack:
  added: []
  patterns: ["Unmanaged C callback bridge", "CGEventTap health-check loop", "Pure-function decision extraction for testability"]

key_files:
  created:
    - OpenGram/Hotkey/HotkeyManager.swift
    - OpenGramTests/HotkeyManagerTests.swift
    - Package.swift
    - OpenGramEntry/main.swift
    - scripts/test.sh
  modified:
    - OpenGram/Hotkey/EventTapBridge.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGram.xcodeproj/project.pbxproj
    - OpenGram.xcodeproj/xcshareddata/xcschemes/OpenGram.xcscheme

decisions:
  - Used @unchecked Sendable on HotkeyManager since C callback bridge inherently crosses isolation boundaries
  - Extracted health-check decision logic into static pure function for testability
  - Added SPM Package.swift alongside Xcode project for CLI-based testing (CLT-only environments)
  - Used Swift Testing framework (@Test/#expect) per CLAUDE.md stack recommendation

metrics:
  duration: "11 minutes"
  completed: "2026-04-13T15:11:18Z"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 12
  tests_passing: 12
---

# Phase 01 Plan 03: Global Hotkey System Summary

CGEventTap with Ctrl+Shift+G detection, Unmanaged C callback bridge, and 5-second health-check loop with wake notification resilience

## What Was Built

### Task 1: HotkeyManager + EventTapBridge (TDD)

HotkeyManager implements the full CGEventTap lifecycle:

- **install()**: Creates event tap at `.cgSessionEventTap` with `.headInsertEventTap` placement, listening for keyDown + tapDisabledByTimeout + tapDisabledByUserInput. Guards against double-install by calling uninstall() first.
- **uninstall()**: Tears down timer, wake observer, run loop source, and mach port. Full cleanup with nil-out.
- **handle()**: C callback delegate. Routes tapDisabledBy* events to reenableTapIfNeeded(). Checks isHotkey() on keyDown events and dispatches to main actor via `Task { @MainActor in }`.
- **isHotkey()**: Matches keyCode 0x05 (G) with Control+Shift flags. Masks out CapsLock/Fn via intersection with [.maskControl, .maskShift, .maskAlternate, .maskCommand], rejects extra modifiers.

EventTapBridge is the file-scope `@convention(c)` function that extracts HotkeyManager from the userInfo opaque pointer via `Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()`.

### Task 2: Health-Check Loop (TDD)

Three-layer tap resilience per SHELL-03:

1. **In-callback**: tapDisabledByTimeout/tapDisabledByUserInput events trigger immediate reenableTapIfNeeded() (handles common runtime disables).
2. **Timer poll**: 5-second repeating Timer calls reenableTapIfNeeded() (catches silent disable after re-signing).
3. **Wake notification**: NSWorkspace.didWakeNotification triggers immediate reenableTapIfNeeded() (handles sleep/wake cycle disables).

reenableTapIfNeeded() checks tap status, attempts re-enable, and falls through to full reinstall() if tapEnable fails (permission revoked scenario).

Decision logic extracted into `HotkeyManager.healthCheckAction(tapExists:isEnabled:)` -- a pure static function returning `.doNothing` or `.reenable` -- for deterministic unit testing without requiring actual CGEventTap permission.

## Test Coverage

12 tests, all passing:

| Test | Category | What It Validates |
|------|----------|-------------------|
| Ctrl+Shift+G fires hotkey | isHotkey | Correct keycode + modifier match |
| Ctrl+G without Shift does not fire | isHotkey | Missing required modifier rejected |
| Ctrl+Shift+Cmd+G does not fire | isHotkey | Extra modifier rejected |
| Ctrl+Shift+A does not fire | isHotkey | Wrong keycode rejected |
| Ctrl+Shift+CapsLock+G fires | isHotkey | CapsLock correctly ignored |
| install and uninstall clears state | lifecycle | eventTap nil after uninstall |
| double install does not crash | lifecycle | No duplicate tap creation |
| healthCheckAction doNothing when enabled | health-check | No action for healthy tap |
| healthCheckAction doNothing when no tap | health-check | No action without tap |
| healthCheckAction reenable when disabled | health-check | Reenable for disabled tap |
| startHealthCheckTimer creates timer | health-check | Timer created with 5s interval |
| uninstall invalidates health timer | health-check | Timer cleaned up on uninstall |

## Infrastructure Changes

- **Package.swift**: Added SPM manifest with OpenGramLib (library target), OpenGram (executable entry point), and OpenGramTests. Enables `swift test` in environments without Xcode.
- **OpenGramEntry/main.swift**: Separated executable entry point from library code for `@testable import` support.
- **scripts/test.sh**: Helper script that passes Swift Testing framework search paths for CLT-only environments.
- **Xcode project**: Added OpenGramTests target, HotkeyManager.swift file reference, test scheme configuration.
- **AppDelegate.swift**: Made class and delegate methods public for cross-module access from OpenGramEntry.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] No test target in Xcode project**
- **Found during:** Task 1 RED phase
- **Issue:** The Xcode project had an OpenGramTests group placeholder but no actual test target
- **Fix:** Added full PBXNativeTarget, build configurations, source build phase, and scheme testable reference
- **Files modified:** OpenGram.xcodeproj/project.pbxproj, OpenGram.xcscheme

**2. [Rule 3 - Blocking] No Xcode installed, only Command Line Tools**
- **Found during:** Task 1 RED phase
- **Issue:** `xcodebuild test` unavailable. Swift Testing and XCTest frameworks not automatically available via SPM with CLT.
- **Fix:** Created Package.swift for SPM-based build/test. Added scripts/test.sh with explicit framework search paths for Swift Testing framework at CLT path. Separated library from executable for @testable import.
- **Files created:** Package.swift, OpenGramEntry/main.swift, scripts/test.sh

**3. [Rule 3 - Blocking] Executable target not testable via @testable import**
- **Found during:** Task 1 RED phase
- **Issue:** SPM executable targets cannot be imported by test targets
- **Fix:** Split into OpenGramLib (library with all app code) + OpenGram (thin executable entry point). AppDelegate made public for cross-module access.
- **Files modified:** AppDelegate.swift, Package.swift

## Commits

| Hash | Message |
|------|---------|
| 1e6499e | test(01-03): add failing tests for hotkey detection and install/uninstall |
| 7d492a8 | feat(01-03): implement HotkeyManager CGEventTap and EventTapBridge |
| b976cef | test(01-03): add failing tests for health-check logic |
| 89d6779 | feat(01-03): add testable health-check decision logic |

## Self-Check: PASSED

- All 6 key files exist on disk
- All 4 commit hashes found in git log
- All 12 tests pass
