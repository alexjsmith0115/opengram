# Phase 6: UX Polish — Underline Accuracy, Smart Text Replacement, and Grammarly-Style Popover - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-14
**Phase:** 06-ux-polish-underline-accuracy-smart-text-replacement-and-gram
**Areas discussed:** Underline rendering, Popover redesign, Replacement UX, Transitions & feedback

---

## Underline Rendering

| Option | Description | Selected |
|--------|-------------|----------|
| Squiggly/wavy | Classic Grammarly-style wavy underline | |
| Straight with color | Keep current straight lines, refine thickness and color | ✓ |
| Dotted/dashed | Dotted underline for subtler look | |

**User's choice:** Straight with color
**Notes:** None

---

### TextWarden Reference Approach

User asked how Grammarly and TextWarden handle underline accuracy. Research revealed:
- Grammarly uses kAXBoundsForRangeParameterizedAttribute, treats inaccurate bounds as a known limitation
- TextWarden has a sophisticated multi-strategy pipeline (bounds validation, char-by-char fallback, multi-line detection, AX watchdog, app quirks)
- No published workaround exists in the macOS community for the full-line-width problem
- TextWarden source at ~/Dev/opensource/textwarden (Apache-2.0)

| Option | Description | Selected |
|--------|-------------|----------|
| Learn and reimplement | Study techniques, write own code. No license obligations. | ✓ |
| Port with attribution | Copy utilities with Apache-2.0 attribution | |
| Reference only | Don't adopt specific techniques | |

**User's choice:** Learn and reimplement
**Notes:** Apache-2.0 discussion — user confirmed learn-and-reimplement approach to avoid license obligations

---

### Positioning Sophistication

| Option | Description | Selected |
|--------|-------------|----------|
| Full pipeline | Bounds validation, char fallback, multi-line, watchdog | ✓ |
| Core validation only | Bounds validation + char fallback only | |
| Validation + watchdog | Bounds validation, char fallback, watchdog (no quirks) | |

**User's choice:** Full pipeline

---

### Multi-line Spans

| Option | Description | Selected |
|--------|-------------|----------|
| Per-line segments | Split into per-line underlines, all open same popover | ✓ |
| First line only | Only underline first visual line | |
| Skip multi-line | Don't render multi-line underlines | |

**User's choice:** Per-line segments

---

### App-Specific Quirks

| Option | Description | Selected |
|--------|-------------|----------|
| Data-driven quirks table | plist/JSON config mapping bundle IDs to quirks | ✓ |
| Hardcoded for known apps | Hardcode for 5 target apps | |
| No per-app quirks | Rely on generic validation only | |

**User's choice:** Data-driven quirks table

---

### AX Watchdog Timeout

| Option | Description | Selected |
|--------|-------------|----------|
| Blocklist + skip | Auto-blocklist for 30s, skip rendering | ✓ |
| Blocklist + fallback UI | Blocklist + toast notification | |
| Silent skip | Skip without blocklisting | |

**User's choice:** Blocklist + skip

---

## Popover Redesign

### Visual Style

| Option | Description | Selected |
|--------|-------------|----------|
| Grammarly-style card | Floating card, shadow, rounded corners, inline diff | ✓ |
| Minimal tooltip | Compact tooltip with expand | |
| System popover | Native NSPopover | |

**User's choice:** Grammarly-style card

---

### Inline Diff

| Option | Description | Selected |
|--------|-------------|----------|
| Strikethrough → green | Red strikethrough original, arrow, green replacement | ✓ |
| Side-by-side columns | Two columns with colored backgrounds | |
| Contextual sentence | Full sentence with highlighted error | |

**User's choice:** Strikethrough → green

---

### Alternative Replacements

| Option | Description | Selected |
|--------|-------------|----------|
| Expandable list | Primary prominent, "N more" disclosure, click to accept | ✓ |
| All visible | Show all alternatives with Accept buttons | |
| Radio selection | Radio buttons + single Accept | |

**User's choice:** Expandable list
**Notes:** Top suggestion should be forefront of UI, expanded list smaller but visible. User clicks suggested word to accept, not an Accept button.

---

### Background Material

| Option | Description | Selected |
|--------|-------------|----------|
| Vibrancy material | NSVisualEffectView translucent | |
| Solid background | Opaque background color | ✓ |
| You decide | Claude picks | |

**User's choice:** Solid background

---

### Panel Type

| Option | Description | Selected |
|--------|-------------|----------|
| Plain NSPanel | Drop .hudWindow, custom-drawn background | ✓ |
| Keep HUD style | Current .hudWindow style | |
| You decide | Claude picks | |

**User's choice:** Plain NSPanel

---

### Accept Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Click word + keep Accept button | Both paths available | |
| Click word, remove Accept button | Only click-word accept | ✓ |
| You decide | Claude picks | |

**User's choice:** Click word, remove Accept button

---

## Replacement UX

### Undo Support

| Option | Description | Selected |
|--------|-------------|----------|
| App-native undo | AXSelectedTextRange + AXSelectedText for native Cmd+Z | ✓ |
| Internal undo buffer | Store previous text, OpenGram-specific undo | |
| No undo support | Keep current approach | |

**User's choice:** App-native undo

---

### Accept All

| Option | Description | Selected |
|--------|-------------|----------|
| Accept All Grammar | Harper-only batch | |
| Accept All (everything) | Initially selected, then deferred | |
| No batch action | | |

**User's choice:** Initially selected "Accept All (everything)", then deferred entirely to future_features.md
**Notes:** User decided no Accept All in this phase.

---

### Write-back Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Range-targeted with fallback | Try AXSelectedTextRange first, fall back to AXValue | ✓ |
| Range-targeted only | Fail if app doesn't support it | |
| Keep full-text overwrite | Don't change strategy | |

**User's choice:** Range-targeted with fallback

---

### Keyboard Navigation Override

User proactively raised that Tab should not be used as the suggestion navigation hotkey — it conflicts with actual text editing in target apps (global key monitor intercepts Tab). Enter has the same problem.

**Decision:** Remove Tab and Enter global key monitors entirely. Keep only Escape. All suggestion keyboard navigation deferred to future_features.md.

---

### Auto-advance After Accept

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-advance | Show next suggestion's popover automatically | |
| Close and wait | Close popover, user navigates manually | ✓ |
| You decide | Claude picks | |

**User's choice:** Close and wait
**Notes:** Tab hotkey removed (conflicts with text editing). Enter also removed. Both deferred to future_features.md.

---

### Dismiss Visual

| Option | Description | Selected |
|--------|-------------|----------|
| Immediate removal | Underline disappears instantly | ✓ |
| Brief fade out | ~200ms fade | |
| You decide | Claude picks | |

**User's choice:** Immediate removal

---

### Reposition After Accept

| Option | Description | Selected |
|--------|-------------|----------|
| Immediate re-query | Re-query AX bounds for all remaining suggestions | ✓ |
| Offset shift + deferred re-query | Quick shift then correct after 100ms | |
| Dismiss and re-check | Full Harper re-check | |

**User's choice:** Immediate re-query

---

### Re-query Failure Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Drop failed, keep valid | Remove bad underlines, keep good ones | ✓ |
| Dismiss all on any failure | Conservative full dismiss | |
| You decide | Claude picks | |

**User's choice:** Drop failed, keep valid

---

## Transitions & Feedback

### Overlay Appearance

| Option | Description | Selected |
|--------|-------------|----------|
| Instant appear | No animation | ✓ |
| Quick fade in | ~150ms fade | |
| Staggered reveal | One-by-one with stagger | |

**User's choice:** Instant appear

---

### Popover Animation

| Option | Description | Selected |
|--------|-------------|----------|
| Subtle scale + fade | 95%→100% scale, ~150ms ease-out | ✓ |
| Instant | No animation | |
| Slide from underline | Slide up from underline position | |

**User's choice:** Subtle scale + fade

---

### Accept Feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Brief green flash | ~200ms green flash on underline | |
| No feedback | Immediate removal, text change is feedback | ✓ |
| Checkmark micro-animation | Small checkmark at underline position | |

**User's choice:** No feedback

---

### Count Badge

| Option | Description | Selected |
|--------|-------------|----------|
| No count indicator | Menu bar shows count already | ✓ |
| Subtle count badge | Floating "N remaining" badge | |
| You decide | Claude picks | |

**User's choice:** No count indicator

---

## Claude's Discretion

- Bounds validation thresholds and heuristic tuning
- App quirks plist/JSON schema design
- AX watchdog implementation details
- Popover card visual design (colors, spacing, typography, shadow, corner radius)
- Scale + fade animation implementation
- Runtime detection of AXSelectedTextRange support
- Underline thickness refinement

## Deferred Ideas

- Accept All batch action → `.planning/future_features.md`
- Suggestion navigation hotkey → `.planning/future_features.md`
- Enter to accept in popover → `.planning/future_features.md`
- Auto-advance after accept → `.planning/future_features.md`
