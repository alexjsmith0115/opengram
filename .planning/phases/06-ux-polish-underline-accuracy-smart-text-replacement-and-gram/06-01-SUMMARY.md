---
phase: 06-ux-polish-underline-accuracy-smart-text-replacement-and-gram
plan: 01
subsystem: SuggestionUI / AppQuirks
tags: [ax-watchdog, bounds-validation, multi-line, app-quirks, focus-ring-removal, tdd]
dependency_graph:
  requires: []
  provides:
    - AXCallWatchdog (thread-safe 0.8s hang detection + 30s blocklist)
    - BoundsValidator (full validation pipeline, multi-line splitting, injectable watchdog)
    - AppQuirksTable (plist-based per-app AX behavior overrides)
  affects:
    - OpenGram/SuggestionUI/OverlayController.swift (Plan 02 will use BoundsValidator)
    - OpenGram/SuggestionUI/UnderlineView.swift (focusedIndex removed)
tech_stack:
  added: []
  patterns:
    - NSLock for high-frequency lock/unlock (not DispatchQueue — lower overhead)
    - DispatchSource.makeTimerSource for background timer on .global(qos: .utility)
    - Dependency injection for AXCallWatchdog in BoundsValidator (testability)
    - CFGetTypeID guard before AXValue cast (prevents crash on unexpected AX return types)
    - NSScreen.screens.first(where: origin == .zero) for coordinate flip (not .main)
key_files:
  created:
    - OpenGram/SuggestionUI/AXCallWatchdog.swift
    - OpenGram/SuggestionUI/BoundsValidator.swift
    - OpenGram/AppQuirks/AppQuirksTable.swift
    - OpenGram/AppQuirks/AppQuirks.plist
    - OpenGramTests/SuggestionUITests/AXCallWatchdogTests.swift
    - OpenGramTests/SuggestionUITests/BoundsValidatorTests.swift
  modified:
    - OpenGram/SuggestionUI/UnderlineView.swift
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGramTests/SuggestionUITests/UnderlineViewTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
decisions:
  - AXCallWatchdog uses NSLock (not DispatchQueue) for thread safety — lower overhead for frequent lock/unlock in the hot path
  - BoundsValidator accepts AXCallWatchdog via init to avoid shared-singleton busy-guard interference in parallel tests
  - kAXLineForIndexParameterizedAttribute uses NSNumber (CFNumber) as parameter, not AXValue — fixed during implementation
  - AppQuirks.plist starts empty; specific app quirks require manual testing with target apps
  - Tab/Enter global key monitors removed per D-14; only Escape remains
metrics:
  duration_minutes: 6
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_created: 6
  files_modified: 4
---

# Phase 6 Plan 1: AXCallWatchdog, BoundsValidator, AppQuirksTable, and Focus Ring Removal Summary

**One-liner:** Thread-safe AX hang watchdog with 0.8s timeout/30s blocklist, full bounds validation pipeline with multi-line splitting, plist-based app quirks table, and dead focus ring code removed from UnderlineView.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | AXCallWatchdog, BoundsValidator, AppQuirksTable | 203992e | AXCallWatchdog.swift, BoundsValidator.swift, AppQuirksTable.swift, AppQuirks.plist, AXCallWatchdogTests.swift, BoundsValidatorTests.swift |
| 2 | UnderlineView focus ring removal (D-01, D-14) | 1a418a4 | UnderlineView.swift, OverlayController.swift, UnderlineViewTests.swift, OverlayControllerTests.swift |

## What Was Built

### AXCallWatchdog

Thread-safe singleton (`NSLock`, not `DispatchQueue`) that tracks active AX calls. A `DispatchSource` background timer fires every 0.1s and blocklists apps whose calls exceed 0.8s. Blocklist entries expire after 30s. Includes a busy guard that skips any second AX call if one is already in flight (< 1.2s). Injectable via `init(hangThreshold:blocklistDuration:)` for fast test execution.

### BoundsValidator

Stateless struct that replaces `OverlayController.boundsForRange`. Full validation pipeline:
1. Watchdog `shouldSkip` check before any AX call
2. `AXValueCreate(.cfRange)` → `copyParameterizedAttributeValue`
3. `CFGetTypeID` guard before AXValue cast (T-06-03 mitigated)
4. Bounds validation: width/height >= 2, width < 800, height < 200, no NaN/inf
5. Per-app coordinate offsets from AppQuirksTable
6. Multi-line detection: height > lineHeight * 1.5 triggers `splitMultiLine`
7. Multi-line split via `kAXLineForIndexParameterizedAttribute` + `kAXRangeForLineParameterizedAttribute`, with Y-coordinate sampling fallback
8. Coordinate flip using `NSScreen.screens.first { origin == .zero }` (not `NSScreen.main`)

Injectable watchdog and quirks table for parallel-safe unit testing.

### AppQuirksTable

Loads `AppQuirks.plist` at startup via `PropertyListDecoder` into `[String: AppQuirk]`. Silent fail on load error (empty table, console log). `AppQuirk` has optional `coordinateOffsetX/Y`, `lineHeightFactor`, and `boundsStrategy` ("rangeBounds" | "skipMultiLine"). Plist ships empty with a documented example entry for Pages.

### UnderlineView / OverlayController Cleanup

- Removed `focusedIndex` property from `UnderlineView`
- Removed focus ring `NSBezierPath` block from `draw()`
- Removed `focusedIndex`, `handleTab`, `handleEnter` from `OverlayController`
- Reduced keyDown global monitor to Escape-only (D-14, D-15)
- Removed 5 Tab/Enter/focusedIndex tests from `OverlayControllerTests`
- Removed 1 `focusedIndex` test from `UnderlineViewTests`

## Test Results

- 14 new tests across `AXCallWatchdogTests` and `BoundsValidatorTests` — all pass
- Full suite: 165 tests, 0 failures

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] kAXLineForIndexParameterizedAttribute uses NSNumber, not AXValue**
- **Found during:** Task 1 GREEN phase
- **Issue:** Plan specified creating AXValue with `.cfIndex` for `kAXLineForIndex/RangeForLine` parameters. `AXValueType` has no `.cfIndex` member — these AX attributes use NSNumber (CFNumber) as both parameter and return type.
- **Fix:** Changed `fetchLineNumber` and `fetchRangeForLine` to pass `NSNumber(value:) as CFTypeRef` and cast returned `ref as? NSNumber`.
- **Files modified:** `OpenGram/SuggestionUI/BoundsValidator.swift`
- **Commit:** 203992e

**2. [Rule 2 - Missing critical functionality] Injectable watchdog for parallel test safety**
- **Found during:** Task 1 GREEN phase — `acceptsValidBounds` test failed due to shared `AXCallWatchdog.shared` busy-guard firing in parallel with `AXCallWatchdogTests`
- **Issue:** `BoundsValidator` hard-coded `AXCallWatchdog.shared`; parallel Swift Testing execution caused busy-guard interference between suites.
- **Fix:** Added `init(watchdog: AXCallWatchdog = .shared, quirksTable: AppQuirksTable = .shared)` to `BoundsValidator`; tests use `freshValidator()` helper that passes a new watchdog instance with long thresholds.
- **Files modified:** `OpenGram/SuggestionUI/BoundsValidator.swift`, `OpenGramTests/SuggestionUITests/BoundsValidatorTests.swift`
- **Commit:** 203992e

**3. [Rule 1 - Bug] Ambiguous `.nan` / `.infinity` in CGRect initializer in test**
- **Found during:** Task 1 GREEN phase compilation
- **Issue:** Swift 6 couldn't resolve `.nan` and `.infinity` as `CGFloat` in `CGRect(x: .nan, ...)` due to ambiguity with `Double`.
- **Fix:** Changed to explicit `CGFloat.nan` and `CGFloat.infinity`.
- **Files modified:** `OpenGramTests/SuggestionUITests/BoundsValidatorTests.swift`
- **Commit:** 203992e

**4. [Rule 1 - Bug] AppQuirksTable needed `Sendable` conformance for Swift 6**
- **Found during:** Task 1 GREEN phase compilation
- **Issue:** `static let shared = AppQuirksTable()` triggered Swift 6 concurrency error: non-Sendable type with shared mutable state.
- **Fix:** Added `Sendable` conformance to `AppQuirksTable` (safe — `quirks` dict is immutable after init).
- **Files modified:** `OpenGram/AppQuirks/AppQuirksTable.swift`
- **Commit:** 203992e

**5. [Rule 2 - Missing critical functionality] OverlayController Tab/Enter monitor and focusedIndex removed**
- **Found during:** Task 2 — UnderlineView.focusedIndex removal caused compile errors in OverlayController
- **Issue:** `OverlayController` still referenced `underlineView?.focusedIndex`, `handleTab`, and `handleEnter` which all depended on the removed property. D-14 mandates their removal.
- **Fix:** Removed `focusedIndex`, `handleTab`, `handleEnter` from `OverlayController`. Reduced keyDown monitor to Escape-only. Removed corresponding tests.
- **Files modified:** `OpenGram/SuggestionUI/OverlayController.swift`, `OpenGramTests/SuggestionUITests/OverlayControllerTests.swift`
- **Commit:** 1a418a4

## Known Stubs

None — all components are fully wired. `AppQuirks.plist` ships empty intentionally; the schema is documented and the table loads correctly from an empty dict.

## Threat Flags

All threats from the plan's threat register were mitigated:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-06-01 DoS via hanging AX calls | AXCallWatchdog 0.8s timeout + 30s blocklist | Implemented |
| T-06-02 Tampered AX CGRect values | BoundsValidator rejects width<2, height<2, width>=800, height>=200, NaN, inf | Implemented |
| T-06-03 Crash on unexpected AX return type | CFGetTypeID guard before AXValue cast | Implemented |
| T-06-04 AppQuirks.plist info disclosure | Accepted — contains only coordinate offsets, no sensitive data | N/A |

## Self-Check: PASSED

All files found. Both task commits verified present.

| Check | Result |
|-------|--------|
| OpenGram/SuggestionUI/AXCallWatchdog.swift | FOUND |
| OpenGram/SuggestionUI/BoundsValidator.swift | FOUND |
| OpenGram/AppQuirks/AppQuirksTable.swift | FOUND |
| OpenGram/AppQuirks/AppQuirks.plist | FOUND |
| OpenGramTests/SuggestionUITests/AXCallWatchdogTests.swift | FOUND |
| OpenGramTests/SuggestionUITests/BoundsValidatorTests.swift | FOUND |
| OpenGram/SuggestionUI/UnderlineView.swift (modified) | FOUND |
| Commit 203992e | FOUND |
| Commit 1a418a4 | FOUND |
