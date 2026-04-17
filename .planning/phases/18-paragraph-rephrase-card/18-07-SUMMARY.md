---
phase: 18-paragraph-rephrase-card
plan: "07"
subsystem: overlay
tags: [overlay, rephrase-card, DI-wiring, multi-qualifier, phase-18]
dependency_graph:
  requires: [18-01, 18-02, 18-03, 18-04, 18-05, 18-06]
  provides: [OverlayController.tryDispatchRephraseCard, OverlayController.selectQualifier, CardQualifier, AppDelegate Phase-18 DI wiring]
  affects: [OverlayController, AppDelegate, CheckCoordinator init order]
tech_stack:
  added: []
  patterns:
    - DI via optional deps with safe fallback (nil scheduler/monitor → card path disabled)
    - Card dispatch as private method called from both show() and update()
    - Static internal selectQualifier enables unit testing without OverlayController instance
    - TextMonitor constructed before OverlayController in AppDelegate for DI correctness
key_files:
  created:
    - OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGramTests/AppDelegateWiringTests.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "CardQualifier is internal (not fileprivate) so selectQualifier static method is unit-testable"
  - "hideCardAndRestore() called BEFORE AXTextReplacer.replace() on Accept — prevents card flicker on stale hash when AX write fires kAXValueChangedNotification"
  - "TextMonitor.onKeystroke NOT wired by AppDelegate — RephraseCardPanelController owns the subscription via closure-chaining on show(), restoring prior value on hide()"
  - "TextMonitor constructed before OverlayController in applicationDidFinishLaunching — required because OverlayController.textMonitor is a let stored property"
metrics:
  duration: ~25 minutes
  completed: 2026-04-16
  tasks: 2
  files: 6
---

# Phase 18 Plan 07: OverlayController Assembly Summary

**One-liner:** OverlayController wired with scheduler/textMonitor/incrementalConfig/splitter/hasher deps, card dispatch branch added to show()/update(), multi-qualifier selection extracted as testable static method, AppDelegate init order refactored for DI correctness.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | OverlayController DI + card dispatch branch + multi-qualifier selection | aa6ba23 | OverlayController.swift, MultiQualifierSelectionTests.swift, OverlayControllerRephraseIntegrationTests.swift, pbxproj |
| 2 | AppDelegate DI wiring + wiring regression test | ec10cb5 | AppDelegate.swift, AppDelegateWiringTests.swift |

## What Was Built

### OverlayController.swift (672 → 926 lines)

**New file-scope type:**
```swift
internal struct CardQualifier: Sendable {
    let paragraph: Paragraph
    let llmIssues: [LLMStyleSuggestion]
    let harperInside: [Suggestion]
    let hash: UInt64
}
```

**Extended init** — 6 params (accessor, scheduler, textMonitor, incrementalConfig, splitter, hasher), all with defaults. Constructs heuristic, rephraseCardPanelController, sourceParagraphHighlight.

**New stored properties:** scheduler, textMonitor, incrementalConfig, splitter, hasher, heuristic, rephraseCardPanelController, sourceParagraphHighlight, currentCardParagraphRange.

**`tryDispatchRephraseCard`** — flag gate → split paragraphs → build CardQualifiers → apply heuristic → selectQualifier → build ViewModel with Accept/Dismiss closures → hide underlines → show highlight → show card. Returns Bool (true = card dispatched).

**`selectQualifier`** (internal static) — caret-containment check first; falls back to nearest midpoint distance. D-12 / REPH-12.

**`hideCardAndRestore`** — removes highlight, clears currentCardParagraphRange, calls showUnderlines(). Used by Accept, Dismiss, and Hide paths.

**Dispatch call sites:** `show()` after suggestionScalarOffsets computed; `update()` after textContext assigned.

### AppDelegate.swift

**Init order change:** TextMonitor now constructed before OverlayController (required — textMonitor is a `let` stored property on OverlayController).

**OverlayController construction:**
```swift
let overlayController = OverlayController(
    scheduler: scheduler,
    textMonitor: textMonitor,
    incrementalConfig: UserDefaultsIncrementalConfig()
)
```
splitter and hasher use their defaults (DoubleNewlineSplitter, Sha256ParagraphHasher) — same instances the scheduler already uses internally.

### Why textMonitor.onKeystroke is NOT wired by AppDelegate

RephraseCardPanelController installs its own `onKeystroke` subscription in `show()` via closure-chaining (preserving prior subscriber) and restores the prior value in `hide()`. AppDelegate wiring here would create a three-way race: AppDelegate closure → card closure → prior AppDelegate closure, with undefined execution order when the card hides. Keeping AppDelegate out of the chain is the correct boundary.

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| MultiQualifierSelectionTests | 4 | PASS |
| OverlayControllerRephraseIntegrationTests | 2 | PASS |
| OverlayControllerTests (regression) | 11 | PASS |
| OverlayControllerDiffTests (regression) | 6 | PASS |
| AppDelegateWiringTests (regression + new) | 8 | PASS |
| **Total** | **31** | **PASS** |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wrong argument order in integration test**
- **Found during:** Task 1 test run
- **Issue:** Plan's test scaffold had `incrementalConfig:` before `scheduler:` but init signature requires `scheduler` first
- **Fix:** Reordered args to match init param order
- **Files modified:** OverlayControllerRephraseIntegrationTests.swift
- **Commit:** included in aa6ba23

## Known Stubs

None. All dispatch paths are fully wired; flag-off path is byte-identical to pre-Phase-18 (REPH-15 satisfied).

## Threat Flags

None. No new network endpoints, auth paths, or external surface. AX write path reuses existing AXTextReplacer.

## Self-Check

- [x] OverlayController.swift exists, 926 lines
- [x] MultiQualifierSelectionTests.swift exists
- [x] OverlayControllerRephraseIntegrationTests.swift exists
- [x] Commit aa6ba23 exists (Task 1)
- [x] Commit ec10cb5 exists (Task 2)
- [x] `grep tryDispatchRephraseCard` returns 3 hits (definition + show call + update call)
- [x] `grep "internal struct CardQualifier"` hits
- [x] `grep "internal static func selectQualifier"` hits
- [x] `grep "await schedulerRef.markDismissed"` hits
- [x] `grep "hideUnderlines(inParagraphScalarRange:"` hits
- [x] `grep "rephraseCardPanelController.show"` hits
- [x] 6/6 new tests pass
- [x] 17/17 regression tests pass
- [x] xcodebuild BUILD SUCCEEDED

## Self-Check: PASSED
