---
phase: 07-automatic-grammar-checking-textmonitor-with-hybrid-ax-notifi
plan: 02
subsystem: TextMonitor
tags: [text-monitor, ax-observer, debounce, polling, app-switch, watchdog]
dependency_graph:
  requires:
    - AXCapabilityCacheProtocol.isNotificationReliable / storeNotificationReliability (Plan 01)
    - AppQuirk.notificationUnreliable (Plan 01)
  provides:
    - TextMonitor class (consumed by Plan 03 for wiring into AppDelegate/OverlayController)
  affects:
    - OpenGram.xcodeproj/project.pbxproj (new TextMonitor group + file references)
tech_stack:
  added: []
  patterns:
    - AXObserver + CFRunLoop + Unmanaged.passRetained pattern (same as TargetAppObserver)
    - DispatchWorkItem debounce with cancel-and-replace
    - Timer.scheduledTimer poll loop with watchdog guard
    - 100ms app-switch debounce to absorb rapid Cmd-Tab sequences
key_files:
  created:
    - OpenGram/TextMonitor/TextMonitor.swift
    - OpenGramTests/TextMonitorTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - TextMonitor init is @MainActor-isolated (class annotation) — all AX and timer operations run on main actor, consistent with AppKit event handling
  - Poll timer always started for unknown-reliability apps (nil from isNotificationReliable) so we can auto-detect unreliable apps on first use rather than waiting for a second session
  - scheduleDebounce exposed as internal (not private) to allow test-driven timing verification
  - MonitorContext is a private nested class (not file-scope) to keep the Unmanaged pattern local to TextMonitor, same as DismissContext in TargetAppObserver
metrics:
  duration: ~20 minutes
  completed: 2026-04-14
  tasks_completed: 1
  files_created: 2
  files_modified: 1
---

# Phase 07 Plan 02: TextMonitor — Hybrid AX Notification + Polling Text Monitor

**One-liner:** @MainActor TextMonitor class using AXObserver for kAXValueChangedNotification with 800ms debounce, 1s poll fallback for notification-unreliable apps, 100ms app-switch debounce, watchdog blocklist respect, and runtime notification reliability auto-detection.

## What Was Built

### TextMonitor.swift (374 lines)

`OpenGram/TextMonitor/TextMonitor.swift` implements the core automatic checking coordinator:

**Dependencies (injected):**
- `any AXTextEngineProtocol` — text extraction
- `any GrammarCheckerProtocol` — grammar check invocation
- `any AXCapabilityCacheProtocol` — notification reliability cache read/write
- `AppQuirksTable` — pre-classification of known-unreliable apps
- `AXCallWatchdog` — blocklist check before every AX poll call

**Key behaviors:**
- `start()` — subscribes to `NSWorkspace.didActivateApplicationNotification` and calls `installOnFocusedElement()` (D-07: always-on)
- `stop()` — removes workspace observer, uninstalls AXObserver, cancels debounce + poll timer + check task
- `forceCheckNow()` — cancels debounce work item and runs `runCheck()` immediately (D-14: hotkey bypass)
- `installObserver(pid:element:bundleID:)` — follows exact `Unmanaged.passRetained` / `Unmanaged.release` pattern from `TargetAppObserver.swift`; registers `kAXValueChangedNotification` on the text element and `kAXFocusedUIElementChangedNotification` on the app element
- `scheduleDebounce()` — cancel-and-replace DispatchWorkItem with 800ms delay (D-05)
- `startPollTimer()` — 1.0s repeating timer (D-03); started when app is pre-classified unreliable, runtime-detected unreliable, or reliability is unknown
- `pollForChanges()` — checks `watchdog.shouldSkip()` first (T-07-03); if text changed without a notification firing, calls `capabilityCache.storeNotificationReliability(bundleID:reliable:false)` (D-02)
- `handleAppActivation(_:)` — 100ms debounce prevents observer churn during rapid Cmd-Tab (T-07-05)
- `isTextElement(_:)` — returns true for `kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole` only

**Threat mitigations implemented:**
- T-07-03: `pollForChanges()` checks `watchdog.shouldSkip()` before every AX read
- T-07-04: `Unmanaged.passRetained` + explicit `.release()` in `uninstallCurrentObserver()` 
- T-07-05: 100ms `appSwitchDebounce` on `handleAppActivation`

### TextMonitorTests.swift (287 lines, 14 tests)

All tests use `@MainActor` helpers with `TMock*` prefixed mock types to avoid name collisions with existing test mocks (`MockGrammarChecker` in `AppDelegateWiringTests.swift`).

Tests cover:
1. `start()` lifecycle — registers workspace observer without crash
2. `stop()` cleanup — `forceCheckNow()` after `stop()` is a no-op (observedElement nil guard)
3. `isTextElement` false for system-wide element (no role attribute)
4. `isTextElement` false for application element (kAXApplicationRole)
5. `scheduleDebounce` cancels prior work — extract count is 0 after 3 rapid calls + 1.1s wait
6. `forceCheckNow` cancels pending debounce — no 800ms wait
7. `forceCheckNow` twice — no crash
8. Watchdog blocklist respected — `shouldSkip` returns true after hang threshold
9. Poll miss detection — `storeNotificationReliability(reliable:false)` recorded in cache
10. `stop()` before `start()` — no crash
11. Multiple start/stop cycles — no observer leak
12. `onCheckComplete` callback wiring — not invoked at assignment
13. `onDismiss` callback wiring — not invoked at assignment
14. Pre-classified unreliable app quirk — `AppQuirksTable` returns `notificationUnreliable: true`

## Test Results

- 14/14 TextMonitor tests pass
- BUILD SUCCEEDED (full OpenGram target)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing AppKit import**
- **Found during:** First build attempt
- **Issue:** `NSWorkspace`, `NSRunningApplication` not in scope — only `ApplicationServices` and `Foundation` were imported.
- **Fix:** Added `import AppKit` to TextMonitor.swift.
- **Files modified:** OpenGram/TextMonitor/TextMonitor.swift

**2. [Rule 3 - Blocking] MockGrammarChecker name collision in test target**
- **Found during:** First test build attempt
- **Issue:** `AppDelegateWiringTests.swift` already defines `MockGrammarChecker` at module scope. Swift Testing compiles all test files together, producing an "Invalid redeclaration" error.
- **Fix:** Renamed all test mock types with `TMock` prefix: `TMockAXTextEngine`, `TMockGrammarChecker`, `TMockCapabilityCache`.
- **Files modified:** OpenGramTests/TextMonitorTests.swift

**3. [Rule 3 - Blocking] @MainActor isolation on makeMonitor helper**
- **Found during:** Second test build attempt
- **Issue:** `TextMonitor.init` is main-actor-isolated (class-level `@MainActor`). Calling it from a non-isolated `makeMonitor` function is a Swift 6 concurrency error.
- **Fix:** Added `@MainActor` to `makeMonitor` private helper function.
- **Files modified:** OpenGramTests/TextMonitorTests.swift

## Known Stubs

None. TextMonitor is a complete implementation. It does not wire into AppDelegate or OverlayController — that is Plan 03's responsibility, as scoped.

## Threat Flags

None. TextMonitor reads text via AX API (same trust boundary as the existing hotkey path). No new network endpoints, file access patterns, or external data flows introduced. All threat mitigations from the plan's threat register (T-07-03, T-07-04, T-07-05) are implemented.

## Self-Check: PASSED

- FOUND: OpenGram/TextMonitor/TextMonitor.swift
- FOUND: OpenGramTests/TextMonitorTests.swift
- FOUND commit: f4925cc
- PASS: TextMonitor.swift contains `@MainActor` (line 11)
- PASS: TextMonitor.swift contains `kAXValueChangedNotification` (not kAXSelectedTextChangedNotification)
- PASS: TextMonitor.swift contains `Unmanaged.passRetained`
- PASS: TextMonitor.swift contains `asyncAfter(deadline: .now() + 0.8`
- PASS: TextMonitor.swift contains `scheduledTimer(withTimeInterval: 1.0`
- PASS: TextMonitor.swift contains `shouldSkip`
- PASS: TextMonitor.swift contains `kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`
- PASS: TextMonitor.swift contains `didActivateApplicationNotification`
- PASS: TextMonitor.swift contains `func forceCheckNow()`
- PASS: TextMonitor.swift contains `storeNotificationReliability`
- PASS: TextMonitorTests.swift contains 14 `@Test` functions
- PASS: BUILD SUCCEEDED
