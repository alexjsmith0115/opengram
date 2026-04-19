# Debug Session: rapid-multi-accept-cascade

**Status:** root-cause-found
**Started:** 2026-04-19
**Goal:** find_root_cause_only

## Symptoms

- **expected:** Accepting 3+ suggestions back-to-back feels instant each time. No queue-up lag, no overlay glitch between accepts. Remaining underlines stay stable.
- **actual:** "I cant accept 3 back to back because dismissed suggestions reappear, existing underlines disappear, and dismissed llm suggestions override harper"
- **reproduction:** Test 3 in `.planning/phases/05-session-local-mirror-improvements/05-UAT.md`. Multiple grammar/LLM suggestions visible, accept (or dismiss) rapidly back-to-back.

## Root Cause

Three independent latent defects combine. Phase 5 Plan 01 widened the race window but did NOT introduce any of them.

### BUG 1 — dismissed Harper reappears

`CheckCoordinator.wireOverlayCallbacks` (`CheckCoordinator.swift:54-57`) treats dismissal as just `lastSuggestions.removeAll { $0.id == ... }`. No persistent dismissed-ID or dismissed-content-key set.

Debounced Harper rerun (`TextMonitor.swift:274-281`, 0.8s) re-flags the same word. `SuggestionDiffEngine` (content-keyed on `scalarStart+scalarLength+original+category`) sees `added` → re-rendered.

### BUG 2 — existing underlines disappear

`CheckCoordinator.handleCheckComplete` (`CheckCoordinator.swift:113-133`) calls `overlayController.update(suggestions:)` with HARPER-ONLY results (`CheckOrchestrator.runCheck` emits only Harper; LLM flows via store events).

`OverlayController.update` diffs full new vs `self.suggestions` — any LLM entries currently displayed classify as `removed` and strip from the view until the next store event re-merges.

### BUG 3 — dismissed LLM returns (looks like "override Harper")

`ParagraphSuggestionStore.markDismissed` (`ParagraphSuggestionStore.swift:147`) keys dismissal to `ParagraphHash` (content hash).

Accepting a Harper suggestion inside the paragraph mutates text → new hash → `reconcile` sweeps old entry (`ParagraphSuggestionStore.swift:67`: `cache[hash] = nil`) taking `.dismissed` with it → new hash submitted as a miss → fresh `.ready` LLM returns.

`mergeHarperAndLLM` (`OverlayController.swift:821-825`) includes it.

### Why Phase 5 surfaced it

Pre-Plan-01 accept was synchronous — scheduleDebounce and store events still fired, but accept's own repaint finished before they arrived.

Plan 01 made accept reposition async (`scheduleReposition(.textChanged)`). Second accept cancels first's reposition task; `update()` / `handleStoreEvent` can run while overlay is mid-reconciliation. Race widens, cascade becomes visible.

## Evidence

- `Suggestion.swift:91` + `HarperService.swift:14` — Harper mints `UUID()` per check, diff relies on content key.
- `SuggestionDiffEngine.swift:7-12` — key is `(scalarStart, scalarLength, original, category)`, no ignore-set gating.
- `CheckCoordinator.swift:48-67` — dismissal never persisted anywhere.
- `CheckOrchestrator.swift:27-36` — `runCheck` emits Harper only.
- `OverlayController.swift:789-825` — `handleStoreEvent` reads `self.suggestions` (post-clobber snapshot) for Harper half of merge.
- `ParagraphSuggestionStore.swift:56-89, 147-151` — content-hash dismissal swept on text mutation.
- Plan 01 commit `8873cee` — only touches `suggestionsForReposition`, `reposition`, `repositionAfterAccept`, `recomputeOverlayFrame`. None of the three cascade sources.

## Files Involved

- `OpenGram/App/CheckCoordinator.swift:54-57, 113-133` — no dismissed-set; Harper-only `update()` clobbers LLM.
- `OpenGram/CheckEngine/CheckOrchestrator.swift:27-36` — `runCheck` contract omits LLM.
- `OpenGram/SuggestionUI/Overlay/OverlayController.swift:789-825` — `handleStoreEvent` merges against stale `self.suggestions`; `update()` diff removes LLM when fed Harper-only.
- `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift:56-89, 147-151` — content-hash dismissal evicted on reconcile sweep after text mutation.
- `OpenGram/CheckEngine/Suggestion.swift:91` + `OpenGram/CheckEngine/Harper/HarperService.swift:14` — fresh UUID per check.
- `OpenGram/SuggestionUI/Panels/SuggestionDiffEngine.swift:7-67` — content-key matching with no dismissed-set gate.

## Suggested Fix Direction

1. **BUG 1:** Introduce a persistent dismissed-set keyed by `SuggestionKey` shape + TTL or text-mutation invalidation, consulted in `CheckCoordinator.handleCheckComplete` (or filter before `overlayController.update`).
2. **BUG 2:** `handleCheckComplete` must pass Harper + current LLM snapshot (read `store.renderableSuggestions` or cache last merged LLM in CheckCoordinator), OR `OverlayController.update` must preserve LLM entries by source filter when caller is Harper-only.
3. **BUG 3:** LLM dismissal needs stronger persistence — either (a) key dismissal by paragraph-location+original-content pair and match fuzzy across small mutations, or (b) propagate dismissal across the "hash changed but paragraph is substantively the same" case.
4. Phase 5 reposition race itself does not need a fix — the underlying policy gaps are the real bug. Tightening accept path further without addressing 1-3 will not resolve UAT-3.
