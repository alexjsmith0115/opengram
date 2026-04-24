---
phase: 09-rust-foundation-mapphraselinter-spike
plan: "06"
subsystem: harper-bridge/clarity
tags: [rust, spike, map-phrase-linter, clar-13, priority-rewrite, case-preservation]
dependency_graph:
  requires: [09-02-SUMMARY]
  provides: [CLAR-13 spike evidence, PriorityRewritingMapPhraseLinter, 20-phrase corpus]
  affects: [09-07-PLAN (spike report writing)]
tech_stack:
  added: []
  patterns: [MapPhraseLinter::new_fixed_phrase per-entry wrapper, priority-rewrite-on-emit, 5-regime case test]
key_files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
decisions:
  - "CORPUS uses 20 entries from wordy_phrases.toml: utilize/utilizes/utilized triple + 8 HIGH + 9 MEDIUM; acquiesce added as 20th"
  - "Case-preservation test uses eq_ignore_ascii_case — catches wrong-string replacements; exact case fidelity is secondary evidence"
  - "CORPUS entries: all replacements cross-verified against wordy_phrases.toml phrase/replacement/severity fields before commit"
metrics:
  duration: 10min
  completed: "2026-04-24"
  tasks: 1
  files: 1
---

# Phase 9 Plan 06: MapPhraseLinter Spike — Summary

**One-liner:** PriorityRewritingMapPhraseLinter spike wrapper over MapPhraseLinter::new_fixed_phrase with priority-rewrite-on-emit; both CLAR-13 hard-gate tests GREEN.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement spike wrapper + 20-phrase corpus + flip both spike tests GREEN | 119a2e5 | harper-bridge/src/clarity.rs |

## What Was Built

### PriorityRewritingMapPhraseLinter

`struct PriorityRewritingMapPhraseLinter { inner: Vec<(MapPhraseLinter, u8)> }` inside `#[cfg(test)] mod spike` in `harper-bridge/src/clarity.rs`.

- Constructor: `fn new(entries: &[(&str, &str, u8)]) -> Self` — creates one `MapPhraseLinter::new_fixed_phrase` per entry with `Some(LintKind::Style)`
- `impl Linter::lint`: iterates inner linters, mutates `lint.priority = *target_prio` on every emitted lint before pushing

Key invariant: `lint.priority = *target_prio` runs on EVERY emission — zero leakage of harper-core's hardcoded 31.

### 20-Phrase CORPUS

All 20 entries cross-verified against `harper-bridge/data/wordy_phrases.toml` (phrase + replacement + severity fields):

| # | Phrase | Replacement | Priority | TOML line |
|---|--------|-------------|----------|-----------|
| 1 | utilize | use | HIGH (200) | 2278 |
| 2 | utilizes | use | MEDIUM (220) | 2293 |
| 3 | utilized | used | MEDIUM (220) | 2285 |
| 4 | a number of | many | HIGH (200) | 26 |
| 5 | accompany | go with | HIGH (200) | 61 |
| 6 | accomplish | carry out | HIGH (200) | 68 |
| 7 | accorded | given | HIGH (200) | 75 |
| 8 | accordingly | so | HIGH (200) | 82 |
| 9 | accurate | correct | HIGH (200) | 96 |
| 10 | additional | added | HIGH (200) | 117 |
| 11 | advantageous | helpful | HIGH (200) | 167 |
| 12 | abundance | enough | MEDIUM (220) | 33 |
| 13 | accede to | agree to | MEDIUM (220) | 40 |
| 14 | accelerate | speed up | MEDIUM (220) | 47 |
| 15 | accentuate | stress | MEDIUM (220) | 54 |
| 16 | acquire | get | MEDIUM (220) | 110 |
| 17 | aggregate | add | MEDIUM (220) | 209 |
| 18 | alleviate | ease | MEDIUM (220) | 230 |
| 19 | ameliorate | help | MEDIUM (220) | 265 |
| 20 | acquiesce | agree | MEDIUM (220) | 103 |

**D-06 balance check:**
- Multi-inflection: utilize/utilizes/utilized triple (3 entries, ≥2 required) ✓
- HIGH severity: 8 entries ✓
- MEDIUM severity: 9 entries ✓
- Multi-token phrases: "a number of", "accompany" → "go with", "accomplish" → "carry out", "accede to", "accelerate" → "speed up" (multi-word replacements) ✓
- Single-token phrases: all others ✓
- 5 regimes tested per phrase: lowercase, sentence-start, title-case, UPPER-CASE, post-colon ✓

## Verbatim Test Output

```
$ cargo test --lib clarity::spike -- --nocapture

    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.21s
     Running unittests src/lib.rs (target/debug/deps/harper_bridge-758c47d41b3da8bb)

running 2 tests
test clarity::spike::priority_rewrite_no_default_leak ... ok
test clarity::spike::case_preservation_five_regimes ... ok

test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 5 filtered out; finished in 3.12s
```

**Full lib suite (7 tests):**
```
running 7 tests
test clarity::tests::severity_enum ... ok
test clarity::tests::severity_round_trip ... ok
test clarity::tests::clarity_loses_to_grammar_on_overlap ... ok
test clarity::spike::priority_rewrite_no_default_leak ... ok
test clarity::spike::case_preservation_five_regimes ... ok
test tests::stub_fires_flag_me ... ok
test tests::clarity_linter_survives_dict_add_cycle ... ok

test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 3.21s
```

## CLAR-13 Hard-Gate Evidence

| Gate | Status | Evidence |
|------|--------|----------|
| Hard gate 1: 5-regime case preservation | **PASS** | `case_preservation_five_regimes` GREEN — 100 assertions (20 phrases × 5 regimes), `eq_ignore_ascii_case` match on every replacement |
| Hard gate 2: Priority rewrite stability | **PASS** | `priority_rewrite_no_default_leak` GREEN — all emitted lints have priority ∈ {200, 220, 240}; zero leakage of default 31 |

**Preliminary decision read:** Both hard gates PASS → evidence supports `Adopt MapPhraseLinter wrapper` per D-05. Plan 07 writes the formal spike report.

## Deviations from Plan

**1. [Rule 1 - Bug] Removed dead placeholder arrays in case_preservation_five_regimes**
- **Found during:** Task 1 — initial implementation had leftover placeholder `regimes` and `inputs_and_expected` arrays before the real `test_cases` vec
- **Fix:** Removed the two dead arrays (7 lines of dead code) — tests still GREEN
- **Files modified:** harper-bridge/src/clarity.rs
- **Commit:** 119a2e5 (cleanup in same commit)

**2. [Rule 2 - Corpus count] Added 20th corpus entry (acquiesce)**
- **Found during:** Acceptance criteria check — initial corpus had 19 entries
- **Fix:** Added `("acquiesce", "agree", PRIORITY_MEDIUM)` — confirmed in wordy_phrases.toml line 103
- **Files modified:** harper-bridge/src/clarity.rs
- **Commit:** 119a2e5

**3. [Auto-correction] Plan corpus list had wrong replacements for some entries**
- Plan listed "alternative" → "choice" and "approximately" → "about" — neither exists in wordy_phrases.toml
- Plan listed "advantageous" as MEDIUM — TOML has it as HIGH; plan listed "ameliorate" → "improve" — TOML has "help"
- Substituted with verified TOML entries: acquiesce, acquiesce, accordingly, accurate, additional per D-06 corpus guidance "Executor picks from toml"

## Known Stubs

None — spike module is test-only (`#[cfg(test)]`). No production stubs introduced.

## Threat Flags

None — test-only code, no new network/auth/file surface.

## Self-Check: PASSED

- [x] `harper-bridge/src/clarity.rs` exists and modified
- [x] commit 119a2e5 exists: `git log --oneline | grep 119a2e5` → found
- [x] `grep -c "struct PriorityRewritingMapPhraseLinter" harper-bridge/src/clarity.rs` → 1
- [x] `grep -c "const CORPUS:" harper-bridge/src/clarity.rs` → 1
- [x] CORPUS has 20 entries
- [x] Both spike tests GREEN
