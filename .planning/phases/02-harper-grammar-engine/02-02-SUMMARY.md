---
phase: 02-harper-grammar-engine
plan: 02
subsystem: check-engine
tags: [swift, unicode, suggestion-model, actor, dictionary, dependency-injection]
dependency_graph:
  requires:
    - phase: 02-01
      provides: HarperBridge.xcframework, UniFFI-generated HarperChecker/GrammarSuggestion types
  provides:
    - Suggestion model with Unicode scalar offset conversion
    - GrammarCheckerProtocol async DI contract
    - HarperService actor wrapping UniFFI HarperChecker
    - DictionaryStore for user word persistence
    - SPM binaryTarget integration for xcframework
  affects: [02-03, phase-3-ui, phase-5-settings]
tech_stack:
  added: []
  patterns: [actor-isolation-for-ffi, unicode-scalar-offset-conversion, grapheme-boundary-snapping, protocol-based-di]
key_files:
  created:
    - OpenGram/CheckEngine/Suggestion.swift
    - OpenGram/CheckEngine/DictionaryStore.swift
    - OpenGram/CheckEngine/GrammarCheckerProtocol.swift
    - OpenGram/CheckEngine/HarperService.swift
    - OpenGramTests/SuggestionTests.swift
  modified:
    - Package.swift
    - HarperBridge.xcframework/macos-arm64_x86_64/Headers/module.modulemap
    - OpenGramTests/TextContextTests.swift
    - OpenGramTests/IconStateMachineTests.swift
    - OpenGramTests/MenuBuilderTests.swift
    - OpenGramTests/AXCapabilityCacheTests.swift
    - OpenGramTests/AXTextEngineTests.swift
key_decisions:
  - "Named Swift-side category enum CheckCategory to avoid collision with UniFFI-generated SuggestionCategory"
  - "Named protocol GrammarCheckerProtocol to avoid collision with UniFFI-generated HarperCheckerProtocol"
  - "Renamed modulemap to module.modulemap and fixed module name to harper_bridgeFFI for SPM discovery"
  - "Named binaryTarget harper_bridgeFFI matching the canImport guard in generated Swift"
patterns_established:
  - "Unicode offset conversion: Harper char == Rust char == Unicode scalar; use String.unicodeScalars view"
  - "Grapheme boundary snapping: rangeOfComposedCharacterSequence prevents mid-cluster slicing"
  - "Actor wrapping for !Send FFI types: Swift actor provides single-threaded isolation for LintGroup"
  - "CheckEngine/ directory for grammar checking service layer types"
requirements-completed: [GRAM-05, GRAM-06, GRAM-07]
duration: 6min
completed: 2026-04-13
---

# Phase 02 Plan 02: Swift Service Layer Summary

**Suggestion model with battle-tested Unicode scalar offset conversion, DictionaryStore persistence, GrammarCheckerProtocol DI contract, and HarperService actor wrapping UniFFI bridge -- all 67 tests green.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-13T17:58:32Z
- **Completed:** 2026-04-13T18:04:16Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments
- Suggestion model with failable init from GrammarSuggestion, Unicode scalar offset conversion tested across ASCII, emoji (single and multi-scalar), CJK, accented characters, and grapheme boundary edge cases
- DictionaryStore reading/writing ~/Library/Application Support/OpenGram/dictionary.txt with atomic writes and sorted output
- HarperService actor providing Swift 6 concurrency safety around !Send UniFFI HarperChecker
- Fixed pre-existing broken test imports in 5 test files and Sendable conformance in test mock
- SPM binaryTarget integration for HarperBridge.xcframework with corrected modulemap

## Task Commits

Each task was committed atomically:

1. **Task 1: Suggestion model with Unicode offset conversion + fix test imports** - `942f7d6` (feat)
2. **Task 2: DictionaryStore, GrammarCheckerProtocol, and HarperService actor** - `b2ee584` (feat)

## Files Created/Modified
- `OpenGram/CheckEngine/Suggestion.swift` - String extension for Unicode scalar offset conversion, CheckCategory/SuggestionSource enums, Suggestion struct with failable init from GrammarSuggestion
- `OpenGram/CheckEngine/DictionaryStore.swift` - DictionaryStoreProtocol and DictionaryStore for file-based word persistence
- `OpenGram/CheckEngine/GrammarCheckerProtocol.swift` - Async DI protocol for grammar checking (avoids UniFFI naming collision)
- `OpenGram/CheckEngine/HarperService.swift` - Actor wrapping UniFFI HarperChecker with concurrency safety
- `OpenGramTests/SuggestionTests.swift` - 14 tests for offset conversion and Suggestion model
- `Package.swift` - Added harper_bridgeFFI binaryTarget dependency
- `HarperBridge.xcframework/.../module.modulemap` - Fixed module name and filename for SPM
- `OpenGramTests/TextContextTests.swift` - Fixed import to OpenGramLib
- `OpenGramTests/IconStateMachineTests.swift` - Fixed import to OpenGramLib
- `OpenGramTests/MenuBuilderTests.swift` - Fixed import to OpenGramLib
- `OpenGramTests/AXCapabilityCacheTests.swift` - Fixed import to OpenGramLib
- `OpenGramTests/AXTextEngineTests.swift` - Fixed import to OpenGramLib, fixed StubCapabilityCache Sendable

## Decisions Made
- **CheckCategory instead of SuggestionCategory**: UniFFI generates a `SuggestionCategory` enum in HarperBridge.swift. The Swift-side enum is `CheckCategory` to avoid ambiguity. Same cases (`.spelling`, `.grammarPunctuation`).
- **GrammarCheckerProtocol instead of HarperCheckerProtocol**: UniFFI generates `HarperCheckerProtocol` as the protocol for HarperChecker. The DI contract is `GrammarCheckerProtocol` -- more descriptive and collision-free.
- **harper_bridgeFFI as binaryTarget name**: The UniFFI-generated Swift file has `#if canImport(harper_bridgeFFI)`. SPM binaryTarget name must match for the import to resolve. Also renamed modulemap from `harper_bridge.modulemap` to `module.modulemap` (SPM convention) and changed module declaration from `framework module harper_bridge` to `module harper_bridgeFFI`.
- **endIndex guard in rangeFromCharOffsets**: `rangeOfComposedCharacterSequence(at: endIndex)` crashes. Added explicit guard to skip snapping when the upper bound is endIndex.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] UniFFI-generated HarperCheckerProtocol name collision**
- **Found during:** Task 2
- **Issue:** Plan specified `HarperCheckerProtocol` but UniFFI already generated a protocol with that name in HarperBridge.swift (line 523).
- **Fix:** Named the Swift-side DI protocol `GrammarCheckerProtocol` instead. File named `GrammarCheckerProtocol.swift`.
- **Files modified:** OpenGram/CheckEngine/GrammarCheckerProtocol.swift
- **Committed in:** b2ee584

**2. [Rule 3 - Blocking] UniFFI-generated SuggestionCategory name collision**
- **Found during:** Task 1
- **Issue:** Plan specified `SuggestionCategory` enum but UniFFI already generated an enum with that name.
- **Fix:** Named the Swift-side enum `CheckCategory` with same cases.
- **Files modified:** OpenGram/CheckEngine/Suggestion.swift
- **Committed in:** 942f7d6

**3. [Rule 3 - Blocking] SPM binaryTarget modulemap not discoverable**
- **Found during:** Task 1
- **Issue:** SPM could not find the xcframework's C module. The modulemap was named `harper_bridge.modulemap` (SPM expects `module.modulemap`) and defined `framework module harper_bridge` (should be `module harper_bridgeFFI` matching the binaryTarget name).
- **Fix:** Renamed file to `module.modulemap`, changed module name to `harper_bridgeFFI`, removed `framework` keyword (static library, not framework).
- **Files modified:** HarperBridge.xcframework/macos-arm64_x86_64/Headers/module.modulemap
- **Committed in:** 942f7d6

**4. [Rule 1 - Bug] rangeOfComposedCharacterSequence crashes at endIndex**
- **Found during:** Task 1
- **Issue:** When `end` offset equals scalar count, `indexFromCharOffset` returns `endIndex`. Calling `rangeOfComposedCharacterSequence(at: endIndex)` crashes.
- **Fix:** Added guard: `(e == self.endIndex) ? e : self.rangeOfComposedCharacterSequence(at: e).lowerBound`.
- **Files modified:** OpenGram/CheckEngine/Suggestion.swift
- **Committed in:** 942f7d6

**5. [Rule 1 - Bug] StubCapabilityCache Sendable violation in test**
- **Found during:** Task 1
- **Issue:** `StubCapabilityCache` in AXTextEngineTests.swift conforms to `AXCapabilityCacheProtocol: Sendable` but has mutable stored properties, causing Swift 6 strict concurrency error.
- **Fix:** Added `@unchecked Sendable` conformance (test-only mock, single-threaded usage).
- **Files modified:** OpenGramTests/AXTextEngineTests.swift
- **Committed in:** 942f7d6

---

**Total deviations:** 5 auto-fixed (2 bugs, 3 blocking)
**Impact on plan:** All auto-fixes necessary for compilation and correctness. Naming changes are cosmetic (same API contract). No scope creep.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GrammarCheckerProtocol ready for AppDelegate wiring in Plan 03
- HarperService actor ready to be instantiated with DictionaryStore and dialect
- Suggestion model ready for Phase 3 UI consumption
- All 67 tests passing (14 new + 53 pre-existing)

## Self-Check: PASSED

All 6 created files verified present on disk. Both task commits (942f7d6, b2ee584) verified in git history.

---
*Phase: 02-harper-grammar-engine*
*Completed: 2026-04-13*
