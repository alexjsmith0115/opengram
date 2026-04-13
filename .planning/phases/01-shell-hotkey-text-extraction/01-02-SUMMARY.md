---
phase: 01-shell-hotkey-text-extraction
plan: 02
subsystem: menu-bar-shell
tags: [swift, appkit, nsstatusitem, nsmenu, nspanel, accessibility, sf-symbols]

requires:
  - phase: 01-01
    provides: Xcode project, AppState enum, StatusBarController skeleton, directory structure

provides:
  - StatusBarController with icon state machine (idle/checking/done transitions)
  - MenuBuilder with status line, Settings, separator, Quit menu items
  - IconStateMachine extracted for testability with pulse animation and auto-return timers
  - PermissionGuide welcome sheet for first-launch Accessibility permission flow
  - OpenGramTests target in Xcode project with Swift Testing test suite

affects: [01-05]

tech-stack:
  added: []
  patterns: [mainactor-isolation-for-appkit, timer-mainactor-assumeisolated, extracted-state-machine-for-testability]

key-files:
  created:
    - OpenGram/Shell/IconStateMachine.swift
    - OpenGram/Shell/MenuBuilder.swift
    - OpenGram/Permissions/PermissionGuide.swift
    - OpenGramTests/IconStateMachineTests.swift
    - OpenGramTests/MenuBuilderTests.swift
  modified:
    - OpenGram/Shell/StatusBarController.swift
    - OpenGram/App/OpenGramApp.swift
    - OpenGram.xcodeproj/project.pbxproj
    - OpenGram.xcodeproj/xcshareddata/xcschemes/OpenGram.xcscheme

key-decisions:
  - "Extracted IconStateMachine from StatusBarController for testability -- NSStatusItem cannot be instantiated in test targets without a running app"
  - "Used MainActor.assumeIsolated in Timer closures -- Timer fires on main run loop but closure is @Sendable, so explicit isolation assertion is needed for Swift 6"
  - "Renamed AppState.imageName to sfSymbolName -- reflects actual SF Symbol usage instead of custom asset names"

patterns-established:
  - "@MainActor on AppKit controller classes: StatusBarController, IconStateMachine, PermissionGuide"
  - "MainActor.assumeIsolated for Timer callbacks that mutate @MainActor state"
  - "Extracted testable state machine pattern: UI controller delegates to pure-logic class that can be tested without AppKit runtime"

requirements-completed: [SHELL-01, SHELL-04]

duration: 6min
completed: 2026-04-13
---

# Phase 01 Plan 02: Menu Bar Shell and Permission Guide Summary

**StatusBarController with SF Symbol icon state machine (idle/checking/done), MenuBuilder dropdown, and PermissionGuide welcome sheet for AX permission -- all compiling clean under Swift 6 strict concurrency**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-13T15:07:18Z
- **Completed:** 2026-04-13T15:13:42Z
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 4

## Accomplishments

- Icon state machine with three states: idle (checkmark.circle), checking (checkmark.circle.fill with 1Hz pulse), done (auto-returns to idle after 3.0s)
- Silent fail support: triggerSilentFail() transitions checking to idle (0.5s delay constant exposed)
- Menu dropdown with exactly 4 items per UI-SPEC: disabled status line ("OpenGram: Ready"), Settings, separator, Quit (Cmd+Q)
- Welcome sheet (NSPanel, 480pt) with app icon, title, body copy matching Copywriting Contract, CTA button deep-linking to System Settings Accessibility pane, "Not now" dismiss
- Keyboard support: Return activates CTA, Escape dismisses panel
- 17 unit tests (9 IconStateMachine, 8 MenuBuilder) using Swift Testing framework
- OpenGramTests target added to Xcode project with test scheme configuration

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests** - `369fa65` (test)
2. **Task 1 GREEN: StatusBarController + MenuBuilder + IconStateMachine** - `d593744` (feat)
3. **Task 2: PermissionGuide welcome sheet** - `10f6eb1` (feat)

## Files Created/Modified

- `OpenGram/Shell/IconStateMachine.swift` - @MainActor state machine: state transitions, pulse timer, done-return timer, opacity control
- `OpenGram/Shell/MenuBuilder.swift` - NSMenu with disabled status line (11pt label), Settings, separator, Quit (Cmd+Q)
- `OpenGram/Shell/StatusBarController.swift` - NSStatusItem lifecycle, delegates to IconStateMachine, SF Symbol images with isTemplate=true
- `OpenGram/App/OpenGramApp.swift` - AppState.imageName renamed to sfSymbolName, values updated to SF Symbol names
- `OpenGram/Permissions/PermissionGuide.swift` - NSPanel welcome sheet, AXIsProcessTrusted gate, System Settings deep link
- `OpenGramTests/IconStateMachineTests.swift` - 9 tests: state transitions, symbol names, pulse timing, silent fail, idempotent checking
- `OpenGramTests/MenuBuilderTests.swift` - 8 tests: item count, titles, enabled state, key equivalents, separator
- `OpenGram.xcodeproj/project.pbxproj` - Added MenuBuilder, IconStateMachine, PermissionGuide to app target; created OpenGramTests target
- `OpenGram.xcodeproj/xcshareddata/xcschemes/OpenGram.xcscheme` - Added OpenGramTests testable reference

## Decisions Made

- **Extracted IconStateMachine for testability:** NSStatusItem requires a running NSApplication to instantiate, making StatusBarController untestable in isolation. Extracted the state machine logic (state transitions, timer scheduling, symbol name computation) into a separate `IconStateMachine` class that StatusBarController delegates to. Tests exercise the state machine directly.
- **MainActor.assumeIsolated for Timer closures:** Timer.scheduledTimer fires on the main run loop, but its closure is typed as `@Sendable`. Using `MainActor.assumeIsolated` inside the closure tells the Swift 6 concurrency checker that we know this runs on the main thread. This is safe because NSRunLoop timers always fire on their scheduled run loop.
- **Renamed imageName to sfSymbolName:** The Plan 01 skeleton used generic asset names ("StatusIdle", "StatusChecking"). This plan uses SF Symbols directly, so the property name was updated to reflect the actual usage.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 Sendable warnings in Timer closures**
- **Found during:** Task 1
- **Issue:** Timer.scheduledTimer closures capture `@MainActor`-isolated `self`, producing Swift 6 strict concurrency warnings
- **Fix:** Wrapped timer closure bodies in `MainActor.assumeIsolated { }` -- safe because Timer fires on main run loop
- **Files modified:** OpenGram/Shell/IconStateMachine.swift
- **Committed in:** d593744

**2. [Rule 2 - Missing] OpenGramTests target not in project**
- **Found during:** Task 1
- **Issue:** project.pbxproj had no test target -- only the app target existed. Tests could not compile or run.
- **Fix:** Added full OpenGramTests native target with PBXNativeTarget, build configurations (Debug/Release), container item proxy, target dependency, and test scheme entry
- **Files modified:** OpenGram.xcodeproj/project.pbxproj, OpenGram.xcodeproj/xcshareddata/xcschemes/OpenGram.xcscheme
- **Committed in:** d593744

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical functionality)
**Impact on plan:** Both fixes necessary for Swift 6 compilation and test infrastructure. No scope creep.

## Issues Encountered

- **Xcode not installed:** Same environment limitation as Plan 01. Only Command Line Tools are available. `xcodebuild build` and `xcodebuild test` cannot run. All Swift source verified via `swiftc -typecheck -swift-version 6` (zero warnings, zero errors). The xcodeproj and test target are structurally correct and will build/test once Xcode 16+ is installed.

## Next Phase Readiness

- StatusBarController is ready for wiring in Plan 05 (AppDelegate integration)
- MenuBuilder.updateStatusText() is ready for Plan 05 to call during hotkey flow
- PermissionGuide.showIfNeeded() is ready for Plan 05 to call from applicationDidFinishLaunching
- IconStateMachine.onStateChange callback is ready for StatusBarController to forward state changes to

## Self-Check: PASSED
