# Requirements: OpenGram v1.4 Clarity Engine

**Defined:** 2026-04-19
**Core Value:** Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions — entirely local by default.
**Spec:** [`CLARITY_ENGINE_SPEC.md`](CLARITY_ENGINE_SPEC.md) (with research-driven corrections applied — see SUMMARY.md §Spec Corrections)

**Milestone goal:** Ship a rules-only Harper-native clarity detection layer powered by a ~500-entry curated phrase dataset (retext-simplify MIT + plainlanguage.gov US public domain), and hand off the `.clarity` dimension from the LLM to deterministic phrase rules. LLM `.tone`/`.rephrase` stay wired and untouched.

**Constraints:**
- NO feature flags, NO migration layer, NO deprecation cycle (per CLAUDE.md standalone-app philosophy). Clean replace.
- NFRs below (CLAR-N1..N4) are **performance targets**, not shipping-blocker requirements.
- `write-good` **dropped as dataset source** (mischaracterized in spec §6.2; ships regex heuristics, not phrase arrays).

---

## v1 Requirements

### Clarity — Detection

- [x] **CLAR-01**: Given input text containing a known wordy phrase, the clarity engine returns a suggestion with the flagged span, the replacement text, and an explanation. Every enabled phrase in the dataset produces exactly one clarity suggestion with the expected replacement for its fixture sentence.

- [ ] **CLAR-02**: Clarity suggestions render as a distinct visual category — solid orange underline (`NSColor.systemOrange`), `source: .harper`, `category: .clarity`. Popover header shows "Clarity" badge. Change from prior behavior: source flips `.llm` (dashed orange) → `.harper` (solid orange); color unchanged.

- [ ] **CLAR-03**: Case preservation — replacement matches the case regime of the flagged span across 5 regimes: lowercase, Sentence-start (capital first letter), Title Case, UPPER CASE, post-colon. Mixed-case proper nouns (e.g., "iPhone") must not trigger replacement.

- [x] **CLAR-04**: Inflection handling — dataset-driven. Each inflected form (`utilize`/`utilizes`/`utilized`) is a separate `PhraseEntry` with its corresponding replacement form. No runtime stemming; agreement filtered at dataset build time.

- [x] **CLAR-05**: Word-boundary safety — phrase matches only trigger on Harper token boundaries. Mid-word substrings never match (e.g., "order to" inside "border tools" must not flag). Validated against a dedicated `NonFlagsFixtures/` corpus.

- [x] **CLAR-06**: Grammar takes priority over clarity when spans overlap. Harper's `remove_overlaps` + priority field resolves this automatically. Clarity priority window is strictly greater than grammar (127) and spelling (63) so clarity loses overlaps. (Corrects spec CD-05 — Harper convention is lower-priority-number = more important.)

- [ ] **CLAR-07**: Individual clarity rule categories are toggleable via the existing `setRuleEnabled` bridge. Toggling `WordyPhrases` off suppresses all clarity suggestions; toggling back on restores them. No app rebuild or restart required.

- [ ] **CLAR-08**: Severity levels — phrases are tagged `High`, `Medium`, or `Low`. `High` + `Medium` enabled by default; `Low` opt-in via Settings. Severity is user-configurable. UX precedent: LanguageTool "Picky Mode".

### Clarity — LLM Clean-Replace

- [ ] **CLAR-09**: `.clarity` is **deleted** from `LLMCheckType` enum and from `LLMStyleSuggestion.Category` — clean replace, no feature flag, no migration. Consequences:
  - `LLMPrompts.systemPrompt` statically strips the clarity dimension (no `enabledChecks` parameter needed — supersedes spec §7.3 L-02).
  - `LLMStyleSuggestion` decode failure on a `.clarity` category is the filter (supersedes spec §7.3 L-03 defensive filter; silently dropped via existing unknown-rawValue guard in `SuggestionDTO.toModel` — no log).
  - `LLMService`, `LLMRequestQueue`, `CheckOrchestrator`, `TextMonitor`, `ParagraphSuggestionStore` stay wired for `.tone` and `.rephrase`.

- [ ] **CLAR-10**: `ParagraphSuggestionStore` audit — confirm whether in-memory or disk-persisted. If persisted, launch-time purge of any entry with `category == .clarity` so stale LLM clarity doesn't surface after the clean-replace ships. (Fills spec §7.5 gap.)

### Rust Foundation

- [x] **CLAR-11**: `harper-bridge/src/lib.rs` exposes a `SuggestionCategory::Clarity` variant and a `Severity` UniFFI enum (`High`/`Medium`/`Low`). `GrammarSuggestion` gains `severity: Option<Severity>` (None for non-clarity lints). Swift-side `Suggestion.init(from:)` populates `severity` from the new FFI field.

- [x] **CLAR-12**: `WordyPhrasesLinter` is registered on `HarperChecker::new()` via `LintGroup::add("WordyPhrases", ...)`. Because `add_to_dictionary` rebuilds the `LintGroup`, a shared `build_lint_group(merged, dialect)` helper is extracted so both code paths register the clarity linter identically. (Fills new gap surfaced during architecture research.)

- [x] **CLAR-13**: `MapPhraseLinter` wrapper spike — before Phase 10 commits matcher design, run a 20-phrase spike using a thin wrapper over Harper's `MapPhraseLinter::new_fixed_phrase` that rewrites `Lint.priority` on every emission to the severity-mapped constant (200/220/240). Native adoption is impossible because harper-core 2.0.0's `MapPhraseLinter::match_to_lint` hardcodes `priority: 31` at `map_phrase_linter.rs:137` (would invert CLAR-06); `new_fixed_phrases` shares one `correct_forms` pool across all patterns (unusable for per-entry replacement). Hard gates: (1) 5-regime case preservation via `Suggestion::replace_with_match_case`; (2) priority rewrite stability — zero leakage of default 31. Adopt the wrapper if both gates pass; fall back to a custom first-token-hashmap matcher if either fails. No harper-core fork. Decision record: `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-SPIKE-REPORT.md`. (Supersedes spec CD-02 and original CLAR-13 wording per Phase 9 D-02/D-09.)

### Dataset

- [x] **CLAR-14**: `harper-bridge/scripts/build_wordy_phrases.py` (Python stdlib only — `urllib.request`, `re`, `json`) fetches retext-simplify `data.json` (MIT) and `plainlanguage.gov/simple-words-and-phrases.md` (US public domain), normalizes into a common schema, deduplicates, tags severity by cross-source confirmation, NFC-normalizes all strings, and emits `harper-bridge/data/wordy_phrases.toml`. Output is committed; script is retained for reproducibility, not run at build time. `write-good` is **not** a source.

- [x] **CLAR-15**: `PhraseEntry` schema includes `dialects: Option<Vec<Dialect>>` (default None = universal). Phase 2 curation tags US-specific entries (e.g., "whilst" excluded from US-only set). Phase 4 matcher filters by the user's dialect config at runtime.

- [x] **CLAR-16**: `THIRD_PARTY.md` at repo root cites retext-simplify (MIT, Titus Wormer) and plainlanguage.gov (US public domain — attribution noted for provenance, not required). MIT license text embedded verbatim.

### Settings + Runtime

- [ ] **CLAR-17**: Settings UI adds a "Clarity" section with:
  - Master toggle: "Enable clarity suggestions" (default ON; `@AppStorage "clarityEnabled"`)
  - Sub-toggle: "Include opinionated suggestions" (default OFF; `@AppStorage "clarityOpinionatedEnabled"` — gates `Low` severity entries)
  
  Changes take effect on the next `check()` without relaunch.

- [ ] **CLAR-18**: Severity filtering lives in Swift (`HarperService` post-processes the Rust-returned `[Suggestion]` array by user-enabled severity). Rust stays stateless. (Spec CD-08.)

- [ ] **CLAR-19**: Acknowledgements UI — Settings → About → Acknowledgements pane bundles the MIT license text for retext-simplify (and any future MIT-licensed dataset sources). `NSHumanReadableCopyright` plist updated. `.dmg` distribution includes runtime notice per MIT terms. (Fills spec licensing gap.)

### Quality

- [ ] **CLAR-20**: Auto-generated fixture test harness — every `PhraseEntry` produces one positive fixture (matches + correct replacement + correct case regime) and one negative fixture (non-matching context, e.g., mid-word substring). Meta-test validates the generator itself. Snapshot-diff 5 well-known entries on every PR to catch silent matcher regressions.

- [ ] **CLAR-21**: NonFlags regression corpus — `NonFlagsFixtures/` seeded with ≥100 sentences that must never flag: mid-word substrings, legitimate uses of flagged phrases in domain-specific contexts, proper nouns containing flagged tokens, quoted/code snippets. Seed drawn from retext-simplify GitHub issue archives. CONTRIBUTING rule: every clarity-related bug report adds at least one NonFlags entry before the fix lands.

---

## Performance Targets (NOT shipping-blocker requirements)

Per user direction — treat as targets, measure and log, but do not gate release on them.

- **CLAR-N1**: Clarity linter adds ≤5ms to Harper `check()` on a 500-word document (p50, Apple Silicon). Combined Harper + Clarity stays under the existing 50ms budget (`performanceUnder50ms` test).
- **CLAR-N2**: Phrase dataset adds ≤200KB uncompressed to the app bundle (~50–100KB after Xcode resource compression).
- **CLAR-N3**: Zero new network dependencies — offline for the clarity path.
- **CLAR-N4**: All phrase matching operates on `&[char]` (Unicode scalars). No byte-offset assumptions. Dataset NFC-normalized at build time.

Measurement checkpoint: Phase 11 logs all four values to test output; shipping not gated on them.

---

## v2 Requirements (deferred)

- **CLAR-V2-01**: Passive voice detection (requires Harper POS data)
- **CLAR-V2-02**: Sentence-length flagging (informational only)
- **CLAR-V2-03**: Expletive construction detection (`"there is X that Y"`)
- **CLAR-V2-04**: Nominalization detection (`"make a decision"` → `"decide"`)
- **CLAR-V2-05**: LLM-backed tone rewriter — reactivate `.tone`/`.rephrase` as user-triggered explicit action
- **CLAR-V2-06**: On-device tone classification via Core ML (distilled BERT)
- **CLAR-V2-07**: Per-dialect UI — UK/AU dataset variants with settings toggle
- **CLAR-V2-08**: Custom user exception dictionary for clarity (suppress specific phrases per-user)
- **CLAR-V2-09**: Per-rule category toggles in Settings beyond master + opinionated
- **CLAR-V2-10**: Build-time dataset regeneration (currently committed output; automate if dataset churns)

---

## Out of Scope

| Feature | Reason |
|---------|--------|
| LLM-powered clarity | Rule-based engine replaces it; LLM stays wired for tone/rephrase only |
| Adverb/intensifier blanket flagging (`very`, `really`, `just`) | Anti-feature — write-good + Hemingway do it and users complain. Gate behind severity or defer to v2 POS rule |
| Cross-sentence clarity (flow, paragraph coherence) | Out of scope for rule-based; revisit in v2+ LLM tone work |
| Multi-language support | US English only for v1 |
| Telemetry for false-positive discovery | Violates privacy posture; NonFlags corpus + user-reported issues is the containment mechanism |
| Migration layer for existing LLMConfig | No feature flags, no migration per CLAUDE.md — clean replace |
| Feature flag for v1.4 rollout | Same reason |
| Real-time as-you-type clarity | Inherited from v1 scope — deferred with rest of real-time work |
| App Store distribution requirements | Direct `.dmg` only; AX entitlement drives this |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLAR-01 | Phase 10 | Complete |
| CLAR-02 | Phase 12 | Pending |
| CLAR-03 | Phase 10 | Pending |
| CLAR-04 | Phase 10 | Complete |
| CLAR-05 | Phase 10 | Complete |
| CLAR-06 | Phase 10 | Complete |
| CLAR-07 | Phase 12 | Pending |
| CLAR-08 | Phase 12 | Pending |
| CLAR-09 | Phase 7 | Pending |
| CLAR-10 | Phase 7 | Pending |
| CLAR-11 | Phase 9 | Complete |
| CLAR-12 | Phase 9 | Complete |
| CLAR-13 | Phase 9 | Complete |
| CLAR-14 | Phase 8 | Complete |
| CLAR-15 | Phase 8 | Complete |
| CLAR-16 | Phase 8 | Complete |
| CLAR-17 | Phase 12 | Pending |
| CLAR-18 | Phase 12 | Pending |
| CLAR-19 | Phase 12 | Pending |
| CLAR-20 | Phase 11 | Pending |
| CLAR-21 | Phase 13 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Performance targets: 4 (non-blocking, measured at Phase 11)
- Mapped to phases: 21 ✓
- Unmapped: 0 ✓

---

*Requirements defined: 2026-04-19 (v1.4 milestone start, informed by 4-researcher pass + synthesis). Traceability populated 2026-04-19 at v1.4 roadmap commit.*
