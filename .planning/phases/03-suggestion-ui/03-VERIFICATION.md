---
phase: 03-suggestion-ui
verified: 2026-04-14T00:00:00Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 1
overrides:
  - must_have: "In Chrome (clipboard mode), a floating diff panel appears after the hotkey showing original text alongside corrected text; clicking Apply pastes the corrected version back into Chrome"
    reason: "UI-08 and UI-09 were explicitly dropped per decision D-01 (no clipboard mode in Phase 3). REQUIREMENTS.md updated accordingly. Clipboard diff panel is deferred to v2."
    accepted_by: "gsd-verifier"
    accepted_at: "2026-04-13T23:30:00Z"
re_verification:
  previous_status: human_needed
  previous_score: 8/9
  gaps_closed:
    - "Scroll dismiss (UAT Test 7): cgEvent PID filter removed; scroll monitor now fires dismiss() unconditionally (commit fffa0c6)"
    - "Reposition after accept (UAT Test 5): repositionAfterAccept now recalculates window frame from union of screen-coord entry rects and calls setFrame (commit 5942772)"
  gaps_remaining: []
  regressions:
    - "Previous verification incorrectly marked Tab/Enter keyboard navigation as VERIFIED. Tab/Enter were removed per D-14/D-15 decisions. Escape-only is the correct current state and satisfies Plan 03-03 must_haves."
human_verification:
  - test: "Verify colored underlines appear in Notes.app after hotkey — visual accuracy"
    expected: "Red underlines under misspelled words; blue underlines under grammar/punctuation errors. Overlay does not steal focus from Notes. Clicking an underline shows popover with original text, replacement, explanation, Harper badge, and Accept/Dismiss/Add to Dictionary buttons. Accept replaces word in Notes."
    why_human: "AX bounds positioning accuracy, overlay transparency, and popover visual appearance require a running macOS environment. UAT confirmed pass for Tests 1-4 and 6 prior to Plan 04; visual confirmation remains manual."
  - test: "Re-test scroll dismissal after Plan 04 fix (UAT Test 7 regression)"
    expected: "While overlay is showing in Notes, scrolling with mouse or trackpad dismisses the overlay immediately. No Input Monitoring TCC dialog appears."
    why_human: "UAT Test 7 was FAILED (cgEvent nil bug). Plan 04 applied the fix (commit fffa0c6). The fix cannot be triggered by unit tests (no event loop). Manual re-test required to confirm scroll now dismisses in Notes."
  - test: "Re-test reposition after accept after Plan 04 fix (UAT Test 5 regression)"
    expected: "With multiple underlines visible, accept a suggestion that changes word length. Remaining underlines shift to stay aligned with their corresponding text (not stuck at old positions)."
    why_human: "UAT Test 5 was FAILED (missing setFrame call). Plan 04 applied the fix (commit 5942772). AX bounds re-query requires live app. Manual re-test required to confirm remaining underlines reposition correctly in Notes."
---

# Phase 3: Suggestion UI Verification Report

**Phase Goal:** Users see errors highlighted in the target application and can accept or dismiss individual suggestions — transparent overlay with colored underlines and click-to-show popover for AX-direct apps
**Verified:** 2026-04-14T00:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after Plan 04 gap closure (commits fffa0c6, 5942772)

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | OverlayWindow is transparent, borderless, floating-level, non-activating, and receives mouse events for underline clicks | VERIFIED | `OverlayWindow.swift`: `NSPanel` with `.nonactivatingPanel`, `backgroundColor = .clear`, `isOpaque = false`, `level = .floating`, `hasShadow = false`, `canBecomeKey: false` |
| 2  | UnderlineView draws solid red underlines for spelling and solid blue for grammar+punctuation | VERIFIED | `UnderlineView.swift`: `colorForCategory(.spelling) = .systemRed`, `colorForCategory(.grammarPunctuation) = .systemBlue` |
| 3  | UnderlineView draws dashed underlines for LLM source (infrastructure only) | VERIFIED | `UnderlineView.swift`: `isDashedForSource(.llm) = true`, `setLineDash([4, 2], count: 2, phase: 0)` in `draw()` |
| 4  | AXAccessor protocol supports copyParameterizedAttributeValue for bounds-for-range queries | VERIFIED | `AXAccessor.swift`: protocol declaration + `SystemAXAccessor` implementation via `AXUIElementCopyParameterizedAttributeValue` |
| 5  | OverlayController converts Suggestion ranges to screen CGRects via AX bounds query and CG-to-AppKit coordinate flip | VERIFIED | `OverlayController.swift`: `boundsForRange` packs `CFRange` into `AXValue`, calls `copyParameterizedAttributeValue` with `kAXBoundsForRangeParameterizedAttribute`, `flipCGRect` flips CG→AppKit |
| 6  | Clicking an underline shows a popover panel with original text, replacement, explanation, source badge, and action buttons | VERIFIED | `OverlayController.swift` L187-229: `showPopover(for:)` creates `PopoverView` in `NSHostingView`; `PopoverView.swift` shows all required content per UI-SPEC |
| 7  | Accepting a suggestion writes the replacement text to the target app via AX and repositions remaining suggestions | VERIFIED | `OverlayController.swift` L283-354: `acceptSuggestion` probes for range-write, falls back to full-text write; calls `repositionAfterAccept` for survivors |
| 8  | After accepting the last suggestion the overlay dismisses automatically | VERIFIED | `OverlayController.swift` L343-345: `if suggestions.isEmpty { dismiss(); return }` |
| 9  | Escape closes popover (popover open) or dismisses all (no popover open); Tab/Enter deferred to Phase 6 per D-14/D-15 | VERIFIED | `OverlayController.swift` L488-493: `handleEscape()` closes popover or calls dismiss(); key monitor fires only on keyCode 53 (Escape); D-14/D-15 decisions explicitly defer Tab/Enter |
| 10 | Overlay dismisses on click-away, target app focus loss, window move/resize, app deactivate, and scroll | VERIFIED | `OverlayController.swift` L144-148: unconditional scroll monitor (Plan 04 fix); L115-141: `TargetAppObserver` registered for all 4 AX notifications; `mouseDownHandler` for click-away |
| 11 | AppDelegate.handleHotkeyFired calls overlayController.show after Harper returns non-empty suggestions | VERIFIED | `AppDelegate.swift` L102: `self.overlayController?.show(suggestions: suggestions, context: context)`; L43-51: `onAddToDictionary` wired to `harperService.addToDictionary`; `onDismissAll` wired to status reset |
| 12 | AX bounds queries are capped at 50 suggestions to prevent main-thread blocking (T-03-02) | VERIFIED | `OverlayController.swift` L11: `private static let maxDisplayedSuggestions = 50`; L73: `Array(suggestions.prefix(Self.maxDisplayedSuggestions))` |
| 13 | Scrolling dismisses the overlay (Plan 04 fix — scroll monitor fires unconditionally) | VERIFIED | `OverlayController.swift` L144-148: `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)` calls `self?.dismiss()` unconditionally; cgEvent PID filter removed |
| 14 | After accepting, remaining underlines reposition by recalculating window frame from new entry rects (Plan 04 fix) | VERIFIED | `OverlayController.swift` L463-481: `repositionAfterAccept` builds screen-coord entries, computes union rect, calls `overlayWindow.setFrame(newWindowRect, display: false)` |
| SC1 | Chrome diff panel (ROADMAP SC 1 — stale) | PASSED (override) | UI-08/UI-09 dropped per D-01. Override applied from initial verification. |

**Score:** 10/10 truths verified (SC1 passes via override; Tab/Enter deferred per D-14/D-15 noted in Truth #9)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Tab/Enter keyboard navigation (UI-11 partial) | Phase 6 | `03-CONTEXT.md` line 118: "D-14/D-15 (Tab/Enter conflict with target app text editing). Phase 3 implements Escape-only keyboard interaction." REQUIREMENTS.md UI-11 remains Pending for Phase 3. |
| 2 | Floating diff panel for clipboard-mode apps (UI-08, UI-09) | v2 / future phase | REQUIREMENTS.md: UI-08 and UI-09 marked Dropped per D-01. Not in current 5-phase roadmap. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `OpenGram/SuggestionUI/OverlayWindow.swift` | Transparent borderless NSPanel | VERIFIED | `class OverlayWindow: NSPanel`, `.nonactivatingPanel`, `canBecomeKey: false`, `backgroundColor = .clear`, `level = .floating`, `hasShadow = false` |
| `OpenGram/SuggestionUI/UnderlineView.swift` | NSView with colored NSBezierPath underlines + hitTest passthrough | VERIFIED | `class UnderlineView: NSView`, `NSBezierPath` drawing, `colorForCategory`, `isDashedForSource`, `expandedHitRect`, `hitTest` returns nil for non-underline points |
| `OpenGram/SuggestionUI/OverlayController.swift` | Full coordinator: bounds query, popover, accept/reposition, Escape key | VERIFIED | All required functions present; Plan 04 fixes confirmed (unconditional scroll, window frame recalc in repositionAfterAccept) |
| `OpenGram/TextEngine/AXAccessor.swift` | Protocol with copyParameterizedAttributeValue | VERIFIED | Protocol + SystemAXAccessor implementation present |
| `OpenGram/SuggestionUI/SuggestionPopoverPanel.swift` | Non-activating NSPanel for popover | VERIFIED | `class SuggestionPopoverPanel: NSPanel`, `.nonactivatingPanel`, `level = .popUpMenu`, `canBecomeKey: false`, `showNear(underlineRect:on:)` |
| `OpenGram/SuggestionUI/PopoverView.swift` | SwiftUI view with all required content | VERIFIED | `struct PopoverView: View`, "Original:", "Accept", "Dismiss", "Add to Dictionary", "Other suggestions:", "checkmark.circle", "Harper", conditional on `.spelling` and `allReplacements.count > 1` |
| `OpenGram/SuggestionUI/TargetAppObserver.swift` | AXObserver wrapper for dismissal detection | VERIFIED | `class TargetAppObserver`, `install(pid:onDismiss:)`, `uninstall()`, all 4 AX notifications, single `Unmanaged.passRetained` + stored release, `Task { @MainActor in }` dispatch |
| `OpenGram/App/AppDelegate.swift` | Integration wiring: hotkey -> Harper -> overlay display | VERIFIED | `overlayController` property, `OverlayController()` init, `show(suggestions:context:)` call, all callbacks wired |
| `OpenGramTests/AppDelegateWiringTests.swift` | Unit tests for AppDelegate overlay wiring | VERIFIED | 7 tests covering all callback wiring paths |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `OverlayController.swift` | `AXAccessor.copyParameterizedAttributeValue` | `boundsForRange` query to position underlines | WIRED | `accessor.copyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute, ...)` |
| `UnderlineView.swift` | `CheckCategory` | switch on category for color selection | WIRED | `colorForCategory` switches on `.spelling`/`.grammarPunctuation` |
| `OverlayController.swift` | `SuggestionPopoverPanel` | `showPopover(for:)` creates and positions panel | WIRED | `popoverPanel.setContent(hostingView)` + `popoverPanel.showNear(underlineRect:on:)` |
| `OverlayController.swift` | `TargetAppObserver` | installs on show, uninstalls on dismiss | WIRED | `targetAppObserver.install(pid:onDismiss:)` in `show()`; `targetAppObserver.uninstall()` in `dismiss()` |
| `PopoverView.swift` | `OverlayController` | action callbacks (onAccept, onDismiss, onAddToDictionary) | WIRED | Closure properties wired in `showPopover(for:)` |
| `AppDelegate.swift` | `OverlayController.show` | called after Harper returns suggestions | WIRED | `self.overlayController?.show(suggestions: suggestions, context: context)` |
| `AppDelegate.swift` | `GrammarCheckerProtocol.addToDictionary` | wired via `OverlayController.onAddToDictionary` | WIRED | `controller.onAddToDictionary = { ... Task { await harperService.addToDictionary(word: word) } }` |
| `OverlayController.scrollMonitor` | `OverlayController.dismiss()` | NSEvent global scroll monitor fires unconditionally (Plan 04 fix) | WIRED | L147-148: `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in self?.dismiss() }` |
| `OverlayController.repositionAfterAccept` | `overlayWindow.setFrame` | Recalculated union rect from new entries (Plan 04 fix) | WIRED | L481: `overlayWindow.setFrame(newWindowRect, display: false)` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `OverlayController.show` | `suggestions: [Suggestion]` | `harperService.check(text:)` in AppDelegate, passed via `show(suggestions:context:)` | Yes — real Harper grammar check results | FLOWING |
| `UnderlineView.entries` | `[UnderlineEntry]` | Built in `OverlayController.show()` from AX `kAXBoundsForRangeParameterizedAttribute` queries | Yes — populated from real AX bounds queries | FLOWING |
| `PopoverView.suggestion` | `Suggestion` | Passed from `OverlayController.showPopover(for:)` on underline click | Yes — real suggestion from Harper results | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `xcodebuild build` succeeds | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` | `BUILD SUCCEEDED` | PASS |
| Full test suite passes (175 tests) | `xcodebuild -scheme OpenGram test -destination 'platform=macOS'` | `Test run with 175 tests in 26 suites passed` | PASS |
| Scroll monitor is unconditional (Plan 04 fix) | `grep -n "scrollWheel" OverlayController.swift` | L147: no cgEvent condition; `_ in self?.dismiss()` | PASS |
| repositionAfterAccept calls setFrame (Plan 04 fix) | `grep -n "setFrame" OverlayController.swift` | L481: `overlayWindow.setFrame(newWindowRect, display: false)` | PASS |
| Tab/Enter not intercepted (D-14/D-15) | `grep "keyCode == 48\|keyCode == 36" OverlayController.swift` | No matches | PASS |
| Escape handler present | `grep "keyCode == 53\|handleEscape" OverlayController.swift` | L154: `if event.keyCode == 53 { self.handleEscape() }` | PASS |
| TargetAppObserver uses Task not assumeIsolated | `grep "Task.*MainActor\|assumeIsolated" TargetAppObserver.swift` | L30: `Task { @MainActor in` | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| UI-01 | 03-01 | Transparent overlay NSWindow draws colored underlines on flagged text | SATISFIED | `OverlayWindow.swift` + `UnderlineView.swift` + `OverlayController.show()` |
| UI-02 | 03-01 | Solid underlines: red=spelling, blue=grammar+punctuation (D-04 two-color) | SATISFIED | `UnderlineView.colorForCategory` verified; D-04 decision documented |
| UI-03 | 03-01 | Dashed underlines for LLM suggestions (infrastructure only) | SATISFIED | `isDashedForSource(.llm)` = true; `setLineDash` path present; LLM data wired in Phase 4 |
| UI-04 | 03-02 | Suggestion popover appears on click showing original, replacement, explanation | SATISFIED | `showPopover(for:)` + `PopoverView` display all required elements on click |
| UI-05 | 03-02 | Popover displays source badge: "Harper" checkmark / "AI" sparkle | SATISFIED | `PopoverView` switches on `suggestion.source`; "Harper"/"AI" and `checkmark.circle`/`sparkles` symbols |
| UI-06 | 03-02 | User can Accept or Dismiss individual suggestions via popover buttons | SATISFIED | `PopoverView` has Accept and Dismiss buttons; `handleAcceptSuggestion` and `handleDismissSuggestion` wired |
| UI-07 | 03-03 | Accepting writes correction back to target app | SATISFIED | `acceptSuggestion` probes for range-write, falls back to full-text via `kAXValueAttribute` |
| UI-08 | N/A | Floating diff panel for clipboard-mode apps | DROPPED per D-01 | REQUIREMENTS.md marks as Dropped; override applied |
| UI-09 | N/A | Diff panel Apply button pastes via clipboard | DROPPED per D-01 | Depends on UI-08; REQUIREMENTS.md marks as Dropped |
| UI-10 | 03-02, 03-04 | Overlay dismisses on Escape, click-away, target field focus loss, scroll | SATISFIED (code) / NEEDS RE-TEST (UAT) | All dismissal paths coded and verified; UAT Test 7 (scroll) was failed but Plan 04 fix applied — needs human re-test |
| UI-11 | 03-03 (partial) | Keyboard navigation: Tab cycles, Enter accepts, Escape dismisses | PARTIAL — Escape only | Escape implemented; Tab/Enter deferred to Phase 6 per D-14/D-15. REQUIREMENTS.md UI-11 remains Pending. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No TODOs, FIXMEs, placeholders, stubs, or empty implementations found in any Phase 3 production files.

### Human Verification Required

#### 1. Visual overlay rendering in Notes.app (previously passed UAT Tests 1-4, 6, 10-12)

**Test:** Open Notes.app, type "Ths is a tset of grammer." Press Ctrl+Shift+G.
**Expected:** Transparent overlay appears with solid red underlines under misspelled words and solid blue underlines under grammar errors. Clicking an underline shows a popover with original text, replacement, explanation, "Harper" badge with checkmark icon, Accept/Dismiss/Add to Dictionary buttons. Accept replaces the word in Notes. Dismiss removes underline without text change. Pressing Escape with popover open closes popover; pressing Escape again dismisses all underlines.
**Why human:** AX bounds positioning, overlay transparency, popover visual appearance, and write-back behavior require a running macOS environment.

#### 2. Scroll dismissal after Plan 04 fix (UAT Test 7 — previously FAILED)

**Test:** While overlay is showing in Notes, scroll with mouse or trackpad.
**Expected:** Overlay dismisses immediately. No Input Monitoring TCC dialog appears.
**Why human:** UAT Test 7 was explicitly FAILED before Plan 04. Plan 04 removed the unreliable cgEvent PID filter (commit fffa0c6). The fix cannot be triggered by unit tests. Manual re-test is required to confirm scroll now works.

#### 3. Reposition after accept after Plan 04 fix (UAT Test 5 — previously FAILED)

**Test:** With multiple underlines visible (type "Ths is a tset" — two misspellings), accept the first suggestion. Verify remaining underlines shift to stay aligned with their corresponding text, not stuck at old positions.
**Expected:** After accepting "Ths"→"This", the underline for "tset" repositions correctly over "tset" in the updated text.
**Why human:** UAT Test 5 was explicitly FAILED before Plan 04. Plan 04 added `overlayWindow.setFrame` and window-local coordinate retranslation (commit 5942772). AX bounds re-query requires live app. Manual re-test required to confirm repositioning is correct.

### Gaps Summary

No automated gaps found. All 10 must-have truths are verified in the codebase. Both UAT failures from the previous verification cycle were addressed by Plan 04 (commits fffa0c6, 5942772) and are verified in code. Three human verification items remain:

- Item 1 verifies UAT Tests 1-4, 6, 10-12 which previously passed — low risk, confirms no regression.
- Items 2 and 3 are the two UAT failures that Plan 04 fixed — these require human re-test to confirm the fixes are effective in a live app environment.

UI-11 (Tab/Enter keyboard navigation) is intentionally partial per decisions D-14/D-15 and is deferred to Phase 6. This does not block Phase 3 completion.

---

_Verified: 2026-04-14T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
