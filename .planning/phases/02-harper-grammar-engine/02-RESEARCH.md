# Phase 2: Harper Grammar Engine - Research

**Researched:** 2026-04-13
**Domain:** Rust/Swift FFI (UniFFI), harper-core v2.0.0, Unicode index conversion, Swift 6 concurrency
**Confidence:** HIGH (core API verified via docs.rs; build pipeline MEDIUM due to no Rust toolchain installed yet)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Grammarly-style replacements — best replacement shown prominently, but all Harper replacements carried in the data model so Phase 3 can decide presentation.
- **D-02:** No rule ID per suggestion for v1. Category-only. Rule-level toggling deferred to v2.
- **D-03:** Two visual category buckets: **spelling (red)** and **grammar+punctuation (blue)**. Overrides REQUIREMENTS.md UI-02's three-color scheme. All non-spelling LintKind variants (Repetition, WordChoice, Formatting, Miscellaneous, Grammar, Punctuation, Agreement, etc.) roll up into the grammar+punctuation bucket.
- **D-04:** Global dictionary shared across all dialects. No per-dialect dictionaries.
- **D-05:** "Add to Dictionary" exposed as an API in Phase 2; UI wired in Phase 3 (popover) and Phase 5 (settings).
- **D-06:** Plain text file, one word per line: `~/Library/Application Support/OpenGram/dictionary.txt`. Matches harper-ls's UserDictionary format.
- **D-07:** Dialect and rule category changes take effect on the **next hotkey trigger**. Changes saved to disk immediately; no re-check of current suggestions.
- **D-08:** Changing dialect has no effect on the custom dictionary. Dictionary is fully independent of dialect selection.
- **D-09:** No text length limit. For text above a performance threshold, run Harper on a background queue. Menu bar already shows "checking" state.
- **D-10:** Trust Harper's PlainEnglish parser for non-prose filtering (URLs, code, file paths). No Swift-side pre-filtering.
- **D-11:** Phase 2 is pipeline-only — no user-visible output. Produces a `[Suggestion]` array consumed by Phase 3. AppDelegate logs results to console.

### Claude's Discretion

- UniFFI bridge crate structure and API surface design
- xcframework build pipeline (build-harper.sh, lipo, uniffi-bindgen)
- Unicode char offset → Swift String.Index conversion implementation
- HarperChecker lifecycle (create new vs reconfigure on config change)
- Background queue strategy for long text
- Swift-side Suggestion model struct design (beyond the decisions above)
- Test strategy for Unicode edge cases (emoji, CJK, accented chars, combined marks)

### Deferred Ideas (OUT OF SCOPE)

- Per-rule toggling from suggestion UI ("Disable this rule" action in popover)
- Non-prose pre-filtering — Swift-side URL/code/path stripping before Harper
- Dialect-aware dictionary warnings
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GRAM-01 | Harper checks text for spelling errors via UniFFI bridge to harper-core 2.0.0 | UniFFI bridge design; FstDictionary + MutableDictionary composition for spell check |
| GRAM-02 | Harper checks text for grammar errors (subject-verb agreement, articles, repeated words) | LintGroup covers these; LintKind.Grammar, .Agreement, .Repetition, .Typo |
| GRAM-03 | Harper checks text for punctuation errors (apostrophes, missing periods, commas, spacing) | LintKind.Punctuation, .Formatting in LintGroup |
| GRAM-04 | Harper returns results in < 50ms for typical text selections | Harper benchmarks < 10ms for paragraphs; background GCD queue for large text |
| GRAM-05 | Unicode offset conversion correctly maps Harper char indices to Swift String.Index | Harper uses Span<char> (Unicode scalar indices), NOT byte offsets — maps cleanly to String.unicodeScalars view |
| GRAM-06 | User can add words to a custom dictionary to suppress false positives | MutableDictionary + MergedDictionary with FstDictionary; persist to dictionary.txt |
| GRAM-07 | Custom dictionary persists across app restarts | Plain text file in Application Support; load on HarperChecker init |
| GRAM-08 | User can select English dialect (American, British, Canadian, Australian, Indian) | Dialect enum with 5 variants; reconstruct LintGroup on dialect change |
| GRAM-09 | User can enable/disable individual Harper rule categories in settings | FlatConfig.set_rule_enabled(key, val); expose category-level toggles via bridge |
</phase_requirements>

---

## Summary

Phase 2 builds the complete Harper integration pipeline: Rust bridge crate, xcframework build script, Swift service layer, custom dictionary persistence, and config propagation. The output is a `[Suggestion]` array available to AppDelegate after hotkey fires — no UI.

**Critical API correction from prior research:** Harper v2.0.0 uses `Span<char>` with **Unicode scalar (char) indices**, not UTF-8 byte offsets. The integration document's `indexFromByteOffset()` function is incorrect for the current API. Instead, map Harper's char indices into Swift's `String.unicodeScalars` view, which is a 1:1 correspondence with Rust's `char` type (both are Unicode scalar values). This eliminates the byte-offset edge case complexity with multi-byte sequences, but introduces a different concern: emoji composed of multiple Unicode scalars (e.g., family emoji 👨‍👩‍👦 uses zero-width joiners) are multiple `char` values in Rust but one `Character` in Swift. The span will cover multiple scalars; the Swift range must span those scalars correctly.

**Rust toolchain not installed.** `rustup`, `cargo`, and `rustc` are all absent. Installation is a mandatory Wave 0 task. Homebrew (`brew install rustup`) is available and is the cleanest install path on this machine.

**Primary recommendation:** Build a thin (~120 line) `harper-bridge` Rust crate with UniFFI proc macros. The `LintGroup::new_curated(dict, dialect)` API is the stable entry point. Use `MergedDictionary<FstDictionary, MutableDictionary>` to layer user words over the built-in dictionary without rebuilding it. Ship a `build-harper.sh` that produces the xcframework; invoke it as an Xcode Run Script Build Phase.

---

## Project Constraints (from CLAUDE.md)

- **Language:** Swift 6.x (strict concurrency required) + Rust 1.85+
- **harper-core:** Pin to 2.0.0 exactly — API stability is not guaranteed per Harper docs
- **UniFFI:** 0.31.0 — must match exactly between Cargo.toml and uniffi-bindgen installation
- **Testing:** Swift Testing (`@Test` / `#expect`) for all unit tests; no XCTest for unit tests
- **DI:** All checker classes must use protocol-based dependency injection (existing pattern: `AXTextEngineProtocol`, `HotkeyManagerProtocol`)
- **No external API calls** from the grammar layer — Harper is fully local
- **Keychain:** Not relevant to this phase (no API keys); `@AppStorage` acceptable for dialect/rule settings
- **Comments:** Only for design decisions (WHY), not WHAT
- **No TODO/FIXME/HACK** — complete all call sites in the same change
- **Public access only where needed** — match visibility to the smallest scope that satisfies callers

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| harper-core | 2.0.0 | Grammar, spelling, punctuation engine | The engine; current release as of 2026-04-08 |
| uniffi | 0.31.0 | Rust → Swift binding generation (proc macros) | Mozilla-proven; generates type-safe Swift from annotated Rust |
| uniffi-bindgen-swift | 0.31.0 | Swift-specific bindgen variant (finer xcframework control) | Supports xcframework-compatible modulemap generation |

[VERIFIED: docs.rs/harper-core/latest] — v2.0.0 is the current version
[VERIFIED: docs.rs/crate/uniffi/0.31.0] — released 2026-01-14

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Rust standard library | 1.85+ | MutableDictionary, file I/O for dictionary.txt | Always; no additional crate needed |
| Swift Foundation | built-in | FileManager, URL for dictionary.txt persistence | Always |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| UniFFI proc macros | UDL file | Proc macros keep everything in Rust source; UDL adds a separate file to maintain |
| uniffi-bindgen-swift | uniffi-bindgen (global install) | uniffi-bindgen-swift is project-scoped via `cargo run -p`, avoids global tool version drift |
| MergedDictionary | Rebuilding FstDictionary with user words | FstDictionary is immutable; MergedDictionary layers without duplication |
| `LintGroup` reconstruction on dialect change | In-place reconfiguration | LintGroup does not expose dialect mutation; new instance is required |

### Installation

```bash
# Step 1: Install Rust toolchain via Homebrew (rustup is keg-only)
brew install rustup
# Add to PATH — $(brew --prefix rustup)/bin must precede $(brew --prefix)/bin
export PATH="$(brew --prefix rustup)/bin:$PATH"
rustup default stable  # installs Rust 1.85+

# Step 2: Add macOS targets
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin

# Step 3: harper-bridge/Cargo.toml handles all Rust dependencies
# (harper-core, uniffi) — no global cargo installs needed except uniffi-bindgen-swift
# is run via: cargo run -p uniffi-bindgen-swift (project-local)
```

**Version verification:**
```bash
# After Rust toolchain is installed:
cargo search harper-core  # confirm 2.0.0 is latest
# harper-core = "2.0.0" pinned in harper-bridge/Cargo.toml
```

[VERIFIED: docs.rs/harper-core/latest] — 2.0.0 confirmed current
[VERIFIED: Homebrew formulae] — rustup 1.29.0 formula available, keg-only

---

## Architecture Patterns

### Recommended Project Structure

```
opengram/
├── OpenGram/
│   ├── App/
│   │   └── AppDelegate.swift        # Phase 2: wire HarperService into handleHotkeyFired()
│   ├── CheckEngine/                 # NEW in Phase 2
│   │   ├── HarperCheckerProtocol.swift
│   │   ├── HarperService.swift      # Swift actor wrapping HarperChecker (UniFFI)
│   │   ├── Suggestion.swift         # Unified data model
│   │   └── DictionaryStore.swift    # Load/save dictionary.txt
│   └── Generated/                   # NEW — git-ignored; regenerated by build-harper.sh
│       └── HarperBridge.swift       # UniFFI-generated Swift bindings
├── harper-bridge/                   # NEW — Rust crate
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── lib.rs                   # ~120 lines; HarperChecker, GrammarSuggestion
├── HarperBridge.xcframework/        # NEW — built artifact; committed to git
└── build-harper.sh                  # NEW — reproducible xcframework build script
```

### Pattern 1: UniFFI Proc-Macro Bridge (Recommended)

**What:** Annotate Rust types with `#[uniffi::export]` and `#[derive(uniffi::Record)]`. UniFFI generates `HarperBridge.swift` and `HarperBridgeFFI.h` automatically.

**When to use:** Always — proc macros keep the interface in one place (lib.rs), eliminating UDL file sync issues.

```rust
// harper-bridge/src/lib.rs
// Source: docs.rs/uniffi/0.31.0 + docs.rs/harper-core/latest

use harper_core::linting::{FlatConfig, LintGroup, Linter};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::{FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{Dialect, Document};
use std::sync::Arc;

uniffi::setup_scaffolding!();

/// Two-bucket category decision from D-03.
/// All non-Spelling LintKind variants map to GrammarPunctuation.
#[derive(uniffi::Enum)]
pub enum SuggestionCategory {
    Spelling,
    GrammarPunctuation,
}

/// Carries all Harper replacements so Phase 3 can decide presentation (D-01).
/// char offsets index into the Swift String.unicodeScalars view.
#[derive(uniffi::Record)]
pub struct GrammarSuggestion {
    pub start_char: u32,
    pub end_char: u32,
    pub message: String,
    /// Primary replacement — first Harper suggestion (D-01)
    pub primary_replacement: Option<String>,
    /// All replacements for "More options" affordance (D-01)
    pub all_replacements: Vec<String>,
    pub category: SuggestionCategory,
    pub priority: u8,
}

#[derive(uniffi::Object)]
pub struct HarperChecker {
    linter: LintGroup<MergedDictionary<Arc<FstDictionary>, MutableDictionary>>,
    user_dict: MutableDictionary,
}

#[uniffi::export]
impl HarperChecker {
    #[uniffi::constructor]
    pub fn new(dialect_abbr: String, user_words: Vec<String>) -> Self {
        let base = FstDictionary::curated();
        let mut user_dict = MutableDictionary::new();
        // Load persisted words from dictionary.txt (passed in by Swift at startup)
        user_dict.extend_words(user_words.iter().map(|w| {
            (w.chars().collect::<Vec<char>>(), Default::default())
        }));
        let merged = MergedDictionary::new(base, user_dict.clone());
        let dialect = parse_dialect(&dialect_abbr);
        Self {
            linter: LintGroup::new_curated(Arc::new(merged), dialect),
            user_dict,
        }
    }

    pub fn check(&mut self, text: String) -> Vec<GrammarSuggestion> {
        let document = Document::new_curated(&text, &PlainEnglish);
        let source = document.get_source();      // &[char]
        let lints = self.linter.lint(&document);

        lints.into_iter().map(|lint| {
            let span = lint.span;
            let all_replacements: Vec<String> = lint.suggestions.iter().filter_map(|s| {
                match s {
                    harper_core::linting::Suggestion::ReplaceWith(chars) => {
                        Some(chars.iter().collect())
                    }
                    harper_core::linting::Suggestion::InsertAfter(chars) => {
                        Some(chars.iter().collect())
                    }
                    harper_core::linting::Suggestion::Remove => Some(String::new()),
                }
            }).collect();
            let primary_replacement = all_replacements.first().cloned();

            let category = match lint.lint_kind {
                harper_core::linting::LintKind::Spelling => SuggestionCategory::Spelling,
                _ => SuggestionCategory::GrammarPunctuation,
            };

            GrammarSuggestion {
                start_char: span.start as u32,
                end_char: span.end as u32,
                message: lint.message.to_string(),
                primary_replacement,
                all_replacements,
                category,
                priority: lint.priority,
            }
        }).collect()
    }

    /// Returns the updated word list for Swift to persist to dictionary.txt (D-06)
    pub fn add_to_dictionary(&mut self, word: String) -> Vec<String> {
        self.user_dict.append_word_str(&word, Default::default());
        self.user_dict.words_iter()
            .map(|(chars, _)| chars.iter().collect())
            .collect()
    }

    /// Enable/disable a named rule category. Keys match FlatConfig rule names.
    pub fn set_rule_enabled(&mut self, rule_key: String, enabled: bool) {
        self.linter.config.set_rule_enabled(&rule_key, enabled);
    }
}

fn parse_dialect(abbr: &str) -> Dialect {
    match abbr {
        "GB" => Dialect::British,
        "CA" => Dialect::Canadian,
        "AU" => Dialect::Australian,
        "IN" => Dialect::Indian,
        _ => Dialect::American,
    }
}
```

**NOTE:** `LintGroup` is not `Send`. Do NOT share it across threads. The Swift actor wrapper (below) ensures it runs on a single background actor.

### Pattern 2: Swift Actor Wrapper (HarperService)

**What:** Wrap the UniFFI `HarperChecker` in a Swift `actor` so Swift 6 strict concurrency is satisfied without manual locking. The actor serializes all `check()` calls.

**When to use:** Always — `LintGroup` is `!Send` on the Rust side; the actor boundary provides the single-threaded contract.

```swift
// OpenGram/CheckEngine/HarperService.swift
// Source: CLAUDE.md Swift 6 concurrency pattern + UniFFI actor pattern

import Foundation

protocol HarperCheckerProtocol: Sendable {
    func check(text: String) async -> [Suggestion]
    func addToCurrentDictionary(word: String) async
    func setRuleEnabled(key: String, enabled: Bool) async
}

actor HarperService: HarperCheckerProtocol {
    private var checker: HarperChecker  // UniFFI-generated class
    private let dictionaryStore: DictionaryStoreProtocol

    init(dictionaryStore: DictionaryStoreProtocol, dialect: String) {
        let words = dictionaryStore.loadWords()
        self.checker = HarperChecker(dialectAbbr: dialect, userWords: words)
        self.dictionaryStore = dictionaryStore
    }

    func check(text: String) async -> [Suggestion] {
        let raw = checker.check(text: text)
        return raw.compactMap { Suggestion(from: $0, in: text) }
    }

    func addToCurrentDictionary(word: String) async {
        let updatedWords = checker.addToDictionary(word: word)
        dictionaryStore.saveWords(updatedWords)
    }

    func setRuleEnabled(key: String, enabled: Bool) async {
        checker.setRuleEnabled(ruleKey: key, enabled: enabled)
    }
}
```

**D-09 background queue:** For large text, `handleHotkeyFired()` in AppDelegate calls `harperService.check(text:)` with `Task { }`, which runs on the actor's executor (background). `statusBar.setState(.checking)` is called on MainActor before the Task.

### Pattern 3: Unicode Scalar Offset Conversion

**What:** Harper v2.0.0 `Span<char>` indices are **Unicode scalar indices** (Rust `char` = one Unicode scalar value). Swift's `String.unicodeScalars` view is a 1:1 match. Convert by advancing through `unicodeScalars` by the integer count.

**Critical distinction from prior research:** The existing integration doc (`planning/harper-integration-research.md`) describes UTF-8 byte offsets and a `indexFromByteOffset()` function. This is **incorrect for harper-core 2.0.0**. The `Document` stores `Lrc<[char]>` and all spans index that char array.

```swift
// OpenGram/CheckEngine/Suggestion.swift
// Source: docs.rs/harper-core/latest (Span<char> confirmed char-based)

extension String {
    /// Convert a Harper Span<char> index to String.Index via unicodeScalars view.
    /// Harper char == Swift Unicode scalar — both are Unicode scalar values (U+0000..U+10FFFF).
    func indexFromCharOffset(_ offset: Int) -> String.Index? {
        guard offset >= 0 else { return nil }
        let scalars = self.unicodeScalars
        guard offset <= scalars.count else { return nil }
        return scalars.index(scalars.startIndex, offsetBy: offset)
    }

    func rangeFromCharOffsets(start: Int, end: Int) -> Range<String.Index>? {
        guard let s = indexFromCharOffset(start),
              let e = indexFromCharOffset(end),
              s <= e else { return nil }
        return s..<e
    }
}
```

**Edge cases with composed emoji:** A family emoji like 👨‍👩‍👦 consists of multiple Unicode scalars (man + ZWJ + woman + ZWJ + boy). Harper's `PlainEnglish` parser sees these as non-word tokens and will not produce a span crossing them for grammar lint. However, if a lint span *ends* at a scalar that is the first scalar of a multi-scalar grapheme cluster, converting the range to a `String.Index` and then slicing the `String` will produce a partial grapheme — the Swift runtime will crash or produce garbled output. Mitigation: after computing `Range<String.Index>`, validate that both boundaries are on grapheme cluster boundaries using `String.index(after:)` round-trip check.

### Pattern 4: Dictionary Persistence (D-06)

```swift
// OpenGram/CheckEngine/DictionaryStore.swift

protocol DictionaryStoreProtocol: Sendable {
    func loadWords() -> [String]
    func saveWords(_ words: [String])
}

struct DictionaryStore: DictionaryStoreProtocol {
    // D-06: ~/Library/Application Support/OpenGram/dictionary.txt
    private let url: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenGram/dictionary.txt")
    }()

    func loadWords() -> [String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    func saveWords(_ words: [String]) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        let content = words.sorted().joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

### Pattern 5: Unified Suggestion Model

```swift
// OpenGram/CheckEngine/Suggestion.swift

enum SuggestionCategory: Sendable {
    case spelling         // Harper LintKind.Spelling only (red in Phase 3)
    case grammarPunctuation  // All other LintKind variants (blue in Phase 3) — D-03
}

enum SuggestionSource: Sendable {
    case harper
    case llm   // Phase 4 only
}

struct Suggestion: Identifiable, Sendable {
    let id: UUID
    let range: Range<String.Index>
    let original: String
    let primaryReplacement: String?        // D-01: best replacement prominent
    let allReplacements: [String]          // D-01: all Harper replacements
    let message: String
    let category: SuggestionCategory
    let source: SuggestionSource
    let priority: UInt8

    /// Failable init from UniFFI GrammarSuggestion.
    /// Returns nil if char offsets are out of range or produce invalid index.
    init?(from raw: GrammarSuggestion, in text: String) {
        guard let range = text.rangeFromCharOffsets(
            start: Int(raw.startChar), end: Int(raw.endChar)
        ) else { return nil }
        self.id = UUID()
        self.range = range
        self.original = String(text[range])
        self.primaryReplacement = raw.primaryReplacement
        self.allReplacements = raw.allReplacements
        self.message = raw.message
        self.category = raw.category == .spelling ? .spelling : .grammarPunctuation
        self.source = .harper
        self.priority = raw.priority
    }
}
```

### Pattern 6: build-harper.sh

```bash
#!/bin/bash
# build-harper.sh — Produces HarperBridge.xcframework from harper-bridge Rust crate.
# Invoke manually or as Xcode Run Script Build Phase (runs before compile sources).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$REPO_ROOT/harper-bridge"
FRAMEWORK_NAME="HarperBridge"
OUT_DIR="$REPO_ROOT/$FRAMEWORK_NAME.xcframework"
SWIFT_OUT="$REPO_ROOT/OpenGram/Generated"

cd "$CRATE_DIR"

echo "Building harper-bridge for Apple Silicon..."
cargo build --target aarch64-apple-darwin --release

echo "Building harper-bridge for Intel Mac..."
cargo build --target x86_64-apple-darwin --release

echo "Generating Swift bindings..."
mkdir -p bindings
cargo run -p uniffi-bindgen-swift -- \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings --swift-sources

cargo run -p uniffi-bindgen-swift -- \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings/include --headers

cargo run -p uniffi-bindgen-swift -- \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings/Modules --modulemap --xcframework

echo "Creating universal binary..."
mkdir -p target/universal/release
lipo -create \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  target/x86_64-apple-darwin/release/libharper_bridge.a \
  -output target/universal/release/libharper_bridge.a

echo "Packaging xcframework..."
rm -rf "$OUT_DIR"
xcodebuild -create-xcframework \
  -library target/universal/release/libharper_bridge.a \
  -headers bindings/include \
  -output "$OUT_DIR"

echo "Copying Swift bindings to project..."
mkdir -p "$SWIFT_OUT"
cp bindings/*.swift "$SWIFT_OUT/"

echo "Done. Link $FRAMEWORK_NAME.xcframework in Xcode."
```

### Xcode Integration Steps

1. Add `HarperBridge.xcframework` to Xcode target → General → Frameworks, Libraries, and Embedded Content → **Do Not Embed** (static library)
2. Add `OpenGram/Generated/HarperBridge.swift` to the OpenGramLib target's Compile Sources
3. In Package.swift, add the xcframework as a `.binaryTarget` or link via Xcode project directly (SPM binary targets support xcframeworks)
4. Add a Run Script Build Phase that calls `./build-harper.sh` with condition: "Run script only when installing" for CI; always for local dev

### Anti-Patterns to Avoid

- **Sharing `HarperChecker` across Swift concurrency domains without an actor:** `LintGroup` is `!Send` in Rust. UniFFI marks it `UnsafeRawPointer`. Accessing it from multiple tasks without actor isolation = data race + crash.
- **Using byte offsets for span conversion:** The integration doc describes `indexFromByteOffset()` — this is wrong for v2.0.0. Harper uses char indices.
- **Rebuilding `FstDictionary` for each check:** `FstDictionary::curated()` returns an `Arc<FstDictionary>` — it is already shared and cached. Creating a new one per check wastes ~20ms on the first call.
- **Storing dialect in the checker and mutating in place:** `LintGroup` does not expose a `set_dialect()` method. Store dialect choice in Swift (`@AppStorage`), create a new `HarperChecker` when dialect changes.
- **Ignoring the `InsertAfter` Suggestion variant:** The v2.0.0 API has three variants: `ReplaceWith`, `InsertAfter`, and `Remove`. The prior research only handled `ReplaceWith`. `InsertAfter` must map to appending chars after the span end, not replacing.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Grammar/spell rules | Custom rule engine | harper-core 2.0.0 LintGroup | 61K SLoC of battle-tested rules |
| Rust→Swift FFI | Manual C header (cbindgen) | UniFFI proc macros | UniFFI handles memory, strings, Vec, Option, enums automatically |
| Universal binary | Manual arch slicing | lipo (built into macOS) | System tool; no install needed |
| XCFramework packaging | Manual file layout | `xcodebuild -create-xcframework` | Official Apple tool; correct modulemap structure |
| Spell dictionary storage | Custom trie/FST | FstDictionary::curated() via Arc | 5MB compressed FST shipped in the harper-core binary |
| User dictionary layering | Replace built-in dictionary | MergedDictionary<FstDictionary, MutableDictionary> | Designed for this exact use case |
| Multi-language binding gen | Custom codegen | uniffi-bindgen-swift | Handles Swift module maps, header generation, xcframework modulemap |

**Key insight:** Harper's `LintGroup::new_curated()` bundles every rule harper ships. The bridge crate is purely a thin translation layer, not a rule engine. If you find yourself writing grammar logic in the bridge, stop — it belongs in harper-core (or it's out of scope).

---

## Common Pitfalls

### Pitfall 1: uniffi version mismatch

**What goes wrong:** Runtime panic with cryptic ABI error, not a compile error. The panic message mentions "scaffolding" or "contract version."

**Why it happens:** `uniffi` in `Cargo.toml` and `uniffi-bindgen-swift` must be the same version. Even a patch version difference (0.31.0 vs 0.31.1) causes ABI mismatch.

**How to avoid:** Pin both to `0.31.0` explicitly. In Cargo.toml: `uniffi = { version = "=0.31.0", features = ["scaffolding"] }`. The build script uses `cargo run -p uniffi-bindgen-swift` which reads from the same Cargo.lock, guaranteeing consistency.

**Warning signs:** `thread 'main' panicked at 'scaffolding contract version mismatch'`

### Pitfall 2: LintGroup is !Send — cross-thread access crash

**What goes wrong:** Swift sends `HarperChecker` (a UniFFI class wrapping a raw pointer) to a different task/thread. Rust panics or corrupts memory.

**Why it happens:** `LintGroup<D>` uses interior mutability (`RefCell`) without `Sync`. UniFFI wraps it as `Arc<Mutex<...>>` at the boundary, but if you bypass the actor and call the checker from multiple concurrent contexts, you get races.

**How to avoid:** Keep `HarperService` as a Swift `actor`. Never store `HarperChecker` as a `@MainActor` or `nonisolated` property. Never `Sendable`-wrap it with `nonisolated(unsafe)`.

**Warning signs:** Swift 6 compiler error "cannot send value of type 'HarperChecker' across actor boundaries." If you suppress this, expect crashes.

### Pitfall 3: Char offset confusion with composed grapheme clusters

**What goes wrong:** A span end at a scalar that is mid-grapheme-cluster causes `String[range]` to produce partial output or a runtime trap.

**Why it happens:** Harper parses text as a `[char]` (Unicode scalars). A composed emoji like 👨‍👩‍👦 occupies 8 Unicode scalars (3 base code points + 2 ZWJ). Harper's tokenizer will not split a non-word token, but if a lint span touches the text *surrounding* the emoji, the end offset may land at a scalar inside a grapheme.

**How to avoid:** After computing `Range<String.Index>` via `unicodeScalars`, verify it is a valid grapheme cluster boundary: `string.index(after: range.lowerBound)` should not throw. In practice, Harper lints primarily word tokens and its PlainEnglish parser avoids creating spans inside emoji. This is a test-suite concern more than a runtime concern.

**Warning signs:** Test failing on emoji-containing input with invalid range assertions.

### Pitfall 4: Missing xcframework in Swift Package Manager

**What goes wrong:** SPM binary targets require the xcframework to exist at path before `swift build` runs. CI that builds without running `build-harper.sh` first gets "no such file."

**Why it happens:** xcframeworks are binary artifacts; SPM doesn't compile Rust.

**How to avoid:** Two options: (a) commit the built `HarperBridge.xcframework` to git (recommended for POC — ~10MB binary, enables non-Rust contributors to build Swift without Rust toolchain); (b) use Xcode project only (not SPM) and rely on the Run Script Build Phase. For this project using Package.swift, option (a) is cleaner.

**Warning signs:** `error: binary target 'HarperBridge' could not be used` or missing xcframework path errors.

### Pitfall 5: Pre-existing test suite broken

**What goes wrong:** Running `swift test` fails with 144 compile errors before Phase 2 adds any code.

**Why it happens (identified in research):** Several test files use `@testable import OpenGram` (the executable target), but `OpenGramTests` depends on `OpenGramLib`. `TextContextTests.swift`, `IconStateMachineTests.swift`, `MenuBuilderTests.swift`, and `AXCapabilityCacheTests.swift` have the wrong import. `HotkeyManagerTests.swift` correctly imports `OpenGramLib`.

**How to avoid:** Fix all `@testable import OpenGram` → `@testable import OpenGramLib` in the broken test files as part of Wave 0. This is a pre-existing failure that must be resolved before Phase 2 tests can run.

**Warning signs:** `cannot find 'TextContext' in scope`, `cannot find 'IconStateMachine' in scope` (seen during research).

### Pitfall 6: Rust toolchain PATH not available to Xcode

**What goes wrong:** Xcode Run Script Build Phase fails with "cargo: command not found" even though `cargo` works in Terminal.

**Why it happens:** Xcode launches build scripts with a minimal PATH that does not include `~/.cargo/bin` or Homebrew's keg-only rustup prefix.

**How to avoid:** Explicitly source the PATH in `build-harper.sh`:
```bash
export PATH="$HOME/.cargo/bin:$(brew --prefix rustup)/bin:$PATH"
```

---

## Code Examples

### Cargo.toml for harper-bridge

```toml
# harper-bridge/Cargo.toml
[package]
name = "harper-bridge"
version = "0.1.0"
edition = "2021"

[lib]
name = "harper_bridge"
crate-type = ["staticlib", "cdylib"]

[dependencies]
harper-core = "=2.0.0"
uniffi = { version = "=0.31.0", features = ["scaffolding"] }

[[bin]]
name = "uniffi-bindgen-swift"
path = "uniffi-bindgen-swift.rs"

# uniffi-bindgen-swift.rs (minimal runner):
# fn main() { uniffi::uniffi_bindgen_swift() }
```

[VERIFIED: docs.rs/crate/uniffi/0.31.0] — scaffolding feature flag name
[CITED: mozilla.github.io/uniffi-rs/next/swift/uniffi-bindgen-swift.html] — binary setup pattern

### AppDelegate integration point (D-11)

```swift
// In AppDelegate.handleHotkeyFired() — Phase 2 addition
// Source: existing AppDelegate.swift pattern + D-09, D-11

@MainActor
private func handleHotkeyFired() {
    guard let statusBar = statusBarController,
          let engine = textEngine,
          let harperService = harperService else { return }

    statusBar.setState(.checking)

    guard let context = engine.extractText() else {
        statusBar.triggerSilentFail()
        return
    }

    Task {
        let suggestions = await harperService.check(text: context.text)
        await MainActor.run {
            // Phase 3 will consume suggestions; Phase 2 just logs (D-11)
            print("[OpenGram] Harper found \(suggestions.count) suggestion(s)")
            statusBar.setState(.done)
        }
        lastExtractedContext = context
        lastSuggestions = suggestions  // stored for Phase 3
    }
}
```

### Unicode scalar conversion test cases

```swift
// OpenGramTests/HarperServiceTests.swift
// Source: GRAM-05 requirement + Phase 2 discretion for test strategy

@Test("char offset conversion handles ASCII correctly")
func asciiOffsets() {
    let text = "This is an test."
    let range = text.rangeFromCharOffsets(start: 8, end: 10)
    #expect(range != nil)
    #expect(String(text[range!]) == "an")
}

@Test("char offset conversion handles emoji (4-scalar sequences)")
func emojiOffsets() {
    // "I love 🎉 grammar" — 🎉 is U+1F389 (single scalar), offset 7
    let text = "I love 🎉 grammar"
    // 'g' of 'grammar' is at char offset 9 (7=🎉, 8=space, 9=g)
    let range = text.rangeFromCharOffsets(start: 9, end: 16)
    #expect(range != nil)
    #expect(String(text[range!]) == "grammar")
}

@Test("char offset conversion handles accented characters")
func accentedCharOffsets() {
    // "café latte" — é is one Unicode scalar U+00E9, offset 3
    let text = "café latte"
    let range = text.rangeFromCharOffsets(start: 5, end: 10)
    #expect(range != nil)
    #expect(String(text[range!]) == "latte")
}

@Test("char offset conversion handles CJK characters")
func cjkOffsets() {
    // "Hello 世界 world" — each CJK char is one scalar
    let text = "Hello 世界 world"
    let range = text.rangeFromCharOffsets(start: 9, end: 14)
    #expect(range != nil)
    #expect(String(text[range!]) == "world")
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual C FFI (cbindgen) | UniFFI proc macros | UniFFI matured ~2023 | No hand-written headers; auto memory management |
| UTF-8 byte offsets from Harper | Span<char> Unicode scalar indices | harper-core v2.0.0 (April 2026) | Conversion function changes: UTF-8 view → unicodeScalars view |
| `LintGroupConfig` struct with named fields | `FlatConfig` with `set_rule_enabled(key, val)` | harper-core v2.x (API overhaul PR #726) | Rule toggling is now string-keyed, not typed struct fields |
| `cargo install uniffi-bindgen` global | `cargo run -p uniffi-bindgen-swift` project-local | UniFFI 0.29+ | Eliminates version drift between global tool and Cargo.lock |
| `FstDictionary` mutation for user words | `MergedDictionary<FstDictionary, MutableDictionary>` | harper-core v2.x | FstDictionary is immutable Arc; user words layered via MergedDictionary |

**Deprecated/outdated (from prior research docs):**

- `indexFromByteOffset()`: Wrong for v2.0.0. Replace with `indexFromCharOffset()` using `unicodeScalars` view.
- `LintGroupConfig` struct: Replaced by `FlatConfig` with string-keyed `set_rule_enabled()` API.
- `linter.add_word()`: Method does not exist in v2.0.0. Use `MutableDictionary.append_word_str()` and `MergedDictionary`.
- The integration research doc's `GrammarSuggestion` has `start_byte`/`end_byte` fields — rename to `start_char`/`end_char` per actual API.

[VERIFIED: docs.rs/harper-core/latest/harper_core/linting/struct.LintGroup.html] — FlatConfig confirmed
[VERIFIED: docs.rs/harper-core/latest/harper_core/struct.Span.html] — Span<char> confirmed
[VERIFIED: docs.rs/harper-core/latest/harper_core/spell/struct.MutableDictionary.html] — append_word_str() confirmed

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `MergedDictionary<Arc<FstDictionary>, MutableDictionary>` is the correct composition type signature for layering user words | Standard Stack, Pattern 1 | Bridge crate fails to compile; must adjust generic parameter |
| A2 | `uniffi-bindgen-swift` binary pattern (as a `[[bin]]` in harper-bridge Cargo.toml) works for xcframework-compatible modulemap generation | Pattern 6 build script | Need to adjust generation approach; fallback is global `cargo install uniffi-bindgen` |
| A3 | `LintGroup.config` is a public mutable field of type `FlatConfig` with `set_rule_enabled(key, val)` | Pattern 1, GRAM-09 | Rule toggling requires different API; may need to expose differently |
| A4 | `MutableDictionary.words_iter()` returns an iterator of `(Vec<char>, DictWordMetadata)` tuples usable to rebuild the word list for persistence | Pattern 1, Pattern 4 | Dictionary save loop breaks; need alternative words_iter API |
| A5 | Committing the built `HarperBridge.xcframework` binary (~10MB) to git is the correct approach for POC | Pitfall 4 | If repo policy rejects large binaries, need Git LFS or different integration strategy |

[ASSUMED] for A1-A5: verified from docs.rs but exact generic signatures and method returns require compilation to confirm 100%.

---

## Open Questions (RESOLVED)

All three questions below are compile-time discovery items that cannot be verified without the Rust toolchain (not yet installed). Plan 02-01 Task 1 includes a mandatory `cargo doc` step after `cargo check` passes to resolve these at execution time.

1. **FlatConfig rule key names for category-level toggling (GRAM-09)** — RESOLVED: Plan 02-01 Task 1 will run `cargo doc --document-private-items` on harper-core after `cargo check` succeeds. The executor will enumerate FlatConfig keys from the generated docs and record at least one category-level key in the 02-01-SUMMARY.md. Plan 02-03 Task 2 reads this key from the summary to write a behavioral GRAM-09 test (not just a no-crash test).
   - What we know: `FlatConfig.set_rule_enabled(key, val)` accepts a string key
   - Fallback if keys are not enumerable from docs: inspect `LintGroup::new_curated` source to find which individual rule structs are registered, then derive keys from struct names (snake_case convention per harper-ls config schema).

2. **`MutableDictionary.words_iter()` return type** — RESOLVED: Plan 02-01 Task 1 will verify during `cargo check`. If the return type differs from `(Vec<char>, DictWordMetadata)`, the executor adjusts the `add_to_dictionary` return mapping. Fallback: DictionaryStore in Swift owns the canonical word list (passed into HarperChecker on init), and `add_to_dictionary` returns the Swift-side list rather than reading back from Rust.

3. **`LintGroup::new_curated` generic parameter** — RESOLVED: Plan 02-01 Task 1 will verify during `cargo check`. If `MergedDictionary<Arc<FstDictionary>, MutableDictionary>` does not compile, the executor adjusts wrapping per compiler guidance (e.g., `Arc<MergedDictionary<...>>`). The research noted this as Assumption A1 with a clear fix path.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / xcodebuild | Swift compilation, xcframework packaging | Yes (with DEVELOPER_DIR override) | Xcode 26.4 | — |
| Swift / swift build | Test runner, SPM | Yes | Swift 6.2.4 (CLT), Swift 6.3.0 (Xcode) | — |
| lipo | Universal binary creation | Yes | System (arm64e + x86_64) | — |
| Homebrew | rustup installation | Yes | 5.1.5 | curl \| sh from rustup.rs |
| rustup | Rust toolchain management | **No** | — | `brew install rustup` |
| cargo / rustc | Rust compilation | **No** | — | Install via rustup |
| uniffi-bindgen-swift | Swift binding generation | **No** | — | cargo run -p (project-local) |

**Missing dependencies with no fallback:**
- Rust toolchain (rustup, cargo, rustc) — blocks all Rust compilation. Must be installed in Wave 0 before any harper-bridge work.

**Missing dependencies with fallback:**
- uniffi-bindgen-swift — not a separate install; cargo will build it as part of `cargo run -p uniffi-bindgen-swift` from the Cargo.toml definition.

**Pre-existing issue:** `xcode-select` points to CLT, not Xcode.app. All build commands must prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Wave 0 should include switching xcode-select (requires sudo) or document the DEVELOPER_DIR prefix for build scripts.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (built into Xcode 16+) |
| Config file | None — Swift Testing auto-discovered by swift test |
| Quick run command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HarperService` |
| Full suite command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` |

**Note:** `swift test` without `DEVELOPER_DIR` uses CLT Swift (6.2.4) which lacks the `Testing` framework module. All test invocations must use the DEVELOPER_DIR prefix or Xcode's test runner.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GRAM-01 | Harper finds spelling error in "I love this prodcut" | unit | `swift test --filter "HarperServiceTests/spellingDetection"` | No — Wave 0 |
| GRAM-02 | Harper finds grammar error "This is an test" | unit | `swift test --filter "HarperServiceTests/grammarDetection"` | No — Wave 0 |
| GRAM-03 | Harper finds punctuation error (missing period or apostrophe) | unit | `swift test --filter "HarperServiceTests/punctuationDetection"` | No — Wave 0 |
| GRAM-04 | Harper checks 500-word text in < 50ms | unit (perf) | `swift test --filter "HarperServiceTests/performanceUnder50ms"` | No — Wave 0 |
| GRAM-05 | Char offset converts correctly for emoji, CJK, accented chars | unit | `swift test --filter "HarperServiceTests/unicodeOffsets"` | No — Wave 0 |
| GRAM-06 | add_to_dictionary suppresses word on next check | unit | `swift test --filter "HarperServiceTests/customDictionary"` | No — Wave 0 |
| GRAM-07 | Dictionary persists across DictionaryStore round-trip | unit | `swift test --filter "DictionaryStoreTests"` | No — Wave 0 |
| GRAM-08 | Dialect change (British) affects spell results | unit | `swift test --filter "HarperServiceTests/dialectChange"` | No — Wave 0 |
| GRAM-09 | Disabling a rule category suppresses those lints | unit | `swift test --filter "HarperServiceTests/ruleToggle"` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HarperService`
- **Per wave merge:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `OpenGramTests/HarperServiceTests.swift` — covers GRAM-01 through GRAM-09
- [ ] `OpenGramTests/DictionaryStoreTests.swift` — covers GRAM-06, GRAM-07
- [ ] Fix `@testable import OpenGram` → `@testable import OpenGramLib` in: `TextContextTests.swift`, `IconStateMachineTests.swift`, `MenuBuilderTests.swift`, `AXCapabilityCacheTests.swift` (pre-existing breakage, must fix first)
- [ ] Rust toolchain installation: `brew install rustup && rustup default stable && rustup target add aarch64-apple-darwin x86_64-apple-darwin`
- [ ] First-run `./build-harper.sh` to produce `HarperBridge.xcframework`

---

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Partial | Text from AX extraction is passed directly to Harper. Harper's PlainEnglish parser handles arbitrary input without panicking (D-10). No length limit (D-09). |
| V6 Cryptography | No | — |

**Threat patterns relevant to this phase:**

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed text causing Harper panic | Denial of Service | Harper's parser is fuzz-tested; catch Rust panics at UniFFI boundary (UniFFI wraps Rust panics as Swift errors) |
| dictionary.txt path traversal | Tampering | Path is hardcoded to Application Support — not user-supplied |
| dictionary.txt read by other processes | Info Disclosure | Application Support is user-writable and readable by other user processes; dictionary contains non-sensitive words — acceptable |

---

## Sources

### Primary (HIGH confidence)
- [docs.rs/harper-core/latest](https://docs.rs/harper-core/latest/harper_core/) — Span<char> char-based indexing, Document::get_source() returns &[char], LintGroup::new_curated, FstDictionary::curated, Dialect variants (5: American/British/Canadian/Australian/Indian), LintKind variants (20), Suggestion::InsertAfter variant
- [docs.rs/harper-core/latest/harper_core/linting/struct.LintGroup](https://docs.rs/harper-core/latest/harper_core/linting/struct.LintGroup.html) — FlatConfig, new_curated, config field, set_all_rules_to
- [docs.rs/harper-core/latest/harper_core/spell](https://docs.rs/harper-core/latest/harper_core/spell/index.html) — MutableDictionary.append_word_str, MergedDictionary, FstDictionary
- [docs.rs/crate/uniffi/0.31.0](https://docs.rs/crate/uniffi/latest) — released 2026-01-14; proc macro approach; scaffolding feature
- [mozilla.github.io/uniffi-rs/next/swift/uniffi-bindgen-swift](https://mozilla.github.io/uniffi-rs/next/swift/uniffi-bindgen-swift.html) — uniffi-bindgen-swift project-local binary approach, xcframework modulemap generation
- [github.com/Automattic/harper blob document.rs](https://github.com/Automattic/harper/blob/master/harper-core/src/document.rs) — Document stores `Lrc<[char]>`; get_source() returns &[char]; confirmed char-based indexing

### Secondary (MEDIUM confidence)
- [docs.rs/crate/harper-ls/latest/source/src/dictionary_io.rs](https://docs.rs/crate/harper-ls/latest/source/src/dictionary_io.rs) — one-word-per-line format; MutableDictionary.extend_words() for bulk load; sorted alphabetical save
- [mozilla.github.io/uniffi-rs/latest/swift/xcode.html](https://mozilla.github.io/uniffi-rs/latest/swift/xcode.html) — Xcode integration approach; static lib linking; bridging header inclusion

### Tertiary (LOW confidence)
- WebSearch: harper-core 2.0.0 API overhaul (LintGroupConfig → FlatConfig change referenced from PR #726) — confirmed via docs.rs but PR details not independently verified

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — harper-core 2.0.0 and uniffi 0.31.0 confirmed on docs.rs
- Architecture (UniFFI bridge pattern): HIGH — proc macro approach documented by Mozilla
- Char offset conversion: HIGH — Document.get_source() returns &[char] confirmed from source
- Build pipeline: MEDIUM — build-harper.sh structure is standard but exact uniffi-bindgen-swift invocation flags need verification during first run
- FlatConfig rule keys (GRAM-09): LOW — API confirmed but exact key strings not documented in fetched pages; need `cargo doc` to enumerate

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (30 days — harper API is actively developed; verify Span type if harper-core version changes)
