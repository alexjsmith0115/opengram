---
phase: 18-paragraph-rephrase-card
plan: "01"
subsystem: SuggestionUI
tags: [ax-write, refactor, extraction, shared-infra]
dependency_graph:
  requires: []
  provides: [AXTextReplacer]
  affects: [OverlayController, RephraseCardPanelController]
tech_stack:
  added: []
  patterns: [dependency-injection, struct-extraction]
key_files:
  created:
    - OpenGram/SuggestionUI/Panels/AXTextReplacer.swift
    - OpenGramTests/SuggestionUITests/Panels/AXTextReplacerTests.swift
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Reused existing MockAXAccessor (dict-based API from AXTextEngineTests) rather than defining a new one — avoids duplicate class in same test target"
  - "AXTextReplacer bounds-guards (scalarStart >= 0, end <= scalars.count) added beyond original OverlayController logic — safer for rephrase-card call site which may pass arbitrary ranges"
metrics:
  duration: "~20 minutes"
  completed: "2026-04-17T01:16:18Z"
  tasks_completed: 2
  files_changed: 4
---

# Phase 18 Plan 01: AXTextReplacer Extraction Summary

AXTextReplacer struct extracted from OverlayController.acceptSuggestion — range-targeted write with full-text fallback, shared by Phase 3 popover accept path and Phase 18 rephrase-card accept path.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Create AXTextReplacer + tests | 89a15a0 | AXTextReplacer.swift, AXTextReplacerTests.swift, project.pbxproj |
| 2 | Swap OverlayController.acceptSuggestion | 71b8c91 | OverlayController.swift |

## Decisions Made

1. **Reused MockAXAccessor** — existing dict-based mock in `AXTextEngineTests.swift` already implements `AXAccessor`. Defining a second `MockAXAccessor` in the test target would cause a duplicate symbol compile error. Tests adapted to its API (`attributeSettable`, `attributeValues`, `setAttributeCalls`).

2. **Bounds guards in fallbackFullWrite** — `AXTextReplacer.fallbackFullWrite` adds explicit `scalarStart >= 0` and `end <= scalars.count` guards absent from the original `OverlayController.fallbackFullWrite`. Safer for future call sites (rephrase card) that may pass externally-computed ranges.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Avoided duplicate MockAXAccessor class**
- **Found during:** Task 1 — test file authoring
- **Issue:** Plan template included a local `MockAXAccessor` definition; same class already exists in `AXTextEngineTests.swift` in the same test target, causing duplicate symbol error
- **Fix:** Removed local definition, adapted tests to use existing `MockAXAccessor` dict-based API
- **Files modified:** `OpenGramTests/SuggestionUITests/Panels/AXTextReplacerTests.swift`
- **Commit:** 89a15a0

**2. [Rule 3 - Blocking] Symlinked HarperBridge.xcframework into worktree**
- **Found during:** Task 1 verification
- **Issue:** Worktree lacks `HarperBridge.xcframework` (build artifact not tracked in git); xcodebuild fails with "no XCFramework found"
- **Fix:** `ln -s /Users/alex/Dev/opengram/HarperBridge.xcframework` into worktree root
- **Files modified:** None (symlink only)

## Verification Results

- `xcodebuild build` — SUCCEEDED
- `AXTextReplacerTests` — 4/4 pass (rangeWrite success, rangeWrite fallback, fullFallback read failure, fullFallback splice correctness)
- `OverlayControllerTests` + `OverlayControllerDiffTests` — 17/17 pass (zero regression)

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or file access patterns introduced.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/Panels/AXTextReplacer.swift` — EXISTS
- `OpenGramTests/SuggestionUITests/Panels/AXTextReplacerTests.swift` — EXISTS
- Commit 89a15a0 — EXISTS
- Commit 71b8c91 — EXISTS
- `grep "struct AXTextReplacer"` — FOUND
- `grep "func replace"` — FOUND
- `grep "AXTextReplacerTests" project.pbxproj` — FOUND
- `grep -c "AXTextReplacer(accessor: accessor)" OverlayController.swift` — 1
- `grep -c "fallbackFullWrite" OverlayController.swift` — 0
