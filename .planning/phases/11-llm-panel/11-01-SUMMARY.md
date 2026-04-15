---
phase: "11-llm-panel"
plan: "11-01"
subsystem: "SuggestionUI"
tags: ["llm", "panel", "swiftui", "appkit", "diff"]
dependency_graph:
  requires:
    - "09-01"  # LLMStyleSuggestion model
  provides:
    - "LLMPanelController.show(suggestions:near:on:onApply:onDismiss:)"
    - "InlineDiffView(original:revised:)"
  affects:
    - "SuggestionUI layer"
tech_stack:
  added:
    - "InlineDiffView: LCS-based word diff renderer in SwiftUI"
    - "LLMSuggestionPanel: SwiftUI card for LLM style suggestions"
    - "LLMPanelController: NSPanel host (nonactivating, floating)"
  patterns:
    - "NSPanel with nonactivatingPanel styleMask (follows SuggestionPopoverPanel)"
    - "NSHostingView wrapping SwiftUI inside AppKit panel"
    - "Auto-flip positioning: above anchor, flip below if insufficient space"
key_files:
  created:
    - "OpenGram/SuggestionUI/InlineDiffView.swift"
    - "OpenGram/SuggestionUI/LLMSuggestionPanel.swift"
    - "OpenGram/SuggestionUI/LLMPanelController.swift"
  modified:
    - "OpenGram.xcodeproj/project.pbxproj"
decisions:
  - "Used LCS algorithm for word diff — minimal edit sequence, correct for short paragraph-level text"
  - "Panel shadow disabled on NSPanel (hasShadow=false); SwiftUI RoundedRectangle provides its own shadow to avoid double-shadow artifact"
  - "Category color extension kept file-private to LLMSuggestionPanel — no external consumers need it"
metrics:
  duration: "4 minutes"
  completed_date: "2026-04-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 1
---

# Phase 11 Plan 01: LLM Suggestion Panel Summary

**One-liner:** Non-activating NSPanel hosting SwiftUI suggestion card with LCS word diff, category-colored dots, and Apply/Dismiss callbacks.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | InlineDiffView word-level diff renderer | bac593c | InlineDiffView.swift, project.pbxproj |
| 2 | LLMSuggestionPanel + LLMPanelController | 29a2d60 | LLMSuggestionPanel.swift, LLMPanelController.swift, project.pbxproj |

## What Was Built

**InlineDiffView** computes a word-level diff using longest common subsequence between `original` and `revised` strings. Removed words render with strikethrough + red secondary tint; added words render bold + blue. Unchanged words are unstyled. Word-level granularity is sufficient for paragraph-level LLM suggestions.

**LLMSuggestionPanel** is a SwiftUI view that renders a vertical stack of up to three `LLMStyleSuggestion` rows. Each row has: a category-colored dot (purple=tone, blue=clarity, green=rephrase) + bold label, an `InlineDiffView`, a `.caption` explanation, and an Apply button. Suggestions are separated by dividers. A Dismiss button sits at the bottom.

**LLMPanelController** hosts the SwiftUI panel in a `NSPanel` with `.nonactivatingPanel` styleMask and `.popUpMenu` level — matching the established `SuggestionPopoverPanel` pattern. The panel is transparent (`backgroundColor = .clear`, `isOpaque = false`). `show()` sizes the panel via `intrinsicContentSize`, positions it above the anchor rect with auto-flip below if space is insufficient, and clamps to the screen's visible frame. `dismiss()` calls `orderOut` and releases the hosting view.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- InlineDiffView.swift: FOUND at OpenGram/SuggestionUI/InlineDiffView.swift
- LLMSuggestionPanel.swift: FOUND at OpenGram/SuggestionUI/LLMSuggestionPanel.swift
- LLMPanelController.swift: FOUND at OpenGram/SuggestionUI/LLMPanelController.swift
- Commit bac593c: FOUND
- Commit 29a2d60: FOUND
- xcodebuild: BUILD SUCCEEDED
