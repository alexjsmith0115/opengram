---
gsd_state_version: 1.0
milestone: v1.4
milestone_name: Clarity Engine
status: executing
stopped_at: Phase 11 Plan 05 complete — Phase 11 all 5 plans done
last_updated: "2026-04-25T15:13:41.403Z"
last_activity: 2026-04-25
progress:
  total_phases: 7
  completed_phases: 6
  total_plans: 42
  completed_plans: 36
  percent: 86
---

## Current Position

Milestone: v1.4 Clarity Engine
Phase: 13 (NonFlags Corpus Seed + UAT) — EXECUTING
Plan: 2 of 7
Next: /gsd-execute-phase 13 → milestone audit/complete/cleanup
Status: Ready to execute
Last activity: 2026-04-25

**v1.3 status:** ✅ Shipped 2026-04-19. See `.planning/milestones/v1.3-ROADMAP.md` + `.planning/milestones/v1.3-MILESTONE-AUDIT.md`. Tag `v1.3` on `12dd9db`.

Progress: 0% (0/7 phases complete, 0/0 plans — plans defined per phase at `/gsd-plan-phase`)

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-19 — v1.4 Clarity Engine started)

**Core value:** Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions — entirely local by default.
**Current focus:** Phase 13 — NonFlags Corpus Seed + UAT

## v1.4 Phase Map

| Phase | Name | Requirements |
|-------|------|--------------|
| 7 | LLM `.clarity` Clean-Deletion | CLAR-09, CLAR-10 |
| 8 | Dataset Pipeline | CLAR-14, CLAR-15, CLAR-16 |
| 9 | Rust Foundation + MapPhraseLinter Spike | CLAR-11, CLAR-12, CLAR-13 |
| 10 | Matcher Implementation | CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06 |
| 11 | Dataset Integration + Fixture Harness | CLAR-20 |
| 12 | Settings UI + Severity Filter + Acknowledgements | CLAR-02, CLAR-07, CLAR-08, CLAR-17, CLAR-18, CLAR-19 |
| 13 | NonFlags Corpus Seed + UAT | CLAR-21 |

Parallelization note: Phases 8 and 9 can run in parallel (no file contention). Phase 7 must complete before Phase 9 (clean `Suggestion.swift` edits).

## Performance Metrics

**Velocity:**

- Total plans completed: 15 (v1.2)
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
| Phase 05-session-local-mirror-improvements P01 | 5min | 3 tasks | 3 files |
| Phase 05-session-local-mirror-improvements P02 | 10min | 2 tasks | 3 files |
| Phase 05-session-local-mirror-improvements P03 | 15min | 3 tasks | 2 files |
| Phase 06-gap-closure-zero-ax-ordering-scope-cleanup P01 | 4min | 2 tasks | 2 files |
| Phase 06-gap-closure-zero-ax-ordering-scope-cleanup P02 | 3min | 2 tasks | 4 files |
| 07 | 6 | - | - |
| Phase 08-dataset-pipeline P07 | 12min | 2 tasks | 4 files |
| Phase 09-rust-foundation P01 | 10min | 3 tasks | 4 files |
| Phase 09-rust-foundation P02 | 4min | 3 tasks | 2 files |
| Phase 09-rust-foundation P03 | 8min | 2 tasks | 2 files |
| Phase 09-rust-foundation P04 | 12min | 1 tasks | 2 files |
| Phase 09 P08 | 8min | 1 tasks | 0 files |
| Phase 10-matcher-implementation P01 | 2min | 2 tasks | 1 files |
| Phase 10-matcher-implementation P02 | 1min | 2 tasks | 1 files |
| Phase 10-matcher-implementation P03 | 2min | 2 tasks | 2 files |
| Phase 10-matcher-implementation P04 | 3min | 3 tasks | 2 files |
| Phase 10-matcher-implementation P05 | 10min | 2 tasks | 1 files |
| 10 | 5 | - | - |
| Phase 11 P11-01 | 8min | 2 tasks | 3 files |
| Phase 11 P04 | 5min | 1 tasks | 2 files |
| Phase 11 P11-05 | 15min | 2 tasks | 1 files |
| Phase 13-nonflags-corpus-seed-uat P01 | 10min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

- [v1.4 Roadmap]: 7-phase structure derived from research SUMMARY.md §Roadmap Implications; Phase 7 rips LLM clarity before Harper clarity lands (zero dual-source window per CLAUDE.md standalone-app clean-replace)
- [v1.4 Roadmap]: Phases 8 (dataset) and 9 (Rust foundation) parallelizable — no file contention; Phase 10 matcher depends on both
- [v1.4 Roadmap]: Performance targets CLAR-N1..N4 treated as measurement checkpoints at Phase 11 only; NOT shipping-blocker requirements per REQUIREMENTS.md constraints
- [v1.4 Roadmap]: `write-good` dropped as dataset source — STACK research confirmed it ships regex heuristics, not phrase arrays; retext-simplify (MIT) + plainlanguage.gov (US PD) only
- [v1.4 Roadmap]: Acknowledgements UI bundled into Phase 12 with other settings surface (CLAR-19) — avoids slipping MIT license compliance past milestone close
- [v1.4 Roadmap]: Priority constants window 200/220/240 (High/Medium/Low) chosen >64 so grammar (127) and spelling (63) win overlap — inverts spec CD-05 per STACK direct harper-core source read
- [09-03]: build_lint_group single construction path; LintGroup::new_curated count in lib.rs reduced 2→1; clarity linter registration survives dict-add by construction (CLAR-12)
- [09-04]: FLAG_ME tokenizes as 3 tokens (Word+Underscore+Word) — matched via windows(3); FlatConfig.is_rule_enabled returns false for unknown keys — must call set_rule_enabled after LintGroup.add()
- [09-07]: CLAR-13 spike decision: Adopt MapPhraseLinter wrapper — both hard gates PASS (5-regime case preservation + zero priority=31 leakage). REQUIREMENTS.md CLAR-13 amended per D-09 (wrapper-vs-custom framing).
- [Phase ?]: Phase 9 final gate: D-35 satisfied — cargo 7/7 green, xcodebuild BUILD SUCCEEDED, ClarityFFITests all green, build-harper.sh idempotent
- [10-01]: PhraseEntry uses 'static str slices + Option<&'static [Dialect]> — const slice avoids heap allocation until Phase 11 TOML parse promotes to owned Vec
- [10-01]: WordyPhrasesLinter::new takes &[PhraseEntry] (constructor injection) — enables Plan 04 gate tests to instantiate with custom corpus without depending on global CORPUS const
- [10-01]: Production wrapper coexists with stub + spike (zero deletions in Plan 01) — Plan 03 atomically swaps registration in lib.rs and deletes both stub + spike in single commit
- [10-02]: Promoted spike tests run against PRODUCTION WordyPhrasesLinter::new(CORPUS) — bypasses build_lint_group dialect filter so all 21 entries (incl. synthetic 'forthwith') exercised at linter level; dialect filter contract tested separately at HarperChecker level in Plan 04
- [10-02]: Test promotion ordering enforced — helpers + tests promoted BEFORE mod spike deletion (Plan 03) per RESEARCH §Pitfall 2 to avoid compile breakage
- [10-03]: Atomic two-task stub→production swap honored D-02 — Task 1 deletes stub + spike from clarity.rs (build intentionally broken on lib.rs:7); Task 2 swaps lib.rs import + build_lint_group + tests in single coherent change. No coexistence period.
- [10-03]: build_lint_group dialect filter — None ⇒ universal; Some(allowed) ⇒ allowed.contains(&dialect). Dialect: PartialEq + Copy verified in harper-core 2.0.0 dict_word_metadata.rs. Signature unchanged per D-15.
- [10-03]: Lib.rs regression tests filter+count on primary_replacement instead of len-equality — real corpus text "Please utilize this." may co-emit grammar/spelling lints alongside the clarity match; len==1 would race against unrelated curated rules.
- [10-04]: Edition 2021 keeps std::env::set_var safe — no unsafe block in case_preservation_under_tr_locale; future move to edition 2024 will require unsafe wrapping per RESEARCH Pitfall 3.
- [10-04]: Synthetic 'forthwith' CORPUS entry intentionally absent from wordy_phrases.toml so Phase 11 TOML wire-up cannot override its dialect tag — preserves dialect-filter test integrity across phase boundaries.
- [10-05]: Phase 10 build gate passed — build-harper.sh exit 0 (idempotent; zero diff on XCFramework + Swift bindings), cargo --lib 11/11, xcodebuild app BUILD SUCCEEDED, xcodebuild test 493/496 (3 deferred AXCallWatchdog parallel-flake failures only — STATE-documented).
- [10-05]: Rule 1 auto-fix on stale FLAG_ME stub test — Plan 10-03 deleted WordyPhrasesStubLinter but Swift ClarityFFITests.stubRoundTrip still asserted FLAG_ME → FLAGGED. Replaced with utilizeRoundTrip exercising live WordyPhrasesLinter surface (utilize → use, Severity::High); same FFI coverage retargeted. Mandated by Plan 10-05 acceptance criterion (no FLAG_ME refs in Swift).
- [Phase ?]: [11-01]: ParsedPhraseEntry owned String fields; OnceLock single-init verified by pointer equality across 102 calls; serde+toml promoted from transitives — zero new compile units
- [11-02]: WordyPhrasesLinter promoted pub(crate)→pub; build_lint_group reads get_corpus() (338 TOML entries) not CORPUS const; dialect_filter_drops_non_matching uses local synthetic forthwith injection — forthwith absent from TOML by design (D-05 / [10-04])
- [Phase ?]: Golden file header stripped of '#' comment lines before assert — header for developers, data lines only compared
- [Phase ?]: [11-04]: All 5 locked entries emit priority=200; plan table had 'at the present time' as medium but TOML is source of truth
- [Phase ?]: [11-05]: CLAR-N1 measured at 91.71ms avg in debug build (non-blocking; 500-word doc, 10 iterations)
- [Phase ?]: [11-05]: CLAR-N2 = 46.8KB (47,935 bytes) — within 200KB target; CLAR-N4: 338 entries all ASCII, zero multi-byte
- [Phase ?]: [11-05]: FFI surface unchanged — HarperBridge.swift SHA identical pre/post build-harper.sh; idempotency confirmed
- [Phase ?]: [13-01]: Empty harness wired BEFORE fixture content — locks 4 per-category test fn API + filter logic; cargo test --test nonflags_corpus → 4 passed in 2.59s with zero fixtures

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
| Test flake | `AXCallWatchdogTests.shouldSkipReturnsTrueForBundle...` + `...blocklistExpires...` — parallel-load timing, pass solo | Deferred (pre-existing, Phase 04-01 documented) | 2026-04-19 |
| Test flake | `TextMonitorStoreIntegrationTests.keystrokeSchedulesDebouncedReconcile` — parallel-load debounce timing, passes solo | Deferred (pre-existing, out of scope) | 2026-04-19 |

## Session Continuity

Last session: 2026-04-25T15:13:28.275Z
Stopped at: Phase 11 Plan 05 complete — Phase 11 all 5 plans done
Resume file: None
