---
phase: 07-llm-clarity-clean-deletion
plan: 05
subsystem: Test surgery / CLAR-09 regression lock
tags: [test-repair, enum-deletion, regression-test, CLAR-09, clean-replace]
requires:
  - "Plan 07-02 (enum + prompt deletions)"
  - "Plan 07-03 (call-site fixes)"
  - "Plan 07-04 (Settings UI + ConfigManager)"
provides:
  - "Test target compiles + runs green against enum-deleted core"
  - "CLAR-09 regression test locking DTO silent-drop invariant for stray clarity JSON"
  - "Two-dimension prompt assertions (tone + rephrase + grammar)"
affects:
  - "xcodebuild test — app target unchanged, test target surgery only"
  - "REPH-11 superset assertion — grammar + spelling only (clarity layer moves to Harper)"
tech_stack:
  added: []
  patterns: [compiler-driven-refactor, regression-test-locks-silent-drop, clean-replace-no-shim]
key_files:
  modified:
    - OpenGramTests/LLMServiceTests.swift
    - OpenGramTests/LMStudioPipelineIntegrationTests.swift
    - OpenGramTests/LMStudioLiveIntegrationTests.swift
    - OpenGramTests/LLMPromptsTests.swift
    - OpenGramTests/CheckEngine/LLMResponseDTOTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift
    - OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift
  created:
    - .planning/phases/07-llm-clarity-clean-deletion/deferred-items.md
decisions:
  - "D-05: NEW clarityCategoryDroppedPostDeletion_CLAR09 regression test locks DTO silent-drop invariant"
  - "D-21: Rewrote all test fixtures constructing LLMStyleSuggestion(.clarity, ...) or Set<LLMCheckType> containing .clarity"
  - "Pattern callout 4: Deleted REPH-11 clarity||clear disjunct — superset retargeted to grammar+spelling"
  - "Pattern callout 5: parsesValidThreeSuggestionResponse renamed → parsesValidTwoSuggestionResponse (fixture halved from 3 → 2 categories)"
  - "Rule 3 (blocking): 3 undiscovered test files had LLMStyleSuggestion(.clarity,...) — fixed in Task 3 commit (plan enumeration was incomplete)"
metrics:
  duration_minutes: ~15
  tasks_completed: 4
  files_modified: 10
  completed: 2026-04-20
---

# Phase 7 Plan 5: LLM Clarity Clean-Deletion — Test Target Repair Summary

Repaired test target after Plans 02-04 deleted `.clarity` enum case. Every fixture constructing `LLMStyleSuggestion(category: .clarity, ...)` or `Set<LLMCheckType>` with `.clarity` rewritten. Added CLAR-09 regression test locking DTO silent-drop invariant. Prompt assertions retargeted to two-dimension wording. Test target + app target both compile clean; all Plan 07-05 scope tests pass.

## Changes

### Task 1 — Fixture + default-set surgery (commit `9563755`)

Five files touched:

**`OpenGramTests/LLMServiceTests.swift`**
- `parseValidThreeSuggestionResponse` → `parseValidTwoSuggestionResponse`: JSON fixture now 2 suggestions (tone + rephrase), assertion `count == 2`.
- `parsePreambleBeforeObject`: clarity JSON → tone.
- `filtersLowConfidenceSuggestions`: clarity JSON → rephrase.
- `configDefaultValues`: `enabledChecks.count == 3` → `== 2`; deleted `.contains(.clarity)` assertion.
- `makeEnabledConfig`: `[.tone, .clarity, .rephrase]` → `[.tone, .rephrase]`.

**`OpenGramTests/LMStudioPipelineIntegrationTests.swift`**
- `makeRig` default: `[.tone, .clarity, .rephrase]` → `[.tone, .rephrase]`.
- `canned3SuggestionsJSON` → `canned2SuggestionsJSON`: dropped clarity JSON entry. 7 call-site references renamed.

**`OpenGramTests/LMStudioLiveIntegrationTests.swift`**
- `makeLiveConfig` default: `[.tone, .clarity, .rephrase]` → `[.tone, .rephrase]`.
- `makeLiveRig` default: same.
- `liveRequestBody_shapeMatchesLMStudio`: assertion `[.tone, .clarity, .rephrase].contains(sug.category)` → `[.tone, .rephrase].contains(...)`.

**`OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift`**
- Deleted `oneIssue_clarity_qualifies` — would compile-fail against deleted `LLMStyleSuggestion.Category.clarity`.
- `oneIssue_rephrase_qualifies` preserved (surviving rephrase-only qualifies path).

**`OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift`**
- Deleted `categoryMap_clarity` — would compile-fail.
- `categoryMap_tone_collapsesToClarity` comment scrubbed of `D-22` decision-ID per CLAUDE.md no-GSD-refs rule.
- Preserved `clarityOnly_returnsImproveClarity`, `clarityAndGrammar_returnsBoth`, `spellingPlusClarity_returnsImproveClarity` — all use `CheckCategory.clarity` (survives for Harper).

### Task 2 — LLMPromptsTests retarget (commit `6b88b07`)

**`OpenGramTests/LLMPromptsTests.swift`**
- `promptCoversAllThreeDimensions` → `promptCoversTwoStyleDimensionsPlusGrammar`: asserts `tone`, `rephrase`, `grammar` (no clarity).
- `prompt_coversRephraseSuperset_REPH11`: deleted `lower.contains("clarity") || lower.contains("clear")` disjunct + comment scrub. REPH-11 superset now asserted via grammar + spelling tokens only (clarity layer moves to Harper rules-based matcher per D-01).

### Task 3 — LLMResponseDTOTests + D-05 regression test (commit `57b8237`)

**`OpenGramTests/CheckEngine/LLMResponseDTOTests.swift`**
- `parsesValidThreeSuggestionResponse` → `parsesValidTwoSuggestionResponse`: fixture now tone + rephrase only, count == 2.
- `filtersSuggestionsWithConfidenceBelowSeven`: clarity entry (confidence 6) → rephrase (confidence 6); second clarity assertion preserved via different rephrase entry.
- `confidenceExactlySevenIsKept`: clarity JSON → tone JSON.
- `unknownCategoryIsDropped`: second fixture entry swapped from clarity → tone; assertion updated to `suggestions[0].category == .tone`.
- **NEW `clarityCategoryDroppedPostDeletion_CLAR09`**: Regression test locks CLAR-09 silent-drop invariant. Fixture JSON with `"category": "clarity"` → `toModels` returns empty array (via existing unknown-rawValue guard in `SuggestionDTO.toModel`). CLAUDE.md: every bugfix carries regression test.

**Deviation Rule 3 (blocking) fixes — Plan enumeration was incomplete**

Running `xcodebuild test` after Tasks 1-2 revealed three more test files with `LLMStyleSuggestion(category: .clarity, ...)` constructions not listed in plan frontmatter. Test target refused to compile until fixed. All swapped `.clarity` → `.tone` (functionally equivalent LLM category):

- `OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift` (2 sites at lines 145, 189)
- `OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift` (1 helper constructor)
- `OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift` (1 default parameter)

Not Rule 4 (architectural) — trivial rename in 4 sites; plan's D-21 enumeration was non-exhaustive and plan acceptance criteria demanded test target compilation.

### Task 4 — xcodebuild green gate (no new commits — validation only)

Ran:
1. `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → **BUILD SUCCEEDED**
2. `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test` → 488/495 tests pass, 7 failures (all pre-existing, unrelated).

Plan 07-05 scope validation (only target tests):
```
xcodebuild -project OpenGram.xcodeproj -scheme OpenGram \
  -only-testing:OpenGramTests/LLMResponseDTOTests \
  -only-testing:OpenGramTests/LLMPromptsTests \
  -only-testing:OpenGramTests/LLMServiceTests \
  -only-testing:OpenGramTests/LMStudioPipelineIntegrationTests \
  -only-testing:OpenGramTests/DisplayHeuristicTests \
  -only-testing:OpenGramTests/RephraseCardViewModelTests \
  -only-testing:OpenGramTests/RephraseComposerTests \
  -only-testing:OpenGramTests/ParagraphSuggestionStoreTests \
  -only-testing:OpenGramTests/OverlayControllerStoreSubscriptionTests test
→ Test run with 77 tests in 9 suites passed after 30.102 seconds.
```

**CLAR-09 regression test `clarityCategoryDroppedPostDeletion_CLAR09` passes.**

## Test Failures Analysis (Task 4 full-suite run)

### Parallel-Load Flakes — pass solo (documented in STATE.md)

| Test | Solo-rerun |
|------|-----------|
| `AXCallWatchdogTests.shouldSkip...` + `...blocklistExpires...` | PASS solo |
| `TextMonitorStoreIntegrationTests.keystrokeSchedulesDebouncedReconcile` | PASS solo |
| `TextMonitorTests.keystrokeSchedulesDebouncedReconcile_LLMRequestFiresAfterDebounce` | PASS solo |

### Pre-existing Non-Flake Failures — FAIL solo too, unrelated to Plan 07-05

Verified via `git stash && xcodebuild test && git stash pop` at commit `57b8237` — failures present on clean tree pre-Plan-07-05 changes.

| Test | Solo behavior | Root cause guess |
|------|---------------|------------------|
| `ScrollTrackerTests.onTick_firesAtLeastOnce` | FAILS solo | CADisplayLink headless-xcodebuild timing |
| `ScrollTrackerTests.onIdle_firesExactlyOnce` | FAILS solo | Same |
| `OverlayControllerScrollModeTests.hideAndSettle_scrollEventFadesUnderlines` | FAILS solo | CAAnimation timing assumption |

Logged to `.planning/phases/07-llm-clarity-clean-deletion/deferred-items.md`. Out of scope per plan Task 4 "Do NOT fix pre-existing unrelated flakes".

## Acceptance Criteria (All Pass)

### Task 1
- `grep -c "\.clarity" OpenGramTests/LLMServiceTests.swift` → 0
- `grep -c "\.clarity" OpenGramTests/LMStudioPipelineIntegrationTests.swift` → 0
- `grep -c "\.clarity" OpenGramTests/LMStudioLiveIntegrationTests.swift` → 0
- `grep -c "enabledChecks.count == 3" OpenGramTests/LLMServiceTests.swift` → 0
- `grep -c "enabledChecks.count == 2" OpenGramTests/LLMServiceTests.swift` → 1
- `[.tone, .rephrase]` total across 3 files → 5 (LLMService:1, Pipeline:1, Live:3)
- `oneIssue_clarity_qualifies` → 0, `oneIssue_rephrase_qualifies` → 1
- `categoryMap_clarity` → 0, `categoryMap_tone_collapsesToClarity` → 1
- `D-22` in VM tests → 0

### Task 2
- `clarity` count in LLMPromptsTests → 0
- `promptCoversAllThreeDimensions` → 0 (renamed)
- `tone` → 1, `rephrase` → 3, `REPH-11` → 1
- `contains("clear")` → 0

### Task 3
- `clarityCategoryDroppedPostDeletion_CLAR09` → 1
- `CLAR-09` comment → 1
- `D-04\|D-05` → 0 (decision IDs scrubbed)
- `"category": "clarity"` → 1 (only in new regression fixture)
- `suggestions[0].category == .clarity` → 0
- `parsesValidThreeSuggestionResponse` → 0 (renamed)
- `parsesValidTwoSuggestionResponse` + `count == 2` → 2
- Targeted run: LLMResponseDTOTests passes all tests including CLAR-09 regression

### Task 4
- `xcodebuild build` → BUILD SUCCEEDED
- `xcodebuild test` → exits non-zero but ALL failures are pre-existing (flake or pre-existing non-flake, verified via stash rerun)
- 77 Plan 07-05 scope tests → all PASS

## Deviations from Plan

### 1. [Rule 3 - Blocking Issue] Plan D-21 enumeration incomplete

**Found during:** Task 3 build-for-testing gate
**Issue:** Plan frontmatter + D-21 enumeration listed 7 test files but missed 3 with `LLMStyleSuggestion(category: .clarity, ...)` constructions. Test target refused to compile.
**Fix:** Swapped `.clarity` → `.tone` at:
- `OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift:145, 189`
- `OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift:8`
- `OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift:46`
**Commit:** `57b8237` (folded into Task 3 commit)
**Rationale:** Blocking — plan acceptance demanded compile-clean test target; rename only, no semantic shift (both `.tone` and `.clarity` decoded identically pre-deletion).

### 2. [Rule 3 - Blocking Issue] Pipeline fixture JSON constant renamed

**Found during:** Task 1
**Issue:** `canned3SuggestionsJSON` literal name referenced count of 3 — post clarity-delete fixture decodes to 2 suggestions via DTO silent-drop. Name-count mismatch.
**Fix:** Renamed → `canned2SuggestionsJSON`, stripped clarity JSON entry. 7 call sites updated.
**Commit:** `9563755`
**Rationale:** Consistency fix. Not architectural.

### 3. [Rule 3 - Blocking Issue] LLMServiceTests `.clarity` hits beyond enumerated lines 157-274

**Found during:** Task 1
**Issue:** Plan called out only `configDefaultValues` + `makeEnabledConfig` helper. Grep revealed clarity JSON strings in `parseValidThreeSuggestionResponse`, `parsePreambleBeforeObject`, `filtersLowConfidenceSuggestions`, `parseMalformedJSONReturnsEmpty` (not affected — was plain text). Plan acceptance criterion `grep -c "\.clarity" → 0` demanded total strip.
**Fix:** Rewrote JSON fixtures in 3 tests, replaced clarity categories with tone/rephrase.
**Commit:** `9563755`

## Threat Flags

None. T-07-12 (clarity reaches UI) mitigated by new CLAR-09 regression test locking DTO silent-drop. T-07-13 (LLM fabricates clarity category) covered by same mechanism via unknown-rawValue guard.

## Self-Check: PASSED

- FOUND: `OpenGramTests/CheckEngine/LLMResponseDTOTests.swift` (clarityCategoryDroppedPostDeletion_CLAR09 present; 0 `D-NN` tokens)
- FOUND: `OpenGramTests/LLMPromptsTests.swift` (0 `clarity` tokens; two-dim + grammar assertions)
- FOUND: `OpenGramTests/LLMServiceTests.swift` (0 `.clarity`; count==2)
- FOUND: `OpenGramTests/LMStudioPipelineIntegrationTests.swift` (0 `.clarity`)
- FOUND: `OpenGramTests/LMStudioLiveIntegrationTests.swift` (0 `.clarity`)
- FOUND: `OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift` (0 `oneIssue_clarity_qualifies`; 1 `oneIssue_rephrase_qualifies`)
- FOUND: `OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift` (0 `categoryMap_clarity`; 0 `D-22`)
- FOUND: commit `9563755` (Task 1)
- FOUND: commit `6b88b07` (Task 2)
- FOUND: commit `57b8237` (Task 3 + Rule 3 blocking fixes)
- Test validation: 77 Plan 07-05 scope tests all pass; app target + test target compile clean
- Pre-existing failures logged to deferred-items.md (out of scope)
