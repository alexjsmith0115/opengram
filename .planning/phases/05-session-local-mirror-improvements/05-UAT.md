---
status: diagnosed
phase: 05-session-local-mirror-improvements
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md]
started: 2026-04-19T00:00:00Z
updated: 2026-04-19T00:06:00Z
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
  root_cause: "Phase 5 accept-path refactor (commit 8873cee, Edits 5-6) deleted the synchronous BoundsValidator loop that rebuilt view.entries in the same tick as the AX text write, and replaced it with tail-call scheduleReposition(.textChanged). No compensating synchronous view.entries update was added. D-09 filter for middle-accept returns non-empty → path takes async axQueue.boundsBatch branch (NOT the zero-AX empty-filter short-circuit). Between replacer.replace returning and async applyBounds firing, UnderlineView keeps drawing pre-accept entries over shifted text → one or more AppKit draw cycles of stale underlines at wrong positions. handleDismissSuggestion (:1223-1233) updates view.entries inline — accept path has no equivalent."
  artifacts:
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "1303-1395"
      issue: "repositionAfterAccept makes zero writes to view.entries across the entire sync phase"
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "524-541, 698-725, 727-747"
      issue: "applyBounds/rebuildUnderlineEntries ordering — toLocalEntries(in: overlayWindow.frame) runs BEFORE recomputeOverlayFrame sets the new frame (secondary latent bug, implicated in Tests 2/3)"
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "1223-1233"
      issue: "handleDismissSuggestion has canonical inline view-update pattern that accept path is missing"
  missing:
    - "Synchronous rebuildUnderlineEntries() call at the end of repositionAfterAccept immediately before scheduleReposition(.textChanged) — existing rebuild skips uncached suggestions (line 707 guard), so invalidated survivors omit cleanly and async applyBounds fills them in once bounds return"
    - "Flip ordering inside applyBounds (and new sync site) so recomputeOverlayFrame runs BEFORE toLocalEntries — compute new window frame first, translate entries against new origin, then setFrame"
  debug_session: .planning/debug/middle-accept-transient-flicker.md

- truth: "With suggestions only trailing toward end of text, accepting the last one causes the overlay to dismiss or shrink smoothly in a single frame. No stutter, no half-drawn underlines, no delay."
  status: failed
  reason: "User reported: the underlines jump and all on the line are gone after accepting the trailing one"
  severity: major
  test: 2
  root_cause: "OverlayController.update() mixes coordinate spaces. Line 360 appends underlineView.entries (WINDOW-LOCAL coords from prior toLocalEntries) to survivingEntries for every diff.unchanged suggestion. Line 409 builds unionRect from that LOCAL data, pads it, passes it to overlayWindow.setFrame at line 420 — feeding LOCAL coords into a SCREEN-coord API. Window jumps to AppKit origin / bottom-left. Not a Phase 5 regression in D-07 itself — empty-filter branch is correct. Latent bug surfaces because AXTextReplacer fires kAXValueChangedNotification → TextMonitor → store.invalidateDisplayed → .suggestionsChanged → handleStoreEvent → update(merged). For TRAILING-accept, every survivor is strictly-before edit site → scalarStart unchanged → SuggestionKey unchanged → ALL survivors take diff.unchanged → survivingEntries 100% LOCAL → unionRect fully LOCAL → window jumps hard. Middle-accept partially corrects because shifted scalarStart → new key → classified as 'added' → boundsValidator fresh SCREEN rects contribute."
  artifacts:
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "349-362"
      issue: "update() diff.unchanged branch: kept = existingEntries.filter{...} reuses LOCAL entries from underlineView.entries"
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "409-420"
      issue: "update() computes unionRect from LOCAL entries then passes it to setFrame (SCREEN) — coordinate space mismatch"
  missing:
    - "In update() diff.unchanged loop, source survivor rects from lastKnownRects[cappedNew[newIndex].id] (SCREEN space) and rebuild UnderlineEntry values with fresh expandedHitRect, matching rebuildUnderlineEntries pattern. Do NOT reuse underlineView.entries (LOCAL)."
    - "Keep added branch unchanged (already SCREEN via boundsValidator). Defensive fallback to fresh boundsValidator query if lastKnownRects[id] missing."
    - "Regression test in OverlayControllerTests asserting overlayWindow.frame.origin matches padded screen rect origin after post-accept update() where all survivors are diff-unchanged"
  debug_session: .planning/debug/trailing-accept-wipes-line.md

- truth: "Accepting 3+ suggestions back-to-back (as fast as you can click) feels instant each time. No queue-up lag, no overlay glitch between accepts. Remaining underlines stay stable."
  status: failed
  reason: "User reported: I cant accept 3 back to back because dismissed suggestions reappear, existing underlines disappear, and dismissed llm suggestions override harper"
  severity: blocker
  test: 3
  root_cause: "Three independent latent defects combine. Phase 5 Plan 01 widened the race window but did NOT introduce any. Pre-Plan-01 accept was synchronous — scheduleDebounce and store events still fired but accept's own repaint finished before they arrived. Plan 01 made accept reposition async (scheduleReposition(.textChanged)); second accept cancels first's reposition task; update() / handleStoreEvent can run mid-reconciliation. BUG 1: CheckCoordinator.wireOverlayCallbacks treats dismissal as just lastSuggestions.removeAll{id} — no persistent dismissed-ID/content-key set. Debounced Harper rerun re-flags same word; SuggestionDiffEngine (content-keyed) sees 'added' → re-rendered. BUG 2: CheckCoordinator.handleCheckComplete calls overlayController.update with Harper-only (CheckOrchestrator.runCheck emits only Harper; LLM flows via store events). OverlayController.update diffs full-new vs self.suggestions — LLM entries classify as 'removed' and strip until next store event re-merges. BUG 3: ParagraphSuggestionStore.markDismissed keys dismissal to ParagraphHash. Accepting Harper inside paragraph mutates text → new hash → reconcile sweeps old entry (line 67: cache[hash]=nil) taking .dismissed with it → new hash submitted as miss → fresh .ready LLM returns → mergeHarperAndLLM includes it."
  sub_issues:
    - "BUG 1: Dismissed Harper suggestions reappear — no dismissed-set"
    - "BUG 2: Existing LLM underlines disappear — Harper-only update() classifies them as removed"
    - "BUG 3: Dismissed LLM suggestions return after Harper accept — content-hash dismissal swept on reconcile"
  artifacts:
    - path: "OpenGram/App/CheckCoordinator.swift"
      line: "54-57"
      issue: "dismissal handler only removes from lastSuggestions; no persistent dismissed-set (BUG 1)"
    - path: "OpenGram/App/CheckCoordinator.swift"
      line: "113-133"
      issue: "handleCheckComplete calls overlayController.update with Harper-only results — clobbers LLM entries (BUG 2)"
    - path: "OpenGram/CheckEngine/CheckOrchestrator.swift"
      line: "27-36"
      issue: "runCheck contract omits LLM"
    - path: "OpenGram/SuggestionUI/Overlay/OverlayController.swift"
      line: "789-825"
      issue: "handleStoreEvent merges against stale self.suggestions; update() diff removes LLM when fed Harper-only"
    - path: "OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift"
      line: "56-89, 147-151"
      issue: "content-hash dismissal evicted on reconcile sweep after text mutation (BUG 3)"
    - path: "OpenGram/SuggestionUI/Panels/SuggestionDiffEngine.swift"
      line: "7-67"
      issue: "content-key matching with no dismissed-set gate"
  missing:
    - "BUG 1: Persistent dismissed-set keyed by SuggestionKey shape + TTL or text-mutation invalidation, consulted in CheckCoordinator.handleCheckComplete (or filter before overlayController.update)"
    - "BUG 2: handleCheckComplete passes Harper + current LLM snapshot (read store.renderableSuggestions or cache last merged LLM in CheckCoordinator), OR OverlayController.update preserves LLM entries by source filter when caller is Harper-only"
    - "BUG 3: LLM dismissal persistence across hash change — either key dismissal by paragraph-location+original-content pair with fuzzy match across small mutations, or propagate dismissal across 'hash changed but paragraph substantively the same' case"
    - "Phase 5 reposition race itself does not need a fix — tightening accept path further without addressing BUGs 1-3 will not resolve UAT-3"
  debug_session: .planning/debug/rapid-multi-accept-cascade.md
