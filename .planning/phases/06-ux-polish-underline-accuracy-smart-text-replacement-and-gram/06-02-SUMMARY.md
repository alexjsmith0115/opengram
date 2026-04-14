---
phase: 06-ux-polish-underline-accuracy-smart-text-replacement-and-gram
plan: 02
subsystem: SuggestionUI
tags: [bounds-validator, range-targeted-accept, ax-write, key-monitor-cleanup, tdd]
dependency_graph:
  requires:
    - BoundsValidator (06-01)
    - AXCallWatchdog (06-01)
  provides:
    - OverlayController with BoundsValidator-backed show() and repositionAfterAccept()
    - Range-targeted AX accept (kAXSelectedTextRangeAttribute + kAXSelectedTextAttribute)
    - Escape-only key monitor (Tab/Enter fully removed)
  affects:
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
    - OpenGramTests/SuggestionUITests/BoundsForRangeTests.swift
tech_stack:
  added: []
  patterns:
    - isAttributeSettable probe before AX write (T-06-05: no partial state on failure)
    - fallbackFullWrite as private method for full AXValue overwrite path
    - Survivor-first reposition: compute surviving suggestions before updating view
    - BoundsValidator injected as private stored property (default .shared watchdog/quirks)
key_files:
  created: []
  modified:
    - OpenGram/SuggestionUI/OverlayController.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
    - OpenGramTests/SuggestionUITests/BoundsForRangeTests.swift
    - OpenGramTests/AXTextEngineTests.swift
decisions:
  - Survivor computation runs unconditionally before view update — D-12 drop behavior works even without an active underlineView
  - BoundsForRangeTests.swift emptied (boundsForRange/flipCGRect deleted from OverlayController; equivalent coverage in BoundsValidatorTests)
  - MockAXAccessor gained setAttributeResultsByCall closure for per-call AX error simulation
  - Task 2 (Tab/Enter/focusedIndex removal) was fully incorporated into Task 1's rewrite — no separate commit needed
metrics:
  duration_minutes: 10
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_created: 0
  files_modified: 4
---

# Phase 6 Plan 2: OverlayController BoundsValidator Integration and Range-Targeted Accept Summary

**One-liner:** OverlayController rewritten to delegate all bounds queries to BoundsValidator, accept via range-targeted AX write with full-value fallback, and use Escape-only key monitoring with focusedIndex/handleTab/handleEnter removed.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Range-targeted accept and BoundsValidator integration | 1acba63 | OverlayController.swift, OverlayControllerTests.swift, BoundsForRangeTests.swift, AXTextEngineTests.swift |
| 2 | Remove Tab/Enter key monitors, clean up focusedIndex | (included in 1acba63) | Already complete in Task 1 rewrite |

## What Was Built

### BoundsValidator Integration in show()

`show()` now creates a `BoundsValidator` instance (stored as `private let boundsValidator`) and calls `validatedBoundsForRange` for each suggestion instead of the old inline `boundsForRange` + `flipCGRect` + sanity-clamp logic. Multi-line suggestions produce multiple `UnderlineEntry` instances all pointing to the same `Suggestion` — clicking any segment opens the same popover. `screenHeight` local variable removed; coordinate conversion is handled inside `BoundsValidator`.

### Range-Targeted Accept (D-11)

`acceptSuggestion` probes `isAttributeSettable(kAXSelectedTextRangeAttribute)` at runtime before deciding the write path:

- **Primary:** Set `kAXSelectedTextRangeAttribute` (selection) then `kAXSelectedTextAttribute` (replacement text). Atomic: if selection set fails, falls through to fallback immediately.
- **Fallback:** `fallbackFullWrite` reads `kAXValueAttribute`, replaces in-memory using scalar offsets, writes back. Used when the element doesn't support range-targeted write or either primary call fails.

T-06-05 mitigation: the element is never left in a partially-modified state. Failed range write falls through to full write rather than leaving selection moved but text unchanged.

### repositionAfterAccept with BoundsValidator (D-12)

Survivor computation is separated from view update: the BoundsValidator loop always runs (regardless of whether `underlineView` is set) to keep `suggestions` and `suggestionScalarOffsets` consistent with reality. Suggestions whose bounds re-query returns nil are dropped. If all suggestions are dropped, `dismiss()` is called. View update (`view.entries = newEntries`) only runs if `underlineView` is non-nil.

### Escape-Only Key Monitor (D-14, D-15)

`keyMonitor` in `show()` uses a simple `if event.keyCode == 53` — no switch, no other cases. `handleTab`, `handleEnter`, and `focusedIndex` are absent from the file. `handleEscape()` takes no parameters (the `textContext:` parameter was unnecessary — the method only checks `isPopoverVisible`).

### Test Updates

- `OverlayControllerTests.swift`: 25 tests covering range-targeted write, fallback, survivor-drop, offset-shifting, and Escape-only keyboard behavior
- `BoundsForRangeTests.swift`: cleared — `boundsForRange`/`flipCGRect` no longer exist on `OverlayController`; equivalent coverage is in `BoundsValidatorTests`
- `AXTextEngineTests.swift` (`MockAXAccessor`): added `setAttributeResultsByCall: ((Int) -> AXError)?` closure for per-call AX error simulation

## Test Results

- Full suite: 166 tests, 0 failures

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Guard on underlineView gated survivor computation, breaking D-12**
- **Found during:** Task 1 GREEN phase (repositionDropsSuggestionsOnBoundsFailure test failure)
- **Issue:** The plan's pseudocode wrapped the entire BoundsValidator survivor loop in `guard let view = underlineView`. This meant that in tests (and production scenarios where the window was dismissed mid-flow), the survivor drop logic never ran — suggestions stayed stale even when BoundsValidator returned nil for all of them.
- **Fix:** Moved `guard let view = underlineView` to only gate the view update step. Survivor computation (`survivingSuggestions`, `survivingOffsets`) runs unconditionally when `suggestionScalarOffsets.count == suggestions.count`.
- **Files modified:** `OpenGram/SuggestionUI/OverlayController.swift`
- **Commit:** 1acba63

**2. [Rule 2 - Missing critical functionality] Tests for surviving suggestions needed valid AXValue rect mocks**
- **Found during:** Task 1 GREEN phase — `acceptRemovesSuggestion`, `repositionShiftsOffsets`, and `repositionDoesNotShiftPriorSuggestions` all failed because BoundsValidator now always runs in reposition, and the mocks didn't supply valid `kAXBoundsForRangeParameterizedAttribute` responses.
- **Fix:** Added `mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())` to tests that expect surviving suggestions. Added `makeAXRectValue()` helper at top of test file.
- **Files modified:** `OpenGramTests/SuggestionUITests/OverlayControllerTests.swift`
- **Commit:** 1acba63

**3. [Rule 2 - Missing critical functionality] MockAXAccessor needed per-call AX error override**
- **Found during:** Task 1 RED phase — `rangeTargetedWriteFallsBackWhenSelectionSetFails` test required the first `setAttributeValue` call to fail (simulate selection set failure) while the second (fallback full write) succeeds. The existing `setAttributeResult: AXError` was a single value for all calls.
- **Fix:** Added `setAttributeResultsByCall: ((Int) -> AXError)?` to `MockAXAccessor`. `setAttributeValue` checks this closure first (passing the call index), falling back to `setAttributeResult` if nil.
- **Files modified:** `OpenGramTests/AXTextEngineTests.swift`
- **Commit:** 1acba63

**4. [Note] Task 2 incorporated into Task 1 rewrite**
- Task 2 (remove handleTab, handleEnter, focusedIndex; simplify handleEscape) was fully executed as part of the Task 1 complete-rewrite of OverlayController.swift. All Task 2 acceptance criteria were satisfied in the same commit. No separate Task 2 commit was needed.

## Known Stubs

None.

## Threat Flags

All threats from the plan's threat register were mitigated:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-06-05 Tampering: partial AX write leaves element in bad state | isAttributeSettable probe + fallback on any write failure | Implemented |
| T-06-06 DoS: repositionAfterAccept retrying failed bounds | Drop suggestions on nil re-query; dismiss if all fail | Implemented |
| T-06-07 Spoofing: key event monitor attack surface | Escape-only monitor (keyCode 53); Tab/Enter removed | Implemented |

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| OpenGram/SuggestionUI/OverlayController.swift | FOUND |
| OpenGramTests/SuggestionUITests/OverlayControllerTests.swift | FOUND |
| OpenGramTests/SuggestionUITests/BoundsForRangeTests.swift | FOUND |
| OpenGramTests/AXTextEngineTests.swift | FOUND |
| Commit 1acba63 | FOUND |
| swift test: 166 tests, 0 failures | PASSED |
