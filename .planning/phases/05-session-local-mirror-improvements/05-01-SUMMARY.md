---
phase: 05-session-local-mirror-improvements
plan: 01
subsystem: overlay-controller
tags: [perf, overlay, ax-cache, accept-path, v1.3]
requirements: [PERF-12]

dependency_graph:
  requires:
    - 04-05 (rebuildUnderlineEntries, scheduleReposition, applyBoundsCallCount precedent)
    - 03-02 (lastKnownRects cache, suggestionsForReposition structure)
  provides:
    - Pre-shift cache invalidation predicate (D-05) for Plan 02 mirror tests
    - boundsBatchCallCount spy for Plan 02 zero-AX assertion
    - scheduleReposition(.textChanged) tail call replacing sync BoundsValidator loop
    - recomputeOverlayFrame() helper for zero-AX window frame rebuild
  affects:
    - OverlayControllerMirrorTests (Plan 02) — all 4 new tests depend on this plan's artifacts

tech_stack:
  added: []
  patterns:
    - Pre-shift cache invalidation predicate using scalar offsets before shift loop
    - Empty-filter .textChanged branch routes to zero-AX rebuild path
    - Actor-isolated call-count spy for async boundary assertions

key_files:
  created: []
  modified:
    - OpenGram/TextEngine/AXCallQueue.swift
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerViewportCullTests.swift

decisions:
  - "boundsBatchCallCount spy placed on AXCallQueue actor (not mock) — spy lives at the production boundary so test assertions survive mock swap-outs"
  - "recomputeOverlayFrame() is private and separate from rebuildUnderlineEntries — rebuildUnderlineEntries runs in many contexts where the caller manages the frame; frame recompute belongs in its own helper"
  - "textChanged_queriesAllRegardlessOfCache renamed to textChanged_queriesOnlyUncachedSuggestions — old name encoded the superseded Phase 3 contract; updated alongside acceptRemovesOnlyAcceptedID to keep the suite internally consistent"

metrics:
  duration: 5 minutes
  completed: 2026-04-19
  tasks_completed: 3
  files_modified: 3
---

# Phase 05 Plan 01: Session-Local Mirror Improvements — Accept Path Refactor Summary

**One-liner:** Zero-AX accept path via pre-shift cache invalidation predicate, `.textChanged` filter flip, and `scheduleReposition(.textChanged)` tail call replacing sync BoundsValidator loop (PERF-12).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add boundsBatchCallCount spy to AXCallQueue | ad5e911 | AXCallQueue.swift |
| 2 | OverlayController accept path refactor | 8873cee | OverlayController.swift |
| 3 | Update Phase 3 viewport cull tests to Phase 5 contract | d23fa69 | OverlayControllerViewportCullTests.swift |

## What Was Built

**Task 1 — AXCallQueue spy:** Added `var boundsBatchCallCount: Int = 0` (internal, actor-isolated) incremented once at the top of `boundsBatch`. Mirrors `applyBoundsCallCount` precedent. Plan 02 asserts `await queue.boundsBatchCallCount` stays unchanged on the zero-AX end-of-doc path.

**Task 2 — OverlayController refactor (6 coordinated edits):**
- **Edit 1:** Split `case .initial, .textChanged:` into separate cases in `suggestionsForReposition`. `.textChanged` now returns `capped.filter { lastKnownRects[$0.id] == nil }` — only cache-invalidated suggestions reach `axQueue.boundsBatch`.
- **Edit 2:** Extended `reposition(reason:)` empty-filter guard — when `reason == .textChanged` and filter is empty, calls `rebuildUnderlineEntries()` + `recomputeOverlayFrame()` instead of `clearUnderlines()`. Zero AX calls, no underline flicker.
- **Edit 3:** Added `private func recomputeOverlayFrame()` — computes union of `lastKnownRects` for all current suggestions, insets by 4pt padding, sets `overlayWindow.setFrame`. Falls back to `dismiss()` if union is null (defensive, should not occur in empty-filter path).
- **Edit 4:** Inserted D-05 pre-shift cache invalidation loop in `repositionAfterAccept` immediately before the existing scalar-offset shift loop. Predicate `beforeEnd <= editStart` preserves strictly-before suggestions; invalidates overlapping and after-edit entries via `lastKnownRects.removeValue(forKey:)`.
- **Edit 5:** Deleted the ~47-line synchronous `BoundsValidator.validatedBoundsForRange` loop from `repositionAfterAccept` (including `screenEntries`, `survivingSuggestions`, `survivingOffsets`, window frame recompute, `toLocalEntries` call).
- **Edit 6:** Replaced deleted block with `scheduleReposition(reason: .textChanged)` — accept path now reuses the queue-routed reposition used by scroll, inheriting cancellation contract and error logging.

**Task 3 — Test updates:**
- `acceptRemovesOnlyAcceptedID` → `acceptInvalidatesAfterEditCacheEntries`: assertions flipped to D-05 — after accepting idA (0-7), idB (10-17) and idC (20-27) both nil (after-edit); added `await controller.currentRepositionTask?.value` drain.
- `textChanged_queriesAllRegardlessOfCache` → `textChanged_queriesOnlyUncachedSuggestions`: assertions updated to reflect D-09 filter — with idA cached, result is `[idB, idC]` (count=2), not all 3.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated textChanged_queriesAllRegardlessOfCache alongside acceptRemovesOnlyAcceptedID**
- **Found during:** Task 3
- **Issue:** The existing `textChanged_queriesAllRegardlessOfCache` test asserted `.textChanged` returns all 3 suggestions regardless of cache — directly contradicts Task 2's D-09 filter flip. Would fail immediately after Task 2 commit.
- **Fix:** Renamed to `textChanged_queriesOnlyUncachedSuggestions` and updated assertions to match new filter behavior (count=2, idB+idC returned when idA is cached).
- **Files modified:** `OpenGramTests/SuggestionUITests/OverlayControllerViewportCullTests.swift`
- **Commit:** d23fa69

## Pre-existing Flake Noted

`OverlayControllerScrollModeTests.hideAndSettle scroll event fades underlines to 0 and sets .faded` — fails under parallel load, passes in isolation. Pre-existing flake documented in STATE.md at Phase 04-05. Confirmed pre-dates this plan (stash-check verified it fails without any of this plan's changes). Out of scope per SCOPE BOUNDARY.

## Verification

- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — SUCCEEDED
- `OverlayControllerViewportCullTests` (5 tests) — all pass
- `OverlayControllerRepositionTests` (5 tests) — all pass
- `grep -c "boundsValidator.validatedBoundsForRange" OverlayController.swift` — 5 (none inside repositionAfterAccept)
- `grep -c "boundsBatchCallCount" AXCallQueue.swift` — 3 (comment + declaration + increment)
- Zero "Phase N" / "Plan N" references in modified source files

## Threat Flags

None. Pure in-process refactor of already-trusted cache. No new network, persistence, secrets, or user input surface. Threat register items T-05-01 through T-05-04 dispositioned as `accept` or `mitigate` in plan frontmatter — no new surface introduced.

## Known Stubs

None. All code paths wired. Plan 02 adds the 4 new mirror-specific tests exercising the zero-AX path end-to-end.

## Self-Check: PASSED

- OpenGram/TextEngine/AXCallQueue.swift — FOUND
- OpenGram/SuggestionUI/Overlay/OverlayController.swift — FOUND
- OpenGramTests/SuggestionUITests/OverlayControllerViewportCullTests.swift — FOUND
- .planning/phases/05-session-local-mirror-improvements/05-01-SUMMARY.md — FOUND
- Commits ad5e911, 8873cee, d23fa69 — all present in git log
