---
status: partial
phase: 03-suggestion-ui
source: [03-VERIFICATION.md]
started: 2026-04-14T15:30:00Z
updated: 2026-04-14T16:00:00Z
---

## Current Test

[awaiting re-test of item 3 after bugfix ace862b]

## Tests

### 1. Verify colored underlines appear in Notes.app after hotkey — visual accuracy
expected: Red underlines under misspelled words; blue underlines under grammar/punctuation errors. Overlay does not steal focus from Notes. Clicking an underline shows popover with original text, replacement, explanation, Harper badge, and Accept/Dismiss/Add to Dictionary buttons. Accept replaces word in Notes.
result: passed

### 2. Re-test scroll dismissal after Plan 04 fix (UAT Test 7 regression)
expected: While overlay is showing in Notes, scrolling with mouse or trackpad dismisses the overlay immediately. No Input Monitoring TCC dialog appears.
result: passed

### 3. Re-test reposition after accept after Plan 04 fix (UAT Test 5 regression)
expected: With multiple underlines visible, accept a suggestion that changes word length. Remaining underlines shift to stay aligned with their corresponding text (not stuck at old positions).
result: failed — underlines on line 4 extended past text after accepting "Ths"->"This". Root cause: suggestion.range still pointed into old text; BoundsValidator queried stale character positions. Fixed in ace862b with 4 regression tests. Awaiting manual re-test.

## Summary

total: 3
passed: 2
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

### Gap 1: repositionAfterAccept used stale suggestion.range for AX bounds queries
status: fixed
fix_commit: ace862b
description: BoundsValidator.cfRangeFor() computed AX bounds positions from suggestion.range (String.Index bound to old text). repositionAfterAccept shifted suggestionScalarOffsets but never rebuilt Suggestion objects with new ranges. Fix rebuilds each surviving Suggestion with range from shifted offsets applied to new text.
regression_tests: repositionUpdatesSuggestionRanges, boundsQueriesUseShiftedOffsets, multiLineAcceptShiftsLaterLines, successiveAcceptsAccumulateShifts
