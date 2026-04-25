# Phase 10: Matcher Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-25
**Phase:** 10-matcher-implementation
**Areas discussed:** Phrase seed source, Stub removal, Dialect filter, PhraseEntry struct, tr_TR CI, Proper-noun guard, Wrapper struct name

---

## Phrase seed source

| Option | Description | Selected |
|--------|-------------|----------|
| Promote spike CORPUS const | Move 20-entry CORPUS array from `#[cfg(test)] mod spike` to module-level const in clarity.rs. Real wrapper consumes it. Phase 11 swaps source from const-array to `include_str!`-parsed `Vec<PhraseEntry>`. Zero TOML parsing in Phase 10. | ✓ |
| Partial TOML parse (20-entry slice) | Phase 10 introduces TOML parser + PhraseEntry struct; reads first ~20 entries from wordy_phrases.toml at HarperChecker::new(). Phase 11 only adds OnceLock + auto-fixture harness. | |
| Hardcoded 20-entry Vec<PhraseEntry> | Define PhraseEntry struct in Phase 10 + hardcode 20 entries with dialect tags. Phase 11 replaces hardcoded Vec with TOML parse. | |

**User's choice:** Promote spike CORPUS const (Recommended)
**Notes:** Keeps Phase 10 scope tight; defers parser to where its consumer (OnceLock cache + auto-fixture harness) lives in Phase 11.

---

## Stub linter removal

| Option | Description | Selected |
|--------|-------------|----------|
| Delete in Phase 10 | Phase 10 atomically replaces `WordyPhrasesStubLinter` with `WordyPhrasesLinter` in `build_lint_group`. Stub + FLAG_ME tests removed. CLAUDE.md standalone-app: clean replace, no coexistence. Real test corpus (CLAR-01 hand-picked 20) supersedes FLAG_ME. | ✓ |
| Keep stub side-by-side until Phase 11 | Leave stub registered alongside new linter through Phase 10. Phase 11 deletes stub when full dataset wired. | |
| Delete stub but keep FLAG_ME test against real linter | Add FLAG_ME→FLAGGED to CORPUS as synthetic entry. Preserves end-to-end FFI smoke test through Phase 11. | |

**User's choice:** Delete in Phase 10 (Recommended)
**Notes:** Amends Phase 9 D-21 which scheduled stub removal for Phase 11; Phase 10 ships the real matcher so stub becomes dead code one phase earlier. Per CLAUDE.md standalone-app philosophy.

---

## Dialect filter

| Option | Description | Selected |
|--------|-------------|----------|
| Build-time in build_lint_group | Filter entries in build_lint_group(merged, dialect): drop entries where user dialect ∉ entry.dialects. Wrapper constructed only with applicable entries. Simpler, faster, already triggers rebuild on dialect change because `add_to_dictionary` calls build_lint_group. | ✓ |
| Per-lint() emission-time filter | Wrapper holds all entries + user dialect. lint() loop checks entry.dialects against current dialect before push. Adds branch per emission. | |
| Hybrid — build-time + recheck on dialect change | Build-time filter (fast path). Settings dialect change forces build_lint_group rebuild. Phase 10 ships build-time; Phase 12 wires rebuild trigger. | |

**User's choice:** Build-time in build_lint_group (Recommended)
**Notes:** Settings-driven dialect change → rebuild path is Phase 12 concern. Phase 10 verification: two HarperChecker instances at different dialects.

---

## PhraseEntry struct

| Option | Description | Selected |
|--------|-------------|----------|
| Define in Phase 10 | Phase 10 introduces `struct PhraseEntry { phrase, replacement, severity, dialects: Option<&'static [Dialect]> }` in clarity.rs. CORPUS becomes `&[PhraseEntry]`. Phase 11 swaps `&'static` → owned types for TOML-parsed entries. | ✓ |
| Defer to Phase 11 | Phase 10 keeps spike's tuple. Phase 11 introduces struct alongside TOML parser. Risk: dialect filter needs ad-hoc 4-tuple + later refactor. | |
| Phase 10 defines struct, but skip dialects field | PhraseEntry without dialects field in Phase 10. Hardcoded CORPUS has no dialect tags. Defer dialect filter to Phase 11. | |

**User's choice:** Define in Phase 10 (Recommended)
**Notes:** Avoids tuple-vs-struct churn between phases. Signature of `WordyPhrasesLinter::new(&[PhraseEntry])` stays stable across phases.

---

## tr_TR CI

| Option | Description | Selected |
|--------|-------------|----------|
| Rust unit test with locale env override | `#[test]` in clarity.rs sets `LANG`/`LC_ALL` to tr_TR.UTF-8 via `std::env::set_var` in test body, exercises CORPUS uppercase regime, asserts `replace_with_match_case` stays ASCII-correct. Pure cargo test — no CI matrix file. | ✓ |
| Inline test using to_uppercase_with_locale-style helper | Test calls Rust's locale-agnostic `char::to_uppercase`. No env hack. But doesn't actually exercise tr_TR — weaker coverage. | |
| Cargo test wrapper script (test-tr-locale.sh) | harper-bridge/scripts/test-tr-locale.sh runs cargo test with LANG=tr_TR.UTF-8 prefixed. Documented in README. | |

**User's choice:** Rust unit test with locale env override (Recommended)
**Notes:** CLAUDE.md compatible (no GHA references in source). ROADMAP SC-6 wording "CI matrix" reframed as "test suite covers tr_TR locale."

---

## Proper-noun

| Option | Description | Selected |
|--------|-------------|----------|
| Rely on MapPhraseLinter native behavior | `MapPhraseLinter::new_fixed_phrase` tokenizes inputs identically to document parser; 'iPhone' is one Word token, won't match CORPUS phrase 'iphone'. Verify with single fixture test. No code guard — contract-test the framework. | ✓ |
| Explicit guard — skip if Word token has internal capitals | In wrapper, before push, check Unicode-correct mixed-case pattern. Skip emission. Defensive. Adds branch per emission. | |
| Dataset-level NonFlags entry only | Add 'iPhone is great' to NonFlagsFixtures/ in Phase 13. Phase 10 has no code guard or test. Risk: violates CLAR-03 acceptance. | |

**User's choice:** Rely on MapPhraseLinter native behavior (Recommended)
**Notes:** Single iPhone fixture test contracts the tokenizer behavior we depend on.

---

## Struct name

| Option | Description | Selected |
|--------|-------------|----------|
| Rename to WordyPhrasesLinter | Matches CLAR-12 / REQUIREMENTS.md / Phase 9 D-18 naming. Swaps cleanly into build_lint_group registration. Hides MapPhraseLinter wrapper detail behind domain name. | ✓ |
| Keep PriorityRewritingMapPhraseLinter | Spike name stays. Honest about implementation. Phase 9 spike report references this name. Risk: name leaks impl detail. | |
| Rename to ClarityLinter | Generic, future-proof for v2 additions. Risk: misleading in Phase 10 (only wordy-phrases scope); CLAR-07 rule key is "WordyPhrases" — mismatch. | |

**User's choice:** Rename to WordyPhrasesLinter (Recommended)
**Notes:** Domain name reads naturally. `group.add("WordyPhrases", WordyPhrasesLinter::new(...))`.

---

## Claude's Discretion

- Exact synthetic dialect-tagged CORPUS entry per D-04 (any low-risk universal phrase tagged American).
- Exact CORPUS phrase + carrier sentence for D-11 word-boundary regression.
- `serial_test` dep adoption vs manual env reset for D-08 — depends on harper-bridge/Cargo.toml dev-deps audit.
- Whether `WordyPhrasesLinter::lint` deduplicates overlapping CORPUS entries before priority rewrite. Likely unnecessary (LintGroup-level `remove_overlaps` runs after).
- Order of CORPUS entries in the const-slice (alphabetical / severity / phase-9-order). Functional no-op.

## Deferred Ideas

- Per-rule-category toggles beyond WordyPhrases master key (Phase 12 + v2).
- OnceLock-cached TOML parse of full ~676-entry dataset (Phase 11).
- Auto-generated +/- fixture harness (Phase 11 CLAR-20).
- Snapshot-diff regression test on 5 well-known entries (Phase 11 CLAR-20).
- Settings-driven dialect change → build_lint_group rebuild trigger (Phase 12).
- Severity threshold + opinionated-Low gating (Phase 12).
- NonFlagsFixtures/ ≥100 sentences (Phase 13 CLAR-21).
- `MapPhraseLinter::new_fixed_phrases` (plural) adoption (deferred indefinitely).
- harper-core fork (rejected per Phase 9 D-05).
- Per-phrase explanation text polish (Phase 12 or v2).
- UK/AU dataset variants (CLAR-V2-07).
