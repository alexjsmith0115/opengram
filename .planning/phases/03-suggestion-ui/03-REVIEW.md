---
phase: 03-suggestion-ui
reviewed: 2026-04-14T15:25:00Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - OpenGram/App/AppDelegate.swift
  - OpenGram/CheckEngine/Suggestion.swift
  - OpenGram/SuggestionUI/OverlayController.swift
  - OpenGram/SuggestionUI/OverlayWindow.swift
  - OpenGram/SuggestionUI/PopoverView.swift
  - OpenGram/SuggestionUI/SuggestionPopoverPanel.swift
  - OpenGram/SuggestionUI/TargetAppObserver.swift
  - OpenGram/SuggestionUI/UnderlineView.swift
  - OpenGram/TextEngine/AXAccessor.swift
  - OpenGramTests/AppDelegateWiringTests.swift
  - OpenGramTests/AXTextEngineTests.swift
  - OpenGramTests/SuggestionUITests/BoundsForRangeTests.swift
  - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
  - OpenGramTests/SuggestionUITests/OverlayWindowTests.swift
  - OpenGramTests/SuggestionUITests/PopoverViewTests.swift
  - OpenGramTests/SuggestionUITests/SuggestionPopoverPanelTests.swift
  - OpenGramTests/SuggestionUITests/TargetAppObserverTests.swift
  - OpenGramTests/SuggestionUITests/UnderlineViewTests.swift
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-04-14T15:25:00Z
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

The Phase 3 Suggestion UI implementation is well-structured with clear separation of concerns: OverlayController coordinates the overlay/popover lifecycle, OverlayWindow and SuggestionPopoverPanel handle AppKit window mechanics, PopoverView provides the SwiftUI suggestion card, UnderlineView renders hit-testable underlines, and TargetAppObserver manages AX dismiss observers. The code uses DI consistently (AXAccessor protocol), has thorough test coverage, and the prior review's findings (WR-01 generation counter race, WR-02 TargetAppObserver thread safety, WR-03 checkTask cancellation) have all been addressed.

This re-review identifies one critical crash path in the fallback text write logic, three warnings around unchecked AX API returns, cursor stack management, and monitor cleanup, and two informational items.

## Critical Issues

### CR-01: Potential crash in fallbackFullWrite when target text has been externally modified

**File:** `OpenGram/SuggestionUI/OverlayController.swift:368-369`
**Issue:** `fallbackFullWrite` calls `scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)` and `scalars.index(startIdx, offsetBy: offset.scalarLength)` without validating that the offsets are within the current text's bounds. The method correctly re-reads the current text from the AX element (line 364-365), but the `offset` values were computed from the *original* text at suggestion creation time. If the user or another process has edited the text field between check and accept, the scalar offsets can exceed the re-read text's scalar count, causing `String.UnicodeScalarView.index(_:offsetBy:)` to trap (fatal error).

**Fix:**
```swift
let scalars = currentText.unicodeScalars
guard offset.scalarStart >= 0,
      offset.scalarStart + offset.scalarLength <= scalars.count else { return false }
let startIdx = scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)
let endIdx = scalars.index(startIdx, offsetBy: offset.scalarLength)
```

## Warnings

### WR-01: AXObserverCreate return value not checked; context leaks on failure

**File:** `OpenGram/SuggestionUI/TargetAppObserver.swift:27`
**Issue:** `AXObserverCreate` returns an `AXError` that is discarded. The subsequent `guard let observer` catches the nil-observer case, but when `AXObserverCreate` fails, the retained `DismissContext` (line 22-23) is never released -- the method returns at line 35 without reaching the code that would use (and later release) the unmanaged reference. The `unmanagedContext` property is set but `uninstall()` is never called on this path, so the next `install()` call will release it. However, if the observer is never installed again (e.g., app quits), this is a leak of the DismissContext and its captured closure.

**Fix:**
```swift
let result = AXObserverCreate(pid, { _, _, _, userData in
    guard let userData else { return }
    let ctx = Unmanaged<DismissContext>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        ctx.handler()
    }
}, &observer)

guard result == .success, let observer else {
    unmanagedContext?.release()
    unmanagedContext = nil
    dismissContext = nil
    return
}
```

### WR-02: NSCursor stack imbalance when popover dismissed during hover

**File:** `OpenGram/SuggestionUI/PopoverView.swift:108-111`
**Issue:** The `onHover` modifier pushes `NSCursor.pointingHand` on hover-in and calls `NSCursor.pop()` on hover-out. If the popover is dismissed while the cursor is hovering over the primary replacement button (e.g., user clicks accept), the SwiftUI view is removed before the hover-out fires. This leaves `pointingHand` on the cursor stack permanently for that app session. The same pattern exists at lines 128-130 for alternative suggestion buttons.

**Fix:** Replace push/pop with `set()` which does not use the stack:
```swift
.onHover { hovering in
    isHoveringPrimary = hovering
    if hovering { NSCursor.pointingHand.set() }
    else { NSCursor.arrow.set() }
}
```

### WR-03: OverlayController.show() does not clean up prior monitors on re-entry

**File:** `OpenGram/SuggestionUI/OverlayController.swift:147-157`
**Issue:** If `show()` is called twice without an intervening `dismiss()`, the `scrollMonitor` and `keyMonitor` from the first call are overwritten without being removed. The orphaned monitors continue firing and calling `dismiss()` on stale state. While AppDelegate currently calls `dismiss()` before each new check cycle (line 76), `show()` itself does not guard against double-call, making this a latent bug.

**Fix:** Add cleanup at the top of `show()`:
```swift
func show(suggestions: [Suggestion], context: TextContext) {
    if let monitor = scrollMonitor {
        NSEvent.removeMonitor(monitor)
        scrollMonitor = nil
    }
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }
    // ... rest of method
```

## Info

### IN-01: Redundant MainActor.run inside MainActor-inherited Task

**File:** `OpenGram/App/AppDelegate.swift:93`
**Issue:** `handleHotkeyFired()` is `@MainActor`, so `Task { ... }` on line 90 inherits the MainActor context. The `await MainActor.run { ... }` on line 93 is redundant -- the code is already executing on the main actor after the `await` resumes. This adds unnecessary indirection.

**Fix:** Remove the `MainActor.run` wrapper and place the code directly in the Task body after the cancellation check.

### IN-02: BoundsForRangeTests.swift is a stub file

**File:** `OpenGramTests/SuggestionUITests/BoundsForRangeTests.swift:1-3`
**Issue:** This file contains only a comment explaining that tests were moved to BoundsValidatorTests.swift. The file serves no purpose and should be deleted.

**Fix:** Delete the file and remove its reference from the Xcode project.

---

_Reviewed: 2026-04-14T15:25:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
