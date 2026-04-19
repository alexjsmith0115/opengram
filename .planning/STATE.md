---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Incremental LLM Checking + Paragraph Rephrase Card
status: verifying
stopped_at: Completed 03-02-PLAN.md
last_updated: "2026-04-19T12:36:53.023Z"
last_activity: 2026-04-19
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 67
---

## Current Position

Phase: 3 (Viewport Cull + Rect Cache) — EXECUTING
Plan: 2 of 2
Status: Phase complete — ready for verification
Last activity: 2026-04-19

**v1.2 parallel status:** Phase 19 UAT pending. v1.2 ships via `/gsd-complete-milestone v1.2` after UAT closes. See `.planning/milestones/v1.2-phases/` for archived phase dirs.

Progress: [██████░░░░] 67%

## Performance Metrics

**Velocity:**

- Total plans completed: 4 (v1.2)
- Average duration: — (v1.1 baseline: see milestones/v1.1-ROADMAP.md)
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 18.3 | 4 | - | - |
| Phase 01-ax-call-queue P03 | 5min | 1 tasks | 1 files |
| Phase 02-cancellable-bounds-queries P01 | 15min | 2 tasks | 1 files |
| Phase 02-cancellable-bounds-queries P03 | 3min | 3 tasks | 2 files |
| Phase 03-viewport-cull-rect-cache P1 | 420 | 2 tasks | 1 files |
| Phase 03 P2 | 480 | 4 tasks | 3 files |

## Accumulated Context

| Phase 15 P01 | 2m | 3 tasks | 4 files |
| Phase 15-paragraph-infrastructure P02 | 5 min | 3 tasks | 3 files |
| Phase 15 P04 | 5m | 3 tasks | 3 files |
| Phase 16-llmcheckscheduler P01 | 15min | 3 tasks | 7 files |
| Phase 16 P03 | 15min | 4 tasks | 3 files |
| Phase 16 P04 | 10min | 4 tasks (Task 5 deferred to Phase 19 UAT) | 6 files |
| Phase 17 P01 | 8min | 2 tasks | 3 files |
| Phase 17-advanced-settings-tab P17-02 | 14m | 3 tasks | 5 files |
| Phase 18.2-rephrase-card-as-default-inserted P02 | 5 min | 1 tasks | 0 files |
| Phase 18.2 P03 | 4 min | 2 tasks | 1 files |
| Phase 18.3 P01 | 15min | 1 tasks | 2 files |
| Phase 18.3 P02 | 8min | 2 tasks | 2 files |
| Phase 18.3 P03 | 10min | 2 tasks | 3 files |
| Phase 20 P09 | 25min | 1 task | 2 files |
| Phase 20 P10a | 10min | 1 task | 9 files |
| Phase 20 P10b | 15min | 1 task | 8 files |
| Phase 01 P01 | 4min | 2 tasks | 2 files |
| Phase 01 P02 | 15min | 3 tasks | 3 files |

### Decisions

- [v1.1 Phase 12]: UserDefaults DI instead of @AppStorage for testability
- [v1.1 Phase 11]: NSHostingView.fittingSize for panel sizing (intrinsicContentSize unreliable before layout)
- [v1.2 Roadmap]: Phase 15 builds splitter/hasher/cache as standalone infra; Phase 16 adds scheduler + wiring. NFR-1 coherence is about state ownership in scheduler, not forcing all code into one phase.
- [v1.2 Roadmap]: Phase 19 (UAT) carries no new requirements — it validates all 33 v1.2 reqs end-to-end.
- [Phase 15]: [Phase 15-01] Paragraph + CacheClock contracts locked; ParagraphInfra pbxproj group established for Plans 02/03/04
- [Phase 15]: Cache uses [String: [UInt64: CacheEntry]] internal shape (D-13); Self-in-default-arg bug forced explicit ParagraphSuggestionCache.defaultTTL form
- [Phase 16-llmcheckscheduler]: LLM protocol gains required analyze(target:previousContext:nextContext:) method with per-call cancellation; legacy analyze(paragraph:) preserved byte-identical for flag-off path
- [Phase 16]: Per-invocation ownTasks snapshot + Task-identity check prevents concurrent check() calls from stomping each other's in-flight entries when clearing the map
- [Phase 16-04]: Feature flag read live on every check() entry (no cached snapshot) — a `defaults write com.opengram llmIncrementalCheckingEnabled` flip takes effect on the next scheduler call without app relaunch (D-14, negative-grep enforced)
- [Phase 16-04]: Scheduler returns [Suggestion]; CheckCoordinator maps source==.llm back to [LLMStyleSuggestion] at the scheduler boundary to preserve existing showLLMPanel contract (rephrase card consumption is Phase 18)
- [Phase 16-04]: Task 5 (human-verify flag-on/flag-off live behavior) deferred to Phase 19 UAT per user choice; all automated evidence green (362/362 tests)
- [Phase 17]: Use defaults.object(forKey:) as? T pattern over defaults.integer/double to distinguish unset from user-set zero
- [Phase 17-advanced-settings-tab]: Scheduler reads incrementalConfig.idleDebounceSeconds per onKeystroke call (SET-10 / D-03 / D-15); Phase 16 static init param removed
- [Phase 18.2-rephrase-card-as-default-inserted]: LLMPanelController retained post-Plan-01 — 6 live callers (streaming handleLLMBatch path + 2 defensive dismiss calls) — Audit grep found non-card call paths in applyLLMSuggestion, handleHotkeyFired top-of-fn defensive dismiss, and handleLLMBatch->showLLMPanel streaming LLM path; only the hotkey-path panel invocation was gated on the deleted cardEnabled flag
- [Phase 18.2]: REPH-15 retired via Supersession in REQUIREMENTS.md (body line 109 + traceability row 252); matches UI-03/UI-08/UI-09 precedent, preserves audit trail for the deleted paragraphRephraseCardEnabled rollout flag.
- [Phase 18.2]: Phase 18.1 UAT Test 1 gap (UAT-18.1-G1) closed: user-confirmed Notes.app smoke test — unified Rephrase card fires by default on qualifying paragraphs with zero UserDefaults mutation. Legacy 3-section LLMPanelController UI did not appear.
- [Phase 18.3]: Inner ScrollView removed from RephraseCardView.bodyContent; outer .frame(minHeight:idealHeight:) preserved per D-02; height cap deferred to controller layer (Plan 02)
- [Phase 18.3]: capHeight placed before clampedY in PanelPositioner (option a opt-in); verticalSafeMargin=40pt private static; flooredSize computed before capped; testHookPanel lives in Plan 02 to keep Plan 03 test-only
- [Phase 18.3]: testHookFittingSize seam: headless NSHostingView always returns idealHeight; inject oversized NSSize to force overflow branch in unit tests
- [Phase 18.3]: Production fix: attach hosting to panel before layoutSubtreeIfNeeded — detached measurement was latent bug (matched LLMPanelController pattern)
- [Phase 20-01]: ParagraphHash uses full 64-char SHA-256 hex (not compressed UInt64 prefix); bundleID partitions collision domain per-app
- [Phase 20-01]: @unchecked Sendable on ParagraphSuggestionState + ParagraphCacheEntry — Error is not Sendable; safe because actor-owned, never mutated post-insert
- [Phase 20-01]: ParagraphSet.Entry is a named struct (not tuple) — Swift tuples lack Sendable conformance across actor hops
- [Phase 20-02]: postDidChange takes injectable NotificationCenter param (default .default) — posting to .default in tests caused cross-suite interference; injectable param is cleaner than wrapper
- [Phase 20-02]: Notification test uses isolated NotificationCenter() instance — not .default — to prevent cross-test pollution in parallel Swift Testing runner
- [Phase 20-03]: Files renamed Phase20Paragraph* to avoid Xcode object-file collision with Phase 15 ParagraphSplitter.swift (same base name, both in same target)
- [Phase 20-03]: Legacy flat-dict JSON detection via JSONSerialization key probe — CacheData custom init(from:) always succeeds via try? fallback, explicit hasCapabilitiesKey guard routes to legacy branch correctly
- [Phase 20-03]: Separator probe stores non-empty values only; empty-string separator skipped in resolveSeparator to allow re-probe when text gains separators
- [Phase 20-04]: withThrowingTaskGroup race: operation + sleep tasks race; first winner returned; defer cancelAll cleans loser; guard let winner guards impossible-nil fallback
- [Phase 20-05]: inFlightCancelled flag suppresses store callback on cancel without racily clearing inFlight; callback protocol LLMRequestQueueStore breaks Plan 05↔06 init-time circular dep; queue delivers raw [LLMStyleSuggestion], Plan 06 maps to Suggestion
- [Phase 20-06]: textProvider closure (NSLock-backed MainActorTextBox) for verify-on-response — store re-reads live text synchronously without MainActor hop
- [Phase 20-06]: Suggestion.range is placeholder in cache (originalText bounds); Plan 09 re-resolves against live AX text at render time (Pitfall #3)
- [Phase 20-06]: sha256Prefix8UInt64 shim on ParagraphHash — temporary compat with Suggestion.paragraphHash: UInt64?; Plan 07 deletes shim + flips field to ParagraphHash? atomically
- [Phase 20-06]: waitForKind polls store actor state directly — waiting on llm.calls.count has two-async-hop race (queue→store actor before cache write)
- [Phase 20-07]: Suggestion.paragraphHash flipped UInt64? → ParagraphHash? atomically with color+z-order change; sha256Prefix8UInt64 shim deleted; LLMCheckScheduler.rebase updated to ParagraphHash in same commit
- [Phase 20-07]: CardQualifier.legacyHash: UInt64 — transitional field bridges to legacy scheduler.markDismissed(UInt64); Plan 10b deletes it when scheduler is removed
- [Phase 20-07]: os.log ParagraphHash interpolation uses hash.sha256 — ParagraphHash lacks CustomStringConvertible; logging via .sha256 property preserves diagnostic value
- [Phase 20-08]: store/splitter/textBoxWriter params default nil — all existing 5-arg TextMonitor call sites compile unchanged; Plan 10 supplies real values
- [Phase 20-08]: textBoxWriter tied to store guard — absent store means no write; simpler single-wire semantics, no independent textBoxWriter fire
- [Phase 20-08]: StubLLM uses NSLock not OSAllocatedUnfairLock — os module not imported in test target; NSLock already present via Foundation
- [Phase 20-09]: Production OverlayController store DI + event handler + click routing already landed in 20-07 (c460237) + scrub pass (aea982f) + WR-02 dedup (8fa2326); Plan 09 execution reduced to adding the missing OverlayControllerStoreSubscriptionTests.swift + pbxproj registration
- [Phase 20-09]: Test fixture polls controller.suggestions (20ms interval up to 2s) instead of fixed sleep — pipeline has 4 async hops (queue task → finishInFlight → handleQueueResponse → event yield → MainActor event loop); fixed sleep is CI-flaky
- [Phase 20-09]: Legacy scheduler test LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit is timing-flaky under parallel load but passes in isolation; flake pre-dates Plan 09 and lives in code slated for deletion in Plan 10b — no fix here
- [Phase 20-10a]: AdvancedSettingsView.resetDefaults(in:center:) takes injectable NotificationCenter (default .default); tests use isolated NotificationCenter() to avoid cross-suite pollution — mirrors Plan 20-02 pattern
- [Phase 20-10a]: Tests migrated from IncrementalConfig fake-protocol stubs to UserDefaults-suite backed OpenGramConfig(defaults:) — eliminates parallel fake-impl surface; scheduler construction sites still pass `incrementalConfig:` (Plan 10b handles)
- [Phase 20-10a]: Plan scope expanded to 9 files (plan named 5) — 4 OverlayController call sites needed `incrementalConfig:` → `config:` rename (AppDelegate + 3 test files); Rule 3 blocking fix, scheduler sites left intact
- [Phase 20-10b]: MainActorTextBox as dedicated file in OpenGram/App/ — matches one-type-per-file convention; NSLock-backed, @unchecked Sendable; store reads via textProvider closure, TextMonitor writes via textBoxWriter hook
- [Phase 20-10b]: AppDelegate `Task { await queue.setStore(store) }` is fire-and-forget — acceptable because TextMonitor.start() runs after sync init returns, worst-case one dropped first response (T-20.10b-01 mitigated)
- [Phase 20-10b]: `hasher` param on OverlayController deleted alongside `legacyHash` — became unused after scheduler removal; zero external callers (conditional step 10 of plan confirmed deletable)
- [Phase 20-10b]: CheckCoordinator LLM fan-out branch (~45 lines) removed from handleHotkeyFired; hotkey path is Harper-only, paragraph-LLM runs event-driven via store→overlay subscription (D-04)
- [Phase 20-10b]: RephraseCardLifecycleTests + 4 LLMCheckScheduler* tests NOT modified — they exercise legacy scheduler which still compiles in isolation; wholesale deletion belongs to Plan 10c
- [Phase 20-10c]: Deletion scope expanded beyond plan list — CheckCoordinatorSchedulerIntegrationTests.swift (100% scheduler, 154 lines) and RephraseCardLifecycleTests.swift (all 3 tests coupled to deleted ParagraphCacheKey/ParagraphSuggestionCache/LLMCheckScheduler) deleted wholesale. Rule 3 blocking — both would fail compile after scheduler/cache removal. Plan's pragmatic option chosen: delete rather than rewrite against store.
- [Phase 20-10c]: Stale comment scrub in CheckOrchestrator/OpenGramConfig/LLMRequestQueue — inline refs to deleted LLMCheckScheduler/UserDefaultsIncrementalConfig rewritten to describe current architecture (paragraph-LLM via event-driven store, D-04).
- [Phase 20-10c post-checkpoint]: Manual validation surfaced that keystrokes never fired LLM — legacy scheduler owned the debounce→reconcile timer; its removal in 10b/10c left only focus-change as a reconcile trigger. Fix wires TextMonitor.scheduleLLMReconcile (debounced DispatchWorkItem, live-read config.llmDebounceMs) on handleValueChanged + TextMonitor.reconcileNow (bypass-debounce) on hotkey path. Renamed driveStoreOnFocusChange → driveStoreReconcile (shared by focus/debounce/hotkey). Commit edec49c.
- [Phase 20-10c post-checkpoint]: Integration tests added for OG→LM Studio call chain. Mocked suite (URLProtocol, 8 tests) runs by default; live suite (4 tests) gated on TEST_RUNNER_OPENGRAM_LIVE_LLM=1 so default xcodebuild test skips with explicit reason. Commit b9bdab4.
- [Phase 01-01]: Busy-guard branch deleted from AXCallWatchdog.shouldSkip; blocklist-only gating; activeCall/beginCall/endCall/checkForHang preserved — hang detection intact. shouldSkipReturnsFalseDuringInFlightCall test locks new contract.
- [Phase 01-02]: AXCallQueue actor: FIFO AX serialization via actor isolation; boundsBatch cancels via CancellationError; elementBounds wraps each raw AX read in watchdog beginCall/endCall (D-06); constructor DI with .shared defaults (D-04). PERF-01 complete.
- [Phase ?]: [Phase 01-03]: axQueue field stored but unused this phase (D-09) — Phase 2 introduces first invocation via currentRepositionTask
- [Phase 02-cancellable-bounds-queries]: currentRepositionTask + scheduleReposition use internal visibility for @testable test access
- [Phase 02-cancellable-bounds-queries]: show() synchronous bounds loop untouched per D-12; async reposition has no production caller this plan
- [Phase ?]: Used applyBoundsCallCount spy (Option C) for cancellation verification — deterministic, no wall-clock race
- [Phase ?]: scrollPathCancels tests literal closure body rather than synthesizing NSEvent — global monitors only fire for other-process events
- [Phase ?]: lastKnownRects internal visibility — @testable tests assert cache state directly
- [Phase ?]: freshElementBounds skips axQueue — sync MainActor read cheap for single element per scroll tick
- [Phase ?]: scroll cull nil-entry pessimistic include — uncached suggestions always queried on first scroll
- [Phase 03]: suggestionsForReposition flipped to internal — @testable access for cull unit tests
- [Phase 03]: Test 5 non-overlapping offsets required — identical offsets cause repositionAfterAccept overlap detection to zero scalarLength and call dismiss()

### Roadmap Evolution

- Phase 20 added: Paragraph-level LLM suggestions with cache + reconciliation (PRD: phases/20-.../CONTEXT.md)

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Human verification | Phase 16-04 Task 5: flag-on/flag-off live behavior in Notes/TextEdit; `defaults write llmIncrementalCheckingEnabled` flip without relaunch; hotkey re-fire on unchanged text shows `LLM fan-out: 0 requests`; edit middle paragraph fires 1 request | Deferred to Phase 19 UAT | 2026-04-16 |
| Human verification | Phase 18-08 Task 4: 12-step rephrase card validation in Notes.app with computer-use MCP screenshots (flag enable, card render, toggle, hide/dismiss/accept paths, edit-closes, flag-off parity) | Deferred to Phase 19 UAT | 2026-04-16 |
| Test flake | `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit` — timing-flaky under parallel load, passes in isolation | Deferred to Plan 10b (scheduler deletion) | 2026-04-17 |

## Session Continuity

Last session: 2026-04-19T12:36:53.018Z
Stopped at: Completed 03-02-PLAN.md
Resume file: None
