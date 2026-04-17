---
phase: 18-paragraph-rephrase-card
plan: "06"
subsystem: overlay
tags: [overlay, highlight, underline-filter, phase-18]
dependency_graph:
  requires: [18-01, 18-03]
  provides: [SourceParagraphHighlight NSView, OverlayController.hideUnderlines/showUnderlines API]
  affects: [OverlayController, UnderlineView render pipeline]
tech_stack:
  added: []
  patterns:
    - Non-interactive NSView with wantsLayer + CALayer styling
    - Scalar-offset-based underline filter (not Range<String.Index>)
    - In-place filter (applyHiddenFilterToCurrentEntries) vs full rebuild (rebuildUnderlineEntriesFromSuggestions)
key_files:
  created:
    - OpenGram/SuggestionUI/Overlay/SourceParagraphHighlight.swift
    - OpenGramTests/SuggestionUITests/SourceParagraphHighlightTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerHideUnderlinesTests.swift
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Overlap check uses half-open intervals: scalarStart < bEnd && aEnd > r.scalarStart — consistent with Unicode scalar range semantics"
  - "applyHiddenFilterToCurrentEntries filters in-place without re-querying AX; rebuildUnderlineEntriesFromSuggestions does a full BoundsValidator pass"
  - "Filter inserted into show() by enumerated index (using pre-computed suggestionScalarOffsets[idx]) and into both unchanged/added loops in update() using newOffsets[newIndex]"
  - "hiddenParagraphScalarRange stored as plain var (internal(set) is redundant for internal properties but kept for consistency with sibling properties)"
metrics:
  duration: ~30 minutes
  completed: 2026-04-17
  tasks: 2
  files: 5
---

# Phase 18 Plan 06: Overlay Primitives (SourceParagraphHighlight + hideUnderlines) Summary

**One-liner:** Non-interactive paragraph highlight NSView and scalar-offset-based underline hide/show API on OverlayController, wired into both show() and update() entry-construction loops.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SourceParagraphHighlight NSView + tests | 9ad3018 | SourceParagraphHighlight.swift, SourceParagraphHighlightTests.swift, pbxproj |
| 2 | OverlayController.hideUnderlines/showUnderlines + tests | ae6744b | OverlayController.swift, OverlayControllerHideUnderlinesTests.swift, pbxproj |

## What Was Built

### Task 1: SourceParagraphHighlight

`OpenGram/SuggestionUI/Overlay/SourceParagraphHighlight.swift` — a minimal `NSView` with:
- `wantsLayer = true`, `layer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor`
- `layer.cornerRadius = 4`, `masksToBounds = true`
- `hitTest(_:) -> nil` — clicks always pass through to target app

### Task 2: OverlayController changes

**New stored property** (line ~38):
```swift
internal(set) var hiddenParagraphScalarRange: (scalarStart: Int, scalarLength: Int)?
```

**New public API** (after `dismiss()`, before `// MARK: - Popover management`):
- `hideUnderlines(inParagraphScalarRange:)` — stores range, calls `applyHiddenFilterToCurrentEntries()`
- `showUnderlines()` — clears range, calls `rebuildUnderlineEntriesFromSuggestions()`
- `shouldHideUnderline(scalarStart:scalarLength:) -> Bool` — overlap check (internal, testable)

**Filter insertion points:**

`show()` — entry loop at line ~88 (after enumerated index, before AX query):
```swift
let off = self.suggestionScalarOffsets[idx]
if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) { continue }
```

`update()` — `diff.unchanged` loop at line ~201 (skip appending entries but still track suggestion/offset):
```swift
if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) {
    survivingSuggestions.append(cappedNew[newIndex])
    survivingOffsets.append(off)
    continue
}
```

`update()` — `diff.added` loop at line ~221 (skip AX query entirely for hidden entries):
```swift
if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) {
    survivingSuggestions.append(suggestion)
    survivingOffsets.append(off)
    continue
}
```

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| SourceParagraphHighlightTests | 3 | PASS |
| OverlayControllerHideUnderlinesTests | 4 | PASS |
| OverlayControllerTests (regression) | 11 | PASS |
| OverlayControllerDiffTests (regression) | 6 | PASS |
| **Total** | **24** | **PASS** |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wrong module name in test imports**
- **Found during:** Task 1 test run
- **Issue:** Plan template used `@testable import OpenGram` but `PRODUCT_MODULE_NAME = OpenGramLib` — all other test files use `@testable import OpenGramLib`
- **Fix:** Changed both new test files to `@testable import OpenGramLib`
- **Files modified:** SourceParagraphHighlightTests.swift, OverlayControllerHideUnderlinesTests.swift
- **Commit:** included in task commits

**2. [Rule 2 - Missing critical functionality] Hidden suggestions still tracked in update() loops**
- **Found during:** Task 2 implementation
- **Issue:** Plan action said "skip entries" but if hidden suggestions are also dropped from `survivingSuggestions`/`survivingOffsets`, they'd be permanently lost when showUnderlines() is called — nothing to rebuild from
- **Fix:** Hidden suggestions are tracked in survivingSuggestions/survivingOffsets but their underline entries are not appended to survivingEntries. rebuildUnderlineEntriesFromSuggestions() can then restore them using the full suggestions array
- **Files modified:** OverlayController.swift

## Known Stubs

None. This plan adds overlay primitives only — no UI data paths.

## Threat Flags

None. No new network endpoints, auth paths, file access, or external surface.

## Self-Check

- [x] SourceParagraphHighlight.swift exists at correct path
- [x] SourceParagraphHighlightTests.swift exists at correct path
- [x] OverlayControllerHideUnderlinesTests.swift exists at correct path
- [x] Commit 9ad3018 exists (Task 1)
- [x] Commit ae6744b exists (Task 2)
- [x] `grep "final class SourceParagraphHighlight"` hits
- [x] `grep "func hideUnderlines"` hits
- [x] `grep "SourceParagraphHighlight" project.pbxproj` hits
- [x] 24/24 tests pass

## Self-Check: PASSED
