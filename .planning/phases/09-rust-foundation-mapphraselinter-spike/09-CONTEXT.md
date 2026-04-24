# Phase 9: Rust Foundation + MapPhraseLinter Spike - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Lay Rust FFI foundation for the clarity engine and run the `MapPhraseLinter` spike:

- Add `SuggestionCategory::Clarity` UniFFI variant + `Severity` UniFFI enum (High/Medium/Low) + `severity: Option<Severity>` field on `GrammarSuggestion` (CLAR-11).
- Extract `build_lint_group(merged, dialect) -> LintGroup` helper so `WordyPhrasesLinter` registration survives `add_to_dictionary` rebuild (CLAR-12).
- Ship stub `WordyPhrasesLinter` (single `FLAG_ME → FLAGGED` entry, severity Medium) proving end-to-end overlay + popover render `Clarity` badge with solid orange via priority constants (success criterion 4).
- New `harper-bridge/src/clarity.rs` module houses priority constants (`High=200`, `Medium=220`, `Low=240`) — chosen to LOSE overlap against grammar (127) and spelling (63) per CLAR-06 (lower priority number wins in Harper's `remove_overlaps`).
- Swift `Suggestion` gains `severity: Severity?` field populated via UniFFI-generated mapping; new Swift `Severity` enum mirrors the Rust variant set.
- Run 20-phrase `MapPhraseLinter` spike using a thin priority-rewrite wrapper; write spike report with decision.

Scope explicitly **excludes**: real dataset wiring (Phase 11 `include_str!`), production matcher implementation (Phase 10), dialect filtering runtime (Phase 10), severity-gated Settings UI (Phase 12), `NonFlagsFixtures/` corpus (Phase 13).

Parallelizable with Phase 8 (Phase 8 is pure data; no file contention). Depends on v1.3 `harper-bridge` baseline.

</domain>

<decisions>
## Implementation Decisions

### MapPhraseLinter spike (CLAR-13)
- **D-01:** Run a **minimal wrapper spike**. Build a thin `Linter` impl (`PriorityRewritingMapPhraseLinter` or similar) that delegates to `MapPhraseLinter::new_fixed_phrase` per entry and rewrites every emitted `Lint.priority` to the severity-mapped constant (200/220/240) before returning. The wrapper is the unit under spike test.
- **D-02:** Pre-spike intel (surface in spike report's framing section): harper-core 2.0.0 `MapPhraseLinter::match_to_lint` hardcodes `priority: 31` (`~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/linting/map_phrase_linter.rs:137`). Native adoption without a wrapper is impossible because priority 31 makes clarity beat grammar (127) and spelling (63), inverting CLAR-06. Additionally `new_fixed_phrases` shares a single `correct_forms` list across all phrases — unusable for per-entry-replacement datasets. Spike premise therefore is "wrapper-over-MapPhraseLinter vs custom first-token-hashmap", not "native MapPhraseLinter vs custom".
- **D-03:** **Hard gates** that must PASS for MapPhraseLinter wrapper adoption:
  1. **5-regime case preservation** — lowercase / Sentence-start / Title Case / UPPER CASE / post-colon, via `Suggestion::replace_with_match_case`. Any regime fail = fallback to custom.
  2. **Priority rewrite stability** — wrapper rewrites priority on EVERY emitted `Lint` to the correct severity constant. Zero leakage of default 31 in spike output. Any leak = fallback.
- **D-04:** Severity propagation and wrapper LoC are NOT hard gates. Spike author notes them in report body but does not fail adoption on them.
- **D-05:** Fallback trigger is strictly "any hard-gate fail". No spike-author-judgment fallback path; no harper-core fork path (rejected upfront — maintenance burden incompatible with standalone-app philosophy per CLAUDE.md).
- **D-06:** Spike corpus = 20 phrases drawn from Phase 8 output `harper-bridge/data/wordy_phrases.toml` — pick a balanced mix: ≥3 Sentence-start, ≥3 Title Case, ≥3 post-colon, ≥3 UPPER CASE, plus lowercase baseline + at least 2 multi-inflection pairs (`utilize`/`utilizes`/`utilized`). Executor curates the 20; spike report lists them.
- **D-07:** Spike report **must contain** (top-to-bottom):
  1. **Decision statement** — `Adopt MapPhraseLinter wrapper` OR `Adopt custom first-token-hashmap` + one-paragraph rationale.
  2. **Gate-by-gate evidence table** — each hard gate → PASS/FAIL + evidence (test output, code snippet, or reproduction command).
- **D-08:** Report location: `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-SPIKE-REPORT.md`. Phase 10 planner reads this first.
- **D-09:** **AMEND CLAR-13 in `.planning/REQUIREMENTS.md`** during execution — current wording ("Adopt `MapPhraseLinter` as the production matcher if spike passes; fall back to a custom first-token-hashmap matcher if severity override or 5-regime case handling are not achievable natively") was written without the priority=31 / shared-`correct_forms` intel. Amendment reframes to wrapper-vs-custom per D-01/D-02. Amendment is part of this phase's scope. (Parallels Phase 7's CLAR-09 D-04 and ROADMAP D-10 amendments.)

### Severity FFI shape (CLAR-11)
- **D-10:** Rust: `pub severity: Option<Severity>` field on `GrammarSuggestion`. `None` for spelling + grammar/punctuation lints, `Some(High|Medium|Low)` for clarity. Natural Rust idiom; UniFFI maps cleanly to Swift optional; non-clarity call paths stay compile-clean without touching `Severity`.
- **D-11:** Severity enum variants = `High | Medium | Low` only. No `Info` / `Unknown` — YAGNI. Matches CLAR-08 + Phase 8 dataset schema D-07 (`"high" | "medium" | "low"`). If v2 informational flags emerge, add then.
- **D-12:** `severity` populated by the clarity linter (stub in Phase 9, real matcher Phase 10) at Lint emission time. Non-clarity linters produce `None`. Mapping happens in the FFI translation block inside `HarperChecker::check` — same place that maps `LintKind → SuggestionCategory`.
- **D-13:** Severity filter lives **Swift-side only**, per CLAR-18. Rust returns ALL clarity suggestions with their severity tag. Swift `HarperService` post-processes the `[Suggestion]` array by reading `@AppStorage("clarityOpinionatedEnabled")` (default OFF) and dropping `Low` entries when disabled. Rust stays stateless. No `filter_by_severity` method on `HarperChecker`.

### Swift Suggestion model
- **D-14:** Swift `Severity` is the UniFFI-generated `public enum Severity { case high, medium, low }` emitted into `OpenGram/Generated/HarperBridge.swift` (module `OpenGramLib`) by the `#[derive(uniffi::Enum)]` on the Rust `Severity` declaration in `harper-bridge/src/clarity.rs`. UniFFI codegen produces `Sendable, Equatable, Hashable` conformances natively. No second `enum Severity` is declared in `OpenGram/CheckEngine/Suggestion.swift` — that would shadow/collide with the generated symbol since both live in the `OpenGramLib` module scope. `Suggestion.swift` references `Severity` directly via the generated type.
- **D-14-AMEND (Phase 9 plan-05 execution):** Original D-14 mandated a hand-declared Swift enum in `Suggestion.swift`. Discovered during plan-05 execution that UniFFI-generated `Severity` already lives in the same `OpenGramLib` module — declaring a second `enum Severity` produces a name collision. Resolution: reuse the generated type. D-14 intent (first-class `Severity` available in scope with `Sendable, Equatable, Hashable`) is satisfied by the UniFFI-generated declaration. D-15 + D-16 unchanged.
- **D-15:** `Suggestion` struct gains `let severity: Severity?` field (optional; `nil` for non-clarity). Existing `Suggestion.init(from: GrammarSuggestion)` path populates from the UniFFI-generated optional. All existing non-clarity call sites work unchanged (severity falls to `nil`).
- **D-16:** No raw `priority: UInt8` field on Swift `Suggestion`. Priority constants are a Rust-internal policy detail — Swift reasons about severity, not priority. Keeps abstraction clean.

### Stub WordyPhrasesLinter (success criterion 4)
- **D-17:** Single hardcoded entry: `FLAG_ME → FLAGGED`, severity `Medium` (default-on per CLAR-08). Chosen because it's deterministic, collision-free with real English, and isolates overlay/popover/severity plumbing from dataset-schema validation (Phase 11 owns that).
- **D-18:** Stub implemented as a standalone `struct WordyPhrasesStubLinter` (NOT a `MapPhraseLinter` instance) in `harper-bridge/src/clarity.rs` — lets Phase 9 ship the FFI+priority+severity surface without pre-committing to the spike outcome. If spike adopts wrapper, Phase 10 swaps in the wrapper. If spike picks custom, Phase 10 ships the hashmap matcher. Either way Phase 11 replaces the stub with the real dataset-driven implementation.
- **D-19:** Stub uses `harper-bridge/src/clarity.rs::PRIORITY_MEDIUM = 220` for its emitted `Lint.priority` — proves the priority → severity → FFI enum round-trip works end-to-end.
- **D-20:** End-to-end validation (proves SC-4 PASSED):
  - **Rust unit test** in `harper-bridge/src/lib.rs` (or `clarity.rs`): construct `HarperChecker::new("US", vec![])`, call `check("FLAG_ME".to_string())`, assert exactly one `GrammarSuggestion` with `category == SuggestionCategory::Clarity`, `severity == Some(Severity::Medium)`, `priority == 220`, `primary_replacement == Some("FLAGGED".to_string())`.
  - **Swift test** in `OpenGramTests`: call through the actual UniFFI bridge, assert `Suggestion` has `category == .clarity` + `severity == .medium`. Locks the FFI evolution and catches UniFFI codegen regressions.
- **D-21:** Stub removal: Phase 11 success criterion 1 wires `include_str!("../data/wordy_phrases.toml")` at `HarperChecker::new()` with `OnceLock`-cached parse. Stub is deleted atomically in that same plan — no coexistence period, clean replace per CLAUDE.md standalone-app philosophy.
- **D-22:** **NO computer-use / Notes.app manual validation in Phase 9.** Stub is internal-only (`FLAG_ME` isn't a real English phrase). Manual validation lands in Phase 10 (real matcher on real phrase) or Phase 12 (Settings UI + UAT). Phase 9 verification is pure automated (Rust + Swift unit tests).

### build_lint_group helper (CLAR-12)
- **D-23:** Helper signature: `fn build_lint_group(merged: Arc<MergedDictionary>, dialect: Dialect) -> LintGroup`. Minimal — only takes what's strictly needed in Phase 9. Builds `LintGroup::new_curated(merged.clone(), dialect)` internally, then calls `lint_group.add("WordyPhrases", Box::new(WordyPhrasesStubLinter::new()))` before returning.
- **D-24:** **NO dialect-filter parameter** and **NO clarity-config parameter** in the Phase 9 signature. CLAR-15 (`dialects: Option<Vec<Dialect>>`) and Settings-driven per-phrase toggles land in Phase 10 / Phase 12 and extend the signature then. Premature now because the stub has a single entry with no dialect metadata.
- **D-25:** Both `HarperChecker::new` and `HarperChecker::add_to_dictionary` switch from inline `LintGroup::new_curated(...)` to `build_lint_group(merged, dialect)`. Single source of truth for linter registration — fixes CLAR-12 by construction.
- **D-26:** CLAR-12 regression test (locks the "clarity linter survives dict-add cycle" invariant):
  ```
  fn clarity_linter_survives_dict_add_cycle() {
      let checker = HarperChecker::new("US".into(), vec![]);
      assert_eq!(checker.check("FLAG_ME".into()).len(), 1);  // stub fires
      let _ = checker.add_to_dictionary("somenewword".into());
      assert_eq!(checker.check("FLAG_ME".into()).len(), 1);  // stub STILL fires
  }
  ```
  Single round-trip test, deterministic, no intrusion into `LintGroup` internals. Lives in `harper-bridge/src/lib.rs` test module.
- **D-27:** Helper owns linter construction (D-23 language "builds internally"). Accepting a pre-built `Box<dyn Linter>` loses the "single source of truth" win — `add_to_dictionary` would need its own construction site.

### Priority constants module
- **D-28:** New file `harper-bridge/src/clarity.rs`. Declared as `mod clarity;` from `lib.rs`, with `use clarity::*;` (or explicit imports) where needed.
- **D-29:** Constants (module-level `pub const`):
  ```rust
  pub const PRIORITY_HIGH: u8 = 200;
  pub const PRIORITY_MEDIUM: u8 = 220;
  pub const PRIORITY_LOW: u8 = 240;
  ```
  Plus a `fn severity_to_priority(sev: Severity) -> u8` helper. No per-entry priority in dataset — policy is code-owned (Phase 8 TOML schema D-12 has no priority field by design).
- **D-30:** `harper-bridge/src/clarity.rs` is the home for Phase 9's clarity-specific Rust surface: priority constants, `severity_to_priority`, `Severity` UniFFI enum declaration, `WordyPhrasesStubLinter`. Phase 10 extends with the real matcher. Phase 11 replaces the stub.

### Locked scope (non-gray, flows from decisions above)
- **D-31:** `HarperChecker::check` FFI translation block adds the severity mapping: clarity lints get `Some(severity_from_priority(lint.priority))`, non-clarity gets `None`. `severity_from_priority` is the inverse helper (200 → High, 220 → Medium, 240 → Low, anything else → logic error / panic in debug).
- **D-32:** `SuggestionCategory::Clarity` added to the UniFFI enum. Match arm in `HarperChecker::check` translation: new `LintKind::Miscellaneous` case path routes to `Clarity` ONLY when the emitting linter tagged the lint with a clarity priority constant (200/220/240). This prevents misc-kind grammar lints from being mislabeled as clarity. (Implementation note: stub uses a dedicated `LintKind` or is distinguished by priority range — executor picks; grep `LintKind::Miscellaneous` in harper-core to see current usage.)
- **D-33:** UniFFI bindings regeneration + XCFramework rebuild is part of Phase 9 scope (the `build-harper.sh` step). Xcode build must pass with the regenerated `HarperBridge.swift` + `HarperBridgeFFI.h`.
- **D-34:** All existing Swift consumers of `Suggestion` stay compile-clean because `severity: Severity?` is optional (defaults to `nil` for non-clarity paths). No call-site churn beyond the one `init(from:)` that populates from UniFFI.
- **D-35:** Build validation per CLAUDE.md: `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` must succeed for both app and test targets before any plan is marked done.

### Claude's Discretion
- Exact naming of the MapPhraseLinter wrapper struct (e.g., `PriorityRewritingMapPhraseLinter` vs `WordyPhrasesSpikeMatcher` vs something shorter). Function matters, name is cosmetic.
- Internal organization of `harper-bridge/src/clarity.rs` — single flat module vs sub-submodule for stub linter. Executor picks based on growth trajectory.
- Exact 20-phrase spike corpus (D-06 gives balance constraints; executor picks the specific entries).
- Whether `severity_to_priority` lives as a `impl Severity` method or a standalone `fn` in clarity.rs. Idiomatic either way.
- Whether stub linter distinguishes via a custom `LintKind` or via priority-range match (D-32 alternative paths). Executor picks after one-screen of harper-core source read.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements + roadmap
- `.planning/REQUIREMENTS.md` §CLAR-11, CLAR-12, CLAR-13 — CLAR-13 will be amended per D-09 during execution
- `.planning/REQUIREMENTS.md` §CLAR-06, CLAR-08, CLAR-15, CLAR-18 — overlap priority contract, severity levels, dialect tagging, stateless Rust
- `.planning/ROADMAP.md` §Phase 9 (success criteria 1–5)

### Spec
- `.planning/CLARITY_ENGINE_SPEC.md` §CLAR-03 (5-regime case preservation), §CLAR-06 (grammar > clarity overlap), §CLAR-13 (spike; superseded by amended REQUIREMENTS CLAR-13 per D-09)

### Standalone-app contract
- `CLAUDE.md` "Standalone Application — No Dependencies" block — authority for "no feature flag, no migration, clean replace"
- `CLAUDE.md` "Build Validation" — `xcodebuild` is canonical
- `CLAUDE.md` "Testing" — Swift Testing for new unit tests; regression test for every bugfix

### Upstream phases
- `.planning/phases/08-dataset-pipeline/08-CONTEXT.md` — D-12 TOML schema (`phrase`, `replacement`, `severity`, `sources`, `dialects?`, `note?`, `id`); Phase 9 FFI + Phase 11 `include_str!` path consume this schema
- `.planning/phases/07-llm-clarity-clean-deletion/07-CONTEXT.md` — `CheckCategory.clarity` preserved with Phase 10-forward docstring (Suggestion.swift:42–43); Phase 9 does not re-touch the case

### Existing code (read before planning)
- `harper-bridge/src/lib.rs` — current FFI surface (`SuggestionCategory`, `GrammarSuggestion`, `HarperChecker::new`, `check`, `add_to_dictionary`, `set_rule_enabled`, `build_merged_dict`, `parse_dialect`)
- `OpenGram/CheckEngine/Suggestion.swift` — `CheckCategory` + `SuggestionSource` enums; `Suggestion` struct (severity field lands here)
- `harper-bridge/Cargo.toml` — `harper-core = "=2.0.0"` pin
- `harper-bridge/build-harper.sh` (or equivalent) — XCFramework build + UniFFI bindgen invocation

### harper-core source (for spike + FFI evolution)
- `~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/linting/map_phrase_linter.rs` — `priority: 31` hardcode at line ~137; `new_fixed_phrase` / `new_fixed_phrases` / `new_similar_to_phrase` constructors; `Suggestion::replace_with_match_case` usage
- `~/.cargo/registry/src/index.crates.io-*/harper-core-2.0.0/src/linting/mod.rs` — `Linter` trait + `LintKind` enum (determines what `LintKind` the stub tags; whether to add a new variant or reuse `Miscellaneous`)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HarperChecker::new` + `add_to_dictionary` already have the twin `LintGroup::new_curated(merged.clone(), dialect)` call sites (`harper-bridge/src/lib.rs:70, 130`) — D-25 helper extraction replaces both in place.
- `build_merged_dict(&user_dict)` helper already exists (`harper-bridge/src/lib.rs:143`) — parallels the CLAR-12 `build_lint_group` pattern. Use it as the style template.
- `HarperChecker::check`'s FFI translation block (`harper-bridge/src/lib.rs:79–115`) is where the severity field gets populated — same switch block that maps `lint.lint_kind → SuggestionCategory`.
- UniFFI `#[derive(uniffi::Enum)]` + `#[derive(uniffi::Record)]` already established on `SuggestionCategory` + `GrammarSuggestion` — additive-only: add `Severity` enum and `severity: Option<Severity>` field, no restructuring.
- `Suggestion.swift` `CheckCategory.clarity` case preserved from Phase 7 with forward-looking docstring — no re-edit needed, just populate severity on the Suggestion struct.
- `Suggestion::replace_with_match_case` in harper-core is what `MapPhraseLinter` already uses — spike 5-regime testing exercises this function, not code we write.

### Established Patterns
- UniFFI-first FFI evolution: add enum variant or record field, regenerate, update Swift init(from:) path. No raw C FFI code in this repo.
- Single-`Mutex<Inner>`-guarded `HarperChecker` state with Swift actor providing additional serialization upstream (lib.rs:32–50). New helper must respect this — pure function, no interior state.
- Swift Testing `@Test` / `#expect` for new unit tests per CLAUDE.md. XCTest only for UI tests.
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` for validation — not `swift build` (SPM masks missing pbxproj refs).
- New Swift files must be added to `OpenGram.xcodeproj` `project.pbxproj` (file references + Sources build phase). Only applies if we create a new `.swift` file — severity enum is additive in existing `Suggestion.swift`, so no pbxproj changes here. Rust-side `clarity.rs` is not in the Xcode project directly (it's compiled into the XCFramework).
- Compiler-driven refactor (Phase 7 insight carries): adding `SuggestionCategory::Clarity` forces exhaustive-match errors on every call site — treat Xcode's error list as the refactor checklist.

### Integration Points
- `harper-bridge/src/lib.rs` — new `mod clarity;` declaration; `build_lint_group` helper insertion; FFI translation block severity mapping.
- `harper-bridge/src/clarity.rs` — new file: `Severity` UniFFI enum, priority constants, `severity_to_priority` / `severity_from_priority` helpers, `WordyPhrasesStubLinter`, unit tests.
- `OpenGram/CheckEngine/Suggestion.swift` — new `Severity` enum, `severity: Severity?` field on `Suggestion`, `init(from:)` population. No pbxproj edit.
- `harper-bridge/build-harper.sh` — rerun post-Cargo-change to regenerate `HarperBridge.swift` + rebuild XCFramework. No script edits expected.
- `OpenGramTests/` — new Swift test asserting FFI-surfaced severity + category on FLAG_ME input (D-20).
- `.planning/REQUIREMENTS.md` — CLAR-13 amendment per D-09 (plan item, not executor afterthought).
- `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-SPIKE-REPORT.md` — new artifact per D-07/D-08.

</code_context>

<specifics>
## Specific Ideas

- Priority=31 hardcode in `MapPhraseLinter::match_to_lint` (harper-core-2.0.0 `map_phrase_linter.rs:137`) — reframes CLAR-13 from "native vs custom" to "wrapper-over-native vs custom". This discovered intel drives D-01 through D-09.
- `new_fixed_phrases` shares a single `correct_forms` list across all supplied phrases. Only `new_fixed_phrase` (singular) is usable for per-entry-replacement datasets like ours — means ~500 stacked linter instances if we ever adopt MapPhraseLinter wrapper, which is fine (harper-core's own grammar LintGroup stacks hundreds of linters).
- Stub linter ships FIRST, spike runs SECOND, matcher lands in PHASE 10. Phase 9 deliberately decouples the FFI surface from the spike outcome: whichever direction the spike picks, Phase 10 swaps in the production matcher and the FFI stays stable.
- The 5-regime case preservation test uses `Suggestion::replace_with_match_case` — spike's case-preservation gate effectively tests harper-core's own helper, not our code. If harper-core's helper is correct (likely — it's battle-tested), the case gate passes trivially and priority rewrite becomes the real decider.

</specifics>

<deferred>
## Deferred Ideas

- Dialect filtering (`dialects: Option<Vec<Dialect>>` per entry per CLAR-15) — Phase 10 implementation. Phase 9 stub has no dialect metadata; `build_lint_group` signature stays minimal without it.
- Per-phrase config plumbing (Settings-driven toggles) — Phase 12 wires Settings UI and `setRuleEnabled`; `build_lint_group` signature extends then.
- `Info` severity variant (non-actionable informational flags like v2 passive-voice / sentence-length) — add in v2 when actually needed.
- Fork harper-core to add native priority override — explicitly rejected per D-05. Revisit only if wrapper AND custom hashmap both fail Phase 10 acceptance.
- `filter_by_severity` method on `HarperChecker` (Rust-side filter) — rejected per D-13 / CLAR-18. Revisit only if Swift-side filter becomes a perf bottleneck (very unlikely at clarity suggestion counts).
- Priority field per TOML entry (dataset owns policy) — D-29 rejects. Revisit if severity policy diverges from code expectations.
- Exposing raw priority on Swift `Suggestion` (D-16 rejects) — add only if a Swift debugger / inspector surface genuinely needs it.

</deferred>

---

*Phase: 09-rust-foundation-mapphraselinter-spike*
*Context gathered: 2026-04-20*
