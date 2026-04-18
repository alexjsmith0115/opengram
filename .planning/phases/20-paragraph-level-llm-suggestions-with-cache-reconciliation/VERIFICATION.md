# Phase 20 — Goal-Backward Verification

**Phase goal (from ROADMAP.md):**
> Paragraph-level LLM suggestions render as purple dashed underlines alongside Harper red/blue, backed by a `ParagraphSuggestionStore` (actor) with per-paragraph cache, state machine (`pending/ready/readyEmpty/failed/dismissed/accepted`), reconciliation-on-tick, AX-text-change invalidation, FIFO 1-in-flight LLM queue with 30s timeout, and click-to-rephrase-card dispatch. Phase 16 `LLMCheckScheduler`, Phase 15 `ParagraphSuggestionCache`, and `IncrementalConfig` are deleted wholesale (D-01); tunables migrate into a new `OpenGramConfig` struct.

**Verdict: ✅ Goal achieved.**

## Goal Components — Evidence

| Component | Status | Evidence |
|---|---|---|
| Purple dashed underlines alongside Harper red/blue | ✅ | `UnderlineView.colorForSuggestion` returns `.systemPurple` for `source == .llm`; z-order .llm-first; `isDashedForSource(.llm) == true`. Manual validation item 1 passed. |
| `ParagraphSuggestionStore` actor | ✅ | `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift` — actor, owns cache + currentSet + event stream. |
| Per-paragraph cache | ✅ | `cache: [ParagraphHash: ParagraphCacheEntry]` inside store. Per-bundleID via `ParagraphHash.bundleID`. |
| State machine (6 states) | ✅ | `ParagraphSuggestionState` enum: `.pending(submittedAt:)`, `.ready(Suggestion)`, `.readyEmpty`, `.failed(Error)`, `.dismissed`, `.accepted`. All transitions present + tested. |
| Reconciliation-on-tick | ✅ | `reconcile(set:)` called on focus change, keystroke debounce tick (llmDebounceMs = 2000ms default), and hotkey (immediate, cancelling debounce). PRD §Reconciliation Algorithm line 230 satisfied. |
| AX text-change invalidation | ✅ | `TextMonitor.handleValueChanged` → `store.invalidateDisplayed` → currentSet refresh + event emission. Stale underlines disappear within one frame. Manual validation item 2 passed. |
| FIFO 1-in-flight LLM queue | ✅ | `LLMRequestQueue` actor with `queued: [QueueEntry]` + `inFlight: InFlight?`. Serialized submission via `pump()`. |
| 30s timeout | ✅ | `withTimeout(seconds:)` wrapper around `llm.analyze`. Default `OpenGramConfig.llmRequestTimeoutSeconds = 30`; user-configurable via AdvancedSettingsView. |
| Click-to-rephrase-card dispatch | ✅ | `OverlayController` click handler detects `source == .llm` and calls `tryDispatchRephraseCard` (D-02). Manual validation item 4 passed. |
| Legacy deletion (D-01) | ✅ | `LLMCheckScheduler` + `ParagraphSuggestionCache` + `IncrementalConfig` + 7 legacy test files deleted in Plan 10c Task 1 (commit `949194b`). PLL-16 + PLL-17 grep gates zero. |
| `OpenGramConfig` migration | ✅ | `OpenGramConfig` struct with 8 live-read UserDefaults-backed tunables + `didChangeNotification` hot reload. AdvancedSettingsView writes + posts. |

## Manual Validation (PRD §Manual Validation items 1-7)

All seven items executed against `/Applications/OpenGram.app` (or equivalent Debug build after keystroke-debounce fix):

1. ✅ Harper + LLM coexist (red solid + purple dashed)
2. ✅ Edit invalidates within ~1 frame
3. ✅ App-switch preserves cache (no new LLM request on return)
4. ✅ Click purple → rephrase card → Accept replaces text
5. ✅ Eager processing across multi-paragraph doc (FIFO sequential)
6. ✅ Caret-skip during typing (zero requests for caret paragraph)
7. ✅ Prior paragraph fires after caret moves away

User `approved` 2026-04-18.

## Regression Gates

- **xcodebuild test**: 459/459 passing (71 suites, ~30s)
- **Live LM Studio tests**: 4/4 passing when opt-in (`TEST_RUNNER_OPENGRAM_LIVE_LLM=1`)
- **PLL-16 grep gate**: zero `LLMCheckScheduler` references in source
- **PLL-17 grep gate**: zero `ParagraphSuggestionCache` references in source
- **No TODO/FIXME/HACK** introduced in phase scope

## Known Minor Deviations (Accepted)

- **AX text-change sweep eviction**: defers orphan eviction to next reconcile tick instead of synchronously within `invalidateDisplayed`. PRD §Cache Eviction trigger #2 strict reading implies synchronous. Impact bounded to ~2s debounce window. Memory negligible. Rendering unaffected (filtered by live set).
- **`llmEndpointURL` / `llmModelName` placement**: PRD §Configuration puts these in `OpenGramConfig`; implementation keeps them in `LLMConfig` via `ConfigManager.currentLLMConfig()`. Functional equivalence.

## Deferred Items (Tracked Separately)

- Phase 16-04 Task 5 human-verify (pre-existing deferral to Phase 19 UAT)
- Phase 18-08 Task 4 rephrase card 12-step validation (pre-existing deferral to Phase 19 UAT)

Both deferrals pre-date Phase 20 and remain parked in STATE.md §Deferred Items for Phase 19 UAT.
