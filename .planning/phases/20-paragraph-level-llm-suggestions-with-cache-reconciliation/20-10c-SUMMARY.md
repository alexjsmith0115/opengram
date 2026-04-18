# Phase 20 Plan 10c — SUMMARY

**Status**: ✅ Complete (Task 1 + Task 2 both closed; bonus mid-checkpoint work landed)
**Duration**: Task 1 ~20 min (2026-04-17) + Task 2 + follow-ups ~3 h (2026-04-18)
**Commits**: `949194b` (Task 1), `b9bdab4` (integration tests), `edec49c` (debounced reconcile fix)

## Scope Delivered

### Task 1 — Legacy deletion (committed 2026-04-17 in `949194b`)

- Deleted `LLMCheckScheduler.swift`, `ParagraphSuggestionCache.swift`, `IncrementalConfig.swift`
- Deleted 7 associated test files (scheduler cancellation, cache, config)
- Removed pbxproj references
- Stale-comment scrub in `CheckOrchestrator` / `OpenGramConfig` / `LLMRequestQueue`
- 444/444 tests green, PLL-16 + PLL-17 grep gates zero

### Task 2 — Manual validation checkpoint (approved 2026-04-18)

User ran through the 7-item checklist in PRD §Manual Validation against `/Applications/OpenGram.app`. All items pass. Checkpoint closed with explicit `approved`.

### Post-checkpoint follow-ups (same session, landed before advancing orchestrator)

Two issues surfaced during manual validation that were significant enough to fix inline rather than spin out:

1. **Integration tests for OG → LM Studio → OG call chain** (commit `b9bdab4`):
   - `LMStudioPipelineIntegrationTests.swift` — 8 mocked tests (URLProtocol-based) covering happy path, empty `enabledChecks` regression, empty baseURL, request-body shape, HTTP 500, verify-on-response mid-edit, short-paragraph skip, event emission
   - `LMStudioLiveIntegrationTests.swift` — 4 live tests against real LM Studio, gated on `TEST_RUNNER_OPENGRAM_LIVE_LLM` env var (opt-in only; default CI runs skip with explicit reason)
   - Registered in pbxproj (4 entries per file: build file, file ref, group, Sources phase)

2. **Keystroke + hotkey → debounced reconcile** (commit `edec49c`):
   - **Root cause**: after legacy `LLMCheckScheduler` deletion in 10b/10c, the only `store.reconcile` call site was `TextMonitor.driveStoreOnFocusChange`. Keystrokes called `invalidateDisplayed` (visual clearing) but never enqueued LLM requests. PRD §Reconciliation Algorithm line 230 specifies reconcile "on every LLM debounce tick" — that timer was owned by the deleted scheduler and had no replacement.
   - **Fix**: `TextMonitor.scheduleLLMReconcile()` — debounced `DispatchWorkItem`, delay live-read from `OpenGramConfig.llmDebounceMs` (default 2000ms). Fires on every `handleValueChanged`. Rapid keystrokes coalesce — each fresh keystroke cancels the prior work.
   - **Hotkey bypass**: `TextMonitor.reconcileNow()` — public, cancels pending debounce and fires immediately. Wired in `AppDelegate.onHotkeyFired` callback alongside existing `CheckCoordinator.handleHotkeyFired`.
   - **Rename**: `driveStoreOnFocusChange` → `driveStoreReconcile` since it's now shared across focus-change / debounce-tick / hotkey entry points.
   - **Cancellation**: `llmReconcileWork?.cancel()` added to `stop()` and `uninstallCurrentObserver()` to prevent zombie timers.
   - 3 new tests in `TextMonitorStoreIntegrationTests` covering single-fire after debounce, rapid-keystroke coalesce, `reconcileNow` bypass-and-cancel.

## Acceptance Criteria

- ✅ All 7 manual validation items pass against running build (user `approved`)
- ✅ Automated tests: **459/459** (was 444 at Task 1 complete; +8 mocked integration +3 keystroke debounce +4 live opt-in)
- ✅ `xcodebuild` clean (zero errors, one pre-existing warning in OverlayController.swift:371 unrelated to phase scope)
- ✅ PLL-16 + PLL-17 grep gates still zero

## Deviations

- **Plan scope expanded**: plan doc only specified "delete legacy + manual validation". Mid-validation the user discovered zero HTTP traffic despite correct settings, which forensic investigation traced to a PRD gap left by 10b/10c. Fix landed in same session per `auto` mode + user direction, rather than deferring to a new phase. Single-session close is cleaner than a reopen cycle.
- **AX text-change sweep eviction**: PRD §Cache Eviction trigger #2 says invalidate should synchronously evict orphans for the active bundleID. Implementation defers eviction to the next reconcile tick (~2s debounce-bounded). Visible behavior identical because `renderableSuggestions` filters by live set. Accepted deviation — tightening can happen as follow-up if memory becomes a concern.

## Artifacts

- Source changes: `OpenGram/TextMonitor/TextMonitor.swift`, `OpenGram/App/AppDelegate.swift`
- Test changes: `OpenGramTests/TextMonitorTests.swift`, `OpenGramTests/LMStudio{Pipeline,Live}IntegrationTests.swift`
- Project: `OpenGram.xcodeproj/project.pbxproj` (+2 test-file registrations)
- Legacy deletions (from Task 1): `LLMCheckScheduler.swift`, `ParagraphSuggestionCache.swift`, `IncrementalConfig.swift`, 7 test files

## Follow-ups

- Phase 19 UAT can now exercise keystroke-driven LLM path end-to-end
- Consider tightening AX-sweep eviction to match PRD §Cache Eviction trigger #2 verbatim (low priority — memory bounded by debounce)
- Live integration suite provides a real regression catch for future LLM/queue refactors; document the `TEST_RUNNER_OPENGRAM_LIVE_LLM=1` invocation in project README when UAT runbook is written
