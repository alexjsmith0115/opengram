---
phase: 03-viewport-cull-rect-cache
plan: 2
subsystem: OpenGramTests/SuggestionUITests
tags: [testing, viewport-cull, rect-cache, perf]
requirements: [PERF-05, PERF-06]

dependency_graph:
  requires:
    - 03-01: lastKnownRects cache + suggestionsForReposition cull logic (provides internal visibility)
  provides:
    - regression gate: 5 Swift Testing cases locking D-14 + D-15 contracts
    - suggestionsForReposition internal visibility (enables @testable cull unit test)
  affects: []

tech_stack:
  added: []
  patterns:
    - inline test helpers (mirrors OverlayControllerRepositionTests pattern)
    - deterministic mock wiring for AXTextReplacer primary write path
    - non-overlapping scalar offsets to prevent repositionAfterAccept dismiss() cascade

key_files:
  created:
    - OpenGramTests/SuggestionUITests/OverlayControllerViewportCullTests.swift
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift (suggestionsForReposition: private → internal)
    - OpenGram.xcodeproj/project.pbxproj (4 entries: PBXBuildFile + PBXFileReference + group child + Sources phase)

decisions:
  - "suggestionsForReposition flipped to internal — @testable access needed; matches applyBoundsCallCount precedent"
  - "Test 5 uses non-overlapping scalar offsets (0-7, 10-17, 20-27) — identical offsets cause repositionAfterAccept to mark idB/idC as overlapping with accepted range, setting scalarLength=0 and triggering dismiss() which nukes entire cache"
  - "Wire kAXValueAttribute + kAXBoundsForRangeParameterizedAttribute in Test 5 — repositionAfterAccept reads updated text then re-queries bounds; failure on either path calls dismiss() and invalidates the assertion"

metrics:
  duration_seconds: 480
  tasks_completed: 4
  files_modified: 3
  completed_date: "2026-04-19"
---

# Phase 3 Plan 2: Viewport-Cull Tests Summary

**One-liner:** 5 Swift Testing cases locking D-14 cull filter + D-15 accept-invalidation contracts via `@testable` access to `suggestionsForReposition` and deterministic MockAXAccessor write-path wiring.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Flip suggestionsForReposition to internal | 2704d8d | OverlayController.swift |
| 2+3 | Write test file + register in pbxproj | 676c824 | OverlayControllerViewportCullTests.swift, project.pbxproj |
| 4 | Run targeted + full test suite | — (validation) | — |

## What Was Built

**Visibility change:** `suggestionsForReposition(reason:context:)` changed from `private` to `internal` with one-line comment explaining the test-seam rationale. Matches `applyBoundsCallCount` / `currentRepositionTask` precedent from prior plan.

**New test file:** `OpenGramTests/SuggestionUITests/OverlayControllerViewportCullTests.swift` — `@Suite("OverlayController viewport cull")` with 5 `@Test` cases:

1. `scrollDuring_filtersOffscreenCachedSuggestions` — seeds 3 suggestions with cached rects at y=100/500/900; element bounds origin=(0,80)/size=(800,200); asserts only idA (y=100, inside padded range 40-320) is returned.
2. `initial_queriesAllRegardlessOfCache` — partial cache (only idA seeded); asserts all 3 returned.
3. `textChanged_queriesAllRegardlessOfCache` — same setup as Test 2, reason `.textChanged`; asserts all 3.
4. `dismissClearsLastKnownRects` — 2 cached entries; `dismiss()`; asserts `lastKnownRects.isEmpty`.
5. `acceptRemovesOnlyAcceptedID` — 3 cached entries; mock wired for write-path success; asserts `lastKnownRects[idA] == nil`, `[idB] != nil`, `[idC] != nil`.

**pbxproj:** 4 entries with IDs `B10000010000000000000052` / `B20000010000000000000052`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test 5 overlapping scalar offset cascade**
- **Found during:** Task 4 first run
- **Issue:** All 3 suggestions had `scalarStart=0, scalarLength=7`. After accepting idA (same range), `repositionAfterAccept` detected idB and idC as overlapping with the accepted range → zeroed their `scalarLength` → `rebuiltSuggestions` empty → `dismiss()` called → `lastKnownRects.removeAll()` → `#expect(idB != nil)` failed.
- **Fix:** Changed scalar offsets to non-overlapping: idA=(0,7), idB=(10,7), idC=(20,7). Updated `kAXValueAttribute` mock to a 27-char string so `rangeFromCharOffsets` stays in bounds for idB/idC after accept.
- **Files modified:** OverlayControllerViewportCullTests.swift
- **Commit:** 676c824 (same commit after fix)

## Verification

- All grep acceptance gates: PASS
- `grep -c "OverlayControllerViewportCullTests.swift" project.pbxproj` → 4
- `plutil -lint project.pbxproj` → OK
- `xcodebuild test -only-testing:OpenGramTests/OverlayControllerViewportCullTests` → 5/5 PASS
- `xcodebuild test -only-testing:OpenGramTests/OverlayControllerRepositionTests` → 5/5 PASS (Phase 2 regression)
- `xcodebuild test -only-testing:OpenGramTests/OverlayControllerTests` → 11/11 PASS
- Full suite: 473 tests, 3 pre-existing failures (AXCallWatchdogTests timing flake × 2, TextMonitorStoreIntegrationTests LLM localhost:1234 timeout × 1) — zero new failures from this plan.
- Build warnings: 0 Swift compiler warnings (1 xcodebuild destination-selection note, not a compiler warning)

## Known Stubs

None.

## Threat Flags

None — test-only code, no production surface, no network, no secrets.

## Self-Check: PASSED

- OverlayControllerViewportCullTests.swift: FOUND
- project.pbxproj entries (4): FOUND
- Commit 2704d8d: FOUND
- Commit 676c824: FOUND
