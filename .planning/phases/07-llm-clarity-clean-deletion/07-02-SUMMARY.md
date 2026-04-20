---
phase: 07-llm-clarity-clean-deletion
plan: 02
subsystem: LLM pipeline / prompt surface
tags: [refactor, enum-deletion, prompt-rewrite, clean-replace, CLAR-09]
requires: []
provides:
  - "LLMCheckType without .clarity"
  - "LLMStyleSuggestion.Category without .clarity"
  - "LLMPrompts.systemPrompt three-dim text"
affects:
  - "Xcode build (intentionally broken at call sites — plans 03+04 fix)"
  - "LLM HTTP request body (via LLMService.makeRequest → systemPrompt)"
  - "DTO decode path (LLMResponseDTO.SuggestionDTO.toModel silently drops stray clarity category)"
tech_stack:
  added: []
  patterns: [compiler-driven-refactor, clean-replace-no-shim]
key_files:
  modified:
    - OpenGram/CheckEngine/LLM/LLMConfig.swift
    - OpenGram/CheckEngine/LLM/LLMStyleSuggestion.swift
    - OpenGram/CheckEngine/LLM/LLMPrompts.swift
  created: []
decisions:
  - "D-12: clean delete of .clarity case from both enums (no alias, no @available)"
  - "D-01: surgical prompt delete of clarity dimension block + count text"
  - "D-02: JSON example retargeted to category: tone (most frequent remaining dim)"
  - "D-03: harperSpans suppression block preserved verbatim"
  - "Deviation Rule 2: suggestion array max 0-3 → 0-2 (count consistency with dim collapse)"
metrics:
  duration_minutes: ~4
  tasks_completed: 2
  files_modified: 3
  completed: 2026-04-20
---

# Phase 7 Plan 2: LLM Clarity Clean-Deletion — Root Refactor Summary

Deleted `.clarity` case from `LLMCheckType` + `LLMStyleSuggestion.Category` and stripped clarity dimension from `LLMPrompts.systemPrompt`. Compiler-driven refactor root — downstream call sites intentionally break until plans 03+04 fix them.

## Changes

### Task 1 — Enum deletions (commit `d5fb8c1`)

**`OpenGram/CheckEngine/LLM/LLMConfig.swift`**
- Removed `case clarity` from `LLMCheckType`.
- Updated docstring tone+clarity+rephrase → tone+rephrase.
- `LLMConfig.default.enabledChecks = Set(LLMCheckType.allCases)` auto-shrinks 3→2 members.

**`OpenGram/CheckEngine/LLM/LLMStyleSuggestion.swift`**
- Removed `case clarity` from nested `Category` enum.
- `CaseIterable` preserved; post-deletion set = `{tone, rephrase}`.

### Task 2 — Prompt rewrite (commit `71ad61a`)

**`OpenGram/CheckEngine/LLM/LLMPrompts.swift`**
- Intro: "four dimensions: clarity, tone, rephrase, grammar/spelling" → "three dimensions: tone, rephrase, grammar/spelling".
- Deleted entire `**clarity**: ...` dimension paragraph.
- JSON example `"category": "clarity"` → `"category": "tone"` (D-02: tone is most frequent remaining dim).
- Rules line `category (string: "clarity"|"tone"|"rephrase")` → `(string: "tone"|"rephrase")`.
- `harperSpans` suppression block left verbatim (D-03).
- Docstring updated to reflect three-dim semantics.

## Deviations from Plan

### 1. [Rule 2 - Missing Critical Functionality] Suggestion array max count

**Found during:** Task 2
**Issue:** Rules line said `"suggestions" is an array of 0 to 3 objects.` Post-deletion only 2 categories remain (tone, rephrase) and rule `Never include more than one suggestion per category` caps total at 2. Leaving "0 to 3" gives the LLM permission to emit a phantom third suggestion that will hit the unknown-rawValue drop in DTO, wasting tokens.
**Fix:** Changed to `"suggestions" is an array of 0 to 2 objects.`
**Files modified:** `OpenGram/CheckEngine/LLM/LLMPrompts.swift`
**Commit:** `71ad61a`
**Rationale:** Consistent with the dim collapse, no plan substitution was defined for this line but it's a derived consistency fix. Not an architectural change.

### 2. Build-break scope narrower than expected (observation, not a fix)

**Found during:** Post-task 2 xcodebuild validation
**Observation:** Plan frontmatter expected break at `OverlayController`, `ParagraphSuggestionStore`, `LLMSettingsView` call sites. Actual first-failure error is at `RephraseCardViewModel.swift:37` (`case .clarity: return .clarity`). Xcode bails after the first file-level compile failure; remaining expected errors at OverlayController/ParagraphSuggestionStore/LLMSettingsView/ConfigManager/DisplayHeuristic/tests will surface once `RephraseCardViewModel.swift` clears in plans 03+04.
**Action:** None needed. The plan's "xcodebuild WILL fail" invariant holds. No call-site fix attempted per sequential_execution instructions.

## Downstream Consequences (reminder for execute-phase)

- Plans 03 + 04 are required before `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` passes again. The break is deliberate — compiler-driven refactor per CONTEXT specific #2.
- First compile failure to tackle: `RephraseCardViewModel.swift:37` (D-16).
- After that clears, subsequent errors will appear at:
  - `OverlayController.swift:894` (switch arm, D-13)
  - `ParagraphSuggestionStore.swift:205` (switch arm, D-15)
  - `LLMSettingsView.swift:78,132` (AppStorage + Toggle, D-18)
  - `ConfigManager.swift:16` (enabledChecks read, D-11)
  - `DisplayHeuristic.swift:10` (predicate, D-17)
  - Test targets (D-21 enumeration)

## Threat Flags

None — no new trust boundaries introduced; existing silent-drop guard in `LLMResponseDTO.SuggestionDTO.toModel` (covered by T-07-03 mitigate disposition) handles any stray `clarity` category in LLM responses.

## Self-Check: PASSED

- FOUND: `OpenGram/CheckEngine/LLM/LLMConfig.swift` (no `.clarity` case)
- FOUND: `OpenGram/CheckEngine/LLM/LLMStyleSuggestion.swift` (no `.clarity` case)
- FOUND: `OpenGram/CheckEngine/LLM/LLMPrompts.swift` (0 `clarity` tokens, "three dimensions" present, `"category": "tone"` JSON example present)
- FOUND: commit `d5fb8c1` (Task 1)
- FOUND: commit `71ad61a` (Task 2)
- Acceptance criteria for both tasks: all grep counts match spec.
- harperSpans block: 3 references intact.
