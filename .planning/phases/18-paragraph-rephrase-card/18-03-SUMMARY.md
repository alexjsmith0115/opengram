---
phase: 18-paragraph-rephrase-card
plan: "03"
subsystem: CheckEngine
tags: [incremental-config, suggestion-model, llm-scheduler, paragraph-hash, dismiss]
dependency_graph:
  requires: [18-02]
  provides: [paragraphRephraseCardEnabled-flag, Suggestion.paragraphHash, LLMCheckScheduler.markDismissed]
  affects: [CheckCoordinator, RephraseCardPanelController]
tech_stack:
  added: []
  patterns: [protocol-extension, thin-wrapper, live-read-per-call]
key_files:
  created:
    - OpenGramTests/CheckEngine/LLMCheckSchedulerMarkDismissedTests.swift
  modified:
    - OpenGram/CheckEngine/LLMCheckScheduler/IncrementalConfig.swift
    - OpenGram/CheckEngine/Suggestion.swift
    - OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGramTests/CheckEngine/IncrementalConfigTests.swift
    - OpenGramTests/CheckEngine/LLMCheckSchedulerTests.swift
    - OpenGramTests/CheckEngine/LLMCheckSchedulerCancellationTests.swift
    - OpenGramTests/CheckEngine/LLMCheckSchedulerFlagOffTests.swift
    - OpenGramTests/App/CheckCoordinatorSchedulerIntegrationTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift
    - OpenGramTests/SuggestionUITests/BoundsValidatorTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerDiffTests.swift
    - OpenGramTests/SuggestionUITests/PopoverViewTests.swift
    - OpenGramTests/SuggestionUITests/UnderlineViewTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerTests.swift
    - OpenGramTests/AppDelegateWiringTests.swift
    - OpenGramTests/CheckOrchestratorTests.swift
    - OpenGramTests/Integration/TwoPhaseCheckFlowTests.swift
    - OpenGramTests/SuggestionDiffEngineTests.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "paragraphRephraseCardEnabled defaults false — dogfooding validates heuristic before enabling"
  - "paragraphHash: nil for Harper and flag-off LLM paths; non-nil only in rebase() per-paragraph"
  - "markDismissed is a thin scheduler wrapper — UI layer never touches ParagraphSuggestionCache directly"
metrics:
  duration: "~25 minutes"
  completed: "2026-04-16"
  tasks_completed: 2
  files_modified: 20
---

# Phase 18 Plan 03: Protocol + Model Plumbing Summary

One-liner: IncrementalConfig extended with REPH-15 gate flag, Suggestion carries D-23 paragraph hash, LLMCheckScheduler gains D-17 markDismissed wrapper — all conformers and construction sites updated atomically.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Extend IncrementalConfig + Suggestion model + update all conformers | b8912e9 | IncrementalConfig.swift, Suggestion.swift, LLMCheckScheduler.swift, 16 test files |
| 2 | LLMCheckScheduler.markDismissed wrapper + tests | de5248c | LLMCheckScheduler.swift, LLMCheckSchedulerMarkDismissedTests.swift, project.pbxproj |

## Conformers Updated

All `IncrementalConfig` conformers updated with `var paragraphRephraseCardEnabled: Bool`:

| File | Type | Value |
|------|------|-------|
| IncrementalConfig.swift | `UserDefaultsIncrementalConfig` | reads `llmParagraphRephraseCardEnabled` key (default false) |
| LLMCheckSchedulerTests.swift | `AlwaysOnIncrementalConfig` | `{ false }` |
| LLMCheckSchedulerCancellationTests.swift | `AlwaysOnIncrementalConfig` | `{ false }` |
| LLMCheckSchedulerCancellationTests.swift | `MutableIncrementalConfig` | stored `_paragraphRephraseCardEnabled: Bool` |
| LLMCheckSchedulerFlagOffTests.swift | `MutableIncrementalConfig` | stored `_paragraphRephraseCardEnabled: Bool` |
| CheckCoordinatorSchedulerIntegrationTests.swift | `MutableIncrementalConfig` | `{ false }` |
| DisplayHeuristicTests.swift | `FakeConfig` | `false` |
| DisplayHeuristicTests.swift | `Mutable` (inline class) | `false` |

## Construction Sites Updated

All `Suggestion(...)` sites updated with `paragraphHash:`:

| File | Path | Value |
|------|------|-------|
| Suggestion.swift | Harper `init?(from:in:)` | `nil` |
| LLMCheckScheduler.swift | `checkFullText` (flag-off) | `nil` |
| LLMCheckScheduler.swift | `rebase` (flag-on per-paragraph) | `paragraphHash` (from `keys[paragraph.index]`) |
| OverlayController.swift | `repositionAfterAccept` rebuild | `suggestion.paragraphHash` (preserved) |
| BoundsValidatorTests.swift | `makeSuggestion` | `nil` |
| OverlayControllerDiffTests.swift | `makeDiffSuggestion` | `nil` |
| PopoverViewTests.swift | 4 make* helpers | `nil` |
| UnderlineViewTests.swift | `makeSuggestion` | `nil` |
| OverlayControllerTests.swift | 2 `makeSuggestion` overloads | `nil` |
| AppDelegateWiringTests.swift | `makeWiringSuggestion` | `nil` |
| CheckOrchestratorTests.swift | inline construction | `nil` |
| TwoPhaseCheckFlowTests.swift | `makeHarperSuggestion` | `nil` |
| SuggestionDiffEngineTests.swift | `makeSuggestion` | `nil` |

## New Tests

**IncrementalConfigTests** (+3):
- `paragraphRephraseCardEnabled_defaultFalse_whenUnset` — pass
- `paragraphRephraseCardEnabled_true_whenSet` — pass
- `paragraphRephraseCardEnabledKey_matchesExpectedString` — pass

**LLMCheckSchedulerMarkDismissedTests** (+3):
- `markDismissed_populatesCacheWithDismissedStatus` — pass
- `markDismissed_noOp_whenNoEntry` — pass
- `dismissedEntry_returnsZeroSuggestions_onNextCheck` — pass

Total test count: 414 (up from 408).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Additional Suggestion construction sites not listed in plan**
- **Found during:** Task 1 — iterative build/test cycle
- **Issue:** `CheckOrchestratorTests.swift`, `TwoPhaseCheckFlowTests.swift`, `SuggestionDiffEngineTests.swift` had `Suggestion(...)` sites not enumerated in the plan
- **Fix:** Added `paragraphHash: nil` to each
- **Files modified:** 3 test files
- **Commit:** b8912e9

**2. [Rule 3 - Blocking] HarperBridge.xcframework missing in worktree**
- **Found during:** Task 1 build validation
- **Issue:** Worktree lacked the compiled xcframework; build failed immediately
- **Fix:** Copied from main repo (`/Users/alex/Dev/opengram/HarperBridge.xcframework`)
- **Commit:** not committed (runtime artifact, gitignored)

## Known Stubs

None. All protocol requirements are fully implemented with real UserDefaults backing or sensible test doubles.

## Threat Flags

None. No new network endpoints, auth paths, or trust-boundary crossings introduced. `markDismissed` operates on in-process actor state only.

## Self-Check: PASSED

- `IncrementalConfig.swift` — `paragraphRephraseCardEnabled` present (4 hits): FOUND
- `Suggestion.swift` — `paragraphHash` field present: FOUND
- `LLMCheckScheduler.swift` — `func markDismissed` present: FOUND
- `LLMCheckSchedulerMarkDismissedTests.swift` — file exists: FOUND
- pbxproj — `LLMCheckSchedulerMarkDismissedTests` registered (4 hits): FOUND
- Commits b8912e9, de5248c — both exist in git log: FOUND
- 3 new IncrementalConfigTests pass: VERIFIED
- 3 new LLMCheckSchedulerMarkDismissedTests pass: VERIFIED
