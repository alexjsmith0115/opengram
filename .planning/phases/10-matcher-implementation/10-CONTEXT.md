# Phase 10: Matcher Implementation - Context

**Gathered:** 2026-04-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Promote the Phase 9 spike `PriorityRewritingMapPhraseLinter` from `#[cfg(test)] mod spike` into production scope as `WordyPhrasesLinter` inside `harper-bridge/src/clarity.rs`. Replace `WordyPhrasesStubLinter` atomically. Add the production-grade gates: 5-regime case preservation across the hand-picked CLAR-01 corpus, Harper-token word-boundary safety (CLAR-05), `dialects: Option<&[Dialect]>` runtime filter (CLAR-15 → CLAR-06 enforcement at non-US dialects), grammar-over-clarity overlap precedence (CLAR-06, already wired via `remove_overlaps` + priority constants), and a `tr_TR.UTF-8` locale unit test guarding Turkish dotted-I edge cases (CLAR-N4 Unicode safety).

Scope explicitly **excludes**: `include_str!("../data/wordy_phrases.toml")` wire-up of the full ~676-entry dataset (Phase 11), `OnceLock`-cached parse (Phase 11), auto-generated +/- fixture harness across full dataset (Phase 11 CLAR-20), Settings UI severity threshold + per-rule toggles (Phase 12 CLAR-07/CLAR-08/CLAR-17/CLAR-18), `NonFlagsFixtures/` ≥100-entry corpus (Phase 13 CLAR-21), MIT acknowledgements pane (Phase 12 CLAR-19).

Depends on Phase 8 dataset schema (provenance for the 20-entry seed) + Phase 9 FFI surface (Severity enum, `severity_from_priority`, `build_lint_group`, `LintKind::Style` + priority-window routing).

</domain>

<decisions>
## Implementation Decisions

### Phrase seed source (CLAR-01 SC-1)
- **D-01:** Promote the spike `CORPUS` const from `#[cfg(test)] mod spike` to a module-level `pub(crate) const CORPUS: &[PhraseEntry]` in `harper-bridge/src/clarity.rs`. The 20 entries (utilize-triple + 8 high + 9 medium, balanced across single-token / multi-token / multi-inflection per Phase 9 D-06) become the production seed. `WordyPhrasesLinter::new(dialect)` consumes `CORPUS` directly. **No TOML parsing in Phase 10.** Phase 11 swaps the source from `&[PhraseEntry]` const-slice to `Vec<PhraseEntry>` parsed from `include_str!("../data/wordy_phrases.toml")` behind `OnceLock`. Keeps Phase 10 scope tight; defers parser to where its OnceLock cache + auto-fixture harness already live (Phase 11).

### Stub linter clean-replace
- **D-02:** `WordyPhrasesStubLinter` is **deleted in Phase 10** atomically with the new `WordyPhrasesLinter` registration in `build_lint_group`. No coexistence period. `stub_fires_flag_me` and `clarity_linter_survives_dict_add_cycle` tests delete with the stub. Real corpus (CORPUS 20 entries) supersedes `FLAG_ME` smoke value; CLAR-12 dict-add-cycle invariant re-asserted via a real corpus entry (e.g., `utilize` → `use` survives `add_to_dictionary("somenewword")`). **Amends Phase 9 D-21** which scheduled stub removal for Phase 11 — Phase 10 ships the real matcher, so stub becomes dead code one phase earlier. Per CLAUDE.md standalone-app: clean replace, no compat shim.

### PhraseEntry struct (CLAR-15 prep)
- **D-03:** Phase 10 introduces `pub(crate) struct PhraseEntry { phrase: &'static str, replacement: &'static str, severity: Severity, dialects: Option<&'static [Dialect]> }` in `harper-bridge/src/clarity.rs`. `&'static` slices match the const-array seed. Phase 11 replaces with owned types (`String` / `Vec<Dialect>`) once TOML parsing lands; signature of `WordyPhrasesLinter::new` stays stable across phases (takes `&[PhraseEntry]` by reference; const-slice and `Vec::as_slice()` both satisfy).
- **D-04:** Hardcoded CORPUS entries carry `dialects: None` initially (universal). Add at least 1 dialect-tagged synthetic CORPUS entry (e.g., `dialects: Some(&[Dialect::American])`) so the dialect-filter test path exercises the non-empty branch. Choice of synthetic entry is executor's discretion — pick one that has zero risk of being a US-vs-UK toggle in Phase 11 (avoid future churn).

### Dialect filter (CLAR-15, CLAR-06 SC-4)
- **D-05:** Filter applied at **build time** inside `build_lint_group(merged, dialect) -> LintGroup`. Before constructing the wrapper, fold `CORPUS` through `entries.iter().filter(|e| match e.dialects { None => true, Some(allowed) => allowed.contains(&dialect) })`. Wrapper receives only the dialect-applicable subset. No per-`lint()` filter — fast path, zero per-emission branch.
- **D-06:** Settings-driven dialect change at runtime triggers a `build_lint_group` rebuild. **Not Phase 10 scope** — Phase 12 wires the rebuild trigger when Settings UI ships. Phase 10 verification: unit test constructs two `HarperChecker` instances (dialect=`American` vs `British`), asserts the dialect-tagged synthetic entry from D-04 fires for one and not the other.

### tr_TR locale safety (CLAR-N4, Phase 10 SC-6)
- **D-07:** Add `#[test] fn case_preservation_under_tr_locale()` in `clarity.rs`. Test sets `LANG=tr_TR.UTF-8` and `LC_ALL=tr_TR.UTF-8` via `std::env::set_var` in test body, runs UPPER CASE regime over CORPUS, asserts `replace_with_match_case` output stays ASCII-correct (no `i → İ` / `I → ı` Turkish dotted-I drift). Pure `cargo test` — **no GitHub Actions matrix file**, no shell wrapper. CLAUDE.md compliant (no GSD/CI references in source). Phase 10 SC-6 ("CI matrix includes `tr_TR` locale run and passes") satisfied by a locale-injected test that runs in every `cargo test` invocation.
- **D-08:** Test cleanup uses `scopeguard` or manual `set_var` revert in test teardown. Document in test docstring that env vars are process-global — test is `#[test] #[serial]` if `serial_test` already in dev-deps; otherwise rely on the fact that the test resets after assertion (acceptable risk because no other Phase 10 test reads `LANG`). **Executor discretion** between `serial_test` dep vs reset-on-exit, depending on dev-deps audit.

### Mixed-case proper noun (CLAR-03 acceptance)
- **D-09:** **No code-level proper-noun guard.** `MapPhraseLinter::new_fixed_phrase` already tokenizes inputs identically to the document parser; `iPhone` is one `TokenKind::Word` token whose content is `['i','P','h','o','n','e']` and won't match a CORPUS phrase like `iphone` (none exist in CORPUS or wordy_phrases.toml). **Contract-test the framework**: add `#[test] fn proper_noun_iphone_does_not_trigger()` that runs `WordyPhrasesLinter` over `"iPhone is great."` and asserts zero lints emitted. Locks `MapPhraseLinter` token-shape behavior we depend on.

### Production wrapper naming
- **D-10:** Rename spike struct `PriorityRewritingMapPhraseLinter` → `WordyPhrasesLinter` in production. Matches CLAR-12 / REQUIREMENTS.md / Phase 9 D-18 naming. `build_lint_group` registration becomes `group.add("WordyPhrases", WordyPhrasesLinter::new(applicable_entries))`. Domain name hides MapPhraseLinter-wrapper impl detail. `WordyPhrasesLinter::description()` returns `"Wordy-phrase clarity linter — flags wordy phrases with simpler replacements per the curated corpus."` (production string, replaces spike's "Spike: …").

### Word-boundary safety (CLAR-05 SC-3)
- **D-11:** Word-boundary correctness inherits from `MapPhraseLinter`'s native behavior: it matches on Harper token windows, not byte/char substrings. The `border tools` / `order to` regression test asserts this contract: `#[test] fn word_boundary_no_midword_match()` runs `WordyPhrasesLinter` over `"You can border tools that work."` and asserts zero clarity lints (CORPUS entry `accede to` cannot fire mid-word inside `border tools`; need to construct a CORPUS-realistic case — pick a CORPUS phrase whose first token appears mid-word in a non-flagging context).
- **D-12:** Test corpus selection for D-11 is **executor discretion** — pick a CORPUS phrase + carrier sentence that demonstrably triggers Harper tokenization to refuse a mid-word match (e.g., CORPUS contains `accept` → carrier `"unacceptable behavior"` does NOT flag).

### 5-regime case preservation (CLAR-03 SC-2)
- **D-13:** Phase 10 reuses Phase 9 spike's `case_preservation_five_regimes` test logic verbatim (5 regimes × 20 phrases = 100 assertions), promoted to a `#[test]` against the production `WordyPhrasesLinter` instead of the spike struct. Test moves from `mod spike` (deleted with stub-removal in D-02 cleanup) to top-level `#[cfg(test)] mod tests` in `clarity.rs`. Same case-fold equality assertion (`replacement.eq_ignore_ascii_case(expected)`).

### Grammar-over-clarity overlap (CLAR-06 SC-5)
- **D-14:** `clarity_loses_to_grammar_on_overlap` test (already shipped Phase 9, `clarity.rs:96`) is the integration-level check. Phase 10 keeps it. CLAR-06 SC-5 satisfied by construction: priority constants (200/220/240) ship in clarity.rs, `remove_overlaps` is harper-core's, and the existing test asserts grammar (priority 127) wins. **No new code in Phase 10 for CLAR-06** — the contract is already locked by Phase 9 D-29/D-31/D-32.

### Locked scope (non-gray, flows from decisions above)
- **D-15:** `build_lint_group` signature stays `fn build_lint_group(merged: Arc<MergedDictionary>, dialect: Dialect) -> LintGroup`. Phase 9 D-23/D-25 contract honored. Body changes from `WordyPhrasesStubLinter::new()` to `WordyPhrasesLinter::new(filtered_corpus_for_dialect(dialect))`. Single source of truth for both `HarperChecker::new` and `add_to_dictionary` rebuild paths.
- **D-16:** `WordyPhrasesLinter::new(entries: &[PhraseEntry]) -> Self` constructs `inner: Vec<(MapPhraseLinter, u8)>` exactly per spike pattern (`clarity.rs:168–185`): `MapPhraseLinter::new_fixed_phrase(entry.phrase, [entry.replacement], format!(…), format!(…), Some(LintKind::Style))` per entry, paired with `severity_to_priority(entry.severity)`.
- **D-17:** Wrapper `Linter::lint` impl reuses spike body (`clarity.rs:187–202`): outer loop over `inner.iter_mut()`, inner loop rewrites `lint.priority = *target_prio` before push. ~40 LoC matches Phase 9 D-04 estimate.
- **D-18:** UniFFI bindings + XCFramework rebuild via `build-harper.sh` runs at end of Phase 10 plan-set. `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` must succeed for app + test targets per CLAUDE.md before any plan marked done.
- **D-19:** Swift consumers of `Suggestion` need zero call-site churn. Phase 9 already wired `severity: Severity?` field through. Phase 10 only changes the producer (stub → real wrapper); consumer FFI surface identical.
- **D-20:** Module declaration `mod clarity;` already in `lib.rs:10`; `use clarity::{Severity, severity_from_priority};` already in `lib.rs:7`. Update import to add `WordyPhrasesLinter` (drop `WordyPhrasesStubLinter`).

### Claude's Discretion
- Exact synthetic dialect-tagged CORPUS entry per D-04 (any low-risk universal phrase tagged `American`).
- Exact CORPUS phrase + carrier sentence for D-11 word-boundary regression.
- `serial_test` dep adoption vs manual env reset for D-08 — depends on `harper-bridge/Cargo.toml` dev-deps audit.
- Whether `WordyPhrasesLinter::lint` deduplicates overlapping CORPUS entries before priority rewrite (e.g., if two CORPUS phrases match overlapping spans). Phase 9 spike didn't address; harper-core's `remove_overlaps` runs at LintGroup level after all linters emit, so wrapper-internal dedup is likely unnecessary. Executor verifies via integration test.
- Order of CORPUS entries in the const-slice (alphabetical vs severity-grouped vs phase-9-order). Functional no-op; readability call.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements + roadmap
- `.planning/REQUIREMENTS.md` §CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06 — Phase 10 scope requirements
- `.planning/REQUIREMENTS.md` §CLAR-15 — `dialects: Option<Vec<Dialect>>` schema (Phase 10 ships matcher-side filter; full dataset tagging is Phase 11)
- `.planning/REQUIREMENTS.md` §CLAR-N4 — Unicode safety (informs D-07 tr_TR test)
- `.planning/REQUIREMENTS.md` §CLAR-12 — `build_lint_group` single source of truth (Phase 9 shipped; Phase 10 inherits)
- `.planning/ROADMAP.md` §Phase 10 — Success criteria 1–6

### Spec
- `.planning/CLARITY_ENGINE_SPEC.md` §CLAR-03 — 5-regime case preservation contract
- `.planning/CLARITY_ENGINE_SPEC.md` §CLAR-05 — word-boundary acceptance ("border tools" non-trigger)
- `.planning/CLARITY_ENGINE_SPEC.md` §CLAR-06 — grammar-clarity overlap rule
- `.planning/CLARITY_ENGINE_SPEC.md` §CD-08 — Severity filtering lives Swift-side (informs Phase 10 stays stateless on user severity prefs)

### Standalone-app contract
- `CLAUDE.md` "Standalone Application — No Dependencies" — authority for D-02 clean stub-replace, no compat shim
- `CLAUDE.md` "Build Validation" — `xcodebuild` canonical (D-18)
- `CLAUDE.md` "Testing" — Swift Testing for new unit tests; regression test for every behavior
- `CLAUDE.md` "Style" — comments only for WHY not WHAT; no GSD references in source

### Upstream phases
- `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-SPIKE-REPORT.md` — wrapper adoption decision; CORPUS provenance; gate evidence (D-01 promotes the spike CORPUS)
- `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-CONTEXT.md` §D-04 (severity propagation), §D-21 (stub-removal — amended by D-02), §D-23/D-25 (`build_lint_group` contract), §D-29/D-31/D-32 (priority constants + FFI routing — already shipped)
- `.planning/phases/08-dataset-pipeline/08-CONTEXT.md` — `PhraseEntry` TOML schema (`phrase`, `replacement`, `severity`, `dialects?`); Phase 10 mirrors this shape in Rust struct (D-03)

### Existing code (read before planning)
- `harper-bridge/src/lib.rs:7` — current `use clarity::{Severity, WordyPhrasesStubLinter, severity_from_priority}` import (D-20 modifies)
- `harper-bridge/src/lib.rs:104–108` — FFI translation block routing `LintKind::Style + priority window → SuggestionCategory::Clarity` (Phase 9 D-32; Phase 10 inherits, no changes)
- `harper-bridge/src/lib.rs:150–157` — current `build_lint_group` body (D-15 modifies)
- `harper-bridge/src/lib.rs:181–199` — current stub tests (`stub_fires_flag_me`, `clarity_linter_survives_dict_add_cycle`); D-02 deletes both, replaces with corpus-based equivalents
- `harper-bridge/src/clarity.rs:12–38` — `Severity` enum + priority constants + helpers (Phase 9 shipped; Phase 10 reuses unchanged)
- `harper-bridge/src/clarity.rs:45–89` — `WordyPhrasesStubLinter` (D-02 deletes)
- `harper-bridge/src/clarity.rs:91–145` — current Phase 9 `mod tests` (`clarity_loses_to_grammar_on_overlap` keeps; `severity_enum` + `severity_round_trip` keep)
- `harper-bridge/src/clarity.rs:148–359` — current Phase 9 `mod spike` (D-01 promotes CORPUS to module-level; D-02 deletes the rest of spike module)
- `harper-bridge/data/wordy_phrases.toml` — referenced for CORPUS provenance (entries cross-referenced against this file in Phase 9 spike report); Phase 10 does NOT parse this file — Phase 11 owns `include_str!`
- `harper-bridge/build-harper.sh` (or equivalent) — XCFramework rebuild step (D-18)

### harper-core source (read for boundary semantics)
- `~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/linting/map_phrase_linter.rs:137` — `priority: 31` hardcode (the reason for the wrapper at all; framing context inherited from Phase 9 D-02)
- `~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/linting/mod.rs` — `Linter` trait, `LintKind::Style` variant, `Lint` struct, `remove_overlaps` (CLAR-06 SC-5 inherits Phase 9 wiring)
- `~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/document.rs` — `Document::tokens` iterator (informs D-09 / D-11 token-shape contract tests)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `clarity::Severity` UniFFI enum + `PRIORITY_HIGH/MEDIUM/LOW` constants + `severity_to_priority` / `severity_from_priority` helpers (Phase 9 shipped at `clarity.rs:12–38`) — Phase 10 imports unchanged.
- `clarity_loses_to_grammar_on_overlap` test (`clarity.rs:96–125`) — CLAR-06 SC-5 already locked; Phase 10 keeps the test, no new overlap test needed.
- Spike's `PriorityRewritingMapPhraseLinter::new` body (`clarity.rs:168–202`) — copied verbatim into production `WordyPhrasesLinter::new` per D-16/D-17. Same `(MapPhraseLinter, u8)` tuple, same priority-rewrite-before-push pattern.
- Spike's `case_preservation_five_regimes` test (`clarity.rs:268–325`) — 5×20 = 100 assertions, promote to top-level `#[cfg(test)] mod tests` against production wrapper per D-13.
- `build_lint_group(merged, dialect)` helper (`lib.rs:150–157`) — single registration site for both `HarperChecker::new` + `add_to_dictionary`. D-15 modifies body; signature unchanged.
- `MergedDictionary` + `Document` setup pattern from spike's `make_merged_dict` helper (`clarity.rs:234–238`) — directly reusable in Phase 10 tests.

### Established Patterns
- UniFFI-first FFI evolution — Phase 10 introduces zero new FFI surface (PhraseEntry is internal Rust). Severity field already crosses FFI from Phase 9.
- Module-level constants + helpers in `clarity.rs`; production linter struct + impl Linter; tests in `#[cfg(test)] mod tests` at file bottom. Same shape Phase 9 established.
- `LintGroup::add(rule_key: &str, linter: impl Linter)` registration; `config.set_rule_enabled(rule_key, true)` because rules added via `add()` default disabled in `FlatConfig` (`lib.rs:152–155`). Phase 10 inherits this exact pattern.
- Compiler-driven refactor when changing `SuggestionCategory` or `Severity` shape — additive-only in Phase 10 (no FFI surface changes), so no exhaustive-match pressure.
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` for validation, both app + test targets, before any plan marked done.
- New Rust files into XCFramework via `build-harper.sh`; **not** added to `OpenGram.xcodeproj` directly. Phase 10 ships zero new Swift files (all changes Rust-side; Swift `Suggestion` already wired Phase 9).

### Integration Points
- `harper-bridge/src/lib.rs:7` — import statement updates (drop `WordyPhrasesStubLinter`, add `WordyPhrasesLinter`).
- `harper-bridge/src/lib.rs:150–157` — `build_lint_group` body swap per D-15.
- `harper-bridge/src/lib.rs:181–199` — replace `stub_fires_flag_me` + `clarity_linter_survives_dict_add_cycle` tests with corpus-based equivalents (one CORPUS entry, e.g., `utilize → use`, used as the smoke test).
- `harper-bridge/src/clarity.rs:45–89` — delete `WordyPhrasesStubLinter` struct + impl entirely.
- `harper-bridge/src/clarity.rs` — add module-level `pub(crate) struct PhraseEntry`, `pub(crate) const CORPUS: &[PhraseEntry]`, `pub(crate) struct WordyPhrasesLinter`, `impl Linter for WordyPhrasesLinter`. New tests: `case_preservation_five_regimes` (promoted from spike), `priority_rewrite_no_default_leak` (promoted from spike), `proper_noun_iphone_does_not_trigger` (D-09), `word_boundary_no_midword_match` (D-11), `case_preservation_under_tr_locale` (D-07), `dialect_filter_drops_non_matching` (D-04 + D-06).
- `harper-bridge/src/clarity.rs:148–359` — delete entire `#[cfg(test)] mod spike` block after promoting CORPUS + tests to top-level scope.
- `harper-bridge/build-harper.sh` — invoke at end of plan-set (D-18). No script changes expected.

</code_context>

<specifics>
## Specific Ideas

- Phase 10 is **a transplant + gates expansion**, not a rewrite. The spike already proved the wrapper works (Phase 9 SPIKE-REPORT both gates PASS). Phase 10's net new code is: (a) `PhraseEntry` struct, (b) dialect-filter helper inside `build_lint_group`, (c) tr_TR locale test, (d) iPhone proper-noun test, (e) word-boundary test. Maybe ~60 net new lines of Rust + ~80 lines of test; rest is delete (stub) + move (spike → production scope).
- The "CI matrix" framing in ROADMAP SC-6 is misleading — there's no GitHub Actions in this repo. The actual mechanism (D-07) is a `cargo test` that locale-injects via `std::env::set_var`. Treat ROADMAP wording as "Turkish locale coverage exists in test suite," not as "CI pipeline change."
- `MapPhraseLinter::new_fixed_phrase` is the single-phrase constructor used by the spike. Phase 10 stays with `_phrase` (singular). `_phrases` (plural) is unusable per Phase 9 D-02 (shared `correct_forms` pool). ~20 linter instances stack inside `WordyPhrasesLinter.inner` Vec at Phase 10 scale; harper-core's curated LintGroup stacks hundreds, so this is well within established pattern.
- Phase 11 will revisit `WordyPhrasesLinter::new` signature: `&[PhraseEntry]` const-slice → `Vec<PhraseEntry>` parsed from TOML. Lifetime of `PhraseEntry` fields flips from `&'static str` to `String`. This is a minor refactor and accepted Phase 11 cost.

</specifics>

<deferred>
## Deferred Ideas

- Per-rule-category toggles beyond `WordyPhrases` master key (CLAR-V2-09) — Phase 12 + v2.
- `OnceLock`-cached TOML parse of full ~676-entry dataset (Phase 11 CLAR-20).
- Auto-generated +/- fixture harness covering full dataset (Phase 11 CLAR-20).
- Snapshot-diff regression test on 5 well-known entries (Phase 11 CLAR-20).
- Settings-driven dialect change → `build_lint_group` rebuild trigger (Phase 12).
- Severity threshold + opinionated-Low gating (Phase 12 CLAR-08, CLAR-17, CLAR-18).
- `NonFlagsFixtures/` ≥100 sentences (Phase 13 CLAR-21).
- `MapPhraseLinter::new_fixed_phrases` (plural) adoption if harper-core ever fixes the shared `correct_forms` constraint (deferred indefinitely; not on radar).
- harper-core fork to remove priority=31 hardcode — explicitly rejected per Phase 9 D-05; standalone-app maintenance burden.
- Per-phrase explanation text richer than "Consider '{replacement}' for '{phrase}'" (Phase 12 polish or v2).
- Cross-language/multi-dialect dataset variants (CLAR-V2-07 — UK/AU dataset toggle).

</deferred>

---

*Phase: 10-matcher-implementation*
*Context gathered: 2026-04-25*
