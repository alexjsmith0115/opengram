---
phase: 05-session-local-mirror-improvements
plan: 03
subsystem: overlay-controller
tags: [perf, overlay, accept-path, coord-space, gap-closure, v1.3]
requirements: [PERF-12]

dependency_graph:
  requires:
    - 05-01 (scheduleReposition(.textChanged) tail, D-05 predicate, rebuildUnderlineEntries, recomputeOverlayFrame)
    - 05-02 (OverlayControllerMirrorTests.swift infrastructure, makeMirrorController factory)
  provides:
    - Sync view.entries rebuild at tail of repositionAfterAccept (closes UAT Gap 1)
    - applyBounds ordering — recomputeOverlayFrame before rebuildUnderlineEntries (secondary latent frame-translation bug)
    - update() diff.unchanged branch sourcing survivor rects from lastKnownRects (SCREEN) not underlineView.entries (LOCAL) (closes UAT Gap 2)
    - 2 new regression tests: accept_rebuildsViewEntriesSynchronously, update_windowFrameOriginIsScreenSpaceForDiffUnchangedSurvivors
    - overlayWindow visibility flipped private → internal for @testable access
  affects:
    - Phase 5 UAT — Gaps 1 + 2 closed; Gap 3 (rapid multi-accept cascade) carved out to future inserted phase

tech_stack:
  added: []
  patterns:
    - Pre-async synchronous view-entries rebuild at accept tail (mirrors handleDismissSuggestion inline pattern)
    - SCREEN-coord lastKnownRects lookup for diff.unchanged survivors (matches diff.added branch)
    - Frame-before-entries ordering — recomputeOverlayFrame precedes rebuildUnderlineEntries so toLocalEntries translates against the updated window origin

key_files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerMirrorTests.swift

decisions:
  - "applyBounds ordering flipped: recomputeOverlayFrame before rebuildUnderlineEntries — toLocalEntries reads overlayWindow.frame; stale origin mis-locates LOCAL entries on cross-line/leftmost accepts. Defensive correctness at zero cost."
  - "update() diff.unchanged rebuilds UnderlineEntry from lastKnownRects[oldSuggestion.id] (SCREEN) — new Suggestion (cappedNew[newIndex]) is stored on the entry for id-continuity; cache lookup uses old id because diff.unchanged's oldSuggestion.id is the cache key written in prior cycles."
  - "overlayWindow visibility flipped private → internal — plan assumed @testable access, but private cannot cross the @testable boundary. Mirrors Phase 2/3/4 test-observable state precedent (applyBoundsCallCount, lastKnownRects, underlineView)."
  - "Test B bypasses show() — Suggestion.range constructed from makeSuggestion uses range bound to literal 'recieve' not to context text, which would crash computeScalarOffsets in show(). Instead built suggestions with ranges bound to the actual 'aaa bbb ccc' context text, then drove update() directly with orderFrontRegardless() to satisfy the isVisible guard."

metrics:
  duration: 15 minutes
  completed: 2026-04-19
  tasks_completed: 3
  files_modified: 2
---

# Phase 05 Plan 03: Session-Local Mirror Improvements — UAT Gap 1 + Gap 2 Closure Summary

**One-liner:** Close UAT Gap 1 (middle-accept transient flicker) and Gap 2 (trailing-accept line wipe) via sync `rebuildUnderlineEntries()` at tail of `repositionAfterAccept` + `update()` diff.unchanged SCREEN-space rebuild; 2 regression tests lock both contracts (PERF-12).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Sync view.entries rebuild at tail of repositionAfterAccept + applyBounds ordering flip | abef708 | OverlayController.swift |
| 2 | Fix update() diff.unchanged SCREEN-space survivor rebuild | 2edcaba | OverlayController.swift |
| 3 | Regression tests for Gap 1 + Gap 2 in OverlayControllerMirrorTests.swift (+ overlayWindow visibility flip) | 4a4c3f4 | OverlayController.swift, OverlayControllerMirrorTests.swift |

## What Was Built

**Task 1 — Sync rebuild + applyBounds ordering flip (Gap 1 closure):**
- `applyBounds` (line 524): swapped order of `recomputeOverlayFrame()` and `rebuildUnderlineEntries()`. Frame now set first so `toLocalEntries(entries, in: overlayWindow.frame)` inside rebuild translates against the up-to-date window origin. Pre-fix this was a latent no-op for single-line middle-accept (origin unchanged) but a real bug for cross-line and leftmost-accept paths where origin shifts.
- `repositionAfterAccept` (line 1386, tail): inserted `recomputeOverlayFrame()` + `rebuildUnderlineEntries()` synchronously between `suggestions = rebuiltSuggestions` and `scheduleReposition(reason: .textChanged)`. Closes the AppKit draw-cycle gap between the synchronous `AXTextReplacer.replace` text write and the async `applyBounds` completion. Pre-fix, pre-accept entries painted over shifted text for one or more frames — user-observed as "blue lines appear in wrong place for a short time before moving to the correct spot". Post-fix: invalidated survivors (cache cleared by D-05 predicate) are simply omitted from the sync rebuild (line 707 guard in `rebuildUnderlineEntries`), and the async reposition fills them in once fresh AX bounds return.

**Task 2 — update() diff.unchanged SCREEN-space rebuild (Gap 2 closure):**
- Deleted `let existingEntries = underlineView?.entries ?? []` (the LOCAL-space source).
- Rewrote `for (oldIndex, newIndex) in diff.unchanged` loop to source rects from `lastKnownRects[oldSuggestion.id]` (SCREEN) and rebuild `UnderlineEntry` values using the same pattern as `rebuildUnderlineEntries` and the `diff.added` branch. `UnderlineEntry.suggestion` carries the new Suggestion (from `cappedNew[newIndex]`) so downstream code sees continuity after `self.suggestions = survivingSuggestions`.
- Defensive fallback: cache miss (should not occur for diff.unchanged — prior cycle succeeded) re-queries via `boundsValidator.validatedBoundsForRange`, re-seeds cache. Preserves SCREEN space.
- Pre-fix root cause: `survivingEntries` mixed LOCAL (from `underlineView.entries`, translated by prior `toLocalEntries`) and SCREEN (fresh from `diff.added`'s `boundsValidator`). `unionRect` over mixed coords was garbage; `overlayWindow.setFrame(windowRect, display: false)` fed LOCAL coords into the SCREEN-coord NSWindow API — window jumped to near-zero origin. For trailing-accept on a single line, every survivor classified as diff.unchanged (scalarStart unchanged → SuggestionKey unchanged) → `survivingEntries` was 100% LOCAL → user-observed as "underlines jump and all on the line are gone after accepting the trailing one".

**Task 3 — Regression tests + overlayWindow visibility flip:**
- `accept_rebuildsViewEntriesSynchronously`: Seeds 3 suggestions ([0..3], [4..7], [8..11]) with SCREEN-space rects and a live `UnderlineView`. Accepts middle (idB). Asserts sync post-accept pre-drain: idB absent (removed + rebuilt), idA present (strictly-before survivor, preserved via `lastKnownRects`). Drains async tail; re-asserts coherence.
- `update_windowFrameOriginIsScreenSpaceForDiffUnchangedSurvivors`: Builds suggestions with ranges bound to actual context text "aaa bbb ccc" so `computeScalarOffsets` inside `update()` produces distinct scalar offsets. Seeds controller with LOCAL-space entries in `underlineView` AND SCREEN-space `lastKnownRects` (simulates post-show() steady state). Calls `update()` with idC dropped (forces `diff.removed` non-empty → bypasses `update()`'s early-return). Asserts `overlayWindow.frame` origin lands near SCREEN-space union (x > 150 and < 250 and y > 400) — not LOCAL near-zero.
- Visibility flip: `OverlayController.overlayWindow` private → internal. Plan assumed `@testable` access but private cannot cross that boundary. Single-word delta; mirrors precedent for `underlineView`, `lastKnownRects`, `applyBoundsCallCount`, `currentRepositionTask`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] overlayWindow private → internal for @testable access**
- **Found during:** Task 3 (writing update_windowFrameOriginIsScreenSpaceForDiffUnchangedSurvivors).
- **Issue:** Plan's `<interfaces>` section asserted "`controller.overlayWindow`, `controller.lastKnownRects`, ... all accessible via `@testable import OpenGramLib`". In reality `overlayWindow` is declared `private let` at line 45 — `@testable` exposes `internal` members but not `private`. Test B requires reading `controller.overlayWindow.frame` after `update()`.
- **Fix:** Flipped declaration from `private let overlayWindow: OverlayWindow` to `let overlayWindow: OverlayWindow` with a comment noting the PERF-12 test seam. Mirrors the existing precedent for `underlineView` (Phase 4 D-27), `lastKnownRects` (Phase 3), and `applyBoundsCallCount` (Phase 2).
- **Files modified:** `OpenGram/SuggestionUI/Overlay/OverlayController.swift`
- **Commit:** 4a4c3f4 (bundled with Task 3 tests)

**2. [Rule 3 - Blocking] Test B bypasses show() because Suggestion.range crosses string-Index boundaries**
- **Found during:** Test B design.
- **Issue:** Plan's Test B called `controller.show(suggestions: seeded, context: controller.textContext!)` to set up `overlayWindow.isVisible == true`. But `seeded` comes from `makeMirrorController` which calls the file-local `makeSuggestion` helper — this constructs `Suggestion.range` from a literal string `"recieve"` (7 chars). `show()` calls `computeScalarOffsets(for: self.suggestions, in: context.text)`; that helper passes a `String.Index` from "recieve" to `unicodeScalars.distance(from:to:)` on "aaa bbb ccc". Swift's cross-string String.Index is implementation-defined; in practice it produces offsets (0, 7) for all three suggestions. `SuggestionKey` (scalarStart/scalarLength/original/category) then collapses all three to the same key → diff behaves unpredictably.
- **Fix:** Built Test B from scratch without the shared factory — constructed Suggestion values with ranges built from the real "aaa bbb ccc" unicode-scalar indices via `scalars.index(_:offsetBy:).samePosition(in:)`. Originals "aaa"/"bbb"/"ccc" distinguish SuggestionKey. Called `orderFrontRegardless()` to satisfy `update()`'s `isVisible` guard without going through `show()`.
- **Files modified:** `OpenGramTests/SuggestionUITests/OverlayControllerMirrorTests.swift`
- **Commit:** 4a4c3f4

## Pre-existing Flake Noted

`OverlayControllerScrollModeTests.hideAndSettle scroll event fades underlines to 0 and sets .faded` — fails under parallel load with the full overlay bundle, passes in suite isolation. Pre-existing; documented in STATE.md at Phase 04-05 and again at Phase 05-01. Confirmed passing solo (`-only-testing:OpenGramTests/OverlayControllerScrollModeTests`: 6/6 green). Out of scope per SCOPE BOUNDARY.

## Verification

- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — SUCCEEDED after Task 1 and after Task 2.
- `xcodebuild test -only-testing:OpenGramTests/OverlayControllerMirrorTests` — 6/6 green (4 prior + 2 new).
- Full overlay regression bundle — 32/33 green, 1 pre-existing parallel-load flake (scroll mode fade test).
- `grep -n "underlineView?.entries ?? \\[\\]" OverlayController.swift` — 0 matches (existingEntries binding deleted).
- `grep -n "lastKnownRects\\[oldSuggestion.id\\]" OverlayController.swift` — 2 matches (cache read + defensive fallback write inside update()).
- `grep -nE "Phase [0-9]|Plan [0-9]" OpenGram/SuggestionUI/Overlay/OverlayController.swift OpenGramTests/SuggestionUITests/OverlayControllerMirrorTests.swift` — 0 matches (CLAUDE.md convention respected).
- Done-criteria verified:
  - Task 1: applyBounds order flipped (recomputeOverlayFrame before rebuildUnderlineEntries); repositionAfterAccept tail shows recomputeOverlayFrame + rebuildUnderlineEntries before scheduleReposition(.textChanged); no BoundsValidator call in repositionAfterAccept body.
  - Task 2: existingEntries binding gone; lastKnownRects[oldSuggestion.id] lookup present; diff.unchanged loop rebuilds UnderlineEntry from SCREEN rects.
  - Task 3: both new tests pass; pre-existing 4 tests pass; pbxproj unchanged (file already registered in Phase 05-02).

### Manual Validation

**Deferred.** Project CLAUDE.md requests manual validation via computer-use MCP for UI-affecting changes. This executor runs headless/automated and cannot reliably test overlay middle-accept + trailing-accept visual behavior against Notes.app without an interactive session. Recommendation: user or a follow-up UAT pass drives the manual validation scripted in PLAN.md's `<verification>` block (3-word Harper error, middle-accept no flicker; trailing errors, trailing-accept leaves earlier underlines visible). The regression tests added here lock the contract at the unit boundary — Gap 1's sync view.entries mutation and Gap 2's SCREEN-coord frame placement are both now under test.

## Threat Flags

None. Pure in-process correctness fix. No new network, persistence, secrets, or user-input surface. All changes stay within the overlay controller's existing trust boundary.

## Known Stubs

None. Both gaps fully closed with production code and regression tests. Gap 3 (rapid multi-accept cascade) is deliberately carved out per the plan's `<scope_note>` — it requires three independent architectural fixes (persistent dismissed-set in CheckCoordinator, Harper/LLM update-contract preservation, ParagraphSuggestionStore dismissal across hash change) that belong to a separate inserted phase.

## Self-Check: PASSED

- OpenGram/SuggestionUI/Overlay/OverlayController.swift — FOUND
- OpenGramTests/SuggestionUITests/OverlayControllerMirrorTests.swift — FOUND
- .planning/phases/05-session-local-mirror-improvements/05-03-SUMMARY.md — FOUND
- Commits abef708, 2edcaba, 4a4c3f4 — all present in git log (verified via `git log --oneline -5`)
