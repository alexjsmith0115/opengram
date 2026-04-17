---
phase: 18-paragraph-rephrase-card
plan: "05"
subsystem: SuggestionUI
tags: [rephrase-card, swiftui, nspanel, lifecycle, fr-18, fr-19, d-02, d-04, d-05, d-06, d-08, d-09]
dependency_graph:
  requires: [02, 03, 04]
  provides: [RephraseCardView, RephraseCardPanelController]
  affects:
    - OpenGram/SuggestionUI/RephraseCard/RephraseCardView.swift
    - OpenGram/SuggestionUI/Panels/RephraseCardPanelController.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewTests.swift
    - OpenGramTests/SuggestionUITests/Panels/RephraseCardPanelControllerTests.swift
    - OpenGram.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - SwiftUI Text composition via AttributedString (mint background workaround — Text.background returns some View)
    - NSPanel nonactivatingPanel + NSHostingView + fittingSize sizing (LLMPanelController template)
    - TextMonitor.onKeystroke closure-chaining for subscription install/restore
    - AXUIElementCopyAttributeValue + AXValueGetValue for caret-in-paragraph check
key_files:
  created:
    - OpenGram/SuggestionUI/RephraseCard/RephraseCardView.swift
    - OpenGram/SuggestionUI/Panels/RephraseCardPanelController.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewTests.swift
    - OpenGramTests/SuggestionUITests/Panels/RephraseCardPanelControllerTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "AttributedString.backgroundColor used for mint-highlight on added tokens — Text.background() returns some View not Text, making it incompatible with Text concatenation"
  - "TextMonitor.onKeystroke subscription uses closure-chaining (capture previousKeystroke, restore on hide) matching research A3 sole-subscriber pattern"
  - "onHide callback called at end of hide() after all teardown so caller receives callback after panel is fully torn down"
metrics:
  duration: "~25 min"
  completed: "2026-04-16"
  tasks_completed: 2
  files_modified: 5
---

# Phase 18 Plan 05: RephraseCard UI Shell Summary

One-liner: SwiftUI RephraseCardView (teal accent bar, additions-only diff, What changed? toggle, Accept/Dismiss) hosted by RephraseCardPanelController (NSPanel lifecycle, resignKey hide, TextMonitor keystroke subscription).

## What Was Built

**Task 1 — RephraseCardView:**
- ZStack layout: `RoundedRectangle` background + leading `Rectangle().fill(Color.teal)` accent bar (3pt) + VStack content
- Header: `Text(header).foregroundStyle(Color.teal)` left + "What changed?" toggle button right
- Body: `ScrollView` wrapping `composedBody` (Text composition from DiffSegments)
- Mint background on added tokens via `AttributedString.backgroundColor` (not `.background()` which returns `some View`)
- Full-diff mode: `.removed` rendered with `.strikethrough().foregroundStyle(.secondary)` + added with `NSFont.boldSystemFont`
- Additions-only mode (default): `.removed` omitted, added with mint bg only
- Actions: Dismiss (plain) + Accept (bordered, `.tint(Color.teal)`, `.keyboardShortcut(.defaultAction)`)
- `@State private var showFullDiff = false` resets to false on each appearance (D-03)

**Task 2 — RephraseCardPanelController:**
- Mirrors LLMPanelController exactly: `styleMask: [.nonactivatingPanel]`, `.popUpMenu` level, `canJoinAllSpaces`, `becomesKeyOnlyIfNeeded`, `isOpaque = false`, `hasShadow = false`
- `layoutSubtreeIfNeeded()` + `fittingSize` before `orderFront` (Phase 11 learning)
- resignKey observer (`NSWindow.didResignKeyNotification`) → `hide()` on click-outside (D-08)
- TextMonitor.onKeystroke closure-chaining: captures `previousKeystroke` on show, restores on hide (D-09 edit-closes multicast-safe)
- `handleKeystroke()`: `AXUIElementCopyAttributeValue` → `AXValueGetValue(.cfRange)` → caret-in-paragraph scalar range check → `hide()`
- `onHide` callback fired last in `hide()` after full teardown
- Safe double-call: `hide()` before `show()` is a no-op

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RephraseCardView + structural tests | 1e7932d | RephraseCardView.swift, RephraseCardViewTests.swift, project.pbxproj |
| 2 | RephraseCardPanelController + lifecycle tests | e8d5a7d | RephraseCardPanelController.swift, RephraseCardPanelControllerTests.swift, project.pbxproj |

## Verification

- `struct RephraseCardView: View` present
- `Color.teal` appears 4 times (accent bar, header foregroundStyle, comment, Accept tint)
- `Color.mint.opacity` and `systemMint` each referenced (mint background contract)
- `@State private var showFullDiff` present
- `"What changed?"` present
- `"Accept"` and `"Dismiss"` each present
- `final class RephraseCardPanelController` present
- `PanelPositioner.marginOrigin` call present
- `styleMask: [.nonactivatingPanel]` present
- `textMonitor.onKeystroke =` assignment present
- `NSWindow.didResignKeyNotification` present
- pbxproj has ≥8 `RephraseCardPanelController` hits
- xcodebuild BUILD SUCCEEDED
- 5 new @Test cases green (2 view + 3 controller)
- 14 TextMonitorTests still green (subscription restoration correct)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Text.background() not composable in Text concatenation**
- **Found during:** Task 1 implementation
- **Issue:** `Text(s).background(Color.mint.opacity(0.25))` returns `some View`, not `Text`. Cannot use in `Text + Text` concatenation for `composedBody`.
- **Fix:** Used `AttributedString` with `attr.backgroundColor = NSColor.systemMint.withAlphaComponent(0.35)` — stays a `Text` value. Visually equivalent (≈ mint 0.25 opacity).
- **Files modified:** RephraseCardView.swift
- **Commit:** 1e7932d

**2. [Rule 3 - Blocking] Commits initially went to main branch instead of worktree branch**
- **Found during:** Post-commit verification
- **Issue:** `cd /Users/alex/Dev/opengram && git commit` executed against the main repo's `main` branch, not the worktree branch `worktree-agent-adf14c0f`.
- **Fix:** Cherry-picked both commits onto the worktree branch. Task commits: 1e7932d, e8d5a7d.
- **Files modified:** none (git plumbing only)

## Known Stubs

None. The card view and panel controller are complete implementations. Accept/Dismiss callbacks are provided by the caller at `show()` time — Plan 07 wires the real AX replacement and scheduler dismiss paths.

## Threat Flags

None — no new network endpoints, auth paths, file access, or schema changes. The AXUIElementCopyAttributeValue call is read-only (caret query only).

## Self-Check: PASSED

- OpenGram/SuggestionUI/RephraseCard/RephraseCardView.swift: FOUND
- OpenGram/SuggestionUI/Panels/RephraseCardPanelController.swift: FOUND
- OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewTests.swift: FOUND
- OpenGramTests/SuggestionUITests/Panels/RephraseCardPanelControllerTests.swift: FOUND
- Commit 1e7932d: FOUND (git log)
- Commit e8d5a7d: FOUND (git log)
- xcodebuild BUILD SUCCEEDED
- 5 tests PASSED
