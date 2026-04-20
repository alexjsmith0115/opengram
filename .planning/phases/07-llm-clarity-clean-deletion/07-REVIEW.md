---
phase: 07-llm-clarity-clean-deletion
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - OpenGram/App/ConfigManager.swift
  - OpenGram/CheckEngine/LLM/LLMConfig.swift
  - OpenGram/CheckEngine/LLM/LLMPrompts.swift
  - OpenGram/CheckEngine/LLM/LLMStyleSuggestion.swift
  - OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift
  - OpenGram/CheckEngine/Suggestion.swift
  - OpenGram/SuggestionUI/Overlay/OverlayController.swift
  - OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift
  - OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift
  - OpenGram/SuggestionUI/Settings/LLMSettingsView.swift
  - OpenGramTests/CheckEngine/LLMResponseDTOTests.swift
  - OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift
  - OpenGramTests/LLMPromptsTests.swift
  - OpenGramTests/LLMServiceTests.swift
  - OpenGramTests/LMStudioLiveIntegrationTests.swift
  - OpenGramTests/LMStudioPipelineIntegrationTests.swift
  - OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift
  - OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift
  - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardViewModelTests.swift
  - OpenGramTests/SuggestionUITests/RephraseCard/RephraseComposerTests.swift
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 07: Code Review Report — LLM `.clarity` Clean Deletion (CLAR-09, CLAR-10)

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

Clean-deletion pass is mechanically sound. `LLMCheckType` + `LLMStyleSuggestion.Category` collapsed to `{tone, rephrase}`. All exhaustive switches on these two enums (`ParagraphSuggestionStore.mapToSuggestion:204`, `OverlayController:893`, `RephraseCardViewModel.checkCategory:36`) are exhaustive with no unreachable branches. Switches over `CheckCategory` (which intentionally retains `.clarity` for Harper) either handle every case explicitly (`UnderlineView.swift:82`) or fall through `default` deliberately (OverlayController synthetic-suggestion filter at L896). DTO drop-path validated by `LLMResponseDTOTests.clarityCategoryDroppedPostDeletion_CLAR09` — unknown rawValue returns nil via `LLMStyleSuggestion.Category(rawValue:)`. Settings Toggle removed cleanly; `llmEnableTone`/`llmEnableRephrase` keys remain; `llmEnableClarity` correctly left dormant on disk per D-09.

Issues found are all documentation/comment drift — two stale docstrings still claim three LLM dimensions, one comment contains a benign historical reference, plus a minor test-coverage gap. No functional regressions.

## Warnings

### WR-01: Stale docstring contradicts two-dimension LLM surface

**File:** `OpenGram/CheckEngine/LLM/LLMPrompts.swift:5-12`
**Issue:** Class-level doc and opening sentence of the system prompt both say "tone, rephrase, and grammar/spelling" framed as "three dimensions". Post-CLAR-09 the LLM evaluates **two** style dimensions (tone, rephrase) plus grammar/spelling as an implicit superset. The phrase "three dimensions" is technically accurate if grammar counts as a dimension, but reads as a hold-over from the pre-deletion four-dim prompt and invites future confusion. The prompt body L16-22 correctly enumerates only tone + rephrase under `## Dimensions`. Code works — LLM replies parse fine — but the preamble contradicts the enumerated contract below it.
**Fix:**
```swift
/// Unified system prompt that evaluates the tone and rephrase style dimensions
/// alongside grammar/spelling (REPH-11 superset). Harper-flagged spans are
/// injected to prevent duplicate suggestions.
```
And in the prompt body:
```
You evaluate two style dimensions (tone, rephrase) and fix grammar/spelling as part of any rewrite.
```

## Info

### IN-01: Stale LLMService docstring says three style dimensions

**File:** `OpenGram/CheckEngine/LLM/LLMService.swift:6`
**Issue:** `/// Sends a single consolidated request for all three style dimensions (clarity, tone, rephrase).` — the parenthetical names `clarity` which no longer exists. Out-of-scope file for this phase but surfaced by the clean-deletion sweep; grep residue.
**Fix:**
```swift
/// Sends a single consolidated request for the tone + rephrase style dimensions
/// (grammar/spelling handled as a REPH-11 superset inside the rephrase).
```

### IN-02: CLAR-10 audit comment orphaned

**File:** `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift:12`
**Issue:** `// in-memory only — CLAR-10 audit 2026-04-19` sits above the `actor` declaration. References phase ID per project rule forbidding GSD-phase refs in source (global CLAUDE.md `no_gsd_refs_in_source`). Harmless but violates stated convention. Requirement IDs (CLAR-10) are preserved per the same rule, but "audit" + date reads as planning residue.
**Fix:** Drop the comment or convert to a plain invariant note:
```swift
// Cache is in-memory only — no persistence.
```

### IN-03: No regression test for `LLMCheckType` Codable stability

**File:** `OpenGramTests/LLMServiceTests.swift` (and `LLMConfig` sibling tests)
**Issue:** `LLMCheckType` is `Codable` and persisted indirectly via UserDefaults read paths (`ConfigManager.currentLLMConfig`). No test asserts the encoded rawValue stays `"tone"` / `"rephrase"` after the enum surgery. If a future rename silently changes wire/storage form, on-disk state would deserialize stale. Low priority — CLAR-10 scope is storage dormancy, not serialization — but a one-line guard would prevent silent drift:
**Fix:**
```swift
@Test func llmCheckType_rawValues_stable() {
    #expect(LLMCheckType.tone.rawValue == "tone")
    #expect(LLMCheckType.rephrase.rawValue == "rephrase")
    #expect(LLMCheckType.allCases.count == 2)
}
```

---

## Phase-specific audit checklist

- **Exhaustive switches post-deletion:** PASS. `ParagraphSuggestionStore.mapToSuggestion:204-207` covers both `.tone` and `.rephrase`. `OverlayController:893-897` covers both with `default` drop for Harper categories passing through `CheckCategory`. `RephraseCardViewModel.checkCategory:36-39` covers both. No compiler-generated `@unknown default` warnings possible since `LLMStyleSuggestion.Category` is closed.
- **Residual `.clarity` references in scope files:** None that represent LLM clarity. Remaining `.clarity` references are all intentional Harper-path survivors (`Suggestion.CheckCategory.clarity` — Phase 10 hook), synthetic-Suggestion placeholders at `OverlayController:1048` + `:1074` (D-14, documented), and `RephraseCardViewModel` header mapping where `.tone → .clarity` is a deliberate UI collapse for header text only.
- **Dead code / orphaned helpers:** None in scope. `RephraseCardViewModel.checkCategory(from:)` remains callable with both enum cases. No unreachable branches.
- **DTO silent-drop of unknown categories:** PASS. `LLMResponseDTOTests:96-105` proves `"clarity"` rawValue returns nil → SuggestionDTO.toModel returns nil → filtered out by compactMap.
- **Tone/rephrase path regressions:** None detected. `DisplayHeuristic.qualifies` still honors `.rephrase` as single-issue auto-qualifier; `RephraseCardViewModel.headerText` still folds `.tone → .clarity` via `checkCategory` so "Improve clarity" still surfaces for tone-only paragraphs.
- **Test coverage gaps:** `LLMCheckType.allCases.count == 2` is asserted indirectly via `LLMConfig.default.enabledChecks.count == 2` (`LLMServiceTests:155`) but no explicit rawValue-stability guard (IN-03).

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
