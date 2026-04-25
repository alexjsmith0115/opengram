---
phase: 10-matcher-implementation
verified: 2026-04-24T23:30:00Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
---

# Phase 10: Matcher Implementation Verification Report

**Phase Goal:** Production-quality clarity matcher detects phrases in real text with correct case, word-boundary, dialect, and overlap behavior.
**Verified:** 2026-04-24T23:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| #   | Truth                                                                                          | Status     | Evidence                                                                                                          |
| --- | ---------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | Matcher per Phase 9 spike (MapPhraseLinter wrapper); every phrase produces exactly one suggestion | ✓ VERIFIED | `WordyPhrasesLinter` wraps `Vec<(MapPhraseLinter, u8)>` (clarity.rs:84-122); `wordy_phrases_fires_corpus_entry` asserts exactly 1 lint for "utilize" → "use"; `case_preservation_five_regimes` iterates 21 entries × 5 regimes = 105 assertions PASS |
| 2   | 5-regime case preservation                                                                     | ✓ VERIFIED | `case_preservation_five_regimes` (clarity.rs:219-271) covers lowercase/sentence-start/title-case/UPPER/post-colon; PASS                                                                                  |
| 3   | Word-boundary correctness                                                                      | ✓ VERIFIED | `word_boundary_no_midword_match` (clarity.rs:289-304): "unaccompanied" with CORPUS entry "accompany" emits zero lints; PASS                                                                              |
| 4   | Dialect filter                                                                                 | ✓ VERIFIED | `build_lint_group` filters CORPUS by dialect (lib.rs:151-158); `dialect_filter_drops_non_matching` (lib.rs:222-246): US fires "forthwith", GB drops it; PASS                                                                                          |
| 5   | Overlap behavior (grammar wins)                                                                | ✓ VERIFIED | `clarity_loses_to_grammar_on_overlap` (clarity.rs:167-197): grammar priority 127 beats clarity 220 via `remove_overlaps`; PASS                                                                                            |
| 6   | tr_TR locale ASCII preservation (CI matrix)                                                    | ✓ VERIFIED | `case_preservation_under_tr_locale` (clarity.rs:306-340) sets LANG/LC_ALL=tr_TR.UTF-8, asserts ASCII-correct replacements; PASS                                                                                       |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact                                  | Expected                                                              | Status     | Details                                                                                                |
| ----------------------------------------- | --------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------ |
| `harper-bridge/src/clarity.rs`            | PhraseEntry, CORPUS, WordyPhrasesLinter, gate tests                   | ✓ VERIFIED | 374 LoC; PhraseEntry struct + 21 CORPUS entries (1 American-tagged) + WordyPhrasesLinter + 8 mod tests |
| `harper-bridge/src/lib.rs`                | build_lint_group dialect-filter + corpus-based regression tests       | ✓ VERIFIED | 248 LoC; `applicable: Vec<PhraseEntry>` (line 151) + `WordyPhrasesLinter::new(&applicable)` (line 160) + 3 mod tests |
| `HarperBridge.xcframework/macos-arm64_x86_64/` | Rebuilt XCFramework with macos slice                              | ✓ VERIFIED | Headers + libharper_bridge.a present                                                                   |
| `OpenGram/Generated/HarperBridge.swift`   | Regenerated UniFFI bindings — Severity + GrammarSuggestion present, no stub | ✓ VERIFIED | enum Severity + struct GrammarSuggestion present; zero WordyPhrasesStubLinter references               |
| `OpenGramTests/ClarityFFITests.swift`     | utilizeRoundTrip Swift test (FLAG_ME stub test replaced)              | ✓ VERIFIED | utilizeRoundTrip asserts .clarity + .high + "use" round-trip; PASS                                     |

### Key Link Verification

| From                          | To                              | Via                                       | Status  | Details                                                                                                       |
| ----------------------------- | ------------------------------- | ----------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------- |
| WordyPhrasesLinter::new       | MapPhraseLinter::new_fixed_phrase | per-entry `iter().map()` (clarity.rs:92-99) | ✓ WIRED | Confirmed grep at clarity.rs:93                                                                               |
| lib.rs build_lint_group       | clarity::WordyPhrasesLinter::new | dialect-filtered &applicable (lib.rs:160) | ✓ WIRED | Confirmed grep at lib.rs:160                                                                                  |
| lib.rs build_lint_group       | clarity::CORPUS                  | `.iter().filter().copied().collect()` (lib.rs:151) | ✓ WIRED | Confirmed grep at lib.rs:151-158                                                                              |
| Swift HarperService           | HarperBridge.xcframework        | SPM binaryTarget                          | ✓ WIRED | xcodebuild BUILD SUCCEEDED + ClarityFFITests utilizeRoundTrip TEST SUCCEEDED                                  |

### Data-Flow Trace (Level 4)

| Artifact                  | Data Variable             | Source                                       | Produces Real Data | Status     |
| ------------------------- | ------------------------- | -------------------------------------------- | ------------------ | ---------- |
| WordyPhrasesLinter::lint  | inner Vec<(MapPhraseLinter, u8)> | constructed from CORPUS via WordyPhrasesLinter::new | Yes (21 entries) | ✓ FLOWING  |
| build_lint_group          | applicable: Vec<PhraseEntry> | CORPUS.iter().filter(dialect).copied().collect() | Yes (filtered)   | ✓ FLOWING  |
| HarperChecker.check       | lints from inner.linter.lint(&document) | LintGroup.lint dispatched to WordyPhrasesLinter | Yes (utilize→use round-trips) | ✓ FLOWING  |

### Behavioral Spot-Checks

| Behavior                                        | Command                                            | Result                                  | Status |
| ----------------------------------------------- | -------------------------------------------------- | --------------------------------------- | ------ |
| Cargo lib tests pass                            | `cargo test --lib --manifest-path harper-bridge/Cargo.toml` | 11 passed; 0 failed; 0 ignored        | ✓ PASS |
| Xcodebuild app builds                           | `xcodebuild -scheme OpenGram build`                | `** BUILD SUCCEEDED **`                 | ✓ PASS |
| Swift FFI round-trip test                       | `xcodebuild ... -only-testing:OpenGramTests/ClarityFFITests test` | utilizeRoundTrip PASS — `** TEST SUCCEEDED **` | ✓ PASS |
| CORPUS contains 21 PhraseEntry items            | `grep -c "PhraseEntry {" clarity.rs`               | 22 (1 struct def + 21 entries)          | ✓ PASS |
| Synthetic American-tagged entry                 | `grep -c "Some(&\[Dialect::American\])" clarity.rs` | 1                                       | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan      | Description                                                                            | Status      | Evidence                                                                                  |
| ----------- | ---------------- | -------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------- |
| CLAR-01     | 10-01,10-03,10-05 | Known wordy phrase returns suggestion with span+replacement+explanation; one per phrase | ✓ SATISFIED | wordy_phrases_fires_corpus_entry asserts exactly 1 suggestion; case_preservation_five_regimes covers all 21 entries |
| CLAR-03     | 10-02,10-04,10-05 | 5-regime case preservation; mixed-case proper nouns ("iPhone") never trigger          | ✓ SATISFIED | case_preservation_five_regimes (5 regimes × 21 entries) + proper_noun_iphone_does_not_trigger PASS |
| CLAR-04     | 10-01,10-02,10-03,10-05 | Dataset-driven inflection (utilize/utilizes/utilized as separate entries)          | ✓ SATISFIED | CORPUS lines 56-58 ship triple inflection; case_preservation_five_regimes exercises each |
| CLAR-05     | 10-03,10-04,10-05 | Word-boundary safety; mid-word substrings never match                                  | ✓ SATISFIED | word_boundary_no_midword_match: "accompany" inside "unaccompanied" emits 0 lints PASS    |
| CLAR-06     | 10-03,10-04,10-05 | Grammar over clarity overlap; clarity priority strictly > grammar(127) and spelling(63) | ✓ SATISFIED | clarity_loses_to_grammar_on_overlap: grammar 127 beats clarity 220 via remove_overlaps PASS |

**Note:** CLAR-15 declared in plan 10-01 frontmatter but REQUIREMENTS.md attributes CLAR-15 to Phase 8 (Complete). Phase 10 reuses the schema by registering the dialect-filter test (`dialect_filter_drops_non_matching`) — coverage incidental, not a phase 10 requirement.

### Anti-Patterns Found

None. All TODO/FIXME/HACK/PLACEHOLDER patterns absent from clarity.rs and lib.rs. No empty implementations. No stub linters. Production wrapper rewrites priority correctly (clarity.rs:111-114).

### Human Verification Required

None. Phase 10 ships pure Rust matcher logic + Swift FFI round-trip; all behavior asserted by automated tests. Visual/UX validation deferred to Phase 12 (CLAR-02 — solid orange underline rendering).

### Gaps Summary

No gaps. All 6 ROADMAP success criteria satisfied:
- SC1 matcher implementation + one-suggestion-per-phrase: PASS via wordy_phrases_fires_corpus_entry + case_preservation_five_regimes
- SC2 case preservation + iPhone non-trigger: PASS via case_preservation_five_regimes + proper_noun_iphone_does_not_trigger
- SC3 word-boundary safety: PASS via word_boundary_no_midword_match
- SC4 dialect filter: PASS via dialect_filter_drops_non_matching
- SC5 grammar-over-clarity overlap: PASS via clarity_loses_to_grammar_on_overlap
- SC6 tr_TR locale: PASS via case_preservation_under_tr_locale

cargo test --lib: 11/11 PASS. xcodebuild app: BUILD SUCCEEDED. ClarityFFITests utilizeRoundTrip: TEST SUCCEEDED. Stub fully removed from Rust + Swift sources.

Pre-existing AXCallWatchdog parallel-timing flakes (3) noted in 10-05-SUMMARY are deferred items per STATE.md 2026-04-19, not Phase 10 regressions; pass cleanly in isolation.

---

_Verified: 2026-04-24T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
