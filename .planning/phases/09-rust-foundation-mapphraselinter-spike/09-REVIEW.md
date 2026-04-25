---
phase: 09-rust-foundation-mapphraselinter-spike
reviewed: 2026-04-24T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - harper-bridge/src/clarity.rs
  - harper-bridge/src/lib.rs
  - OpenGram/CheckEngine/Suggestion.swift
  - OpenGramTests/ClarityFFITests.swift
  - OpenGramTests/SuggestionTests.swift
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-04-24
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 9 adds the Severity FFI surface (Rust enum + priority constants), `WordyPhrasesStubLinter`, `MapPhraseLinter` spike module (test-only), and `Suggestion.severity` field in Swift. The core routing logic, priority semantics, and FFI surface are correct. Two warnings and two info items found; no critical issues.

## Warnings

### WR-01: Built-in harper-core Style lints silently route to `GrammarPunctuation` — undocumented, fragile

**File:** `harper-bridge/src/lib.rs:104-108`

**Issue:** harper-core 2.0.0 has multiple built-in linters that emit `LintKind::Style` with `priority = 31` (`OxfordComma`, `NoOxfordComma`, `ThriveOn`, `WouldNeverHave`, `MoreAdjective`, `Addicting`, `SomewhatSomething`, `PhraseSetCorrections`, etc.). The routing match:

```rust
(LintKind::Style, Some(sev)) => (SuggestionCategory::Clarity, Some(sev)),
_ => (SuggestionCategory::GrammarPunctuation, None),
```

correctly routes them to `GrammarPunctuation` because `severity_from_priority(31)` returns `None`. This is the right behavior, but it is purely accidental: no comment, no assertion, no test pins this invariant. If a future change shifts any built-in priority into `{200, 220, 240}` (e.g., a harper-core upgrade), those lints silently mis-route to `.clarity`.

**Fix:** Add a comment making the invariant explicit, and add a unit test that feeds a known built-in Style lint (e.g., trigger an Oxford comma lint) and asserts `category == GrammarPunctuation`:

```rust
// Safety: harper-core built-in Style lints use priority=31, which is NOT in
// {PRIORITY_HIGH, PRIORITY_MEDIUM, PRIORITY_LOW}. severity_from_priority(31) == None,
// so they fall through to GrammarPunctuation. If a harper-core upgrade changes
// a built-in Style lint's priority to 200/220/240, this match will mis-route it.
// Pin that assumption with a test if upgrading harper-core.
(LintKind::Style, Some(sev)) => (SuggestionCategory::Clarity, Some(sev)),
_ => (SuggestionCategory::GrammarPunctuation, None),
```

---

### WR-02: `add_to_dictionary` allows duplicate words — list grows unboundedly

**File:** `harper-bridge/src/lib.rs:133-134`

**Issue:** `add_to_dictionary` calls `inner.user_words.push(word)` with no dedup check. Calling it twice with the same word stores the word twice in `user_words`. On each call `build_merged_dict` rebuilds from `user_dict` (which already has the word), so the dictionary is correct, but `user_words` (returned to Swift for persistence) accumulates duplicates. If Swift persists and later re-loads this list, the checker initializes with N copies of the word.

**Fix:**

```rust
pub fn add_to_dictionary(&self, word: String) -> Vec<String> {
    let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
    // Guard: no-op if word already present
    if inner.user_words.contains(&word) {
        return inner.user_words.clone();
    }
    // ... rest unchanged
```

## Info

### IN-01: `guard offset >= 0` is always true — dead branch

**File:** `OpenGram/CheckEngine/Suggestion.swift:11`

**Issue:** `offset` is `Int`, but its only callers convert from `UInt32` (`Int(raw.startChar)`). The guard `offset >= 0` can never be false. Dead code.

**Fix:** Remove the guard or change parameter type to `UInt` to make the invariant structural:

```swift
// Option A: remove the check
func indexFromCharOffset(_ offset: Int) -> String.Index? {
    let scalars = self.unicodeScalars
    guard offset <= scalars.count else { return nil }
    return scalars.index(scalars.startIndex, offsetBy: offset)
}
```

---

### IN-02: `case_preservation_five_regimes` assertion accepts any case-insensitive match across all corpus phrases — weak signal for failing cases

**File:** `harper-bridge/src/clarity.rs:315-324`

**Issue:** The filter at line 313 (`r.eq_ignore_ascii_case(expected)`) searches across all lints emitted by the full corpus linter, not just the lint for the current `phrase`. If phrase A and phrase B both appear in the input sentence and phrase B's replacement happens to match phrase A's expected string, the assertion passes falsely. The current corpus is small enough that false positives are unlikely, but the test design is imprecise.

**Fix:** Build a single-entry linter per phrase instead of running all 20 corpus entries and filtering globally:

```rust
for (phrase, replacement, prio) in CORPUS {
    let mut single = PriorityRewritingMapPhraseLinter::new(&[(*phrase, *replacement, *prio)]);
    // ... run test_cases against `single`
}
```

---

_Reviewed: 2026-04-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
