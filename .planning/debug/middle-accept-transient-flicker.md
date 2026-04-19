---
status: diagnosed
trigger: "middle-accept-transient-flicker"
created: 2026-04-19T00:00:00Z
updated: 2026-04-19T00:30:00Z
---

## Current Focus

hypothesis: After Phase 5's accept-path refactor replaced the sync BoundsValidator loop with async `scheduleReposition(.textChanged)`, `acceptSuggestion` never clears the stale `view.entries` between the sync text shift and the async `applyBounds` completion. During that interval the UnderlineView continues to render the pre-accept entries (including the accepted-and-shifted ones) over text that has already been replaced in the target app, producing the "wrong position for a short time before snapping to correct spot" flicker.
test: Traced data flow through `acceptSuggestion` -> `repositionAfterAccept` -> `scheduleReposition(.textChanged)` -> `reposition(reason:)` -> `applyBounds` -> `rebuildUnderlineEntries`. Compared against `handleDismissSuggestion` which DOES clear the entry.
expecting: A discrete write to `view.entries` is missing between the sync mutation of `suggestions`/`suggestionScalarOffsets`/`lastKnownRects` and the async boundsBatch return.
next_action: Return ROOT CAUSE FOUND.

reasoning_checkpoint:
  hypothesis: "acceptSuggestion never clears/rebuilds view.entries synchronously, so the UnderlineView keeps rendering pre-accept entries (stale S2 underline still there, stale S3 at pre-shift screen position) until the async axQueue.boundsBatch completes and rebuildUnderlineEntries runs — that is the observed 'wrong place for short time, then snap'."
  confirming_evidence:
    - "OverlayController.swift:1249-1297 acceptSuggestion — cancels reposition task, mutates lastKnownRects/suggestions/suggestionScalarOffsets, calls repositionAfterAccept. No view.entries mutation anywhere in the path."
    - "OverlayController.swift:1303-1395 repositionAfterAccept — D-05 cache invalidation, scalar-offset shift, textContext rebuild, suggestions rebuild, then scheduleReposition(.textChanged). No view.entries touched."
    - "OverlayController.swift:1223-1233 handleDismissSuggestion — does `view.entries.removeAll { $0.suggestion.id == suggestion.id }` + `view.needsDisplay = true` inline. Proves the pattern exists elsewhere, just not on accept."
    - "OverlayController.swift:441-446 scheduleReposition spawns Task {} — runs on next tick. Between this call returning and applyBounds firing, AppKit gets at least one draw cycle where view.entries is pre-accept state."
    - "Phase 5 SUMMARY.md Edits 5-6: explicitly deleted the synchronous BoundsValidator loop that used to rebuild entries in the same tick as the text write. Replacement is scheduleReposition(.textChanged) with no compensating sync clear."
    - "Phase 5 CONTEXT D-04 spells out 'the empty-filter case STILL routes through reposition() so rebuildUnderlineEntries runs' — explicit recognition that the view needs rebuilding, but relies on the async path to do it. Never closes the stale-entries gap before that async runs."
  falsification_test: "Add `view.entries = []` or a filtered rebuild immediately after the sync `suggestions = rebuiltSuggestions` in repositionAfterAccept. If the flicker disappears, the hypothesis is confirmed. If it persists, the root cause is elsewhere (async boundsBatch returning stale AX bounds, coordinate-space bug in toLocalEntries ordering, etc.)."
  fix_rationale: "Root cause is a missing synchronous write to view.entries between the model mutation and the async bounds query. Fixing the async path's ordering (e.g., window-frame-before-local-coords) doesn't help because during the interim NEITHER applyBounds nor rebuildUnderlineEntries has run — the stale entries are literally the pre-accept set still on screen. The fix is to either clear stale entries immediately (accept small flicker to empty) or rebuild them synchronously from preserved lastKnownRects (zero-flicker for strictly-before survivors)."
  blind_spots:
    - "Have not yet measured actual frame-gap duration empirically — on a fast mac the Task dispatch + actor hop + axQueue round-trip may be <16ms on end-of-doc (zero-AX empty-filter path) but can be much longer when boundsBatch fires against a busy AX tree."
    - "Have not verified whether the same bug causes Test 2 (trailing-accept 'underlines jump and all on the line are gone') and Test 3 (rapid multi-accept 'dismissed suggestions reappear') — those may share this root cause or have independent bugs. Scoped to Test 1 only per trigger."
    - "Ordering bug in applyBounds is also real (toLocalEntries uses old overlayWindow.frame before recomputeOverlayFrame sets the new one, OverlayController.swift:524-541 + 698-725) — but for middle-accept with same-line layout the window origin is unchanged (still `min(R1.minX, …)`) so that ordering bug does NOT cause the observed flicker in Test 1. Flagging as secondary finding; may manifest in other acceptance shapes."

## Symptoms

expected: With 3+ underlined suggestions in a line, accepting the middle one leaves earlier underlines in the exact same screen position with no flicker. Later underlines shift cleanly.
actual: "The new implementation largely works, but I do see random issue like this screenshot. The blue lines appear in the wrong place for a short time before moving to the correct spot"
errors: None reported
reproduction: Test 1 in .planning/phases/05-session-local-mirror-improvements/05-UAT.md. Type text with 3+ grammar errors in a row, press Ctrl+Shift+G, click middle suggestion to accept. Blue underlines render at wrong position briefly, then snap correct.
started: Phase 5 UAT (Plan 01 accept-path refactor landed in commit 8873cee).

## Eliminated

- hypothesis: "Coordinate-space bug in rebuildUnderlineEntries — toLocalEntries called with overlayWindow.frame BEFORE recomputeOverlayFrame updates the window frame, so entries use old origin while window moves to new origin."
  evidence: "For middle-accept on a single line, R1 is leftmost and stays leftmost after accept; union(R1, newR3).origin == union(R1, R2, R3).origin on both X (leftmost = R1.minX) and Y (same baseline). Frame size shrinks horizontally, origin unchanged — entries' local coords are correct despite wrong ordering. Bug is real but doesn't drive Test 1's symptom. Flagged as secondary."
  timestamp: 2026-04-19T00:20:00Z

- hypothesis: "Stale AX bounds returned by axQueue.boundsBatch before target app completes text re-layout."
  evidence: "Symptom is EARLIER underlines flickering (S1, preserved via lastKnownRects, never goes through boundsBatch on the middle-accept path). Stale AX bounds could affect S3 (the invalidated/queried one) but not S1. Also contradicted by user reporting a 'snap to correct' which implies a subsequent correct state — if AX returned stale bounds, they'd stay stale until another reposition fires, which nothing in this path triggers."
  timestamp: 2026-04-19T00:22:00Z

## Evidence

- timestamp: 2026-04-19T00:05:00Z
  checked: .planning/phases/05-session-local-mirror-improvements/05-01-SUMMARY.md Edits 5 and 6
  found: "Edit 5 deleted the ~47-line synchronous BoundsValidator.validatedBoundsForRange loop from repositionAfterAccept (including screenEntries, survivingSuggestions, survivingOffsets, window frame recompute, toLocalEntries call). Edit 6 replaced deleted block with scheduleReposition(reason: .textChanged)."
  implication: The pre-refactor code rebuilt view.entries synchronously inside the same tick as the AX text write. The refactor dropped that sync rebuild and punted entirely to the async reposition. No compensating sync clear was added.

- timestamp: 2026-04-19T00:10:00Z
  checked: OverlayController.swift:1249-1297 (acceptSuggestion) + :1303-1395 (repositionAfterAccept)
  found: "acceptSuggestion touches: currentRepositionTask.cancel (1250), suggestionScalarOffsets (1256-1263), replacer.replace (1267-1273), lastKnownRects.removeValue (1276), suggestions.remove (1281), suggestionScalarOffsets.remove (1283), then repositionAfterAccept. repositionAfterAccept does D-05 invalidation, scalar-offset shift, textContext rebuild, suggestions rebuild, scheduleReposition(.textChanged). Total view.entries mutations across both functions: ZERO."
  implication: From the moment replacer.replace returns (target app text is new) until applyBounds fires at the end of the async task, the UnderlineView is still displaying entries for S1 old-pos, S2 old-pos, S3 old-pos — but the text under those underlines has already shifted in the target app. Flicker window = one or more draw cycles.

- timestamp: 2026-04-19T00:12:00Z
  checked: OverlayController.swift:1223-1233 (handleDismissSuggestion)
  found: "Dismiss path: suggestions.removeAll; view.entries.removeAll { $0.suggestion.id == suggestion.id }; view.needsDisplay = true. Inline sync update of the view's entries."
  implication: The pattern for "mutate model and update view in the same tick" exists. Accept path should be doing the equivalent (and historically did, via the BoundsValidator sync loop). The refactor regressed.

- timestamp: 2026-04-19T00:15:00Z
  checked: OverlayController.swift:441-446 (scheduleReposition) + :452-483 (reposition)
  found: "scheduleReposition wraps body in Task { await self?.reposition(reason: reason) }. reposition awaits axQueue.boundsBatch. On the middle-accept path, filter returns [S3] (S1 cached/preserved, S3 invalidated) — not empty, so hits the axQueue path. axQueue actor-hop + AX round-trip delays applyBounds by at least one draw cycle; typically 8-20ms."
  implication: Async gap confirmed. Within that gap, draw cycles fire using stale view.entries. User perceives the pre-applyBounds frame(s) as a flicker.

- timestamp: 2026-04-19T00:18:00Z
  checked: OverlayController.swift:524-541 (applyBounds) + :698-725 (rebuildUnderlineEntries) + :727-747 (recomputeOverlayFrame)
  found: "applyBounds order: applyBoundsCallCount++; lastKnownRects seeded; rebuildUnderlineEntries(); recomputeOverlayFrame(). rebuildUnderlineEntries calls toLocalEntries(entries, in: overlayWindow.frame) — uses the CURRENT (pre-recompute) overlayWindow.frame. recomputeOverlayFrame then sets overlayWindow.setFrame(newFrame) AFTER."
  implication: Secondary bug: local-coord translation uses pre-recompute window frame, then window frame changes. For acceptance shapes where new_frame.origin != old_frame.origin (e.g., accepting the LEFTMOST suggestion, or any accept that crosses a line boundary, or suggestions on multiple lines), entries render at wrong screen coords. For Test 1's same-line middle-accept this happens to be a no-op (leftmost stays leftmost), so it's not the Test 1 symptom — but it is a latent bug that will surface on related acceptance shapes. Worth flagging for Test 2 (trailing-accept) and Test 3 (rapid multi-accept) triage.

- timestamp: 2026-04-19T00:25:00Z
  checked: OverlayController.swift:493-518 (suggestionsForReposition), Phase 5 D-07/D-09 invariants
  found: "D-09: .textChanged filters to uncached suggestions. D-07: if filter is empty, short-circuits to rebuildUnderlineEntries+recomputeOverlayFrame and returns. If filter is non-empty, hits axQueue. Middle-accept with S1-preserved, S3-invalidated produces a non-empty filter ([S3]) — the zero-AX short-circuit does NOT trigger, so the async path IS taken, so the flicker window opens."
  implication: The D-07 empty-filter short-circuit was designed for the END-OF-DOC accept case where all survivors are strictly before the edit. Middle-accept does not benefit from it. The contract in phase spec ("earlier underlines stay in exact same screen position") held in intent (lastKnownRects preserved) but not in wall-clock rendering (view.entries not updated until async applyBounds lands).

## Resolution

root_cause: |
  Phase 5 accept-path refactor removed the synchronous BoundsValidator-driven rebuild of `view.entries` and replaced it with a tail-call to the async `scheduleReposition(.textChanged)`. For middle-accept, the filter (`.textChanged` = uncached suggestions) is non-empty (S3 is invalidated), so the path takes the async `axQueue.boundsBatch` branch instead of the zero-AX empty-filter short-circuit. Between `replacer.replace` returning (target app text now shifted) and the async `applyBounds` callback firing (view.entries rebuilt from preserved lastKnownRects + fresh bounds), the UnderlineView continues to render the pre-accept entries — S1 at correct old pos (still correct in screen coords), S2 still underlined (text underneath now gone), and S3 at its pre-shift screen position (text underneath now moved). Across one or more AppKit draw cycles the user sees underlines painted over text that has moved, which reads as "blue lines appear in the wrong place for a short time before moving to the correct spot."

  Contrast: `handleDismissSuggestion` (OverlayController.swift:1227) removes the dismissed entry from `view.entries` synchronously. The accept path has no equivalent — it relies entirely on the async `applyBounds` to rebuild the view, and nothing holds the user's frame during the gap.

fix: |
  Proposed direction (not yet applied — goal: find_root_cause_only): between the sync model mutations in `acceptSuggestion`/`repositionAfterAccept` and the `scheduleReposition(.textChanged)` tail call, synchronously rebuild `view.entries` from the updated `suggestions` array and the post-invalidation `lastKnownRects`. Suggestions with preserved rects (strictly-before) get entries immediately; suggestions with invalidated rects (overlap/after-edit) get no entry until the async bounds return — producing a clean "old underlines stay put, shifted/new underlines appear once queried" experience instead of the stale-then-snap flicker.

  Concrete: call `rebuildUnderlineEntries()` synchronously at the end of `repositionAfterAccept` immediately BEFORE `scheduleReposition(.textChanged)`. That function already iterates `suggestions` and skips any id without a `lastKnownRects` entry (line 707 `guard let rects = lastKnownRects[suggestion.id] else { continue }`), so invalidated survivors are correctly omitted for now and filled in by the subsequent async applyBounds. Note: sync rebuildUnderlineEntries has the SAME ordering issue with `toLocalEntries(in: overlayWindow.frame)` — for middle-accept with same-line layout this is a no-op (origin unchanged) so it works, but for the full fix across Tests 2/3 you'll also want to do the window-frame recompute BEFORE the local-coord translation (i.e., change the order inside applyBounds and the new sync rebuild site to: compute new frame first, then toLocalEntries with new frame origin, then setFrame).

verification: (empty — diagnose-only mode)

files_changed: []
