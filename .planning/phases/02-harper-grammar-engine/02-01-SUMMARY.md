---
phase: 02-harper-grammar-engine
plan: 01
subsystem: harper-bridge
tags: [rust, uniffi, xcframework, grammar-engine, build-pipeline]
dependency_graph:
  requires: []
  provides: [harper-bridge-crate, xcframework, swift-bindings]
  affects: [02-02, 02-03]
tech_stack:
  added: [harper-core-2.0.0, uniffi-0.31.0, rust-1.94.1]
  patterns: [mutex-interior-mutability, unsafe-send-sync-behind-mutex, uniffi-proc-macros]
key_files:
  created:
    - harper-bridge/Cargo.toml
    - harper-bridge/Cargo.lock
    - harper-bridge/src/lib.rs
    - harper-bridge/uniffi-bindgen-swift.rs
    - build-harper.sh
    - HarperBridge.xcframework/
    - OpenGram/Generated/HarperBridge.swift
  modified:
    - .gitignore
decisions:
  - "uniffi 0.31.0 'scaffolding' feature does not exist; proc macros work without feature flags"
  - "LintGroup is not generic in v2.0.0; uses Arc<dyn Dictionary> internally"
  - "MergedDictionary uses builder pattern (new() + add_dictionary()) not constructor args"
  - "Mutex<HarperCheckerInner> with unsafe Send+Sync needed because LintGroup is !Send"
  - "words_iter() returns Box<dyn Iterator<Item = &[char]>> not (Vec<char>, DictWordMetadata)"
  - "user_words tracked as Vec<String> on Rust side for dictionary persistence"
  - "uniffi-bindgen-swift binary requires 'cli' feature flag with required-features in Cargo.toml"
  - "DEVELOPER_DIR override needed in build script for xcode-select CLT fallback"
  - "Generated Swift file named harper_bridge.swift; renamed to HarperBridge.swift on copy"
metrics:
  duration: 16m
  completed: "2026-04-13T17:54:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 7
  files_modified: 1
---

# Phase 02 Plan 01: Rust Bridge Crate and XCFramework Summary

UniFFI-annotated harper-bridge crate wrapping harper-core 2.0.0 with Mutex-based interior mutability, producing a universal xcframework (arm64+x86_64) and generated Swift bindings.

## Discovered API Details

### FlatConfig Rule Key Names (GRAM-09)

Rule keys are the struct names passed to `insert_struct_rule!` in `LintGroup::new_curated`. Confirmed keys include:

- `"SpellCheck"` -- spell checking (enabled by default)
- `"RepeatedWords"` -- repeated word detection (enabled by default)
- `"LongSentences"` -- long sentence detection (enabled by default)
- `"CommaFixes"` -- comma corrections (enabled by default)
- `"OxfordComma"` -- oxford comma enforcement (enabled by default)
- `"NoOxfordComma"` -- oxford comma removal (disabled by default)
- `"SpelledNumbers"` -- spelled number suggestions (disabled by default)
- `"SentenceCapitalization"` -- requires dictionary (enabled by default)
- `"UnclosedQuotes"` -- unclosed quote detection (enabled by default)
- `"Spaces"` -- spacing corrections (enabled by default)

### words_iter() Return Type

`Dictionary::words_iter(&self) -> Box<dyn Iterator<Item = &'_ [char]> + Send + '_>`

Returns borrowed char slices, not `(Vec<char>, DictWordMetadata)` tuples as the research assumed. The bridge works around this by maintaining a separate `user_words: Vec<String>` for persistence rather than reading back from the dictionary.

### LintGroup Generic Parameter

`LintGroup` is **not generic** in v2.0.0. It stores `BTreeMap<String, Box<dyn Linter>>` internally and accepts `Arc<impl Dictionary + 'static>` in `new_curated()`. The research assumption A1 (`MergedDictionary<Arc<FstDictionary>, MutableDictionary>`) was incorrect -- `MergedDictionary` is also not generic, using `Vec<Arc<dyn Dictionary>>` internally.

## Completed Tasks

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Install Rust toolchain and create harper-bridge crate | 7f8e4cc | harper-bridge/Cargo.toml, harper-bridge/src/lib.rs, .gitignore |
| 2 | Build xcframework and generate Swift bindings | 72ca8dd | build-harper.sh, HarperBridge.xcframework/, OpenGram/Generated/HarperBridge.swift |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] uniffi 0.31.0 has no 'scaffolding' feature**
- **Found during:** Task 1
- **Issue:** Plan specified `uniffi = { version = "=0.31.0", features = ["scaffolding"] }` but the `scaffolding` feature does not exist in uniffi 0.31.0. Available features are: bindgen, build, cli, cargo-metadata, etc.
- **Fix:** Removed the features requirement. UniFFI proc macros (`uniffi::setup_scaffolding!()`, `#[derive(uniffi::Object)]`, etc.) work without any feature flag.
- **Files modified:** harper-bridge/Cargo.toml
- **Commit:** 7f8e4cc

**2. [Rule 3 - Blocking] LintGroup is not generic in harper-core 2.0.0**
- **Found during:** Task 1
- **Issue:** Research assumed `LintGroup<MergedDictionary<Arc<FstDictionary>, MutableDictionary>>` but LintGroup uses `Box<dyn Linter>` internally with no type parameter.
- **Fix:** Used `LintGroup` directly. `new_curated()` accepts `Arc<impl Dictionary + 'static>`.
- **Files modified:** harper-bridge/src/lib.rs
- **Commit:** 7f8e4cc

**3. [Rule 3 - Blocking] MergedDictionary uses builder pattern, not constructor args**
- **Found during:** Task 1
- **Issue:** `MergedDictionary::new(base, user_dict)` does not compile. `new()` takes zero arguments.
- **Fix:** Used `MergedDictionary::new()` followed by `add_dictionary()` calls for each sub-dictionary.
- **Files modified:** harper-bridge/src/lib.rs
- **Commit:** 7f8e4cc

**4. [Rule 3 - Blocking] LintGroup is !Send -- UniFFI requires Send+Sync**
- **Found during:** Task 1
- **Issue:** `LintGroup` contains `Box<dyn Linter>` (not Send) and `Lrc<BTreeMap<...>>` (not Send). UniFFI's `FfiConverterArc` requires `Send + Sync`.
- **Fix:** Wrapped internals in `Mutex<HarperCheckerInner>` and added `unsafe impl Send/Sync for HarperCheckerInner`. Safety justified by Mutex providing exclusive access, and the Swift actor providing single-threaded contract.
- **Files modified:** harper-bridge/src/lib.rs
- **Commit:** 7f8e4cc

**5. [Rule 3 - Blocking] words_iter() returns &[char] not (Vec<char>, DictWordMetadata)**
- **Found during:** Task 1
- **Issue:** `Dictionary::words_iter()` returns `Box<dyn Iterator<Item = &[char]>>`, not tuple with metadata.
- **Fix:** Maintained a separate `user_words: Vec<String>` in `HarperCheckerInner` for dictionary persistence instead of reading back from the dictionary trait.
- **Files modified:** harper-bridge/src/lib.rs
- **Commit:** 7f8e4cc

**6. [Rule 3 - Blocking] uniffi-bindgen-swift requires 'cli' feature**
- **Found during:** Task 1
- **Issue:** `uniffi::uniffi_bindgen_swift()` is gated behind `#[cfg(feature = "cli")]`. The binary target failed to compile without it.
- **Fix:** Added `[features] cli = ["uniffi/cli"]` and `required-features = ["cli"]` to the binary target in Cargo.toml.
- **Files modified:** harper-bridge/Cargo.toml
- **Commit:** 7f8e4cc

**7. [Rule 3 - Blocking] xcodebuild requires Xcode.app, not CLT**
- **Found during:** Task 2
- **Issue:** `xcode-select` pointed to `/Library/Developer/CommandLineTools`. `xcodebuild -create-xcframework` requires full Xcode.
- **Fix:** Added `DEVELOPER_DIR` override in build-harper.sh to point to `/Applications/Xcode.app/Contents/Developer`.
- **Files modified:** build-harper.sh
- **Commit:** 72ca8dd

**8. [Rule 1 - Bug] Generated Swift file named harper_bridge.swift not HarperBridge.swift**
- **Found during:** Task 2
- **Issue:** UniFFI generates Swift files named after the crate (snake_case), producing `harper_bridge.swift` instead of expected `HarperBridge.swift`.
- **Fix:** Updated build-harper.sh to rename the file during copy: `cp bindings/harper_bridge.swift "$SWIFT_OUT/HarperBridge.swift"`.
- **Files modified:** build-harper.sh
- **Commit:** 72ca8dd

## Verification Results

- `cargo check` passes cleanly (0 errors, 0 warnings)
- `cargo doc --document-private-items --no-deps` completes without error
- `build-harper.sh` completes successfully
- `HarperBridge.xcframework/Info.plist` exists
- Universal binary contains both arm64 and x86_64 architectures
- `OpenGram/Generated/HarperBridge.swift` contains HarperChecker class, GrammarSuggestion struct, SuggestionCategory enum
- Generated Swift bindings include check(), addToDictionary(), setRuleEnabled() methods
- Rust toolchain: rustc 1.94.1 (exceeds 1.85+ requirement)

## Self-Check: PASSED

All 8 created files verified present on disk. Both task commits (7f8e4cc, 72ca8dd) verified in git history.
