---
phase: 18
review_file: 18-REVIEW.md
fixes_applied: 4
fixes_deferred: 0
status: fixed
fixed_at: 2026-04-16
---

# Phase 18: Code Review Fix Report

**Fixed at:** 2026-04-16
**Source review:** `.planning/phases/18-paragraph-rephrase-card/18-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (WR-01 through WR-04)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-01: RephraseComposer overlap sentinel corrected

**File modified:** `OpenGram/SuggestionUI/RephraseCard/RephraseComposer.swift`
**Commit:** e04e4a3
**Applied fix:** Replaced `appliedLower: String.Index?` sentinel (tracking only `lowerBound`) with `appliedRange: Range<String.Index>?` and switched the skip condition from `edit.range.upperBound > applied` to `edit.range.overlaps(applied)`. The old guard failed to skip edits whose range sat entirely below the applied range's start (e.g., `[0,4)` not caught when `appliedLower = 5`), potentially applying stale String.Index values into already-mutated content.

**Evidence:** BUILD SUCCEEDED; 441/441 tests green.

---

### WR-02: tryDispatchRephraseCard double-dispatch on update() prevented

**File modified:** `OpenGram/SuggestionUI/Overlay/OverlayController.swift`
**Commit:** 8fa2326
**Applied fix:** Added `currentCardParagraphHash: UInt64?` property. In `tryDispatchRephraseCard`, after `selectQualifier` resolves the winning paragraph, early-return `true` when `currentCardParagraphHash == selected.hash` (card already shown for same paragraph). Set `currentCardParagraphHash = selected.hash` alongside `currentCardParagraphRange` when dispatching. Clear `currentCardParagraphHash = nil` in `hideCardAndRestore()`. This prevents `update()` from tearing down and rebuilding the card panel on every incremental diff cycle when the selected paragraph hasn't changed.

**Evidence:** BUILD SUCCEEDED; 441/441 tests green.

---

### WR-03: AXValue force-cast hardened with CFGetTypeID guard

**File modified:** `OpenGram/SuggestionUI/Panels/RephraseCardPanelController.swift`
**Commit:** deccdf9
**Applied fix:** Added `CFGetTypeID(rangeRef) == AXValueGetTypeID()` to the guard chain in `handleKeystroke()` before the `as! AXValue` cast. If a buggy target app returns an unexpected CFType for `kAXSelectedTextRangeAttribute`, the guard exits cleanly instead of crashing. Removed the now-redundant `// swiftlint:disable:next force_cast` comment since the cast is still present but is safe post-guard.

**Evidence:** BUILD SUCCEEDED; 441/441 tests green.

---

### WR-04: acceptClosure calls rephraseCardPanelController.hide() before hideCardAndRestore()

**File modified:** `OpenGram/SuggestionUI/Overlay/OverlayController.swift`
**Commit:** c50aae4
**Applied fix:** Prepended `self.rephraseCardPanelController.hide()` to `acceptClosure` before `self.hideCardAndRestore()`. `RephraseCardPanelController.hide()` clears `onHide` before firing it (nil-then-call pattern), so when it fires `onHide` → `hideCardAndRestore()` here, `onHide` is already nil. Any subsequent `hide()` call triggered via `kAXValueChangedNotification → handleKeystroke` finds `onHide == nil` and is a no-op, eliminating the redundant `showUnderlines()` AX re-query on accept.

**Evidence:** BUILD SUCCEEDED; 441/441 tests green.

---

## Skipped Issues

None.

---

_Fixed: 2026-04-16_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
