---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Incremental LLM Checking + Paragraph Rephrase Card
status: executing
stopped_at: Completed 20-06-PLAN.md
last_updated: "2026-04-17T22:35:00.000Z"
last_activity: 2026-04-17 -- Phase 20 Plan 06 complete
progress:
  total_phases: 10
  completed_phases: 7
  total_plans: 40
  completed_plans: 35
  percent: 87
---

## Current Position

Phase: 20
Plan: 06 complete
Status: Executing
Last activity: 2026-04-17 -- Phase 20 Plan 06 complete

Progress: [██░░░░░░░░] 20% (Phase 15 + Phase 16 complete out of 5 v1.2 phases)

## Performance Metrics

**Velocity:**

- Total plans completed: 4 (v1.2)
- Average duration: — (v1.1 baseline: see milestones/v1.1-ROADMAP.md)
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 18.3 | 4 | - | - |

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

## Session Continuity

Last session: 2026-04-18T02:40:56.807Z
Stopped at: Completed 20-03-PLAN.md
Resume file: None
