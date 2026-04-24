---
phase: 09-rust-foundation-mapphraselinter-spike
plan: 04
subsystem: rust
tags: [harper-core, clarity, wordy-phrases, lint-group, uniffi]

requires:
  - phase: 09-rust-foundation-mapphraselinter-spike/plan-03
    provides: "WordyPhrasesStubLinter skeleton + build_lint_group helper; stub registered under key WordyPhrases"
  - phase: 09-rust-foundation-mapphraselinter-spike/plan-02
    provides: "Severity FFI enum, priority constants (200/220/240), severity_from_priority, LintKind::Style→Clarity routing"

provides:
  - "WordyPhrasesStubLinter.lint body: 3-token window scan for FLAG+Underscore+ME sentinel, emits Lint(Style, 220, ReplaceWith(FLAGGED))"
  - "build_lint_group enables WordyPhrases rule via FlatConfig.set_rule_enabled (rules added via add() default to disabled)"
  - "stub_fires_flag_me Rust test GREEN: CLAR-11 end-to-end round-trip proved"
  - "clarity_linter_survives_dict_add_cycle Rust test GREEN: CLAR-12 invariant confirmed"

affects: [09-05, 09-06, matcher-implementation]

tech-stack:
  added: []
  patterns:
    - "3-token window match (Word + Punctuation::Underscore + Word) for multi-token phrases spanning punctuation"
    - "FlatConfig requires explicit set_rule_enabled after LintGroup.add() — unknown keys default to false"
    - "Token API: document.tokens() → impl Iterator<Item = &Token>; span.get_content(source) → &[char]; TokenKind::Word(_)"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs
    - harper-bridge/src/lib.rs

key-decisions:
  - "FLAG_ME tokenizes as 3 tokens (Word(FLAG) + Punctuation(Underscore) + Word(ME)) — matched via windows(3) not single-token slice compare"
  - "FlatConfig.is_rule_enabled returns unwrap_or(false) — rules added with add() are disabled until explicitly enabled; added set_rule_enabled call in build_lint_group"
  - "Span covers full 3-token range [0..7) so overlap resolution (plan 02 clarity_loses_to_grammar test) still applies correctly"

patterns-established:
  - "After LintGroup.add(key, linter), call group.config.set_rule_enabled(key, true) or the linter silently produces no output"

requirements-completed: [CLAR-11, CLAR-12]

duration: 12min
completed: 2026-04-24
---

# Phase 9 Plan 04: WordyPhrasesStubLinter Match Logic Summary

**3-token window scan (FLAG + Underscore + ME) fills lint body; FlatConfig rule-enable fix unblocks LintGroup routing; CLAR-11 + CLAR-12 Rust tests GREEN.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-24T23:15:55Z
- **Completed:** 2026-04-24T23:28:00Z
- **Tasks:** 1 (TDD)
- **Files modified:** 2

## Accomplishments

- `WordyPhrasesStubLinter.lint` scans tokens via `windows(3)`, matches FLAG+Underscore+ME, emits `Lint { span: [0..7), lint_kind: LintKind::Style, priority: PRIORITY_MEDIUM=220, suggestions: [ReplaceWith("FLAGGED")] }`
- `build_lint_group` calls `group.config.set_rule_enabled("WordyPhrases", true)` — required because `FlatConfig::is_rule_enabled` returns `false` for any key not explicitly set
- `stub_fires_flag_me` GREEN: `category=Clarity`, `severity=Some(Medium)`, `priority=220`, `primary_replacement=Some("FLAGGED")`
- `clarity_linter_survives_dict_add_cycle` GREEN: stub fires before and after `add_to_dictionary` rebuilds LintGroup
- Spike tests (`case_preservation_five_regimes`, `priority_rewrite_no_default_leak`) correctly remain RED — plan 06 fills

## Token API Used

`span.get_content(source)` — method exists on `Span<T>` at `harper-core 2.0.0/src/span.rs:114`. Returns `&[T]`, panics on invalid span. Used for direct char slice comparison against `[char; 4]` / `[char; 2]` arrays.

## Test Output

```
running 7 tests
test clarity::tests::severity_round_trip ... ok
test clarity::tests::severity_enum ... ok
test clarity::spike::case_preservation_five_regimes ... FAILED  (expected — plan 06)
test clarity::spike::priority_rewrite_no_default_leak ... FAILED  (expected — plan 06)
test clarity::tests::clarity_loses_to_grammar_on_overlap ... ok
test tests::stub_fires_flag_me ... ok
test tests::clarity_linter_survives_dict_add_cycle ... ok
test result: FAILED. 5 passed; 2 failed
```

## Task Commits

1. **Task 1: WordyPhrasesStubLinter.lint body + FlatConfig rule enable** - `7d8b51c` (feat)

## Files Created/Modified

- `harper-bridge/src/clarity.rs` — lint body: imports (`TokenKind`, `LintKind`, `Suggestion`, `Punctuation`), 3-token window scan impl
- `harper-bridge/src/lib.rs` — `build_lint_group`: added `set_rule_enabled("WordyPhrases", true)` after `add()`

## Decisions Made

- Used `windows(3)` over the full token vec rather than a stateful 3-token cursor — simpler, no allocation difference at this scale
- Span covers all 3 tokens (`window[0].span.start..window[2].span.end`) so replacement covers the full `FLAG_ME` text including underscore

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FLAG_ME tokenizes as 3 tokens, not 1**
- **Found during:** Task 1 (initial implementation)
- **Issue:** Plan specified matching a single 7-char token `['F','L','A','G','_','M','E']`. Harper tokenizes `FLAG_ME` as `Word(FLAG)` + `Punctuation(Underscore)` + `Word(ME)` — the single-token match produced 0 lints.
- **Fix:** Rewrote lint body to use `windows(3)` and match the 3-token sequence.
- **Files modified:** harper-bridge/src/clarity.rs
- **Verification:** Direct stub test emits 1 lint; confirmed via `debug_raw_lints_flag_me` temporary test (removed before commit).
- **Committed in:** 7d8b51c

**2. [Rule 1 - Bug] FlatConfig disables rules not explicitly enabled**
- **Found during:** Task 1 (test still failing after lint body was correct)
- **Issue:** `LintGroup::organized_lints` gates each linter behind `is_rule_enabled(key)`, which returns `unwrap_or(false)`. Rules added via `add()` are never auto-enabled — they silently produce no output until enabled.
- **Fix:** Added `group.config.set_rule_enabled("WordyPhrases", true)` in `build_lint_group` in lib.rs.
- **Files modified:** harper-bridge/src/lib.rs
- **Verification:** `stub_fires_flag_me` and `clarity_linter_survives_dict_add_cycle` both GREEN.
- **Committed in:** 7d8b51c

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs in plan's assumed API behavior)
**Impact on plan:** Both fixes necessary for correctness. No scope change; single commit covers all.

## Issues Encountered

None beyond the two auto-fixed bugs above.

## Next Phase Readiness

- Plan 05 (Swift ClarityFFITests.stubRoundTrip RED→GREEN): stub now emits correct data through FFI; Swift severity field wiring is all that remains
- Plan 06 (spike tests + MapPhraseLinter): lint body pattern established; window(3) approach generalizes to phrase matching

---
*Phase: 09-rust-foundation-mapphraselinter-spike*
*Completed: 2026-04-24*
