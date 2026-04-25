---
phase: 09-rust-foundation-mapphraselinter-spike
verified: 2026-04-25T00:13:43Z
status: passed
score: 5/5 must-haves verified (SC4 FFI portion verified; UI portion deferred to Phase 12)
overrides_applied: 1
overrides:
  - sc: 4
    reason: "SC4 UI rendering portion (overlay orange underline + popover Clarity badge) is explicitly Phase 12 scope per ROADMAP Phase 12 SC4 (CLAR-02/07/08/17/18/19). Phase 9 plans 01-08 have zero UI tasks. FFI portion of SC4 verified green via ClarityFFITests/stubRoundTrip; UI deferred to Phase 12 visual UAT."
    persisted_in: "09-HUMAN-UAT.md"
human_verification:
  - test: "Trigger hotkey in Notes.app on text containing FLAG_ME; observe overlay and popover"
    expected: "Overlay renders solid orange underline over FLAG_ME; popover header reads Clarity"
    why_human: "UI rendering path (OverlayController orange underline + popover Clarity badge) requires running app + visual validation"
    deferred_to_phase: 12
---

# Phase 9: Rust Foundation + MapPhraseLinter Spike Verification Report

**Phase Goal:** FFI surface + linter registration path ready for matcher; spike resolves MapPhraseLinter vs custom-hashmap decision before Phase 10 locks scope
**Verified:** 2026-04-24T20:15:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SuggestionCategory::Clarity + Severity enum + Option<Severity> on GrammarSuggestion cross FFI; Swift Suggestion.severity wired; bindings compile | ✓ VERIFIED | `clarity.rs`: `Severity` enum with `#[derive(uniffi::Enum)]`; `lib.rs`: `SuggestionCategory::Clarity` + `severity: Option<Severity>` on `GrammarSuggestion`; `HarperBridge.swift` generated with `public enum Severity` + `severity` field; `Suggestion.swift` maps `raw.severity`; `ClarityFFITests/stubRoundTrip` green |
| 2 | build_lint_group helper extracted; called from both new() and add_to_dictionary; unit test confirms clarity linter survives dict-add cycle | ✓ VERIFIED | `lib.rs:150`: `fn build_lint_group(merged, dialect)` called at `lib.rs:75` (new) and `lib.rs:137` (add_to_dictionary); `clarity_linter_survives_dict_add_cycle` test green (7/7 cargo tests pass) |
| 3 | Priority constants High=200/Medium=220/Low=240 defined; overlap test proves grammar (127) and spelling (63) win against clarity | ✓ VERIFIED | `clarity.rs:19-21`: `PRIORITY_HIGH=200`, `PRIORITY_MEDIUM=220`, `PRIORITY_LOW=240`; `clarity_loses_to_grammar_on_overlap` test asserts grammar lint (127) survives `remove_overlaps` against clarity (220) — green |
| 4 | Stub WordyPhrasesLinter FLAG_ME→FLAGGED returns Clarity suggestion end-to-end; overlay renders solid orange underline; popover header reads "Clarity" | PARTIAL | FFI path verified: `stub_fires_flag_me` green (category=Clarity, severity=Some(Medium), priority=220, replacement=FLAGGED); `ClarityFFITests/stubRoundTrip` green through HarperService → Suggestion(from:). UI rendering (orange underline, Clarity popover header) not verified — Phase 12 wires OverlayController clarity rendering; requires human visual check |
| 5 | MapPhraseLinter spike report documents severity override feasibility, case preservation, and decision | ✓ VERIFIED | `09-SPIKE-REPORT.md` present; documents hardcoded priority-31 issue, gate-by-gate evidence (both gates PASS), 20-phrase corpus, decision: Adopt MapPhraseLinter wrapper; `spike::case_preservation_five_regimes` and `spike::priority_rewrite_no_default_leak` both green |

**Score:** 4/5 truths verified (SC4 partially verified — Rust+FFI confirmed, UI rendering deferred to human)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `harper-bridge/src/clarity.rs` | Severity enum, priority constants, WordyPhrasesStubLinter, spike module | ✓ VERIFIED | 359 lines; all required items present and substantive; spike module in `#[cfg(test)] mod spike` |
| `harper-bridge/src/lib.rs` | SuggestionCategory::Clarity, GrammarSuggestion.severity, build_lint_group, clarity routing in check() | ✓ VERIFIED | 200 lines; all elements present and wired |
| `OpenGram/CheckEngine/Suggestion.swift` | severity: Severity? field, init(from:) severity mapping, .clarity case in CheckCategory | ✓ VERIFIED | severity field present with `= nil` default; init(from:) maps all severity cases; CheckCategory.clarity present |
| `OpenGram/Generated/HarperBridge.swift` | Severity enum, SuggestionCategory.clarity, severity field on GrammarSuggestion | ✓ VERIFIED | Generated file contains `public enum Severity`, `SuggestionCategory.clarity`, `severity: Severity?` field |
| `OpenGramTests/ClarityFFITests.swift` | stubRoundTrip test end-to-end | ✓ VERIFIED | Single test `stubRoundTrip` — checks category==.clarity, severity==.medium, replacement==FLAGGED; xcodebuild passes |
| `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-SPIKE-REPORT.md` | D-07 spike report with decision | ✓ VERIFIED | Present; complete per D-07 contract |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `WordyPhrasesStubLinter` | `build_lint_group` | `group.add("WordyPhrases", ...)` | ✓ WIRED | `lib.rs:152`: group.add registers stub; `lib.rs:155`: `set_rule_enabled("WordyPhrases", true)` enables it |
| `build_lint_group` | `HarperChecker::new()` | direct call `lib.rs:75` | ✓ WIRED | Called with `merged.clone(), dialect` |
| `build_lint_group` | `add_to_dictionary` rebuild | direct call `lib.rs:137` | ✓ WIRED | Called with `merged.clone(), inner.dialect` |
| `GrammarSuggestion.severity` | `Suggestion.init(from:)` | switch on `raw.severity` | ✓ WIRED | `Suggestion.swift:123-129`: maps .some(.high/medium/low) → Severity, .none → nil |
| `SuggestionCategory::Clarity` Rust → `CheckCategory.clarity` Swift | `HarperService.check()` | `Suggestion(from:in:)` + `case .clarity` switch arm | ✓ WIRED | `HarperService.swift:13-14`; `Suggestion.swift:119` |
| `severity_from_priority` | `check()` FFI translation | `(LintKind::Style, Some(sev)) => (SuggestionCategory::Clarity, Some(sev))` | ✓ WIRED | `lib.rs:104-108`: routing logic uses severity_from_priority to classify Clarity category |
| `PriorityRewritingMapPhraseLinter` spike | 20-phrase corpus tests | `clarity.rs spike module` | ✓ WIRED | Both gate tests reference CORPUS const; `#[cfg(test)]` gates spike from release binary |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `WordyPhrasesStubLinter` | Hard-coded FLAG_ME match | Intentional stub — Phase 10 replaces with dataset | Yes (by design for stub) | ✓ FLOWING (stub scope) |
| `Suggestion.severity` | `raw.severity` from FFI | `HarperChecker.check()` → `GrammarSuggestion.severity` → `severity_from_priority` | Yes — round-trips through priority constants | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 7 Rust lib tests pass | `cargo test --lib` (harper-bridge) | `test result: ok. 7 passed; 0 failed` | ✓ PASS |
| xcodebuild app compiles | `xcodebuild build` | `** BUILD SUCCEEDED **` | ✓ PASS |
| ClarityFFITests stubRoundTrip | `xcodebuild test -only-testing:OpenGramTests/ClarityFFITests` | `✔ 1 test passed` | ✓ PASS |
| FLAG_ME → FLAGGED Rust | `stub_fires_flag_me` (cargo test) | category=Clarity, severity=Some(Medium), priority=220 | ✓ PASS |
| Clarity survives dict-add | `clarity_linter_survives_dict_add_cycle` (cargo test) | 1 suggestion pre and post dict-add | ✓ PASS |
| Overlap: grammar beats clarity | `clarity_loses_to_grammar_on_overlap` (cargo test) | grammar lint (127) survives remove_overlaps vs clarity (220) | ✓ PASS |
| Spike: 5-regime case preservation | `spike::case_preservation_five_regimes` (cargo test) | 100 assertions (20 × 5 regimes) all pass | ✓ PASS |
| Spike: zero priority-31 leak | `spike::priority_rewrite_no_default_leak` (cargo test) | all lints ∈ {200,220,240} | ✓ PASS |
| Full xcodebuild test suite | `xcodebuild test` | 496 tests, 4 failures (pre-existing flakes: AXCallWatchdog ×2, TextMonitor ×1, OverlayController scroll ×1 — all documented in STATE.md as pre-existing deferred items, pass in isolation) | ✓ PASS (phase scope) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CLAR-11 | 09-02, 09-05 | Severity FFI enum + SuggestionCategory::Clarity + Option<Severity> on GrammarSuggestion; Swift Suggestion.severity | ✓ SATISFIED | clarity.rs Severity enum; lib.rs GrammarSuggestion.severity; HarperBridge.swift generated; Suggestion.swift mapped; stubRoundTrip green |
| CLAR-12 | 09-03, 09-04 | build_lint_group helper; clarity linter survives dict-add cycle | ✓ SATISFIED | lib.rs:150 build_lint_group; called from new() and add_to_dictionary; clarity_linter_survives_dict_add_cycle green |
| CLAR-13 | 09-06, 09-07 | MapPhraseLinter spike — both hard gates pass; decision record written | ✓ SATISFIED | spike module in clarity.rs; both spike tests green; 09-SPIKE-REPORT.md present with decision: Adopt MapPhraseLinter wrapper |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `clarity.rs` | 87 | `description()` returns "placeholder for dataset-driven matcher" | Info | Intentional — stub linter description; Phase 10 replaces struct; not user-visible |

No blockers. The stub `description()` string is correct documentation of the stub's temporary nature.

### Human Verification Required

#### 1. Clarity Overlay + Popover Rendering

**Test:** Launch OpenGram. Open Notes.app, type "FLAG_ME" in a note. Press Ctrl+Shift+G.
**Expected:** Solid orange underline appears over "FLAG_ME" in the overlay. Clicking the underline opens a popover with "Clarity" badge in the header and "FLAGGED" as the suggested replacement.
**Why human:** SC4 includes "overlay renders solid orange underline" and "popover header reads Clarity". OverlayController's orange rendering path for `.clarity` category and popover Clarity badge are Phase 12 scope, but SC4 states it as a Phase 9 criterion. The FFI + Swift model layer are verified green. The UI rendering layer requires visual confirmation.

### Gaps Summary

No blocking gaps. SC4's UI portion (orange underline rendering, popover Clarity header) cannot be verified programmatically. The Rust+FFI+Swift model layer for SC4 is fully verified. If Phase 12 is confirmed to own the OverlayController clarity rendering wiring and this is accepted as deferred, status can be promoted to passed after human visual check or override.

---

_Verified: 2026-04-24T20:15:00Z_
_Verifier: Claude (gsd-verifier)_
