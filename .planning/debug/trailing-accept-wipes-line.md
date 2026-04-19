# Debug Session: trailing-accept-wipes-line

**Status:** root-cause-found
**Started:** 2026-04-19
**Goal:** find_root_cause_only

## Symptoms

- **expected:** With suggestions only trailing toward end of text, accepting the last one causes the overlay to dismiss or shrink smoothly in a single frame. No stutter, no half-drawn underlines, no delay. Earlier preserved underlines stay.
- **actual:** "the underlines jump and all on the line are gone after accepting the trailing one"
- **reproduction:** Test 2 in `.planning/phases/05-session-local-mirror-improvements/05-UAT.md`. Type text where suggestions only trail toward end (e.g. `"fox jumpps over lazzy dog"` — two trailing suggestions). Accept the final one. Remaining underlines on that line jump then disappear.

## Root Cause

`OverlayController.update()` mixes coordinate spaces when computing `windowRect` after the `.suggestionsChanged` event fires post-accept.

- `update()` line 360 appends `underlineView.entries` (**window-local** coords, set by prior `toLocalEntries` call) to `survivingEntries` for every `diff.unchanged` suggestion.
- Line 409 builds `unionRect = survivingEntries.reduce(.null) { $0.union($1.hitRect) }` from that LOCAL data, pads it, passes it to `overlayWindow.setFrame(windowRect, display: false)` at line 420 — feeding LOCAL coords into a SCREEN-coord API.
- Window jumps to a screen location that was actually a window-local coordinate (near AppKit origin / bottom-left of main screen).

Not a Phase 5 regression in the D-07 path itself — the empty-filter branch (`rebuildUnderlineEntries + recomputeOverlayFrame`) does its job correctly for the trailing-accept geometry. The bug is a latent coordinate-space mismatch in `update()` that becomes user-visible because:

1. `AXTextReplacer` fires `kAXValueChangedNotification` → `TextMonitor.handleValueChanged` → `driveStoreOnValueChange` → `store.invalidateDisplayed` → `.suggestionsChanged` → `handleStoreEvent` → `update(merged, ctx)`. Runs async shortly after `repositionAfterAccept`.
2. For TRAILING-accept, every survivor is strictly-before the edit site → `scalarStart` unchanged → `SuggestionKey(scalarStart, length, original, category)` unchanged → ALL survivors take the `diff.unchanged` branch → `survivingEntries` is 100% LOCAL-coord → `unionRect` fully LOCAL → window jumps hard.
3. For MIDDLE-accept, post-edit survivors have shifted `scalarStart` → new `SuggestionKey` → classified as `added` → `boundsValidator.validatedBoundsForRange` fresh SCREEN rects contribute to the union. Partial correction explains UAT Test 1's milder "briefly wrong then correct."

Subsequent Harper debounce (0.8s) fires another `update()` with fresh Harper UUIDs. `diff.unchanged` matches by content-key so `jumpps` is "unchanged", but `existingEntries.filter { $0.suggestion.id == oldSuggestion.id }` matches the OLD UUID's entries (still LOCAL) → same bug compounds. If entries get cleared mid-flight, `survivingEntries.isEmpty` → `dismiss()` → overlay vanishes entirely. Matches symptom: "jump and all on the line are gone."

## Evidence

- D-05 predicate preserves `lastKnownRects[jumpps.id]` correctly (`beforeEnd=10 <= editStart=16`).
- D-07 empty-filter branch produces correct entries and frame in isolation.
- `AXTextReplacer.replace` → `kAXValueChangedNotification` → `TextMonitor` → `store.invalidateDisplayed` → `.suggestionsChanged` → `update()` is the failure-triggering arc.
- `update()` line 360: `kept = existingEntries.filter { $0.suggestion.id == oldSuggestion.id }` — `existingEntries` are LOCAL (from `underlineView.entries` populated by `toLocalEntries`).
- `update()` line 409-420: `unionRect` from LOCAL entries → `setFrame(windowRect)` → window screen-frame set from local coords.
- `SuggestionDiffEngine.diff` keys on scalarStart+length+original+category — trailing-accept survivors have unchanged key → 100% diff-unchanged path.

## Files Involved

- `OpenGram/SuggestionUI/Overlay/OverlayController.swift:349-362, 409-420` — `update()` diff.unchanged branch reuses LOCAL entries and treats their union as SCREEN.

## Suggested Fix Direction

In `update()` diff.unchanged loop, source survivor rects from `lastKnownRects[cappedNew[newIndex].id]` (SCREEN space) and rebuild `UnderlineEntry` values with fresh `expandedHitRect` — matching `rebuildUnderlineEntries`'s pattern. Do NOT reuse `underlineView.entries` (LOCAL). Keep `added` branch unchanged (already uses `boundsValidator` → SCREEN). Defensive fallback to fresh `boundsValidator` query if `lastKnownRects[id]` missing.

Add regression test in `OverlayControllerTests` asserting `overlayWindow.frame.origin` matches padded screen rect origin after a post-accept `update()` call where all survivors are diff-unchanged.
