---
phase: 10-matcher-implementation
reviewed: 2026-04-24T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - harper-bridge/src/clarity.rs
  - harper-bridge/src/lib.rs
  - OpenGramTests/ClarityFFITests.swift
findings:
  critical: 0
  warning: 4
  info: 8
  total: 12
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-04-24
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Production `WordyPhrasesLinter` swap-in clean. Dialect filter correct via `build_lint_group` partition before linter construction. CORPUS-driven case-preservation/proper-noun/word-boundary tests solid. Four warnings: env-var mutation in tr_TR test races under parallel tests + breaks under Rust 2024 edition; static replacement string in `MapPhraseLinter` message diverges from case-adjusted suggestion; `unsafe impl Send/Sync` rationale incomplete; `set_rule_enabled` silently swallows bad keys. Info items cover duplication, test-fixture coupling, Swift test thinness, temp-dir leak.

## Warnings

### WR-01: tr_TR locale test mutates process-global env unsafely

**File:** `harper-bridge/src/clarity.rs:313-339`
**Issue:** `std::env::set_var` is process-global; `cargo test` runs tests in parallel by default so concurrent tests calling `std::env::var`/`set_var` race. Panic between set and reset leaks `tr_TR.UTF-8` to other tests. Rust 1.85 + 2024 edition marks `set_var` `unsafe` — code will fail to compile under 2024 edition without `unsafe` block. Test also asserts a property already guaranteed by stdlib (`char::to_uppercase`/`to_lowercase` use Unicode tables, never `LANG`/`LC_ALL`).
**Fix:** Drop env-var manipulation entirely — assertion holds without it. If retaining, gate test with `serial_test::serial` and wrap in `unsafe { ... }`:
```rust
// Option A: drop env mutation, keep ASCII-correctness assertion
#[test]
fn case_preservation_ascii_only() {
    let merged = make_merged_dict();
    let mut linter = WordyPhrasesLinter::new(CORPUS);
    for entry in CORPUS {
        let input = format!("WE MUST {} IT.", entry.phrase.to_uppercase());
        let doc = Document::new(&input, &PlainEnglish, merged.as_ref());
        for lint in linter.lint(&doc) {
            if let Some(rep) = primary_replacement(&lint) {
                assert!(rep.chars().all(|c| !c.is_alphabetic() || c.is_ascii()));
            }
        }
    }
}
```

### WR-02: MapPhraseLinter message hard-codes lowercase phrase casing

**File:** `harper-bridge/src/clarity.rs:96-99`
**Issue:** `format!("Consider '{}' for '{}'", entry.replacement, entry.phrase)` is built at constructor time with the corpus' lowercase canonical form. When user types `"Utilize"` or `"UTILIZE"`, Harper's `replace_with_match_case` adjusts the `Suggestion::ReplaceWith` chars but the `lint.message` string still reads `"Consider 'use' for 'utilize'"` — UI may show mismatched casing between the message and the suggestion offered.
**Fix:** Either drop the phrase from the message (`format!("Consider '{}'", entry.replacement)`) or override `lint.message` per-match in `WordyPhrasesLinter::lint` using the document slice at `lint.span`.

### WR-03: unsafe impl Send/Sync rationale incomplete

**File:** `harper-bridge/src/lib.rs:50-55`
**Issue:** Comment states "Swift-side actor provides single-threaded contract" — but Rust cannot rely on caller discipline. `Mutex<T>: Send` requires `T: Send`; manually impl'ing `Send` for a struct containing `Lrc` (non-`Send` `Rc`) bypasses the type system. If UniFFI ever dispatches a `&self` method on a different thread (future async exports, runtime changes), `Lrc::clone` cross-thread is UB.
**Fix:** Verify `Lrc` is `Rc` not `Arc` (it is — `harper_core` uses single-threaded ref-counts internally). Document precisely:
```rust
// Safety: HarperCheckerInner contains Lrc (single-threaded Rc) via LintGroup.
// UniFFI dispatches sync `&self` exports on the caller's thread; the Mutex
// serializes access. No Lrc clone ever crosses threads because:
// (1) all `&mut self` work happens inside the lock, on one thread at a time;
// (2) we never spawn or send `inner` across threads.
// If we add async exports or move work to a thread pool, reassess.
unsafe impl Send for HarperCheckerInner {}
unsafe impl Sync for HarperCheckerInner {}
```

### WR-04: set_rule_enabled silently swallows invalid keys

**File:** `harper-bridge/src/lib.rs:144-147`
**Issue:** Accepts arbitrary `rule_key: String`; if the key doesn't match any registered rule, the call is a silent no-op. Swift caller has no feedback that the toggle had no effect — surface area for typo bugs (e.g., `"WordyPhrase"` vs `"WordyPhrases"`).
**Fix:** Return `bool` indicating whether the key matched, or panic-debug-assert in dev builds:
```rust
pub fn set_rule_enabled(&self, rule_key: String, enabled: bool) -> bool {
    let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
    // FlatConfig::set_rule_enabled returns () today; check existence first.
    let known = inner.linter.config.is_rule_enabled(&rule_key).is_some();
    if known { inner.linter.config.set_rule_enabled(&rule_key, enabled); }
    known
}
```

## Info

### IN-01: Duplicated linter description string

**File:** `harper-bridge/src/clarity.rs:97, 120`
**Issue:** Description `"Wordy-phrase clarity linter — flags wordy phrases with simpler replacements per the curated corpus."` written verbatim in two places.
**Fix:** Extract `const DESCRIPTION: &str = "..."` and reference from both sites.

### IN-02: forthwith fixture entry coupled to test fixture in production CORPUS

**File:** `harper-bridge/src/clarity.rs:78-81`
**Issue:** Production `CORPUS` contains a synthetic test-only entry (`forthwith` with American-only dialect tag) whose comment notes it must not collide with the future TOML loader. Risk of accidental removal during refactor; production users see "forthwith → at once" suggestions.
**Fix:** Move to a separate `pub(crate) const TEST_CORPUS_DIALECT_FIXTURES: &[PhraseEntry]` and have `dialect_filter_drops_non_matching` use a constructor that takes both. Or feature-flag the entry under `#[cfg(any(test, feature = "test-fixtures"))]`.

### IN-03: title_case/sentence_start helpers duplicate Harper utilities

**File:** `harper-bridge/src/clarity.rs:139-158`
**Issue:** Manual char-iteration helpers for case conversion are test-only but reinvent logic `harper_core::replace_with_match_case` already implements.
**Fix:** Acceptable as test helpers; consolidate if Harper exposes case-folding publicly.

### IN-04: Redundant clone in HarperChecker::new

**File:** `harper-bridge/src/lib.rs:67-78`
**Issue:** `user_words.clone()` at line 78 clones the input `Vec<String>` for storage; constructor already owns the moved input.
**Fix:** Use `user_words` directly for storage; clone only at return sites.

### IN-05: Unused PhraseEntry import in lib.rs

**File:** `harper-bridge/src/lib.rs:7`
**Issue:** `PhraseEntry` imported but only referenced inside the `Vec<PhraseEntry>` annotation in `build_lint_group`.
**Fix:** Elide the annotation — `let applicable: Vec<_> = CORPUS.iter().filter(...).copied().collect();` — and drop `PhraseEntry` from the import.

### IN-06: Temp dir leaked by ClarityFFITests

**File:** `OpenGramTests/ClarityFFITests.swift:9-11`
**Issue:** `makeService` creates `temporaryDirectory.appendingPathComponent(UUID().uuidString)` per test invocation and never deletes it. Accumulates over many test runs.
**Fix:** Capture the URL and clean up in test teardown:
```swift
private func makeService(dialect: String = "US") -> (HarperService, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = DictionaryStore(directoryURL: url)
    return (HarperService(dictionaryStore: store, dialect: dialect), url)
}
// in test: defer { try? FileManager.default.removeItem(at: url) }
```

### IN-07: Swift FFI test coverage thin

**File:** `OpenGramTests/ClarityFFITests.swift`
**Issue:** Single test covers one CORPUS entry at one severity. Rust side has 3 integration + 7 unit tests; Swift side has 1. Missing FFI-level coverage of: `.medium`/`.low` severity round-trip, GB-dialect filter dropping `forthwith`, `severity == nil` for spelling/grammar (D-10 invariant), `category == .grammarPunctuation` routing.
**Fix:** Add tests for each missing axis. Minimum: dialect filter + severity-medium round-trip + spelling-has-nil-severity.

### IN-08: Comment couples reviewer to Harper internals

**File:** `harper-bridge/src/lib.rs:161-162`
**Issue:** Comment states `"Rules added via add() default to disabled in FlatConfig (unwrap_or(false))"` — accurate today but a future Harper version could flip the default; comment then misleads.
**Fix:** Reframe as defensive: `// Defensive: explicit enable is required regardless of Harper's default.`

---

_Reviewed: 2026-04-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
