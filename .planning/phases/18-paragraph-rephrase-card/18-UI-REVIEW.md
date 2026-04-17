---
phase: 18
overall_score: 20/24
pillars:
  copywriting: 4/4
  visuals: 3/4
  color: 3/4
  typography: 4/4
  spacing: 3/4
  experience_design: 3/4
reviewed_at: 2026-04-16
---

# Phase 18 — UI Review

**Audited:** 2026-04-16
**Baseline:** 18-UI-SPEC.md (approved design contract)
**Screenshots:** Not captured (macOS native app, no dev server)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 4/4 | Labels precise, toggle copy contextual, header logic correct |
| 2. Visuals | 3/4 | Shadow contract violated — panel shadow disabled, no SwiftUI shadow added |
| 3. Color | 3/4 | Mint opacity 0.35 vs spec 0.25; dark mode not verified for Color.teal on body text |
| 4. Typography | 4/4 | Three-level hierarchy (headline/body/callout) matches spec exactly |
| 5. Spacing | 3/4 | Leading padding asymmetric vs trailing; Divider positioned above body not below header |
| 6. Experience Design | 3/4 | No Escape key shortcut; Dismiss has no accessibilityLabel; card shadow gap degrades depth cue |

**Overall: 20/24**

---

## Top 3 Priority Fixes

1. **Missing card shadow** (severity: HIGH) — `RephraseCardPanelController.swift:63` sets `hasShadow = false` with comment "SwiftUI card provides its own shadow", but `RephraseCardView` has no `.shadow()` modifier. Result: card floats over the target app with no visual separation from content beneath. Spec requires "default NSPanel shadow." Fix: either remove `hasShadow = false` to restore panel shadow, or add `.shadow(radius: 8, y: 4)` on the ZStack at `RephraseCardView.swift:36`.

2. **Mint background opacity deviation** (severity: MEDIUM) — `RephraseCardView.swift:108` uses `NSColor.systemMint.withAlphaComponent(0.35)`, but spec (D-05) declares `Color.mint.opacity(0.25)`. Alpha 0.35 is 40% stronger than spec. On dark backgrounds this makes added tokens visually dominant — a readability concern when there are many additions. Fix: change to `0.25` or tune during dogfood. Note: using `NSColor.systemMint` directly bypasses SwiftUI's dark-mode adaptive behavior; `Color.mint` would be adaptive.

3. **No Escape key to dismiss** (severity: MEDIUM) — spec interaction table has Dismiss as a deliberate "neutral" close. The `.keyboardShortcut(.defaultAction)` on Accept (`RephraseCardView.swift:131`) handles Return, but there is no `.keyboardShortcut(.cancelAction)` on Dismiss. Since this is a `.nonactivatingPanel`, standard Escape handling may not reach the card. Users who expect Escape to dismiss floating panels (universal Mac UX pattern) get no response. Fix: add `.keyboardShortcut(.cancelAction)` to the Dismiss button.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

Strong across all contract points:

- Header strings (`RephraseCardViewModel.swift:22-28`) match spec FR-16 table exactly: "Improve clarity", "Fix grammar", "Improve clarity and fix grammar". Empty-set guard returns `""` so card cannot appear with blank header.
- Toggle label is contextual (`RephraseCardView.swift:50`): "What changed?" in additions-only mode, "Additions only" when full-diff is active. Spec says toggle label toggles — implementation exceeds spec by making both states explicit.
- "Accept" and "Dismiss" are precise, non-generic action labels aligned with the hide-vs-dismiss semantic distinction.
- No generic "OK"/"Cancel"/"Submit" patterns found.
- Accessibility label on toggle (`RephraseCardView.swift:56`) is clear: "Show additions only" / "Show full diff" — descriptive verb phrases, not just label echoes.

No copywriting defects.

### Pillar 2: Visuals (3/4)

Strong:
- Teal leading accent bar: `Rectangle().fill(Color.teal).frame(width: 3)` inside ZStack, clipped by outer `RoundedRectangle(cornerRadius: 10)` (`RephraseCardView.swift:21-23, 37`). Full-height bar with rounded corners on leading edge via clip — matches spec anatomy.
- Divider separates header from body (`RephraseCardView.swift:27`). Provides clear zone hierarchy.
- `ScrollView` wrapping body (`RephraseCardView.swift:63`) ensures tall diff content doesn't overflow card bounds.
- `Spacer(minLength: 0)` between body and actions (`RephraseCardView.swift:29`) pushes actions to card bottom — correct.
- `SourceParagraphHighlight` is non-interactive (`hitTest` returns nil, `RephraseCardView.swift`... actually `SourceParagraphHighlight.swift:30`), click-through correct.

Weakness:
- **Shadow gap**: Spec says "Shadow: default NSPanel shadow". `RephraseCardPanelController.swift:63` disables NSPanel shadow (`hasShadow = false`) but no SwiftUI `.shadow()` is added to the card. The card will render without any shadow, reducing perceived elevation and blending with underlying app content. The comment claims SwiftUI provides the shadow — this is incorrect.

### Pillar 3: Color (3/4)

Strong:
- `Color.teal` used on three spec-declared elements only: accent bar, header text, Accept button tint (`RephraseCardView.swift:22, 47, 130`). Accent is not over-applied.
- `NSColor.windowBackgroundColor` for card background — respects dark/light mode.
- `NSColor.systemBlue.withAlphaComponent(0.08)` for source-paragraph highlight (`SourceParagraphHighlight.swift:9`) — matches spec exactly.
- `.foregroundStyle(.secondary)` on Dismiss and removed-tokens — correct spec contrast treatment.

Weaknesses:
- **Mint opacity deviation**: `NSColor.systemMint.withAlphaComponent(0.35)` (`RephraseCardView.swift:108`) vs spec `Color.mint.opacity(0.25)`. Confirmed as a known trade-off in 18-05-SUMMARY.md (Text.background() incompatibility), but the alpha was bumped from 0.25 to 0.35 without documenting rationale beyond "visually equivalent" — which it is not: 0.35 is 40% more opaque.
- **NSColor vs Color for mint**: Using `NSColor.systemMint` bypasses SwiftUI's adaptive color system. `Color.mint` is adaptive; `NSColor.systemMint` in light-appearance mode returns the light variant always. In dark mode via dark `NSColor.systemMint.cgColor` this may work correctly (AppKit system colors are adaptive), but it's a fragility — SwiftUI `Color.mint` is the correct idiomatic choice for this context.
- **Color.teal on header**: `Color.teal` in light mode is `#009A87`-ish. On `windowBackgroundColor` (white in light mode) this passes WCAG AA for large text. In dark mode `Color.teal` lightens adaptively — still AA-compliant. No hardcoded hex values found.

### Pillar 4: Typography (4/4)

Three-level hierarchy exactly matches spec:

| Element | Implementation | Spec |
|---------|---------------|------|
| Header | `.font(.headline).bold().foregroundStyle(.teal)` (line 45-47) | `.font(.headline).bold().foregroundStyle(.teal)` |
| Body | `.font(.body)` (line 65) | `.font(.body)` |
| Toggle button | `.font(.callout)` (line 53) | Not specified (uses `.callout` — sensible) |
| Buttons | System default (lines 120, 127) | System default |

- No arbitrary `fontSize` values.
- No more than 3 distinct text styles in use — well within the 4-max threshold.
- Bold on header, bold on added tokens in full-diff mode (`attr.font = .boldSystemFont(ofSize: NSFont.systemFontSize)`, line 110) — correct spec alignment.
- `NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)` in `mintText(_:bold:)` is functionally correct but mixes AppKit font API with SwiftUI `AttributedString`. Consistent with the NSColor workaround already noted. Not a typography flaw per se.

### Pillar 5: Spacing (3/4)

Strong:
- VStack internal spacing: `12pt` (`RephraseCardView.swift:25`). Consistent.
- HStack button gap: `12pt` (`RephraseCardView.swift:118`). Matches spec "Gap between buttons: 12pt."
- Right padding on actions: `16pt` via `.padding(.trailing, 16)` at line 33. Matches spec "Right padding: 16pt."
- Leading content padding: `3 (accentBarWidth) + 12 = 15pt` (line 32). Logical — clears the accent bar and adds breathing room.
- Card frame: `minWidth: 360, idealWidth: 380, maxWidth: 520, minHeight: 180, idealHeight: 260` (line 36). Spec says "≈380×260" — close.

Weaknesses:
- **Leading vs trailing asymmetry**: Leading content padding is `15pt` (3+12), trailing is `16pt`. One pixel difference introduces subtle visual tension — the content column is not centred within the non-accent area. Spec doesn't mandate symmetry, but conventional card padding is symmetric (16/16). Consider `padding(.leading, 16)` and let the accent bar overlap via ZStack leading alignment (which it already does).
- **Divider placement**: `Divider()` is placed between header and body (`RephraseCardView.swift:27`). Spec diagram shows: header row → (visual separator) → body → actions. The Divider matches spec. However, there is no divider between body and actions — the spec diagram shows `─────────` above the actions row. The `Spacer(minLength: 0)` provides gap but no visual divider. Likely intentional (spec shows divider only above body), but the body-to-actions transition may look crowded on short diffs.
- Vertical padding: `12pt` top and bottom. On a 380×260 card this is proportionate. No issues.

### Pillar 6: Experience Design (3/4)

Strong:
- `.nonactivatingPanel` correctly set — card never steals focus from target app (`RephraseCardPanelController.swift:52`).
- `becomesKeyOnlyIfNeeded = true` further reduces focus disruption (line 58).
- Click-outside hide via `NSWindow.didResignKeyNotification` (line 83).
- Edit-closes (FR-18): keystroke → caret AX query → paragraph-range check → hide (lines 132-149). Correct implementation.
- `.keyboardShortcut(.defaultAction)` on Accept maps Return/Enter (line 131).
- `onHide` callback called after full teardown (line 125), avoiding race conditions.
- Hide-vs-dismiss semantic properly separated: hide leaves cache untouched, dismiss calls `markDismissed` (per ViewModel contract).
- `SourceParagraphHighlight.hitTest` returns nil — clicks pass through (spec: "Non-interactive").
- No loading/error states needed per spec — card only appears when data is complete. Correct omission.

Weaknesses:
- **No Escape shortcut**: Dismiss button lacks `.keyboardShortcut(.cancelAction)`. Non-activating panels may still receive key events when the user clicks within the card. Without Escape-to-dismiss, keyboard-only close requires clicking outside. This deviates from universal macOS panel UX convention.
- **Dismiss button lacks accessibilityLabel**: The Dismiss button has no explicit `.accessibilityLabel`. SwiftUI will derive "Dismiss" from the label — this is acceptable by VoiceOver convention, but the Accept button similarly relies on implicit label "Accept". Neither has explicit accessibility annotation for role or hint. Spec says "Accept is primary, not destructive; Dismiss is neutral" — `.accessibilityAddTraits` could express this (`Accept` → `.isButton`, no hint needed; `Dismiss` → no special trait). Minor.
- **Full-diff toggle has no animation**: Switching `showFullDiff` causes an abrupt body re-render with no crossfade or transition. Spec says "Animation beyond default NSPanel transitions" is out of scope, but the toggle animation is a within-card interaction — a brief `.animation(.easeInOut(duration: 0.15))` on the body content would reduce disorientation. Advisory, not blocking.
- **Shadow gap**: Covered in Visuals but also degrades UX — without shadow, the floating card may be hard to distinguish from the underlying app's own UI on light-background targets (Notes, TextEdit).

---

## Registry Safety

No `components.json` found. Registry audit skipped.

---

## Files Audited

- `/Users/alex/Dev/opengram/OpenGram/SuggestionUI/RephraseCard/RephraseCardView.swift`
- `/Users/alex/Dev/opengram/OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift`
- `/Users/alex/Dev/opengram/OpenGram/SuggestionUI/RephraseCard/TextDiff.swift`
- `/Users/alex/Dev/opengram/OpenGram/SuggestionUI/Panels/RephraseCardPanelController.swift`
- `/Users/alex/Dev/opengram/OpenGram/SuggestionUI/Overlay/SourceParagraphHighlight.swift`
- `/Users/alex/Dev/opengram/.planning/phases/18-paragraph-rephrase-card/18-UI-SPEC.md`
- `/Users/alex/Dev/opengram/.planning/phases/18-paragraph-rephrase-card/18-CONTEXT.md`
- `/Users/alex/Dev/opengram/.planning/phases/18-paragraph-rephrase-card/18-05-SUMMARY.md`
- `/Users/alex/Dev/opengram/.planning/phases/18-paragraph-rephrase-card/18-07-SUMMARY.md`
