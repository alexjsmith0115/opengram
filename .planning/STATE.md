---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Incremental LLM Checking + Paragraph Rephrase Card
status: executing
stopped_at: Completed 18.3-02-PLAN.md
last_updated: "2026-04-17T16:13:38.029Z"
last_activity: 2026-04-17
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 28
  completed_plans: 26
  percent: 93
---

## Current Position

Phase: 18.3 (rephrase-card-panel-sizing-fix-inserted) — EXECUTING
Plan: 3 of 4
Status: Ready to execute
Last activity: 2026-04-17

Progress: [██░░░░░░░░] 20% (Phase 15 + Phase 16 complete out of 5 v1.2 phases)

## Performance Metrics

**Velocity:**

- Total plans completed: 0 (v1.2)
- Average duration: — (v1.1 baseline: see milestones/v1.1-ROADMAP.md)
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

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

Last session: 2026-04-17T16:13:34.034Z
Stopped at: Completed 18.3-02-PLAN.md
Resume file: None
