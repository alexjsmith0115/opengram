---
status: partial
phase: 05-session-local-mirror-improvements
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md]
started: 2026-04-19T00:00:00Z
updated: 2026-04-19T00:05:00Z
---

## Current Test

[testing paused — 1 item outstanding]

## Tests

### 1. Accept middle suggestion — earlier underlines stay put
expected: With 3+ underlined suggestions in a line, accepting the middle one leaves earlier underlines in the exact same screen position with no flicker. Later underlines shift cleanly.
result: issue
reported: "The new implementation largely works, but I do see random issue like this screenshot. The blue lines appear in the wrong place for a short time before moving to the correct spot"
severity: major

### 2. Accept last (end-of-doc) suggestion — zero-AX path
expected: With suggestions only trailing toward end of text, accepting the last one causes the overlay to dismiss or shrink smoothly in a single frame. No stutter, no half-drawn underlines, no delay.
result: issue
reported: "the underlines jump and all on the line are gone after accepting the trailing one"
severity: major

### 3. Rapid multi-accept — accept several suggestions in quick succession
expected: Accepting 3+ suggestions back-to-back (as fast as you can click) feels instant each time. No queue-up lag, no overlay glitch between accepts. Remaining underlines stay stable.
result: issue
reported: "I cant accept 3 back to back because dismissed suggestions reappear, existing underlines disappear, and dismissed llm suggestions override harper"
severity: blocker

### 4. Overlay frame tightness after accept
expected: After accepting a suggestion, the transparent overlay window covers only the remaining underlined regions (with small 4pt padding). No oversized ghost area left behind, no click-through dead zones where old underlines used to be.
result: pass

### 5. Edit-after-cached — invalidation does not flicker earlier underlines
expected: With existing suggestions cached, type additional text AFTER the last underlined word (append to end). Earlier underlines stay visually stable — no re-layout flash. Any new suggestion in the appended text appears normally after the checker runs.
result: blocked
blocked_by: other
reason: "User reported: the llm suggestions are too overbearing to test this — LLM suggestion noise masks the signal of whether earlier Harper underlines stay stable on append"

## Summary

total: 5
passed: 1
issues: 3
pending: 0
skipped: 0
blocked: 1

## Gaps

- truth: "With 3+ underlined suggestions in a line, accepting the middle one leaves earlier underlines in the exact same screen position with no flicker. Later underlines shift cleanly."
  status: failed
  reason: "User reported: The new implementation largely works, but I do see random issue like this screenshot. The blue lines appear in the wrong place for a short time before moving to the correct spot"
  severity: major
  test: 1
  artifacts: []
  missing: []

- truth: "With suggestions only trailing toward end of text, accepting the last one causes the overlay to dismiss or shrink smoothly in a single frame. No stutter, no half-drawn underlines, no delay."
  status: failed
  reason: "User reported: the underlines jump and all on the line are gone after accepting the trailing one"
  severity: major
  test: 2
  artifacts: []
  missing: []

- truth: "Accepting 3+ suggestions back-to-back (as fast as you can click) feels instant each time. No queue-up lag, no overlay glitch between accepts. Remaining underlines stay stable."
  status: failed
  reason: "User reported: I cant accept 3 back to back because dismissed suggestions reappear, existing underlines disappear, and dismissed llm suggestions override harper"
  severity: blocker
  test: 3
  artifacts: []
  missing: []
  sub_issues:
    - "Dismissed suggestions reappear after subsequent accepts"
    - "Existing underlines disappear mid-sequence"
    - "Dismissed LLM suggestions override Harper suggestions"
