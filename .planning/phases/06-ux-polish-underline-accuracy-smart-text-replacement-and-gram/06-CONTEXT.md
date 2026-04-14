# Phase 6: UX Polish — Underline Accuracy, Smart Text Replacement, and Grammarly-Style Popover - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual and interaction refinement of the existing suggestion UI. Three focus areas: (1) accurate underline positioning with a proper bounds validation pipeline, (2) smart text replacement via range-targeted AX writes that integrate with the target app's undo stack, and (3) a Grammarly-style popover card with inline diff and click-to-accept interaction. No new features — this phase polishes what Phases 1–5 built.

</domain>

<decisions>
## Implementation Decisions

### Underline Rendering
- **D-01:** Keep straight lines with color (no squiggly/wavy). Refine thickness and color intensity. Current 2px solid lines retained as the base style.
- **D-02:** Full bounds validation pipeline inspired by TextWarden's approach (learn and reimplement, no code porting). Includes: bounds validation (reject garbage values like < 2px width), character-by-character fallback for bad ranges, multi-line span splitting into per-line segments, and AX watchdog timeout.
- **D-03:** Multi-line error spans rendered as per-line underline segments. Each visual line gets its own underline. Clicking any segment opens the same popover.
- **D-04:** Data-driven app quirks table — plist/JSON config mapping bundle IDs to known AX quirks (coordinate offsets, line height factors, bounds strategy overrides). Extensible without code changes.
- **D-05:** AX watchdog with 0.8s timeout. Auto-blocklist the app's bundle ID for 30 seconds on timeout. Skip underline rendering for blocklisted apps. Suggestions still logged and accessible via menu bar.

### Popover Redesign
- **D-06:** Grammarly-style floating card — solid opaque background (no vibrancy/blur), rounded corners, subtle shadow, clear visual hierarchy. Drop the current `.hudWindow` style mask; use plain borderless NSPanel with custom-drawn background.
- **D-07:** Inline diff: original text with red strikethrough, arrow, replacement in green.
- **D-08:** Primary replacement is the forefront of the popover UI. Click the suggested word directly to accept — no separate Accept button. Cursor change + hover highlight for discoverability.
- **D-09:** Alternative replacements shown via expandable disclosure ("N more suggestions"). Expanded list uses smaller text. Each alternative is clickable to accept.
- **D-10:** Dismiss and Add to Dictionary remain as explicit buttons. Add to Dictionary only shown for `.spelling` category (unchanged from Phase 3 D-07).

### Replacement UX
- **D-11:** Range-targeted AX write with fallback. Primary: set `AXSelectedTextRange` to error span, then set `AXSelectedText` to replacement (integrates with target app's native undo stack, Cmd+Z works). Fallback: full `AXValue` overwrite when app doesn't support `AXSelectedTextRange`.
- **D-12:** After accepting, immediately re-query AX bounds for all remaining suggestions and rebuild underline entries. Drop underlines whose bounds re-query fails; keep valid ones. If all fail, dismiss the overlay.
- **D-13:** Immediate removal on dismiss — no fade, no animation. Text change in the target app is the feedback for accept.

### Keyboard Navigation (Phase 3 Override)
- **D-14:** **Remove Tab and Enter global key monitors.** Tab conflicts with text editing in the target app (bad UX — global monitor intercepts Tab meant for the app). Enter has the same problem. Only Escape remains as a global key monitor (dismiss overlay). All other suggestion keyboard navigation deferred to `.planning/future_features.md`.
- **D-15:** Escape behavior unchanged from Phase 3 D-12/D-13: closes popover if open, dismisses full overlay if no popover is open.

### Transitions & Feedback
- **D-16:** Overlay (underlines) appears instantly — no fade, no animation. Consistent with Phase 1's silent/instant philosophy.
- **D-17:** Popover uses subtle scale + fade animation: 95% → 100% scale with fade-in (~150ms ease-out). Reverse on dismiss.
- **D-18:** No visual feedback on accept (no flash, no checkmark). The text change in the target app is the confirmation.
- **D-19:** No suggestion count badge on the overlay. Menu bar already shows the count. Keep overlay minimal.

### Claude's Discretion
- Bounds validation thresholds and heuristic tuning
- App quirks plist/JSON schema design
- AX watchdog implementation details (threading, blocklist storage)
- Popover card visual design (exact colors, spacing, typography, shadow, corner radius)
- Scale + fade animation implementation (Core Animation, SwiftUI transitions, or AppKit animator)
- How to detect AXSelectedTextRange support at runtime before attempting range-targeted write
- Underline thickness refinement (exact pixel values)

### Deferred to Future
- **Accept All** batch action — deferred, added to `.planning/future_features.md`
- **Suggestion navigation hotkey** — Tab/Enter removed, proper alternative deferred to `.planning/future_features.md`
- **Auto-advance after accept** — deferred to `.planning/future_features.md`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/01-shell-hotkey-text-extraction/01-CONTEXT.md` — AX-only extraction (D-05), silent-fail pattern (D-07), AX write-back (D-12)
- `.planning/phases/02-harper-grammar-engine/02-CONTEXT.md` — Two-color scheme (D-03), suggestion model (D-01)
- `.planning/phases/03-suggestion-ui/03-CONTEXT.md` — Overlay architecture (all decisions), keyboard nav being partially overridden here (D-11, D-12)

### Requirements
- `.planning/REQUIREMENTS.md` §Suggestion UI (UI-01 through UI-11) — UI-11 keyboard navigation partially overridden by D-14

### Reference Implementation (study only, do not copy code)
- `~/Dev/opensource/textwarden` — TextWarden source (Apache-2.0). Study their bounds validation, multi-line resolution, AX watchdog, and app quirks patterns. Learn-and-reimplement approach; no code porting.

### Future Features
- `.planning/future_features.md` — Accept All, suggestion nav hotkey, auto-advance, Enter-to-accept deferred here

### Product Design
- `planning/initial_design.prd` — Original product architecture and UI design

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `OpenGram/SuggestionUI/OverlayController.swift` — Core overlay orchestration. `show()`, `dismiss()`, `acceptSuggestion()`, `repositionAfterAccept()` all need modification. The scalar offset tracking and bounds query logic will be replaced by the new validation pipeline.
- `OpenGram/SuggestionUI/UnderlineView.swift` — `draw()` renders underlines via NSBezierPath. `colorForCategory()` and `isDashedForSource()` stay. Hit testing and cursor rects stay. Focus ring rendering (D-14) should be removed.
- `OpenGram/SuggestionUI/PopoverView.swift` — SwiftUI view for popover content. Needs full redesign for Grammarly-style card with inline diff, click-to-accept words, expandable alternatives.
- `OpenGram/SuggestionUI/SuggestionPopoverPanel.swift` — NSPanel with `.hudWindow` style. Must be replaced with plain borderless NSPanel per D-06.
- `OpenGram/SuggestionUI/OverlayWindow.swift` — Transparent floating NSPanel. Configuration is sound; no changes needed.
- `OpenGram/SuggestionUI/TargetAppObserver.swift` — AX observer for dismiss triggers. No changes needed.
- `OpenGram/CheckEngine/Suggestion.swift` — Suggestion model. No changes needed.
- `OpenGram/TextEngine/AXAccessor.swift` — AX abstraction layer. May need new methods for `AXSelectedTextRange` and `AXSelectedText` set operations.

### Established Patterns
- Protocol-based DI (`AXAccessor` protocol wraps AX calls for testability)
- Swift 6 strict concurrency with `@MainActor` for UI-touching code
- SPM with `OpenGramLib` library target and `OpenGramTests` test target
- `nonisolated static` helpers for testability without MainActor context

### Integration Points
- `OverlayController.show()` — Bounds query pipeline replacement
- `OverlayController.acceptSuggestion()` — Range-targeted write-back replacement
- `OverlayController.repositionAfterAccept()` — Re-query with new validation pipeline
- `OverlayController.handleTab()` / `handleEnter()` — Remove per D-14
- `AppDelegate.swift` — Key monitor setup may move if global monitors are reduced

</code_context>

<specifics>
## Specific Ideas

- TextWarden's bounds validation pipeline is the primary reference for underline accuracy improvements. Their techniques: reject < 2px bounds, character-by-character fallback, multi-line per-line splitting, AX watchdog with 30s blocklist, data-driven app quirks. Reimplement from scratch (no code porting).
- The popover click-to-accept pattern (click the suggested word, not a button) means the replacement text in the popover must have clear interactive affordance — cursor change to pointer and hover highlight are essential for discoverability.
- Removing Tab/Enter global monitors is a Phase 3 override driven by real UX testing: global key monitors intercept keystrokes meant for the target app, which is unacceptable for commonly-used keys. Only Escape survives because it's universally expected to dismiss floating UI and rarely conflicts.
- The range-targeted AX write (AXSelectedTextRange + AXSelectedText) is a significant improvement over the current full-text AXValue overwrite — it integrates with the target app's native undo stack so Cmd+Z works naturally.

</specifics>

<deferred>
## Deferred Ideas

- **Accept All batch action** — Apply all suggestions at once. Added to `.planning/future_features.md`.
- **Suggestion navigation hotkey** — A dedicated keyboard shortcut to cycle through suggestions. Tab was rejected as it conflicts with text editing. Added to `.planning/future_features.md`.
- **Enter to accept in popover** — Removed because global key monitor intercepts Enter meant for the target app. Added to `.planning/future_features.md`.
- **Auto-advance after accept** — Automatically show next suggestion's popover after accepting one. Added to `.planning/future_features.md`.

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-ux-polish-underline-accuracy-smart-text-replacement-and-gram*
*Context gathered: 2026-04-14*
