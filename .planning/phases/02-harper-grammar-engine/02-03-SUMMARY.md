---
phase: 02-harper-grammar-engine
plan: 03
subsystem: check-engine-integration
tags: [swift, integration-tests, appdelegate, harper-service, dictionary, tdd]
dependency_graph:
  requires:
    - phase: 02-01
      provides: HarperBridge.xcframework, UniFFI-generated bindings
    - phase: 02-02
      provides: HarperService actor, GrammarCheckerProtocol, DictionaryStore, Suggestion model
  provides:
    - AppDelegate wired to HarperService for end-to-end hotkey-to-check flow
    - Integration tests proving all GRAM requirements (01-04, 06-09)
    - Fixed addToDictionary to actually suppress spell-check false positives
  affects: [phase-3-ui, phase-5-settings]
tech_stack:
  added: []
  patterns: [async-actor-integration, appstorage-dialect-persistence, tdd-integration-tests]
key_files:
  created:
    - OpenGramTests/HarperServiceTests.swift
    - OpenGramTests/DictionaryStoreTests.swift
  modified:
    - OpenGram/App/AppDelegate.swift
    - OpenGram/CheckEngine/DictionaryStore.swift
    - harper-bridge/src/lib.rs
    - build-harper.sh
    - HarperBridge.xcframework/macos-arm64_x86_64/Headers/module.modulemap
    - HarperBridge.xcframework/macos-arm64_x86_64/libharper_bridge.a
    - OpenGram/Generated/HarperBridge.swift
key_decisions:
  - "User dictionary words get DialectFlags::all() metadata so SpellCheck recognizes them in any dialect"
  - "Document::new() with merged dictionary instead of Document::new_curated() so tokenizer sees user words"
  - "Linter rebuilt after addToDictionary to pick up new MergedDictionary with updated user words"
  - "build-harper.sh auto-fixes modulemap (rename + module name) so rebuilds don't break SPM"
metrics:
  duration: 18m
  completed: "2026-04-13T18:25:33Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 7
requirements-completed: [GRAM-01, GRAM-02, GRAM-03, GRAM-04, GRAM-06, GRAM-07, GRAM-08, GRAM-09]
---

# Phase 02 Plan 03: AppDelegate Integration and GRAM Test Suite Summary

HarperService wired into AppDelegate hotkey flow with async actor check, plus 15 integration tests proving all GRAM requirements -- spelling, grammar, punctuation, performance, dictionary, dialect, and rule toggling.

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-13T18:07:19Z
- **Completed:** 2026-04-13T18:25:33Z
- **Tasks:** 2/2
- **Files modified:** 9 (2 created, 7 modified)
- **Tests:** 82 total (67 pre-existing + 15 new), all passing

## Accomplishments

- AppDelegate hotkey flow now runs Harper check asynchronously via Task{}, stores suggestions, logs count
- @AppStorage("selectedDialect") persists dialect preference for Phase 5 Settings UI
- 10 HarperService integration tests covering GRAM-01 through GRAM-09
- 5 DictionaryStore persistence tests covering round-trip, empty file, and directory creation
- Fixed critical bug: addToDictionary now actually suppresses spell-check for added words
- build-harper.sh auto-fixes modulemap naming for SPM compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire HarperService into AppDelegate hotkey flow** - `d9863da` (feat)
2. **Task 2: Integration tests for all GRAM requirements** - `8439bca` (test)

## Files Created/Modified

- `OpenGram/App/AppDelegate.swift` - Added harperService property, @AppStorage dialect, async Harper check in handleHotkeyFired
- `OpenGramTests/HarperServiceTests.swift` - 10 integration tests for GRAM-01 through GRAM-09
- `OpenGramTests/DictionaryStoreTests.swift` - 5 tests for dictionary persistence (GRAM-07)
- `OpenGram/CheckEngine/DictionaryStore.swift` - Added init(directoryURL:) for test injection
- `harper-bridge/src/lib.rs` - Fixed addToDictionary to rebuild linter, use merged dict for Document, dialect-aware metadata
- `build-harper.sh` - Auto-fix modulemap rename and module name after xcframework generation
- `HarperBridge.xcframework/` - Rebuilt with dictionary fix, corrected modulemap
- `OpenGram/Generated/HarperBridge.swift` - Regenerated bindings (no API change)

## GRAM Requirements Verified

| Requirement | Test | Verified |
|-------------|------|----------|
| GRAM-01: Spelling detection | `spellingDetection()` - "prodcut" flagged as .spelling | PASS |
| GRAM-02: Grammar detection | `grammarDetection()` - "an test" flagged as .grammarPunctuation | PASS |
| GRAM-03: Punctuation detection | `punctuationDetection()` - "Dont" flagged for missing apostrophe | PASS |
| GRAM-04: Performance <50ms | `performanceUnder50ms()` - 500-word text checked under 50ms | PASS |
| GRAM-06: Custom dictionary | `customDictionarySuppression()` - addToDictionary suppresses re-check | PASS |
| GRAM-07: Dictionary persistence | `roundTripPersistence()` + 4 more DictionaryStore tests | PASS |
| GRAM-08: Dialect switching | `dialectSwitchingGB()` + `dialectVariants()` - US/GB/AU/CA | PASS |
| GRAM-09: Rule toggling | `ruleTogglingSpellCheck()` + `ruleTogglingReEnable()` + `ruleTogglingRepeatedWords()` | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] addToDictionary did not suppress spell-check for added words**
- **Found during:** Task 2 (TDD RED phase -- test correctly failed)
- **Issue:** Three compounding bugs in harper-bridge: (a) `Document::new_curated()` uses only `FstDictionary`, not the merged dictionary, so the tokenizer never sees user words. (b) After adding a word, the `MergedDictionary` inside `LintGroup` still held a stale snapshot. (c) User words were added with `Default::default()` metadata which has no dialect flags, causing `SpellCheck`'s dialect filter to skip them.
- **Fix:** (a) Store `Arc<MergedDictionary>` in `HarperCheckerInner`, use `Document::new()` with it. (b) Rebuild linter after `add_to_dictionary` with fresh merged dict. (c) Use `DialectFlags::all()` metadata for user words so they're recognized in every dialect. Extracted `build_merged_dict()` helper to DRY the construction.
- **Files modified:** `harper-bridge/src/lib.rs`
- **Commit:** 8439bca

**2. [Rule 3 - Blocking] build-harper.sh regenerates broken modulemap on each run**
- **Found during:** Task 2 (xcframework rebuild after Rust fix)
- **Issue:** `xcodebuild -create-xcframework` generates `harper_bridge.modulemap` with `framework module harper_bridge` each time. SPM needs `module.modulemap` with `module harper_bridgeFFI`. Plan 02 fixed this manually but it breaks on every rebuild.
- **Fix:** Added post-build step to build-harper.sh that renames the modulemap and fixes the module declaration automatically.
- **Files modified:** `build-harper.sh`
- **Commit:** 8439bca

**3. [Rule 2 - Missing] DictionaryStore lacked testable initializer**
- **Found during:** Task 2
- **Issue:** DictionaryStore had only a parameterless init() hardcoding ~/Library/Application Support/OpenGram/. Tests need to use a temporary directory to avoid polluting production data.
- **Fix:** Added `init(directoryURL:)` internal initializer for dependency injection.
- **Files modified:** `OpenGram/CheckEngine/DictionaryStore.swift`
- **Commit:** 8439bca

## Decisions Made

- **DialectFlags::all() for user words:** User dictionary words should be valid in every dialect. If a user adds "prodcut" to their dictionary, it should be accepted whether they're using US, GB, AU, or CA dialect. Matches Harper's own test pattern (issue #1876).
- **Document::new() over Document::new_curated():** The curated constructor only uses `FstDictionary`. For user words to be recognized by the tokenizer (which sets word metadata checked by SpellCheck), the merged dictionary must be passed to Document construction.
- **build-harper.sh modulemap auto-fix:** Rather than documenting a manual post-build step, the build script now handles the SPM compatibility fix automatically. This prevents future rebuilds from breaking the Swift build.

## Verification Results

- `swift build` passes with AppDelegate changes
- `swift test` passes: 82 tests in 13 suites (67 pre-existing + 15 new)
- `swift test --filter HarperServiceTests` passes: 10 tests
- `swift test --filter DictionaryStoreTests` passes: 5 tests
- No test regressions from Phase 1 or Plan 02

## Self-Check: PASSED

All created files verified present on disk. Both task commits (d9863da, 8439bca) verified in git history.

---
*Phase: 02-harper-grammar-engine*
*Completed: 2026-04-13*
