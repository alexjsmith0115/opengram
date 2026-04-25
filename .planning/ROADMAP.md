# Roadmap: OpenGram

## Milestones

- ✅ **v1.1 LLM Integration Refinement** — Phases 09-14 (shipped 2026-04-15)
- ✅ **v1.2 Incremental LLM Checking + Paragraph Rephrase Card** — Phases 15-18.3 + 20 (shipped 2026-04-19; Phase 19 skipped)
- ✅ **v1.3 Performance & Scroll-Tracking** — Phases 1-6 (shipped 2026-04-19; reset numbering)
- ✅ **v1.4 Clarity Engine** — Phases 7-13 (shipped 2026-04-25)

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

<details>
<summary>✅ v1.2 Incremental LLM Checking + Paragraph Rephrase Card (Phases 15-18.3 + 20) — SHIPPED 2026-04-19</summary>

- [x] Phase 15: Paragraph Infrastructure (4/4 plans) — completed 2026-04-16 · superseded by Phase 20
- [x] Phase 16: LLMCheckScheduler (4/4 plans) — completed 2026-04-16 · superseded by Phase 20
- [x] Phase 17: Advanced Settings Tab (3/3 plans) — completed 2026-04-16
- [x] Phase 18: Paragraph Rephrase Card (8/8 plans) — completed 2026-04-17
- [x] Phase 18.1: Rephrase Card Hotkey Wiring Fix (INSERTED) (2/2 plans) — completed 2026-04-17
- [x] Phase 18.2: Rephrase Card as Default (INSERTED) (3/3 plans) — completed 2026-04-17
- [x] Phase 18.3: Rephrase Card Panel Sizing Fix (INSERTED) (4/4 plans) — completed 2026-04-17
- [~] Phase 19: Integration & UAT — skipped (scope absorbed by 18.1 UAT + 18.3-04 manual validation + v1.3 Phase 05 UAT; moot after Phase 20 rewrite)
- [x] Phase 20: Paragraph-level LLM Suggestions with Cache + Reconciliation (12/12 plans) — completed 2026-04-18 · mid-milestone architectural rewrite

Full details: [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md)

</details>

<details>
<summary>✅ v1.3 Performance & Scroll-Tracking (Phases 1-6) — SHIPPED 2026-04-19</summary>

- [x] Phase 1: AX Call Queue (3/3 plans) — completed 2026-04-19 · PERF-01, PERF-02
- [x] Phase 2: Cancellable Bounds Queries (3/3 plans) — completed 2026-04-19 · PERF-03, PERF-04
- [x] Phase 3: Viewport Cull + Rect Cache (2/2 plans) — completed 2026-04-19 · PERF-05, PERF-06
- [x] Phase 4: Scroll Handling — `trackFrame` + `hideAndSettle` (5/5 plans) — completed 2026-04-19 · PERF-07..11
- [x] Phase 5: Session-Local Mirror Improvements (3/3 plans) — completed 2026-04-19 · PERF-12
- [x] Phase 6: v1.3 Gap Closure — Zero-AX Ordering + Scope Cleanup (2/2 plans) — completed 2026-04-19 · closes GAP-1/2/3

Full details: [milestones/v1.3-ROADMAP.md](milestones/v1.3-ROADMAP.md) · [milestones/v1.3-MILESTONE-AUDIT.md](milestones/v1.3-MILESTONE-AUDIT.md)

</details>

<details>
<summary>✅ v1.4 Clarity Engine (Phases 7-13) — SHIPPED 2026-04-25</summary>

- [x] Phase 7: LLM `.clarity` Clean-Deletion (6/6 plans) — completed 2026-04-20 · CLAR-09, CLAR-10
- [x] Phase 8: Dataset Pipeline (7/7 plans) — completed 2026-04-20 · CLAR-14, CLAR-15, CLAR-16
- [x] Phase 9: Rust Foundation + MapPhraseLinter Spike (8/8 plans) — completed 2026-04-25 · CLAR-11, CLAR-12, CLAR-13
- [x] Phase 10: Matcher Implementation (5/5 plans) — completed 2026-04-25 · CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06
- [x] Phase 11: Dataset Integration + Fixture Harness (5/5 plans) — completed 2026-04-25 · CLAR-20
- [x] Phase 12: Settings UI + Severity Filter + Acknowledgements (4/4 plans) — completed 2026-04-25 · CLAR-02, CLAR-07, CLAR-08, CLAR-17, CLAR-18, CLAR-19
- [x] Phase 13: NonFlags Corpus Seed + UAT (7/7 plans) — completed 2026-04-25 · CLAR-21 (UAT 1+2 PASS; UAT 3 rephrase-card label leak deferred-to-v1.5)
- [x] CLAR-06 production-pipeline gap closure (audit-driven) — `resolve_clarity_overlaps` helper in `harper-bridge/src/lib.rs` + `tests/clar06_overlap_pipeline.rs` (2 cases)

Full details: [milestones/v1.4-ROADMAP.md](milestones/v1.4-ROADMAP.md) · [milestones/v1.4-MILESTONE-AUDIT.md](milestones/v1.4-MILESTONE-AUDIT.md)

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| All v1.1 phases (09-14) | v1.1 | — | Complete | 2026-04-15 |
| All v1.2 phases (15-18.3, 20) | v1.2 | — | Complete | 2026-04-19 |
| All v1.3 phases (1-6) | v1.3 | — | Complete | 2026-04-19 |
| All v1.4 phases (7-13) | v1.4 | 42/42 | Complete | 2026-04-25 |

## Backlog

### Phase 999.1: Rephrase card stale cache — no re-dispatch on second hotkey (BACKLOG)

**Goal:** [Captured for future planning] After the rephrase card has been shown and dismissed for paragraph P, a second Ctrl+Shift+G against the same unchanged paragraph does not re-show the card. Likely root cause: `ParagraphSuggestionCache` hit returns cached suggestions, but `OverlayController.tryDispatchRephraseCard` WR-02 dedup guard (`currentCardParagraphHash`) still matches even after dismiss, OR scheduler's `.dismissed` cache entries short-circuit the re-dispatch. Also check that `hideCardAndRestore()` / `onDismissAll` properly clears `currentCardParagraphHash` and `hiddenParagraphScalarRange`.
**Requirements:** TBD
**Plans:** 4/7 plans executed

Plans:
- [ ] TBD (promote with /gsd-review-backlog when ready)

Surfaced during Phase 18.3 Plan 04 manual validation — 2026-04-17.
