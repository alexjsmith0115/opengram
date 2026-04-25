# Roadmap: OpenGram

## Milestones

- ✅ **v1.1 LLM Integration Refinement** — Phases 09-14 (shipped 2026-04-15)
- ✅ **v1.2 Incremental LLM Checking + Paragraph Rephrase Card** — Phases 15-18.3 + 20 (shipped 2026-04-19; Phase 19 skipped)
- ✅ **v1.3 Performance & Scroll-Tracking** — Phases 1-6 (shipped 2026-04-19; reset numbering)
- 🚧 **v1.4 Clarity Engine** — Phases 7-13 (started 2026-04-19)

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

### 🚧 v1.4 Clarity Engine (Phases 7-13) — IN PROGRESS

- [ ] **Phase 7: LLM `.clarity` Clean-Deletion** — Rip LLM clarity before Harper clarity lands; zero dual-source window · CLAR-09, CLAR-10
- [x] **Phase 8: Dataset Pipeline** — `build_wordy_phrases.py` + `wordy_phrases.toml` (~500 entries) from retext-simplify + plainlanguage.gov · CLAR-14, CLAR-15, CLAR-16 (completed 2026-04-20)
- [x] **Phase 9: Rust Foundation + MapPhraseLinter Spike** — `SuggestionCategory::Clarity`, `Severity` FFI enum, stub linter, `build_lint_group` helper, 20-phrase spike · CLAR-11, CLAR-12, CLAR-13 (completed 2026-04-25)
- [x] **Phase 10: Matcher Implementation** — Production matcher per spike decision; 5-regime case preservation; word-boundary; dialect filter · CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06 (completed 2026-04-25)
- [ ] **Phase 11: Dataset Integration + Fixture Harness** — `include_str!` wire-up, auto-generated +/- fixtures per entry, snapshot-diff CI, perf logging · CLAR-20
- [ ] **Phase 12: Settings UI + Severity Filter + Acknowledgements** — Clarity toggles, severity filter in `HarperService`, About → Acknowledgements pane · CLAR-02, CLAR-07, CLAR-08, CLAR-17, CLAR-18, CLAR-19
- [ ] **Phase 13: NonFlags Corpus Seed + UAT** — ≥100 non-flag regression fixtures + manual validation in Notes/TextEdit · CLAR-21

## Phase Details

### Phase 7: LLM `.clarity` Clean-Deletion
**Goal**: LLM no longer produces, persists, or surfaces `.clarity` suggestions — clean replace ahead of Harper clarity
**Depends on**: v1.3 shipped (standalone-app contract honored; no feature flag)
**Requirements**: CLAR-09, CLAR-10
**Success Criteria** (what must be TRUE):
  1. `.clarity` case absent from `LLMCheckType` enum and `LLMStyleSuggestion.Category`; grep proves zero references outside deletion commit
  2. `LLMPrompts.systemPrompt` emits no clarity-dimension instruction; LLM batch responses carrying `"category":"clarity"` are silently dropped at DTO decode via the existing unknown-rawValue guard and never reach the overlay
  3. Audit documents that no archived `LLMConfig`/`Set<LLMCheckType>` path exists in production; `ConfigManager` reads individual bool keys, never a serialised `Set<LLMCheckType>`; no decoder fallback needed.
  4. `ParagraphSuggestionStore` audit confirms in-memory-only actor (no disk I/O); CLAR-10's conditional purge clause not triggered; audit artifact is one-line code comment at actor declaration.
  5. Hotkey flow in Notes.app with `.tone` + `.rephrase` enabled shows no clarity suggestion (visual validation per CLAUDE.md computer-use workflow)
**Plans**: 7 plans
- [x] 07-01-PLAN.md — Doc amendments (REQUIREMENTS.md CLAR-09 strike + ROADMAP.md Phase 7 criteria 2/3/4 per D-04/D-10)
- [x] 07-02-PLAN.md — Enum + prompt core deletions (LLMCheckType.clarity, LLMStyleSuggestion.Category.clarity, LLMPrompts.systemPrompt rewrite per D-01/D-02/D-12)
- [x] 07-03-PLAN.md — Call-site switch fixes (OverlayController + ParagraphSuggestionStore + RephraseCardViewModel + DisplayHeuristic + Suggestion.swift docstring; default-arm preserved; D-22 scrub)
- [x] 07-04-PLAN.md — Settings UI + ConfigManager (LLMSettingsView Clarity Toggle removal + ConfigManager llmEnableClarity read deletion per D-11/D-18/D-19)
- [x] 07-05-PLAN.md — Test surgery + D-05 regression test (7 test files; D-05 silent-drop test; REPH-11 clarity-token strip; xcodebuild green gate)
- [x] 07-06-PLAN.md — UAT Notes.app manual validation per D-22 + ROADMAP criterion 5
**UI hint**: yes

### Phase 8: Dataset Pipeline
**Goal**: Curated, license-attributed, NFC-normalized ~500-entry clarity phrase dataset committed to repo
**Depends on**: Nothing (parallelizable with Phase 9; pure data work)
**Requirements**: CLAR-14, CLAR-15, CLAR-16
**Success Criteria** (what must be TRUE):
  1. `harper-bridge/scripts/build_wordy_phrases.py` runs with Python stdlib only (no third-party deps) and produces byte-deterministic output given same inputs
  2. `harper-bridge/data/wordy_phrases.toml` committed with ~500 entries; every entry has `phrase`, `replacement`, `severity`, optional `dialects` list; all strings NFC-normalized (verified by script's own round-trip check)
  3. Each inflected form (`utilize`/`utilizes`/`utilized`) appears as its own `PhraseEntry` — no runtime stemming required; 20-40 judgment-call entries hand-reviewed and noted in script comments
  4. `THIRD_PARTY.md` at repo root embeds retext-simplify MIT license text verbatim + plainlanguage.gov US public-domain provenance note; `write-good` absent as source
  5. Severity tagging derived from cross-source confirmation (phrases in both retext-simplify AND plainlanguage.gov default High; single-source default Medium; subjective entries Low)
**Plans**: 6 plans

Plans:
- [x] 08-01-PLAN.md — Wave 0 tests + fixtures (unittest tree, synthetic retext + plainlang + overrides + SHA manifest + golden TOML)
- [x] 08-02-PLAN.md — Core script infrastructure (NFC + typography + SHA verify + hand-rolled TOML emitter + atomic write)
- [x] 08-03-PLAN.md — Source parsers (retext-simplify JS regex + plainlanguage.gov MD regex; D-22/D-23/D-24/P-8 semantics)
- [x] 08-04-PLAN.md — Merge + severity + judgment flags (rules 2+3 per D-21) + overrides layering (D-09/D-10)
- [x] 08-05-PLAN.md — Vendor real sources + SOURCES.sha256 + curate overrides + commit generated wordy_phrases.toml (checkpoint)
- [x] 08-06-PLAN.md — THIRD_PARTY.md at repo root (MIT verbatim + plainlanguage.gov PD note + commit SHAs)
- [x] 08-07-PLAN.md — Gap closure: add utilizes/utilized via pipeline add-op (CLAR-04 inflection contract)

### Phase 9: Rust Foundation + MapPhraseLinter Spike
**Goal**: FFI surface + linter registration path ready for matcher; spike resolves `MapPhraseLinter` vs custom-hashmap decision before Phase 10 locks scope
**Depends on**: v1.3 harper-bridge baseline
**Requirements**: CLAR-11, CLAR-12, CLAR-13
**Success Criteria** (what must be TRUE):
  1. `SuggestionCategory::Clarity` variant + `Severity` UniFFI enum (`High`/`Medium`/`Low`) + `Option<Severity>` field on `GrammarSuggestion` ship across FFI; Swift `Suggestion` gains matching `severity: Severity?`; regenerated UniFFI bindings compile in Xcode
  2. `build_lint_group(merged, dialect)` helper extracted and called from both `HarperChecker::new()` and `add_to_dictionary` rebuild path; unit test confirms clarity linter survives a dictionary-add cycle (CLAR-12)
  3. Priority constants `High=200` / `Medium=220` / `Low=240` defined in clarity module; overlap test proves grammar (127) and spelling (63) win against clarity on span conflict via `remove_overlaps`
  4. Stub `WordyPhrasesLinter` with hard-coded single `FLAG_ME → FLAGGED` entry returns a `Clarity` suggestion for "FLAG_ME" input end-to-end; overlay renders solid orange underline; popover header reads "Clarity"
  5. `MapPhraseLinter` spike report written to phase directory documenting: severity override feasibility, case-preservation semantics, and decision — `MapPhraseLinter` wrapper adopted as production matcher OR custom first-token-hashmap fallback selected
**Plans**: 8 plans

Plans:
- [x] 09-01-PLAN.md — Wave 0 failing test scaffolding (Severity round-trip, stub_fires_flag_me, dict-add-cycle, spike harness, Swift ClarityFFITests)
- [x] 09-02-PLAN.md — Severity FFI surface (clarity.rs Severity enum + priority constants + helpers; SuggestionCategory::Clarity variant; GrammarSuggestion.severity field; FFI translation block severity mapping)
- [x] 09-03-PLAN.md — build_lint_group helper extraction + WordyPhrasesStubLinter skeleton (replaces twin LintGroup::new_curated call sites; CLAR-12 single source of truth)
- [x] 09-04-PLAN.md — Stub WordyPhrasesLinter match logic (FLAG_ME→FLAGGED token scan; flips Rust stub_fires_flag_me + dict-add-cycle tests GREEN)
- [x] 09-05-PLAN.md — UniFFI regen + XCFramework rebuild + Swift Suggestion.severity field + init mapping (flips ClarityFFITests.stubRoundTrip GREEN)
- [x] 09-06-PLAN.md — MapPhraseLinter wrapper spike (PriorityRewritingMapPhraseLinter + 20-phrase corpus + 5-regime case + priority-leak hard gates)
- [x] 09-07-PLAN.md — 09-SPIKE-REPORT.md per D-07 + REQUIREMENTS.md CLAR-13 amendment per D-09
- [x] 09-08-PLAN.md — Final xcodebuild gate (cargo + xcodebuild app + xcodebuild test full green per D-35)

### Phase 10: Matcher Implementation
**Goal**: Production-quality clarity matcher detects phrases in real text with correct case, word-boundary, dialect, and overlap behavior
**Depends on**: Phase 8 (dataset schema for matcher targets), Phase 9 (FFI surface + spike decision)
**Requirements**: CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06
**Success Criteria** (what must be TRUE):
  1. Matcher implemented per Phase 9 spike decision (MapPhraseLinter wrapper preferred, custom first-token-hashmap fallback); every enabled phrase in a hand-picked 20-entry test set produces exactly one suggestion with correct span and replacement
  2. Case preservation passes 5-regime Rust unit test: lowercase input stays lowercase, Sentence-start capitalizes first letter, Title Case preserves per-word capitalization, UPPER CASE stays upper, post-colon treated as Sentence-start; "iPhone"-style mixed-case proper nouns never trigger
  3. Word-boundary safety: mid-word substrings (e.g., "order to" inside "border tools") do not flag; test asserts on Harper token boundaries
  4. Dialect filter: entries tagged `dialects = ["en-US"]` suppressed when user's dialect config is non-US; universal entries (no dialect tag) always active
  5. Grammar-over-clarity overlap resolved by Harper's `remove_overlaps` + priority constants from Phase 9; integration test constructs overlapping grammar + clarity span and asserts grammar wins
  6. CI matrix includes `tr_TR` locale run (Turkish dotted-I edge cases) and passes
**Plans**: 5 plans

Plans:
- [x] 10-01-PLAN.md — Add production types (PhraseEntry struct + CORPUS const + WordyPhrasesLinter struct/impl) alongside stub
- [x] 10-02-PLAN.md — Promote spike test helpers + 2 spike tests (case_preservation_five_regimes, priority_rewrite_no_default_leak) to top-level mod tests
- [x] 10-03-PLAN.md — Atomic swap: register WordyPhrasesLinter via build_lint_group with dialect filter, delete WordyPhrasesStubLinter + mod spike, replace lib.rs stub tests with corpus equivalents
- [x] 10-04-PLAN.md — Add 4 new gate tests: proper_noun_iphone_does_not_trigger, word_boundary_no_midword_match, case_preservation_under_tr_locale, dialect_filter_drops_non_matching
- [x] 10-05-PLAN.md — Final phase gate: build-harper.sh + xcodebuild app + xcodebuild test all green per D-18

### Phase 11: Dataset Integration + Fixture Harness
**Goal**: Real ~500-entry dataset wired into `HarperChecker::new()`; auto-generated regression suite locks matcher behavior against dataset changes
**Depends on**: Phase 8 (dataset file), Phase 10 (matcher)
**Requirements**: CLAR-20 (validates CLAR-01..06 end-to-end with production dataset)
**Success Criteria** (what must be TRUE):
  1. `include_str!("../data/wordy_phrases.toml")` wired at `HarperChecker::new()`; `OnceLock`-cached parse verified by logging parse count = 1 across 100 sequential `check()` calls
  2. Auto-generated fixture harness produces 1 positive (matches + correct replacement + correct case regime) + 1 negative (non-matching context) test per `PhraseEntry` across 3 contexts (lowercase / Sentence-start / mid-word); meta-test validates the generator itself
  3. Snapshot-diff test locks 5 well-known entries (`utilize → use`, `in order to → to`, `at the present time → at present`, etc.) on every PR run; snapshot mismatch fails CI
  4. Full fixture suite runs green across all ~500 entries (or documented regressions triaged + resolved)
  5. Perf logged (not blocking): CLAR-N1 (`check()` overhead on 500-word doc), CLAR-N2 (bundle-size delta), CLAR-N4 (Unicode-scalar matching) values printed to test output; shipping not gated on them
**Plans**: 5 plans

Plans:
- [ ] 11-01-PLAN.md — PhraseEntry migration: serde + toml deps; ParsedPhraseEntry struct; parse_wordy_phrases(); PARSED_CORPUS OnceLock + get_corpus()
- [ ] 11-02-PLAN.md — Wire production dataset into build_lint_group: get_corpus() replaces CORPUS.iter(); WordyPhrasesLinter::new_from_parsed; relocate forthwith synthetic injection
- [ ] 11-03-PLAN.md — Fixture harness tests/fixture_harness.rs: positive (lowercase + Sentence-start) + negative (mid-word) + meta-tests
- [ ] 11-04-PLAN.md — Snapshot-diff tests/snapshot_diff.rs + golden_clarity_snapshot.txt: 5 locked entries (utilize, in order to, at the present time, a number of, additional)
- [ ] 11-05-PLAN.md — Perf measurements (CLAR-N1/N2/N4) + phase gate: build-harper.sh + xcodebuild app target green

### Phase 12: Settings UI + Severity Filter + Acknowledgements
**Goal**: User can toggle clarity, tune severity threshold, and view MIT license attribution — all without relaunch
**Depends on**: Phase 11 (real dataset runtime), Phase 9 (severity field on Suggestion)
**Requirements**: CLAR-02, CLAR-07, CLAR-08, CLAR-17, CLAR-18, CLAR-19
**Success Criteria** (what must be TRUE):
  1. Settings window has "Clarity" section with master toggle `clarityEnabled` (default ON, `@AppStorage`) + sub-toggle `clarityOpinionatedEnabled` (default OFF, gates `Low` severity); toggling either takes effect on next `check()` without relaunch
  2. Severity filter lives in Swift (`HarperService` post-processes Rust-returned `[Suggestion]` by `@AppStorage`-read user setting); Rust stays stateless (CLAR-18)
  3. Per-rule toggle verified: calling `setRuleEnabled("WordyPhrases", false)` via the existing bridge suppresses all clarity suggestions on next check; toggling back on restores them with no app restart (CLAR-07)
  4. Clarity suggestion popover shows "Clarity" badge (solid orange underline, source `.harper`, category `.clarity`) — visual validation via computer-use MCP in Notes.app
  5. Settings → About → Acknowledgements pane displays MIT license text for retext-simplify; `NSHumanReadableCopyright` plist updated; DMG distribution includes the notice (CLAR-19)
**Plans**: TBD
**UI hint**: yes

### Phase 13: NonFlags Corpus Seed + UAT
**Goal**: Regression containment mechanism seeded pre-launch; full v1.4 pipeline validated end-to-end in real macOS apps
**Depends on**: Phase 12 (full UX surface)
**Requirements**: CLAR-21
**Success Criteria** (what must be TRUE):
  1. `NonFlagsFixtures/` directory contains ≥100 sentences seeded from retext-simplify GitHub issue archives + hand-curated proper-noun / quoted-code / domain-context cases; each fixture asserts zero clarity suggestions on that input
  2. NonFlags suite wired as regression test; runs on every PR; any new clarity false-positive fixes MUST add a NonFlags entry before landing (CONTRIBUTING.md rule added)
  3. Manual UAT in Notes.app: hotkey-fire on text with known wordy phrases produces solid-orange clarity underlines; hover/click shows "Clarity" popover; Accept replaces text; Dismiss suppresses
  4. Manual UAT in TextEdit: clarity toggle master OFF suppresses all clarity suggestions; opinionated sub-toggle ON surfaces Low-severity entries; verified via computer-use MCP screenshots
  5. With `.tone` + `.rephrase` enabled in LLM settings, zero clarity suggestions surface from LLM path (confirms Phase 7 clean-deletion held across full milestone)
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. AX Call Queue | v1.3 | 3/3 | Complete | 2026-04-19 |
| 2. Cancellable Bounds Queries | v1.3 | 3/3 | Complete | 2026-04-19 |
| 3. Viewport Cull + Rect Cache | v1.3 | 2/2 | Complete | 2026-04-19 |
| 4. Scroll Handling — trackFrame + hideAndSettle | v1.3 | 5/5 | Complete | 2026-04-19 |
| 5. Session-Local Mirror Improvements | v1.3 | 3/3 | Complete | 2026-04-19 |
| 6. v1.3 Gap Closure — Zero-AX Ordering + Scope Cleanup | v1.3 | 2/2 | Complete | 2026-04-19 |
| 7. LLM `.clarity` Clean-Deletion | v1.4 | 0/0 | Not started | — |
| 8. Dataset Pipeline | v1.4 | 7/7 | Complete   | 2026-04-20 |
| 9. Rust Foundation + MapPhraseLinter Spike | v1.4 | 8/8 | Complete   | 2026-04-25 |
| 10. Matcher Implementation | v1.4 | 5/5 | Complete    | 2026-04-25 |
| 11. Dataset Integration + Fixture Harness | v1.4 | 0/0 | Not started | — |
| 12. Settings UI + Severity Filter + Acknowledgements | v1.4 | 0/0 | Not started | — |
| 13. NonFlags Corpus Seed + UAT | v1.4 | 0/0 | Not started | — |

## v1.4 Requirements Traceability

| Requirement | Phase |
|-------------|-------|
| CLAR-01 | Phase 10 |
| CLAR-02 | Phase 12 |
| CLAR-03 | Phase 10 |
| CLAR-04 | Phase 10 |
| CLAR-05 | Phase 10 |
| CLAR-06 | Phase 10 |
| CLAR-07 | Phase 12 |
| CLAR-08 | Phase 12 |
| CLAR-09 | Phase 7 |
| CLAR-10 | Phase 7 |
| CLAR-11 | Phase 9 |
| CLAR-12 | Phase 9 |
| CLAR-13 | Phase 9 |
| CLAR-14 | Phase 8 |
| CLAR-15 | Phase 8 |
| CLAR-16 | Phase 8 |
| CLAR-17 | Phase 12 |
| CLAR-18 | Phase 12 |
| CLAR-19 | Phase 12 |
| CLAR-20 | Phase 11 |
| CLAR-21 | Phase 13 |

**Coverage:** 21/21 v1 requirements mapped ✓ · Performance targets CLAR-N1..N4 = measurement checkpoints (Phase 11), non-blocking

## Backlog

### Phase 999.1: Rephrase card stale cache — no re-dispatch on second hotkey (BACKLOG)

**Goal:** [Captured for future planning] After the rephrase card has been shown and dismissed for paragraph P, a second Ctrl+Shift+G against the same unchanged paragraph does not re-show the card. Likely root cause: `ParagraphSuggestionCache` hit returns cached suggestions, but `OverlayController.tryDispatchRephraseCard` WR-02 dedup guard (`currentCardParagraphHash`) still matches even after dismiss, OR scheduler's `.dismissed` cache entries short-circuit the re-dispatch. Also check that `hideCardAndRestore()` / `onDismissAll` properly clears `currentCardParagraphHash` and `hiddenParagraphScalarRange`.
**Requirements:** TBD
**Plans:** 5/5 plans complete

Plans:
- [ ] TBD (promote with /gsd-review-backlog when ready)

Surfaced during Phase 18.3 Plan 04 manual validation — 2026-04-17.
