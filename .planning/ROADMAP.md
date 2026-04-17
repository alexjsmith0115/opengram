# Roadmap: OpenGram

## Milestones

- ✅ **v1.1 LLM Integration Refinement** — Phases 09-14 (shipped 2026-04-15)
- 🚧 **v1.2 Incremental LLM Checking + Paragraph Rephrase Card** — Phases 15-19 (in progress)

## Phases

<details>
<summary>✅ v1.1 LLM Integration Refinement (Phases 09-14) — SHIPPED 2026-04-15</summary>

- [x] Phase 09: LLM Service Consolidation (2/2 plans) — completed 2026-04-15
- [x] Phase 10: App Whitelist (1/1 plan) — completed 2026-04-15
- [x] Phase 11: LLM Suggestion Panel (1/1 plan) — completed 2026-04-15
- [x] Phase 12: Integration & Testing (2/2 plans) — completed 2026-04-15
- [x] Phase 13: Tech Debt Cleanup (1/1 plan) — completed 2026-04-15
- [x] Phase 14: UAT — Manual Validation (1/1 plan) — completed 2026-04-15

Full details: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)

</details>

### 🚧 v1.2 Incremental LLM Checking + Paragraph Rephrase Card (In Progress)

**Milestone Goal:** Cut wasted LLM tokens/latency via per-paragraph change detection and caching. Surface a Grammarly-style unified paragraph rephrase card for qualifying paragraphs. Two staged feature flags: `llmIncrementalCheckingEnabled` (Part A) and `paragraphRephraseCardEnabled` (Part B).

- [x] **Phase 15: Paragraph Infrastructure** — Splitter, hasher, and cache as standalone, unit-testable components (no AppDelegate surface) (completed 2026-04-16)
- [x] **Phase 16: LLMCheckScheduler** — Scheduler + per-paragraph cancellation + AppDelegate DI wiring + flag-off fallback (completed 2026-04-16; Task 5 human-verify deferred to Phase 19 UAT)
- [x] **Phase 17: Advanced Settings Tab** — Tunables exposed before feature flags go user-visible (completed 2026-04-16)
- [x] **Phase 18: Paragraph Rephrase Card** — Full Part B UI: card rendering, diff views, accept/dismiss/hide semantics, highlight (completed 2026-04-17)
- [ ] **Phase 19: Integration & UAT** — End-to-end validation, visual regression, manual dogfooding

## Phase Details

### Phase 15: Paragraph Infrastructure
**Goal**: Paragraph splitter, stable hasher, and LRU+TTL cache exist as independent, fully unit-tested components ready for the scheduler to compose.
**Depends on**: Phase 14
**Requirements**: INCR-01, INCR-02, INCR-06, INCR-07, INCR-10, INCR-12
**Success Criteria** (what must be TRUE):
  1. Splitting a 500-paragraph document on double-newline boundaries completes in <10ms
  2. Two paragraphs differing only in whitespace produce identical hashes; differing in punctuation or case produce different hashes
  3. Cache lookup for a `(bundleID, paragraphHash)` key completes in <1ms and returns the correct suggestion status (`pending`/`active`/`dismissed`)
  4. LRU eviction triggers on insert and keeps each bundleID under 500 entries; entries unreferenced for 30 minutes are expired
  5. Dismissed cache entries do not resurface when queried again with the same key
**Plans**: 4 plans
- [x] 15-01-PLAN.md — Paragraph struct + CacheClock protocol + ParagraphInfra group bootstrap
- [x] 15-02-PLAN.md — ParagraphSplitting protocol + DoubleNewlineSplitter + tests (INCR-01)
- [x] 15-03-PLAN.md — ParagraphHashing protocol + Sha256ParagraphHasher + tests (INCR-02)
- [x] 15-04-PLAN.md — ParagraphSuggestionCache actor (LRU+TTL) + tests (INCR-06/07/10/12)

### Phase 16: LLMCheckScheduler
**Goal**: `LLMCheckScheduler` is the single coherent component owning all of Phase 15's pieces plus scheduling, per-paragraph cancellation, and neighbor-context assembly. Injected into AppDelegate via DI; existing LLM call site unchanged in shape.
**Depends on**: Phase 15
**Requirements**: INCR-03, INCR-04, INCR-05, INCR-08, INCR-09, INCR-11, INCR-13, INCR-14
**Success Criteria** (what must be TRUE):
  1. Triggering the hotkey twice on an unchanged field fires zero additional LLM requests on the second trigger
  2. Editing paragraph N while paragraph M's LLM request is in flight cancels only N's request; M's request completes normally
  3. Each LLM request includes one preceding and one following paragraph as context-only; prompt instructs model to return suggestions for target only
  4. With `llmIncrementalCheckingEnabled` off, behavior is byte-identical to pre-v1.2 full-text LLM path
  5. Scheduler does not block the main thread; all LLM requests are async
**Plans**: 4 plans
- [x] 16-01-PLAN.md — LLM API extension: analyze(target:previousContext:nextContext:) + structured prompt builder + tests
- [x] 16-02-PLAN.md — LLMCheckScheduler actor core flow (split/hash/cache/neighbor-context/offset-rebase) + tests (INCR-04/05/09/11/12/13)
- [x] 16-03-PLAN.md — Per-paragraph cancellation + idle-debounce + checkOnFocusLoss + tests (INCR-03/08)
- [x] 16-04-PLAN.md — Flag-off branch + AppDelegate/CheckCoordinator DI wiring + flag-off regression tests + integration test (INCR-11/14) (completed 2026-04-16; Task 5 human-verify deferred to Phase 19 UAT)
**UI hint**: no

### Phase 17: Advanced Settings Tab
**Goal**: New "Advanced" tab in Settings window exposes `minIssueCount`, `minWordCount`, and `idleDebounceSeconds` with a reset action and instability warning — all readable live by the scheduler and display heuristic.
**Depends on**: Phase 16
**Requirements**: SET-07, SET-08, SET-09, SET-10
**Success Criteria** (what must be TRUE):
  1. Advanced tab is visible in Settings with tunables and their current values
  2. Changing `idleDebounceSeconds` takes effect on the next scheduler evaluation without app restart
  3. Changing `minIssueCount` or `minWordCount` takes effect on the next rephrase card qualification check without app restart
  4. "Reset to defaults" restores all three values to 2, 12, and 1.5 respectively
  5. Warning note at tab top is visible stating settings are unstable
**Plans**: 3 plans
- [x] 17-01-PLAN.md — Extend IncrementalConfig protocol + UserDefaultsIncrementalConfig with 3 tunables + static defaults + tests (SET-07, SET-10)
- [x] 17-02-PLAN.md — Scheduler live-read refactor: remove idleDebounceSeconds init param, read incrementalConfig.idleDebounceSeconds per onKeystroke; update AppDelegate + existing scheduler tests (SET-10)
- [x] 17-03-PLAN.md — AdvancedSettingsView SwiftUI view + wire into SettingsView TabView + tests + pbxproj registration (SET-07, SET-08, SET-09)
**UI hint**: yes

### Phase 18: Paragraph Rephrase Card
**Goal**: Qualifying paragraphs surface a single unified rephrase card (additions-only diff by default, full-diff toggle, dynamic header, Accept/Dismiss/hide semantics, source-paragraph highlight). Non-qualifying paragraphs continue using existing per-issue popovers unchanged.
**Depends on**: Phase 16, Phase 17
**Requirements**: REPH-01, REPH-02, REPH-03, REPH-04, REPH-05, REPH-06, REPH-07, REPH-08, REPH-09, REPH-10, REPH-11, REPH-12, REPH-13, REPH-14, REPH-15
**Success Criteria** (what must be TRUE):
  1. A paragraph with ≥2 LLM issues shows a rephrase card (not per-issue popovers); its per-issue underlines are hidden while the card is visible
  2. Card header reads "Improve clarity", "Fix grammar", or "Improve clarity and fix grammar" based on issue mix; spelling issues are silent
  3. "What changed?" toggle switches from additions-only (mint-green highlights, no strikethrough) to full diff (strikethrough removed + bold added) without reissuing LLM request
  4. Clicking outside hides the card without changing cache state; next trigger re-shows it for the same unchanged paragraph
  5. Dismiss marks the paragraph dismissed; card does not reappear for that paragraph while text is unchanged
  6. Accept applies rephrase to source text; no underlines appear on the next check cycle for that paragraph
  7. With `paragraphRephraseCardEnabled` off, all LLM suggestions use existing per-issue popover UI
**Plans**: 8 plans
- [x] 18-01-PLAN.md — Extract AXTextReplacer + swap OverlayController accept call-site (D-15)
- [x] 18-02-PLAN.md — TextDiff + DisplayHeuristic + RephraseComposer + RephraseCardViewModel (D-01/D-11/D-18/D-21/D-22)
- [x] 18-03-PLAN.md — IncrementalConfig.paragraphRephraseCardEnabled + Suggestion.paragraphHash + scheduler.markDismissed wrapper (D-14/D-17/D-23)
- [x] 18-04-PLAN.md — TextMonitor.onKeystroke callback for FR-18 edit-closes (D-09)
- [x] 18-05-PLAN.md — RephraseCardView + RephraseCardPanelController (D-02/D-04/D-05/D-06/D-08)
- [x] 18-06-PLAN.md — SourceParagraphHighlight NSView + OverlayController.hideUnderlines/showUnderlines (D-10/D-13)
- [x] 18-07-PLAN.md — OverlayController card dispatch + multi-qualifier selection + AppDelegate DI wiring (D-12)
- [x] 18-08-PLAN.md — Lifecycle integration tests + flag-off regression + REPH-11 prompt assertion + manual UAT checkpoint
**UI hint**: yes

### Phase 18.1: Rephrase Card Hotkey Wiring Fix (INSERTED)

**Goal:** Rephrase card fires end-to-end in the hotkey path. `CheckCoordinator.handleHotkeyFired()` merges scheduler LLM Suggestions (`.source == .llm`, `paragraphHash` set) into `overlayController.update()` so `tryDispatchRephraseCard()` actually receives qualifying LLM issues. `LLMPanelController` invocation is gated on `!paragraphRephraseCardEnabled` so the legacy per-issue panel never double-fires alongside the card. An integration test proves the full hotkey → scheduler → coordinator → overlay → card wire.
**Requirements**: WIRE-01 (v1.2 milestone audit gap), closes E2E coverage for REPH-01..REPH-10, REPH-12, REPH-13, REPH-15
**Depends on:** Phase 18
**Success Criteria** (what must be TRUE):
  1. `CheckCoordinator.handleHotkeyFired()` routes scheduler LLM Suggestions to `overlayController.update()` (merged with Harper suggestions) — not exclusively to `LLMPanelController`.
  2. `LLMPanelController` is invoked only when `paragraphRephraseCardEnabled == false` — no double-panel when card flag is on.
  3. Integration test: mock scheduler returns qualifying LLM suggestions → hotkey fires → `tryDispatchRephraseCard` fires → `RephraseCardPanelController.show()` called with correct ViewModel.
  4. Flag-off regression test updated to assert `LLMPanelController` path when flag=false, and NOT invoked when flag=true.
  5. Full `xcodebuild test` green; no regression in Phase 15-18 suites.
  6. `REQUIREMENTS.md` traceability updated: INCR-02, INCR-04, INCR-09, INCR-13, SET-08, SET-09 flipped from `[ ]` to `[x]`.
**Plans:** 2 plans

Plans:
- [ ] 18.1-01-PLAN.md — CheckCoordinator LLM routing fix + integration test + flag-off/on regression (WIRE-01, REPH-01..REPH-15)
- [ ] 18.1-02-PLAN.md — REQUIREMENTS.md stale checkbox fix (REQ-STALE-01: INCR-02, INCR-04, INCR-09, INCR-13, SET-08, SET-09)

### Phase 19: Integration & UAT
**Goal**: All v1.2 requirements verified end-to-end: automated integration tests pass, visual regression baseline captured, manual dogfooding confirms card UX and scheduler behavior in real apps.
**Depends on**: Phase 18
**Requirements**: (validation — all v1.2 reqs verified, no new requirements)
**Success Criteria** (what must be TRUE):
  1. All automated tests pass (unit + integration for scheduler, cache, splitter, heuristic, card)
  2. Scroll-and-return to unchanged field produces zero LLM requests (verified by integration test)
  3. Rephrase card renders correctly in at least one native Cocoa app (Notes) and one target app (Obsidian)
  4. `llmIncrementalCheckingEnabled=off` path is behaviorally identical to v1.1 (regression test passes)
  5. No visual regressions in existing per-issue popover UI for non-qualifying paragraphs
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 09. LLM Service Consolidation | v1.1 | 2/2 | Complete | 2026-04-15 |
| 10. App Whitelist | v1.1 | 1/1 | Complete | 2026-04-15 |
| 11. LLM Suggestion Panel | v1.1 | 1/1 | Complete | 2026-04-15 |
| 12. Integration & Testing | v1.1 | 2/2 | Complete | 2026-04-15 |
| 13. Tech Debt Cleanup | v1.1 | 1/1 | Complete | 2026-04-15 |
| 14. UAT — Manual Validation | v1.1 | 1/1 | Complete | 2026-04-15 |
| 15. Paragraph Infrastructure | v1.2 | 4/4 | Complete   | 2026-04-16 |
| 16. LLMCheckScheduler | v1.2 | 4/4 | Complete   | 2026-04-16 |
| 17. Advanced Settings Tab | v1.2 | 3/3 | Complete   | 2026-04-16 |
| 18. Paragraph Rephrase Card | v1.2 | 8/8 | Complete   | 2026-04-17 |
| 18.1. Rephrase Card Hotkey Wiring Fix | v1.2 | 0/2 | In progress | - |
| 19. Integration & UAT | v1.2 | 0/TBD | Not started | - |
