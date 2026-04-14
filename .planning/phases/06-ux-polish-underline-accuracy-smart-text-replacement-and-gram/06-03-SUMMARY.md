---
phase: 06-ux-polish-underline-accuracy-smart-text-replacement-and-gram
plan: 03
subsystem: SuggestionUI
tags: [popover-redesign, grammarly-style, click-to-accept, inline-diff, dismiss-animation, tdd]
dependency_graph:
  requires:
    - OverlayController with showPopover/closePopover (06-02)
    - Suggestion model with allReplacements (CheckEngine)
  provides:
    - PopoverView: Grammarly-style card with inline diff, click-to-accept, expandable alternatives
    - PopoverAnimationState: ObservableObject driving scale+fade lifecycle
    - SuggestionPopoverPanel: borderless panel without .hudWindow
    - OverlayController.acceptSuggestion with replacementOverride parameter
    - OverlayController.closePopover with D-17 reverse animation
  affects:
    - OpenGram/SuggestionUI/PopoverView.swift
    - OpenGram/SuggestionUI/SuggestionPopoverPanel.swift
    - OpenGram/SuggestionUI/OverlayController.swift
tech_stack:
  added: []
  patterns:
    - PopoverAnimationState ObservableObject for cross-boundary animation control (OverlayController owns, SwiftUI observes)
    - scaleEffect + opacity driven by ObservableObject (avoids @State-only limitation for external dismiss triggers)
    - withAnimation(.easeOut(duration: 0.15)) in closePopover + asyncAfter(0.15s) for panel removal
    - onHover with balanced NSCursor.pointingHand.push()/pop() for pointing hand cursor (D-08)
    - replacementOverride: String? = nil as optional parameter on acceptSuggestion (clean single-method alternative accept)
key_files:
  created: []
  modified:
    - OpenGram/SuggestionUI/PopoverView.swift
    - OpenGram/SuggestionUI/SuggestionPopoverPanel.swift
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGramTests/SuggestionUITests/PopoverViewTests.swift
    - OpenGramTests/SuggestionUITests/SuggestionPopoverPanelTests.swift
decisions:
  - PopoverAnimationState as ObservableObject (not Binding<Bool> or @State) — OverlayController needs to trigger dismiss animation from outside the SwiftUI view hierarchy; ObservableObject is the cleanest cross-boundary signal
  - replacementOverride: String? = nil on acceptSuggestion rather than a separate acceptSuggestionWithReplacement method — one method, optional override, cleaner call site
  - hasShadow = true on NSPanel + SwiftUI shadow — belt-and-suspenders; system shadow is fallback when SwiftUI renders before layout is complete
metrics:
  duration_minutes: 2
  completed_date: "2026-04-14"
  tasks_completed: 1
  files_created: 0
  files_modified: 5
---

# Phase 6 Plan 3: Grammarly-Style Popover Redesign Summary

**One-liner:** Grammarly-style floating card with inline diff (red strikethrough → green), click-to-accept primary word, expandable alternatives DisclosureGroup, scale+fade animation via PopoverAnimationState ObservableObject, and borderless SuggestionPopoverPanel.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Failing tests for new PopoverView interface | 2a0f7e9 | PopoverViewTests.swift, SuggestionPopoverPanelTests.swift |
| 1 (GREEN) | Grammarly-style PopoverView + panel + OverlayController wiring | 9f2a9df | PopoverView.swift, SuggestionPopoverPanel.swift, OverlayController.swift |
| 2 | Checkpoint: manual verification (auto-approved) | — | — |

## What Was Built

### PopoverView (full replacement)

Opaque `RoundedRectangle(cornerRadius: 12)` card with shadow replaces the HUD-chrome popover. Layout (top to bottom):

1. **Inline diff row (D-07):** `Text(original).strikethrough(true, color: .red)` → `Image("arrow.right")` → `Text(primary).foregroundColor(.green)`
2. **Click-to-accept primary word (D-08):** `Button` wrapping a semibold `Text(primary)` with accent-colored background. `onHover` balanced `NSCursor.pointingHand.push()/pop()`. No separate Accept button.
3. **Expandable alternatives (D-09):** `DisclosureGroup` shown only when `allReplacements.count > 1`. Each alternative is a `Button` that fires `onAcceptAlternative(alt)`.
4. **Explanation text:** `suggestion.message`
5. **Footer row (D-10):** Source badge (Harper/AI), Dismiss button, Add to Dictionary (spelling only)

### PopoverAnimationState

`@MainActor final class PopoverAnimationState: ObservableObject` with `@Published var isVisible = false`. `OverlayController` owns the instance, passes it into `PopoverView`. SwiftUI `scaleEffect(isVisible ? 1.0 : 0.95)` and `opacity(isVisible ? 1.0 : 0.0)` bind to it. `onAppear` animates in; `closePopover()` animates out via `withAnimation(.easeOut(duration: 0.15)) { animState.isVisible = false }` then `asyncAfter(0.15s) { popoverPanel.orderOut(nil) }`.

### SuggestionPopoverPanel (updated)

- `styleMask: [.nonactivatingPanel]` — `.hudWindow` removed (D-06)
- `backgroundColor = .clear` — SwiftUI renders the full background
- `hasShadow = true` — system shadow as belt-and-suspenders

### OverlayController (updated)

- `currentAnimationState: PopoverAnimationState?` stored property
- `showPopover(for:)` creates `PopoverAnimationState`, passes it to `PopoverView`, wires `onAcceptAlternative` → `acceptSuggestion(_:context:replacementOverride:)`
- `acceptSuggestion(_:context:replacementOverride:String?=nil)` — `replacementOverride ?? suggestion.primaryReplacement` selects the text to write
- `closePopover()` guards on `isPopoverVisible`, triggers reverse animation, then `asyncAfter(0.15s)` calls `orderOut(nil)` (D-17)

## Test Results

- 174 tests, 0 failures (full suite)
- 46 tests in `PopoverView|SuggestionPopoverPanel|OverlayController` filter — all pass
- New tests added: `onAcceptAlternative` callback, disclosure group visibility (single/multiple), Add to Dictionary shown/hidden, `styleMaskExcludesHudWindow`, `backgroundColorIsClear`, `hasShadowIsTrue`

## Deviations from Plan

None — plan executed exactly as written.

The `PopoverAnimationState` ObservableObject approach was the plan's preferred approach (explicitly recommended over the Binding alternative).

## Known Stubs

None. All callbacks are wired through to production code paths. The popover renders live suggestion data from the Harper pipeline.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| T-06-08 mitigated | PopoverView.swift | NSCursor push/pop balanced within onHover closures; SwiftUI onDisappear handles cleanup when view is removed |
| T-06-09 mitigated | OverlayController.swift | onAcceptAlternative passes strings sourced from suggestion.allReplacements (Harper-produced, trusted); no user-supplied text |
| T-06-10 accepted | PopoverView.swift | Click-to-accept is local UI interaction; no network boundary crossed |

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| OpenGram/SuggestionUI/PopoverView.swift | FOUND |
| OpenGram/SuggestionUI/SuggestionPopoverPanel.swift | FOUND |
| OpenGram/SuggestionUI/OverlayController.swift | FOUND |
| OpenGramTests/SuggestionUITests/PopoverViewTests.swift | FOUND |
| OpenGramTests/SuggestionUITests/SuggestionPopoverPanelTests.swift | FOUND |
| Commit 2a0f7e9 (RED tests) | FOUND |
| Commit 9f2a9df (GREEN implementation) | FOUND |
| swift test: 174 tests, 0 failures | PASSED |
