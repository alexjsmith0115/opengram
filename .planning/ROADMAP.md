# Roadmap: OpenGram

## Milestones

- ✅ **v1.1 LLM Integration Refinement** — Phases 09-14 (shipped 2026-04-15)
- 🚧 **v1.2 Incremental LLM Checking + Paragraph Rephrase Card** — Phases 15-19 (in progress; UAT pending)
- 🚧 **v1.3 Performance & Scroll-Tracking** — Phases 1-5 (reset numbering; in progress)

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
- [x] **Phase 18.1: Rephrase Card Hotkey Wiring Fix (INSERTED)** — CheckCoordinator LLM routing fix so card dispatches in hotkey path (completed 2026-04-17)
- [x] **Phase 18.2: Rephrase Card as Default (INSERTED)** — Remove `paragraphRephraseCardEnabled` flag and legacy LLM panel path; card is the unconditional product default (completed 2026-04-17)
- [x] **Phase 18.3: Rephrase Card Panel Sizing Fix (INSERTED)** — Card panel frame clips content; Accept button not visible, Dismiss barely visible. Fix `RephraseCardPanelController` / `RephraseCardView` sizing so full card renders. (completed 2026-04-17)
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
**Plans:** 3/3 plans complete

Plans:
- [x] 18.1-01-PLAN.md — CheckCoordinator LLM routing fix + integration test + flag-off/on regression (WIRE-01, REPH-01..REPH-15)
- [x] 18.1-02-PLAN.md — REQUIREMENTS.md stale checkbox fix (REQ-STALE-01: INCR-02, INCR-04, INCR-09, INCR-13, SET-08, SET-09)

### Phase 18.2: Rephrase Card as Default (INSERTED)

**Goal:** The Paragraph Rephrase card is the unconditional default UX for qualifying LLM style results. The `paragraphRephraseCardEnabled` rollout flag is removed from the codebase entirely — no UserDefaults key, no `IncrementalConfig` property, no gate checks, no flag-off branches, no flag-off regression tests. `CheckCoordinator` always routes LLM `.source == .llm` Suggestions through `OverlayController.update()` for card dispatch; the legacy `LLMPanelController.show()` call path for scheduler LLM style results is deleted. If `LLMPanelController` has no remaining callers after removal, delete it and its tests.
**Requirements**: closes UAT gap "card behind feature flag" from Phase 18.1 verification; simplifies v1.2 shipping surface to a single Part A flag (`llmIncrementalCheckingEnabled`).
**Depends on:** Phase 18.1
**Success Criteria** (what must be TRUE):
  1. `paragraphRephraseCardEnabled` property is removed from `IncrementalConfig` protocol and from `UserDefaultsIncrementalConfig`; the `"llmParagraphRephraseCardEnabled"` UserDefaults key constant is deleted.
  2. `OverlayController.tryDispatchRephraseCard()` no longer gates on the flag; card dispatch runs whenever a qualifying LLM Suggestion set is present.
  3. `CheckCoordinator.handleHotkeyFired()` (and any streaming path) no longer reads the flag and no longer invokes `LLMPanelController.show()` for scheduler `.source == .llm` Suggestions — card is the only surface for paragraph rephrase.
  4. If `LLMPanelController` retains no other callers after step 3, it is deleted along with its tests; otherwise only the LLM-style-suggestion call path is removed.
  5. Flag-off regression tests are deleted: `OverlayControllerFlagOffRegressionTests.swift`, `LLMCheckSchedulerFlagOffTests.swift`, `IncrementalConfigTests.paragraphRephraseCardEnabled_*`, and any `paragraphRephraseCardEnabled: false` variants in remaining integration tests simplified or removed.
  6. No references to `paragraphRephraseCardEnabled` or `llmParagraphRephraseCardEnabled` remain in `OpenGram/**` or `OpenGramTests/**` (grep is empty).
  7. Full `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` green; full test suite green (`xcodebuild test`).
  8. Manual validation: hotkey on a qualifying paragraph in Notes.app shows the unified Rephrase card (single Accept / Dismiss), NOT the 3-section Clarity/Tone/Rephrase legacy panel, with no UserDefaults modification required.
**Plans:** 3/3 plans complete

Plans:
- [x] 18.2-01-PLAN.md — Delete `paragraphRephraseCardEnabled` flag, gates, and flag-off tests; scrub all stub properties (REPH-15, UAT-18.1-G1)
- [x] 18.2-02-PLAN.md — LLMPanelController caller audit + conditional deletion (UAT-18.1-G1)
- [x] 18.2-03-PLAN.md — REQUIREMENTS.md REPH-15 supersession + manual Notes.app validation

### Phase 18.3: Rephrase Card Panel Sizing Fix (INSERTED)

**Goal:** The unified Rephrase card renders with its full content visible — header, revised-text body, rationale, and BOTH Accept and Dismiss controls — on first display against a qualifying paragraph in any target app (Notes.app, TextEdit, Obsidian). No clipping, no missing buttons, no scroll required to reach Accept.
**Requirements**: closes post-18.2 UAT observation "card renders but Accept button not visible, Dismiss barely visible" (Phase 18.1 UAT Test 1 residual_followup). Validates Phase 18 UI-SPEC D-02/D-04/D-05/D-06 card-frame contract against real-world LLM content.
**Depends on:** Phase 18.2
**Success Criteria** (what must be TRUE):
  1. `RephraseCardPanelController` sizes the `NSPanel` frame to fit the `RephraseCardView` intrinsic content (or adds an internal `NSScrollView` so content is reachable). The window is not fixed to an undersized rectangle.
  2. When the LLM returns a typical response (header + 2-4 line revised text + 1-3 line rationale), the rendered card shows: header, full revised text, full rationale, one Accept button, one Dismiss button — all visible within the panel frame on first dispatch.
  3. When the LLM returns a longer response (8+ lines of rationale/revised text), the card either auto-expands or scrolls to keep Accept and Dismiss reachable without user resizing.
  4. Panel positioning does not push the card off-screen at the document edges; if the anchor would clip, the panel shifts to stay within the active screen's visible frame.
  5. xcodebuild build + xcodebuild test both green; no regressions in the 437-test baseline.
  6. Manual validation in Notes.app with the Phase 18.2 test paragraph: Accept button visible, Dismiss button visible, full card content readable without scrolling the underlying document.
**Plans:** 4/4 plans complete
- [x] 18.3-01-PLAN.md — Remove inner SwiftUI ScrollView from RephraseCardView.bodyContent (D-01/D-02/D-03)
- [x] 18.3-02-PLAN.md — Add PanelPositioner.capHeight helper + conditional NSScrollView wrapper in RephraseCardPanelController (D-04/D-05/D-06/D-08/D-09/D-10)
- [x] 18.3-03-PLAN.md — Regression tests for capHeight + short/long/teardown controller paths (D-11/D-12/D-13/D-14/D-15)
- [x] 18.3-04-PLAN.md — Manual validation checkpoint in Notes.app against the Phase 18.2 UAT paragraph

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
| 18.1. Rephrase Card Hotkey Wiring Fix | v1.2 | 2/2 | Complete   | 2026-04-17 |
| 20. Paragraph-level LLM Suggestions | v1.2 | 12/12 | ✅ Complete | 2026-04-18 |
| 19. Integration & UAT | v1.2 | 0/TBD | Not started | - |
| 01. AX Call Queue | v1.3 | 3/3 | Complete | 2026-04-19 |
| 02. Cancellable Bounds Queries | v1.3 | 3/3 | Complete   | 2026-04-19 |
| 03. Viewport Cull + Rect Cache | v1.3 | 0/2 | Not started | - |
| 04. Scroll Handling — trackFrame + hideAndSettle | v1.3 | 5/5 | Complete | 2026-04-19 |
| 05. Session-Local Mirror Improvements | v1.3 | 2/3 | In Progress (gap closure) |  |

## Backlog

### Phase 999.1: Rephrase card stale cache — no re-dispatch on second hotkey (BACKLOG)

**Goal:** [Captured for future planning] After the rephrase card has been shown and dismissed for paragraph P, a second Ctrl+Shift+G against the same unchanged paragraph does not re-show the card. Likely root cause: `ParagraphSuggestionCache` hit returns cached suggestions, but `OverlayController.tryDispatchRephraseCard` WR-02 dedup guard (`currentCardParagraphHash`) still matches even after dismiss, OR scheduler's `.dismissed` cache entries short-circuit the re-dispatch. Also check that `hideCardAndRestore()` / `onDismissAll` properly clears `currentCardParagraphHash` and `hiddenParagraphScalarRange`.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd-review-backlog when ready)

Surfaced during Phase 18.3 Plan 04 manual validation — 2026-04-17.

### Phase 20: Paragraph-level LLM suggestions with cache + reconciliation

**Goal:** Paragraph-level LLM suggestions render as purple dashed underlines alongside Harper red/blue, backed by a `ParagraphSuggestionStore` (actor) with per-paragraph cache, state machine (`pending/ready/readyEmpty/failed/dismissed/accepted`), reconciliation-on-tick, AX-text-change invalidation, FIFO 1-in-flight LLM queue with 30s timeout, and click-to-rephrase-card dispatch. Phase 16 `LLMCheckScheduler`, Phase 15 `ParagraphSuggestionCache`, and `IncrementalConfig` are deleted wholesale (D-01); tunables migrate into a new `OpenGramConfig` struct. No feature flag — direct replacement per CLAUDE.md "no deprecation cycles."
**Requirements**: PLL-01..PLL-18 (see 20-VALIDATION.md — requirement IDs enumerated there)
**Depends on:** Phase 19
**Plans:** 3/3 plans complete

Plans:
- [x] 20-01-PLAN.md — Data-model primitives (ParagraphHash, ParagraphSet, state/entry, StoreEvent) + ParagraphHashTests
- [x] 20-02-PLAN.md — OpenGramConfig (8 live-read tunables, UserDefaults + NotificationCenter)
- [x] 20-03-PLAN.md — Caret-aware ParagraphSplitter + AXCapabilityCache separator persistence (D-05)
- [x] 20-04-PLAN.md — withTimeout primitive + tests
- [x] 20-05-PLAN.md — LLMRequestQueue actor (FIFO, one-in-flight, cancel, 30s timeout) + callback protocol
- [x] 20-06-PLAN.md — ParagraphSuggestionStore actor (reconcile + invalidate + verify-on-response + state machine + event stream)
- [x] 20-07-PLAN.md — UnderlineView.colorForSuggestion + z-order + Suggestion.paragraphHash UInt64 → ParagraphHash?
- [x] 20-08-PLAN.md — TextMonitor store/splitter DI + keystroke-invalidate + focus-change eager-reconcile (D-03)
- [x] 20-09-PLAN.md — OverlayController store subscription + click→rephrase card (D-02) + accept/dismiss store transitions (D-04)
- [x] 20-10a-PLAN.md — DisplayHeuristic/AdvancedSettingsView/OverlayController config param → OpenGramConfig
- [x] 20-10b-PLAN.md — AppDelegate rewire + CheckCoordinator Harper-only + OverlayController scheduler/legacyHash removal + MainActorTextBox
- [x] 20-10c-PLAN.md — Delete LLMCheckScheduler/ParagraphSuggestionCache/IncrementalConfig + legacy tests + manual validation checkpoint (D-01) (completed 2026-04-18; includes post-checkpoint keystroke→debounced-reconcile fix + mocked/live LM Studio integration test suites)

---

## 🚧 v1.3 Performance & Scroll-Tracking (In Progress)

**Milestone Goal:** Bring overlay UX closer to Grammarly-quality scroll-following in native AX-friendly apps (Notes, TextEdit, Mail); degrade gracefully elsewhere. Phase numbering reset for v1.3 — phases 1–5.

**Source:** `.planning/OPENGRAM_PERFORMANCE_SPEC.md`
**Requirements:** PERF-01..12
**Dependency order:** 1 → 2 → 3 → 4 → 5 (each phase unblocks the next; earlier tasks are shippable standalone)

- [x] **Phase 1: AX Call Queue** — FIFO actor queue off main actor; watchdog busy-guard removed (PERF-01, PERF-02) (completed 2026-04-19)
- [x] **Phase 2: Cancellable Bounds Queries** — Task-based reposition; cancel at accept/dismiss/scroll sites (PERF-03, PERF-04) (completed 2026-04-19)
- [x] **Phase 3: Viewport Cull + Rect Cache** — `lastKnownRects` + scroll-time cull; initial/textChanged query all (PERF-05, PERF-06) (completed 2026-04-19)
- [x] **Phase 4: Scroll Handling — `trackFrame` + `hideAndSettle`** — per-app via AppQuirks; CADisplayLink pump; 12ms-budget demotion; scroll-area AX observer (PERF-07, PERF-08, PERF-09, PERF-10, PERF-11) (completed 2026-04-19)
- [x] **Phase 5: Session-Local Mirror Improvements** — preserve cached rects before edit site on accept; `.textChanged` queries only invalidated; UAT Gaps 1+2 closed via sync view.entries rebuild + update() SCREEN-space survivor path (PERF-12) (all 3 plans complete 2026-04-19; Gap 3 rapid-multi-accept carved out to separate phase)

### v1.3 Phase Details

#### Phase 1: AX Call Queue
**Goal:** AX bounds reads are serialized through a FIFO actor queue running off the main actor; concurrent reads no longer drop under burst load; watchdog busy-guard is removed while hang detection and per-app blocklist remain.
**Depends on:** —
**Requirements:** PERF-01, PERF-02
**Success Criteria:**
1. `AXCallQueue` actor exists and all bounds/element reads from `OverlayController` route through it
2. `AXCallWatchdog.shouldSkip` returns `false` for non-blocklisted apps regardless of in-flight call state; hang detection + blocklist expiry still work
3. Existing `OverlayController` tests pass; new `AXCallQueueTests` cover success, cancellation, and failure paths
4. `xcodebuild test` passes with zero warnings

**Plans:** 3 plans

Plans:
- [x] 01-01-PLAN.md — Remove AXCallWatchdog busy-guard branch + swap test coverage (PERF-02) — completed 2026-04-18
- [x] 01-02-PLAN.md — AXCallQueue actor + 4 tests + pbxproj registration (PERF-01) — completed 2026-04-18
- [x] 01-03-PLAN.md — OverlayController init seam for axQueue DI (PERF-01 wiring prep)

#### Phase 2: Cancellable Bounds Queries
**Goal:** Every reposition campaign runs inside a cancellable `Task`; accept/dismiss/scroll action sites cancel any pending reposition before proceeding.
**Depends on:** Phase 1
**Requirements:** PERF-03, PERF-04
**Success Criteria:**
1. A second `scheduleReposition` call cancels the first before any bounds apply (verified via spy on apply count)
2. `acceptSuggestion` and `dismiss()` each cancel `currentRepositionTask` before mutating state
3. Scroll monitor cancels pending reposition on every event (pre-Phase 4 placeholder — Phase 4 replaces with state machine)
4. No task leaks — every `currentRepositionTask` reaches a terminal state before the next is assigned

**Plans:** 3 plans

Plans:
- [x] 02-01-PLAN.md — OverlayController reposition infra: currentRepositionTask + RepositionReason + 5 methods + 3 cancel sites + applyBoundsCallCount spy (PERF-03, PERF-04)
- [x] 02-02-PLAN.md — SlowMockAXAccessor test helper + TestHelpers pbxproj group (PERF-03 infra)
- [x] 02-03-PLAN.md — OverlayControllerRepositionTests (5 tests: cancellation, acceptSuggestion-cancels, dismiss-cancels, scroll-path-cancels, no-task-leaks) + pbxproj registration (PERF-03, PERF-04)

#### Phase 3: Viewport Cull + Rect Cache
**Goal:** Per-suggestion last-known screen rects are cached; scroll repositions skip suggestions whose cached rects do not intersect the padded visible element bounds; initial and textChanged repositions still query all.
**Depends on:** Phase 2
**Requirements:** PERF-05, PERF-06
**Success Criteria:**
1. `lastKnownRects` populated on every successful `applyBounds`; cleared on `dismiss()` and for accepted suggestion's ID
2. `.scrollDuring` / `.scrollSettled` reposition filters via `padded.intersects(rect)` against fresh element bounds
3. `.initial` / `.textChanged` reposition queries all suggestions regardless of cache
4. Viewport-cull unit tests cover: offscreen filter, initial-queries-all, cache cleared on dismiss

**Plans:** 2/2 plans complete

Plans:
- [x] 03-01-PLAN.md — OverlayController lastKnownRects cache + scrollCullPaddingY + freshElementBounds + rebuildUnderlineEntries; replace Phase 2 placeholders; cache seed in show()/update()/applyBounds; clear in dismiss + per-ID in accept (PERF-05, PERF-06)
- [x] 03-02-PLAN.md — OverlayControllerViewportCullTests (5 tests: scrollDuring-cull, initial-queries-all, textChanged-queries-all, dismiss-clears, accept-removes-accepted-ID) + visibility flip + pbxproj registration (PERF-05, PERF-06)

#### Phase 4: Scroll Handling — `trackFrame` + `hideAndSettle`
**Goal:** Per-app scroll mode drives either a CADisplayLink-pumped `trackFrame` reposition (Notes/TextEdit/Mail) or a `hideAndSettle` fade-reposition-fade fallback (all others); 3 consecutive frames >12ms demote the session; scroll-area AX observer catches programmatic scrolls.
**Depends on:** Phase 3
**Requirements:** PERF-07, PERF-08, PERF-09, PERF-10, PERF-11
**Success Criteria:**
1. `ScrollMode` field added to `AppQuirk`; `AppQuirks.plist` allowlists `com.apple.Notes`, `com.apple.TextEdit`, `com.apple.mail` as `trackFrame`; unknown apps default to `hideAndSettle`
2. `hideAndSettle` fades underlines to 0 on first scroll event, repositions on settle (`.scrollSettled`), fades back to 1
3. `trackFrame` `ScrollTracker` pumps `onTick` while `noteScrollEvent()` fires; emits one `onIdle` after `idleTimeout`
4. Three consecutive frames exceeding 12ms demote the current session to `hideAndSettle` until `dismiss()`
5. `ScrollAreaObserver` installed on nearest `kAXScrollAreaRole` ancestor catches `kAXScrolledVisibleChildrenChangedNotification`; fires `handleScrollEvent()`
6. `dismiss()` tears down tracker, timer, observer; resets `frameBudgetMisses` and `scrollState`

**Plans:** 5 plans

Plans:
- [x] 04-01-PLAN.md — AppQuirk ScrollMode enum + plist allowlist + tests (PERF-07) — completed 2026-04-19
- [x] 04-02-PLAN.md — ScrollTracker CADisplayLink pump + tests + pbxproj (PERF-09) — completed 2026-04-19
- [x] 04-03-PLAN.md — ScrollAreaObserver kAXScrolledVisibleChildrenChanged + tests + pbxproj (PERF-11) — completed 2026-04-19
- [x] 04-04-PLAN.md — OverlayController scroll state machine + fade + demotion + observer wire (PERF-07/08/09/10/11) — completed 2026-04-19
- [x] 04-05-PLAN.md — OverlayControllerScrollModeTests + recordFrameCost seam + full-suite gate (PERF-07/08/10) — completed 2026-04-19


#### Phase 5: Session-Local Mirror Improvements
**Goal:** After accept, cached rects are preserved for suggestions strictly before the edit site; overlapping and shifted suggestions are invalidated; `.textChanged` reposition queries only the invalidated subset, producing a zero-AX-call path for edits at document end.
**Depends on:** Phase 4
**Requirements:** PERF-12
**Success Criteria:**
1. `acceptSuggestion` removes `lastKnownRects` entries only for suggestions overlapping or strictly after the edit site
2. `.textChanged` reposition filter queries only `{suggestion | lastKnownRects[id] == nil}`
3. If filtered list is empty, reposition exits early with zero AX calls
4. Unit tests cover: accept-preserves-earlier, accept-invalidates-later, zero-AX-on-end-edit

**Plans:** 3/3 plans complete

Plans:
- [x] 05-01-PLAN.md — OverlayController refactor: D-05 pre-shift invalidation + D-09 .textChanged filter + D-07 empty-filter zero-AX branch + D-08 recomputeOverlayFrame helper + D-01/D-03 BoundsValidator loop deletion + scheduleReposition tail call + AXCallQueue.boundsBatchCallCount spy + Phase 3 test flip (PERF-12)
- [x] 05-02-PLAN.md — OverlayControllerMirrorTests.swift (4 tests: preserve-earlier, invalidate-later, zero-AX-on-end-edit, filter-only-uncached) + pbxproj registration (PERF-12)
- [x] 05-03-PLAN.md — Gap closure for UAT gaps 1-2: sync rebuildUnderlineEntries at tail of repositionAfterAccept + applyBounds ordering flip + update() SCREEN-space survivor rebuild + 2 regression tests (PERF-12) — completed 2026-04-19

### v1.3 Final Verification

Before archiving v1.3:
1. `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` and `xcodebuild test` both pass with zero warnings for both app and test targets
2. Manual validation per CLAUDE.md: build, launch, type text with errors in Notes; scroll while underlines visible — verify trackFrame follow in Notes and fade-settle-fade in a non-allowlisted app (Pages or TextEdit-baseline)
3. Accessibility permission removed + re-added — no first-run regressions
4. `AppQuirks.plist` loads without errors (check `AppQuirksTable` log)
5. Dismiss after various scroll states — verify `currentRepositionTask` reaches terminal state every time (no leaks)
