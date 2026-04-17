---
phase: 18-paragraph-rephrase-card
plan: "02"
subsystem: SuggestionUI/RephraseCard
tags: [tdd, diff-algorithm, display-heuristic, view-model, pure-logic]
dependency_graph:
  requires: [18-01]
  provides: [TextDiff, DiffSegment, DisplayHeuristic, RephraseComposer, RephraseCardViewModel]
  affects: [CheckCategory (Equatable+Hashable)]
tech_stack:
  added: []
  patterns: [word-level-LCS, descending-range-substitution, live-config-read, pure-value-viewmodel]
key_files:
  created:
    - OpenGram/SuggestionUI/RephraseCard/TextDiff.swift
    - OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift
    - OpenGram/SuggestionUI/RephraseCard/RephraseComposer.swift
    - OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/TextDiffTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift
  modified:
    - OpenGram/CheckEngine/Suggestion.swift (CheckCategory: +Equatable, +Hashable)
    - OpenGram.xcodeproj/project.pbxproj (RephraseCard source+test groups, 8 file refs)
decisions:
  - "RephraseComposer overlap guard: sort by upperBound descending on lowerBound ties, track appliedLower to skip any edit whose upperBound exceeds already-applied lowerBound"
  - "UUID C009 for RephraseCard source group (C007 was already ParagraphInfra — collision fixed)"
  - "Import OpenGramLib not OpenGram in all test files (module name mismatch with plan template)"
metrics:
  duration: ~25min
  completed: "2026-04-16"
  tasks: 2
  files: 10
---

# Phase 18 Plan 02: Pure-Logic Layer (TextDiff + DisplayHeuristic + RephraseComposer + RephraseCardViewModel) Summary

Word-level LCS diff + FR-12 display heuristic + in-app rephrase composer + pure-value ViewModel — all zero-SwiftUI, zero-AppKit, 31 Swift Testing cases green.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | TextDiff RED+GREEN | ee3d6e9 | TextDiff.swift, TextDiffTests.swift, pbxproj |
| 2 | DisplayHeuristic + RephraseComposer + RephraseCardViewModel RED+GREEN | 90edcf8 | 6 new files, Suggestion.swift |

## What Was Built

**TextDiff** (`D-01`): Word-level LCS via classic DP matrix. Traceback emits per-token segments, coalesce pass merges adjacent same-kind segments with single spaces. Handles Unicode whitespace (U+00A0), emoji tokens, empty inputs.

**DisplayHeuristic** (`D-11`, FR-12): Live-read qualifier — reads `config.minIssueCount` / `config.minWordCount` on every call. Returns true if any of: issue count >= threshold, any clarity/rephrase issue present, word count >= threshold with at least one issue.

**RephraseComposer** (`D-21`): Applies `LLMStyleSuggestion.revisedText` substitutions in descending `lowerBound` order. Overlap detection: ties broken by `upperBound` descending (wider range wins), `appliedLower` tracking skips any edit whose `upperBound` exceeds the already-consumed lowerBound.

**RephraseCardViewModel** (`D-22`, `D-18`): Pure value type with `static func headerText(for: Set<CheckCategory>) -> String` — exact FR-16 strings for all category combos. `static func checkCategory(from: LLMStyleSuggestion.Category) -> CheckCategory` collapses `.tone` to `.clarity` per D-22. `onAccept` / `onDismiss` as `@MainActor` closures. Toggle state not in ViewModel — owned by View as `@State` per D-03.

**CheckCategory** conformance addition: `Equatable, Hashable` added to support `Set<CheckCategory>` in headerText and `#expect(== .x)` in tests.

## Test Results

- TextDiffTests: 8/8 passed
- DisplayHeuristicTests: 7/7 passed
- RephraseComposerTests: 5/5 passed
- RephraseCardViewModelTests: 11/11 passed
- **Total: 31/31 green**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RephraseComposer overlap detection insufficient**
- **Found during:** Task 2 test run (overlappingRanges test failed, got "HIING" not "GREETING")
- **Issue:** Original guard only checked `edit.range.upperBound <= result.endIndex`. For two edits with same lowerBound (both matching at offset 0), the wider match was applied first replacing the string, but the narrower edit's range indices still passed the guard and partially overwrote the replacement.
- **Fix:** Sort ties by upperBound descending (wider first), track `appliedLower: String.Index?`, skip any edit whose `upperBound > appliedLower`.
- **Files modified:** `OpenGram/SuggestionUI/RephraseCard/RephraseComposer.swift`
- **Commit:** 90edcf8

**2. [Rule 3 - Blocker] Wrong module import in test files**
- **Found during:** Task 1+2 test run (module not found)
- **Issue:** Plan templates used `@testable import OpenGram` but the module is named `OpenGramLib` (verified from existing test files pattern).
- **Fix:** Changed all 4 test files to `@testable import OpenGramLib`.
- **Files modified:** All 4 test files
- **Commit:** 90edcf8

**3. [Rule 1 - Bug] pbxproj UUID collision**
- **Found during:** Task 1 build (Paragraph*.swift resolved at worktree root)
- **Issue:** RephraseCard source group was assigned UUID `A4000001000000000000C007` which was already used by the ParagraphInfra source group. xcodebuild resolved ParagraphInfra files relative to SuggestionUI path instead of CheckEngine path.
- **Fix:** Renamed RephraseCard group UUID to `A4000001000000000000C009` (next available in C00x series).
- **Files modified:** `OpenGram.xcodeproj/project.pbxproj`
- **Commit:** ee3d6e9

## Known Stubs

None. All 4 types are fully implemented pure functions with no placeholder data or TODO stubs.

## Threat Flags

None. Pure logic layer — no network endpoints, AX paths, file access, or schema changes at trust boundaries.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/RephraseCard/TextDiff.swift` — FOUND
- `OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift` — FOUND
- `OpenGram/SuggestionUI/RephraseCard/RephraseComposer.swift` — FOUND
- `OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift` — FOUND
- `OpenGramTests/SuggestionUITests/RephraseCard/TextDiffTests.swift` — FOUND
- `OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift` — FOUND
- `OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift` — FOUND
- `OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift` — FOUND
- Commits ee3d6e9 + 90edcf8 — FOUND in git log
- 31/31 tests passed — VERIFIED
