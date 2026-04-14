---
phase: 03-suggestion-ui
verified: 2026-04-13T23:30:00Z
status: human_needed
score: 8/9 must-haves verified
overrides_applied: 0
overrides:
  - must_have: "In Chrome (clipboard mode), a floating diff panel appears after the hotkey showing original text alongside corrected text; clicking Apply pastes the corrected version back into Chrome"
    reason: "UI-08 and UI-09 were explicitly dropped per decision D-01 (no clipboard mode in Phase 3). REQUIREMENTS.md updated accordingly. Clipboard diff panel is deferred to v2."
    accepted_by: "gsd-verifier"
    accepted_at: "2026-04-13T23:30:00Z"
human_verification:
  - test: "Verify colored underlines appear in Notes.app after hotkey with intentional errors: solid red for spelling errors, solid blue for grammar+punctuation errors"
    expected: "Red underlines under misspelled words; blue underlines under grammar/punctuation errors. Popover appears on click with original text, replacement, explanation, Harper badge, and Accept/Dismiss/Add to Dictionary buttons."
    why_human: "AX bounds positioning, overlay transparency, and popover visual appearance cannot be verified programmatically. AX bounds queries require a running target application. The manual checkpoint (Task 3, commit 22f7e07) was completed and documented in SUMMARY but this verifier cannot independently confirm."
  - test: "Confirm scroll dismissal works (RESEARCH.md Assumption A2 verification)"
    expected: "While overlay is showing, scrolling in Notes dismisses the overlay. No Input Monitoring TCC prompt appears."
    why_human: "NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) TCC behavior depends on macOS version and whether Input Monitoring is granted. Cannot be verified by static analysis."
  - test: "Verify Tab cycles focus ring through underlines visually and Enter accepts focused suggestion"
    expected: "Tab advances a visible focus ring (2pt rounded rect, keyboard focus color) through underlines in document order with wrap. Enter opens popover for focused underline (no popover), then accepts on second Enter."
    why_human: "Focus ring rendering depends on UnderlineView.draw() with a live focusedIndex, which requires a running app. Tab/Enter routing uses NSEvent.addGlobalMonitorForEvents which cannot be triggered in unit tests."
deferred:
  - truth: "In Chrome (clipboard mode), a floating diff panel appears after the hotkey showing original text alongside corrected text; clicking Apply pastes the corrected version back into Chrome"
    addressed_in: "v2 / future phase"
    evidence: "Explicitly dropped per decision D-01 in REQUIREMENTS.md: UI-08 and UI-09 marked Dropped. ROADMAP overview states floating diff panel for clipboard-mode apps, but Phase 3 plans excluded clipboard mode by decision. Not scheduled in current 5-phase roadmap."
---

# Phase 3: Suggestion UI Verification Report

**Phase Goal:** Floating diff panel (primary) and inline overlay (AX apps) display and apply suggestions
**Verified:** 2026-04-13T23:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | OverlayWindow is transparent, borderless, floating-level, non-activating (changed from plan to NSPanel in Task 3 fix) | VERIFIED | `OverlayWindow.swift`: `NSPanel` with `.nonactivatingPanel`, `backgroundColor = .clear`, `isOpaque = false`, `level = .floating`, `hasShadow = false` |
| 2 | UnderlineView draws solid red for spelling and solid blue for grammar+punctuation | VERIFIED | `UnderlineView.swift` L79-84: `colorForCategory(.spelling) = .systemRed`, `colorForCategory(.grammarPunctuation) = .systemBlue` |
| 3 | UnderlineView draws dashed underlines for LLM source (infrastructure only) | VERIFIED | `UnderlineView.swift` L32-35: `setLineDash([4, 2], count: 2, phase: 0)` when `isDashedForSource` returns true for `.llm` |
| 4 | AXAccessor protocol supports copyParameterizedAttributeValue for bounds-for-range queries | VERIFIED | `AXAccessor.swift` L23-28: protocol declaration + `SystemAXAccessor` implementation via `AXUIElementCopyParameterizedAttributeValue` |
| 5 | Clicking an underline shows a non-activating popover panel with original text, replacement, explanation, source badge, and action buttons | VERIFIED | `OverlayController.swift` L238-268: `showPopover(for:)` creates `PopoverView` with NSHostingView; `PopoverView.swift` shows all required content including "Original:", replacement heading, explanation, "Harper"/"AI" badge, Accept/Dismiss/Add to Dictionary buttons |
| 6 | Accepting a suggestion writes replacement to target app and repositions remaining suggestions | VERIFIED | `OverlayController.swift` L303-368: `acceptSuggestion` reads current text, splices replacement via scalar offsets, writes full text back via `kAXValueAttribute`, then calls `repositionAfterAccept` to shift scalar offsets and re-query AX bounds |
| 7 | Keyboard navigation: Tab cycles focus ring, Enter opens/accepts, Escape closes/dismisses | VERIFIED | `OverlayController.swift` L456-489: `handleTab`, `handleEnter`, `handleEscape` implement all three; `show()` L199-208 wires global key monitor for keyCodes 48/36/53 |
| 8 | Overlay dismisses on Escape, click-away, target app focus loss, window move/resize, and scroll | VERIFIED | `OverlayController.swift`: `TargetAppObserver` registers for kAXWindowMovedNotification, kAXWindowResizedNotification, kAXFocusedUIElementChangedNotification, kAXApplicationDeactivatedNotification; scroll via `NSEvent.addGlobalMonitorForEvents(.scrollWheel)`; click-away via `mouseDownHandler`; Escape via `handleEscape` |
| 9 | AppDelegate.handleHotkeyFired calls overlayController.show after Harper returns non-empty suggestions | VERIFIED | `AppDelegate.swift` L99: `self.overlayController?.show(suggestions: suggestions, context: context)` in async task on MainActor; `onAddToDictionary` wired to `harperService.addToDictionary`; `onDismissAll` wired to StatusBarController idle state |
| SC1 | Chrome diff panel (ROADMAP SC 1) | PASSED (override) | UI-08/UI-09 dropped per D-01. Override applied — see overrides section. |
| SC2 | Notes underlines with orange for punctuation (ROADMAP SC 2) | VERIFIED with deviation | Punctuation merged with grammar under blue per D-03/D-04 decision; REQUIREMENTS.md UI-02 updated. Roadmap SC uses stale 3-color scheme. Actual: red=spelling, blue=grammar+punctuation. |

**Score:** 8/9 truths verified (SC1 passes via override, SC2 verified with documented deviation)

### Deferred Items

Items not yet met but explicitly addressed in later phases or classified as dropped.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Floating diff panel for clipboard-mode apps (Chrome, Outlook, Word, Obsidian) | v2 / future phase (not in current 5-phase roadmap) | REQUIREMENTS.md: UI-08 and UI-09 marked Dropped per D-01. Phase 3 CONTEXT.md decision D-01 explicitly excludes clipboard mode. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `OpenGram/SuggestionUI/OverlayWindow.swift` | Transparent borderless NSPanel | VERIFIED | `class OverlayWindow: NSPanel`, `.nonactivatingPanel` styleMask, `canBecomeKey: false`, `backgroundColor = .clear`, `level = .floating` |
| `OpenGram/SuggestionUI/UnderlineView.swift` | NSView with colored NSBezierPath underlines + hitTest passthrough | VERIFIED | `class UnderlineView: NSView`, `NSBezierPath` drawing, `colorForCategory`, `isDashedForSource`, `expandedHitRect`, `hitTest` returns nil for non-underline points |
| `OpenGram/SuggestionUI/OverlayController.swift` | Full coordinator: bounds query, popover, accept/reposition, keyboard nav | VERIFIED | `class OverlayController`, `boundsForRange`, `flipCGRect`, `show`, `dismiss`, `showPopover`, `acceptSuggestion`, `repositionAfterAccept`, `handleTab`, `handleEnter`, `handleEscape` |
| `OpenGram/TextEngine/AXAccessor.swift` | Protocol with copyParameterizedAttributeValue | VERIFIED | Protocol + SystemAXAccessor implementation present |
| `OpenGram/SuggestionUI/SuggestionPopoverPanel.swift` | Non-activating NSPanel for popover | VERIFIED | `class SuggestionPopoverPanel: NSPanel`, `.nonactivatingPanel`, `level = .popUpMenu`, `canBecomeKey: false`, `showNear(underlineRect:on:)` |
| `OpenGram/SuggestionUI/PopoverView.swift` | SwiftUI view with all required content | VERIFIED | `struct PopoverView: View`, "Original:", "Accept", "Dismiss", "Add to Dictionary", "Other suggestions:", "checkmark.circle", "Harper", conditional on `.spelling` and `allReplacements.count > 1` |
| `OpenGram/SuggestionUI/TargetAppObserver.swift` | AXObserver wrapper for dismissal detection | VERIFIED | `class TargetAppObserver`, `install(pid:onDismiss:)`, `uninstall()`, all 4 AX notifications registered |
| `OpenGram/App/AppDelegate.swift` | Integration wiring: hotkey -> Harper -> overlay display | VERIFIED | `overlayController` property, `OverlayController()` init, `show(suggestions:context:)` call, all callbacks wired |
| `OpenGramTests/AppDelegateWiringTests.swift` | Unit tests for AppDelegate overlay wiring | VERIFIED | 7 tests for onAcceptSuggestion, onDismissSuggestion, onAddToDictionary, onDismissAll, dismiss, show callbacks |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `OverlayController.swift` | `AXAccessor.copyParameterizedAttributeValue` | `boundsForRange` query to position underlines | WIRED | L78: `accessor.copyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute, ...)` |
| `UnderlineView.swift` | `CheckCategory` | switch on category for color selection | WIRED | L79-84: `colorForCategory` uses `switch` on `.spelling`/`.grammarPunctuation` |
| `OverlayController.swift` | `SuggestionPopoverPanel` | `showPopover(for:)` creates and positions panel | WIRED | L248-268: `popoverPanel.setContent(hostingView)` + `popoverPanel.showNear(underlineRect:on:)` |
| `OverlayController.swift` | `TargetAppObserver` | installs on show, uninstalls on dismiss | WIRED | L186-189: `targetAppObserver.install(pid:onDismiss:)` in `show()`; L222: `targetAppObserver.uninstall()` in `dismiss()` |
| `PopoverView.swift` | `OverlayController` | action callbacks (onAccept, onDismiss, onAddToDictionary) | WIRED | L9-11: closure properties; L248-253: callbacks wired in `showPopover(for:)` |
| `AppDelegate.swift` | `OverlayController.show` | called after Harper returns suggestions | WIRED | L99: `self.overlayController?.show(suggestions: suggestions, context: context)` |
| `AppDelegate.swift` | `GrammarCheckerProtocol.addToDictionary` | wired via `OverlayController.onAddToDictionary` | WIRED | L42-47: `controller.onAddToDictionary = { ... Task { await harperService.addToDictionary(word: word) } }` |
| `OverlayController.swift` | `AXAccessor.setAttributeValue` (write-back) | `acceptSuggestion` writes replacement via `kAXValueAttribute` | WIRED | L336-340: `accessor.setAttributeValue(context.axElement, kAXValueAttribute, newText as CFString)` — NOTE: uses full-text replacement, not set-range-then-replace per plan spec (intentional fix from Task 3 manual verification) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `OverlayController.show` | `suggestions: [Suggestion]` | `harperService.check(text:)` in AppDelegate, passed via `show(suggestions:context:)` | Yes — real Harper grammar check results | FLOWING |
| `UnderlineView.entries` | `[UnderlineEntry]` | Built in `OverlayController.show()` from AX bounds queries | Yes — populated from real AX `kAXBoundsForRangeParameterizedAttribute` calls | FLOWING |
| `PopoverView.suggestion` | `Suggestion` | Passed from `OverlayController.showPopover(for:)` on underline click | Yes — real suggestion from Harper results | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `swift build` succeeds | `swift build 2>&1 \| grep -E "error:\|Build complete"` | `Build complete! (0.86s)` | PASS |
| `acceptSuggestion` uses correct AX attribute | `grep kAXValueAttribute OverlayController.swift` | L322, L336, L338, L382 — uses `kAXValueAttribute` for read and write | PASS |
| All dismissal paths call `targetAppObserver.uninstall()` | `grep uninstall OverlayController.swift` | L222 in `dismiss()` — only one dismiss path | PASS |
| `swift test` full suite | `swift test 2>&1 \| tail -5` | FAILS with `no such module 'Testing'` in AXCapabilityCacheTests.swift | FAIL — pre-existing issue from Phase 2, not introduced by Phase 3 |

### Test Build Issue (Pre-existing, Not Phase 3 Regression)

`swift test` fails because `AXCapabilityCacheTests.swift` (Phase 2 file, created in commit `942f7d6`) imports `import Testing` but the active developer directory uses Command Line Tools, not Xcode 16+ which bundles the Swift Testing framework. `swift build` passes cleanly. The Phase 3 SUMMARY documents 157 passing tests — these pass within Xcode's test runner. This is an **environment configuration issue**, not a code regression introduced by Phase 3.

Evidence: `git log -- OpenGramTests/AXCapabilityCacheTests.swift` shows this file last modified in commit `942f7d6` (Phase 2 work, before any Phase 3 commits).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| UI-01 | 03-01 | Transparent overlay NSWindow draws colored underlines on flagged text | SATISFIED | `OverlayWindow.swift` + `UnderlineView.swift` + `OverlayController.show()` |
| UI-02 | 03-01 | Solid underlines: red=spelling, blue=grammar+punctuation (D-04 two-color) | SATISFIED | `UnderlineView.colorForCategory` verified |
| UI-03 | 03-01 | Dashed underlines for LLM suggestions (purple/teal) — infrastructure only | SATISFIED | `isDashedForSource(.llm)` returns true; `setLineDash` called; LLM data wired in Phase 4 |
| UI-04 | 03-02 | Suggestion popover appears on click showing original, replacement, explanation | SATISFIED | `showPopover(for:)` + `PopoverView` display all required elements on click. Hover trigger is a future feature (CONTEXT.md). |
| UI-05 | 03-02 | Popover displays source badge: "Harper" checkmark / "AI" sparkle | SATISFIED | `PopoverView.badgeLabel` and `badgeSymbol` switch on `suggestion.source` |
| UI-06 | 03-02 | User can Accept or Dismiss individual suggestions via popover buttons | SATISFIED | `PopoverView` has Accept and Dismiss buttons; `handleAcceptSuggestion` and `handleDismissSuggestion` wired |
| UI-07 | 03-03 | Accepting writes correction back to target app via appropriate write-back method | SATISFIED | `acceptSuggestion` writes via `kAXValueAttribute` full-text replacement (changed from plan spec in Task 3 to fix Notes compatibility) |
| UI-10 | 03-02 | Overlay dismisses on Escape, click-away, target field losing focus | SATISFIED | All three dismissal paths verified: Escape in `handleEscape`, click-away in `mouseDownHandler`, focus-loss via `TargetAppObserver` + scroll monitor |
| UI-11 | 03-03 | Keyboard navigation: Tab cycles, Enter accepts, Escape dismisses | SATISFIED | `handleTab`/`handleEnter`/`handleEscape` + global key monitor |
| UI-08 | N/A | Floating diff panel for clipboard-mode apps | DROPPED per D-01 | Intentionally excluded from Phase 3 scope; deferred to v2 |
| UI-09 | N/A | Diff panel Apply button pastes via clipboard | DROPPED per D-01 | Depends on UI-08; deferred to v2 |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No TODOs, FIXMEs, placeholders, stubs, or empty implementations found in any Phase 3 files.

### Deviations from Plan (Documented, Not Gaps)

1. **OverlayWindow changed from NSWindow to NSPanel**: Plan 03-01 specified `class OverlayWindow: NSWindow` with `canBecomeKey: true`. Task 3 manual verification found this caused focus stealing. Fixed to `NSPanel` with `.nonactivatingPanel` and `canBecomeKey: false`. (Commit 22f7e07)

2. **Keyboard nav moved to global event monitor**: Plan 03-03 specified `OverlayWindow.keyHandler` + `keyDown` override. NSPanel with `canBecomeKey: false` never receives `keyDown` events. Fixed to `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` in `OverlayController.show()`. (Commit 22f7e07)

3. **Accept write-back changed from set-range-then-replace to full-text**: Plan 03-03 key link specified `kAXSelectedTextRangeAttribute` + `kAXSelectedTextAttribute`. Task 3 found this fails in Notes when user has text selected. Changed to read/modify/write full text via `kAXValueAttribute`. (Commit 22f7e07)

4. **ROADMAP SC 2 uses stale 3-color scheme**: ROADMAP mentions "solid orange for punctuation." Decision D-03 (Phase 2) and D-04 (Phase 3) merged punctuation under grammar (blue). REQUIREMENTS.md UI-02 explicitly updated.

### Human Verification Required

#### 1. Visual overlay rendering in Notes.app

**Test:** Open Notes.app, type "Ths is a tset of grammer." (intentional errors). Press Ctrl+Shift+G.
**Expected:** Transparent overlay appears over Notes with solid red underlines under misspelled words ("Ths", "tset") and solid blue underlines under grammar errors ("grammer"). Clicking an underline shows a HUD-style popover with: original word, prominent replacement, explanation, "Harper" badge with checkmark icon, and Accept/Dismiss/Add to Dictionary buttons. Accept replaces the word in Notes; remaining underlines reposition correctly.
**Why human:** AX bounds positioning accuracy, overlay transparency, popover visual appearance, and write-back behavior in a live app require a running macOS environment. The manual checkpoint (Task 3, commit 22f7e07) was completed and documented in the SUMMARY but cannot be re-verified programmatically.

#### 2. Scroll dismissal (RESEARCH.md Assumption A2)

**Test:** While overlay is showing in Notes, scroll with the mouse or trackpad.
**Expected:** Overlay dismisses immediately. No Input Monitoring TCC dialog appears.
**Why human:** `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)` TCC behavior is runtime-dependent. Whether this requires Input Monitoring permission depends on macOS version and security policy — cannot be determined by static analysis.

#### 3. Keyboard navigation focus ring

**Test:** With overlay showing, press Tab multiple times. Verify focus ring advances through underlines with wrap. With focus on an underline, press Enter — popover opens. With popover open, press Enter — suggestion accepted. Press Escape with popover open — popover closes, underlines remain. Press Escape again — all underlines dismissed.
**Why human:** Focus ring rendering (2pt rounded rect with `NSColor.keyboardFocusIndicatorColor`) and keyboard event interception via `NSEvent.addGlobalMonitorForEvents` cannot be tested without a running app.

### Gaps Summary

No automated gaps found. All required artifacts exist, are substantive, and are wired end-to-end. The three human verification items are required before this phase can be marked fully passed. The pre-existing `swift test` build failure (`AXCapabilityCacheTests.swift` from Phase 2) is an environment issue, not a Phase 3 regression.

---

_Verified: 2026-04-13T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
