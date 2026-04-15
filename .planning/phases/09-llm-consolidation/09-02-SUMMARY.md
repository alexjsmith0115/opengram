---
phase: "09-llm-consolidation"
plan: "09-02"
subsystem: "CheckEngine"
tags: ["llm", "refactor", "service", "protocol"]
dependency_graph:
  requires:
    - "09-01"
  provides:
    - "LLMService.analyze(paragraph:config:apiKey:)"
    - "LLMPrompts.systemPrompt()"
    - "LLMProviderProtocol.analyze"
  affects:
    - "CheckOrchestrator"
    - "LLMConfig"
    - "LLMStyleSuggestion"
tech_stack:
  added: []
  patterns:
    - "Actor with currentTask cancellation before new request"
    - "URLProtocol mocking for network tests"
    - "LLMResponseDTO decode path reused in parseJSONContent"
key_files:
  created: []
  modified:
    - "OpenGram/CheckEngine/LLMPrompts.swift"
    - "OpenGram/CheckEngine/LLMProviderProtocol.swift"
    - "OpenGram/CheckEngine/LLMService.swift"
    - "OpenGram/CheckEngine/LLMConfig.swift"
    - "OpenGram/CheckEngine/LLMStyleSuggestion.swift"
    - "OpenGram/CheckEngine/CheckOrchestrator.swift"
    - "OpenGramTests/LLMServiceTests.swift"
    - "OpenGramTests/LLMPromptsTests.swift"
    - "OpenGramTests/CheckOrchestratorTests.swift"
decisions:
  - "Moved LLMCheckType from LLMProviderProtocol to LLMConfig to keep CheckOrchestrator compiling during Phase 12 transition"
  - "Updated CheckOrchestrator to call analyze() and bridge LLMStyleSuggestion -> Suggestion via D-16 substring search, rather than leaving a compile error"
  - "parseJSONContent now searches for { not [ (unified response is an object, not array)"
metrics:
  duration: "~20 minutes"
  completed: "2026-04-15"
  tasks_completed: 3
  files_modified: 9
---

# Phase 09 Plan 02: Service Refactor Summary

Single `analyze()` call replaces three per-category `check()` dispatches. Unified system prompt covers clarity/tone/rephrase in one LLM pass with confidence-gated filtering.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | LLMPrompts unified system prompt | 34457e3 |
| 2 | LLMProviderProtocol + LLMService refactor | 34457e3 |
| 3 | Test suite updated for new API | 268f38b |

## What Was Built

**LLMPrompts.swift** — Replaced three per-category system prompts with `systemPrompt(harperSpans:)` and `userMessage(for:)`. The unified prompt instructs the LLM to evaluate all three dimensions (clarity, tone, rephrase) in one pass and return a `{"suggestions": [...]}` JSON object. Harper span injection retained (D-11).

**LLMProviderProtocol.swift** — Replaced `check(text:type:config:harperSpans:)` with `analyze(paragraph:config:apiKey:) -> [LLMStyleSuggestion]`. `healthCheck` unchanged.

**LLMService.swift** — Actor refactored:
- `private var currentTask: Task<[LLMStyleSuggestion], Error>?` — cancels in-flight request on new `analyze()` call
- Single POST to `/v1/chat/completions` using unified prompt
- Parses via `LLMResponseDTO.toModels()` with four-step resilient fallback (strip fences → strip preamble → JSONDecoder → brace-matching)
- Returns `[]` on any failure (D-08 pattern)

**LLMConfig.swift** — `LLMCheckType` enum moved here from `LLMProviderProtocol` (it was deleted from there) so `CheckOrchestrator` keeps compiling until Phase 12.

**LLMStyleSuggestion.Category** — Added `checkCategory: CheckCategory` bridge property for the legacy `Suggestion` type mapping in `CheckOrchestrator`.

**CheckOrchestrator.swift** — Updated to call `analyze()` instead of per-type `check()`. New `mapStyleSuggestions(_:sourceText:)` helper converts `[LLMStyleSuggestion]` to `[Suggestion]` using D-16 substring search. Phase 12 will replace this bridge entirely.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMCheckType scope error after protocol cleanup**
- **Found during:** Task 2
- **Issue:** `LLMCheckType` was defined in `LLMProviderProtocol.swift` which was replaced. `LLMConfig` and `CheckOrchestrator` still referenced it.
- **Fix:** Moved `LLMCheckType` to `LLMConfig.swift` with a comment noting Phase 12 removal.
- **Files modified:** `LLMConfig.swift`
- **Commit:** 34457e3

**2. [Rule 3 - Blocking] CheckOrchestrator called old check() API**
- **Found during:** Task 2 (expected per plan)
- **Issue:** Build failure in CheckOrchestrator after protocol signature change.
- **Fix:** Updated CheckOrchestrator to call `analyze()` and added `mapStyleSuggestions()` bridge rather than leaving a compile error. Build stays green.
- **Files modified:** `CheckOrchestrator.swift`
- **Commit:** 34457e3

**3. [Rule 1 - Bug] LLMStyleSuggestion.Category missing checkCategory**
- **Found during:** Task 2 (during CheckOrchestrator update)
- **Issue:** `CheckOrchestrator.mapStyleSuggestions()` needed `style.category.checkCategory` but `LLMStyleSuggestion.Category` had no such property.
- **Fix:** Added `checkCategory: CheckCategory` computed property to `LLMStyleSuggestion.Category`.
- **Files modified:** `LLMStyleSuggestion.swift`
- **Commit:** 34457e3

**4. [Rule 1 - Bug] parseJSONContent searches { not [ (unified format is object)**
- **Found during:** Task 2
- **Issue:** Old parser stripped preamble before `[` (array), but new unified response is a JSON object `{"suggestions": [...]}` so the search should be for `{`.
- **Fix:** Updated step 2 of resilient parser to search for `{`.
- **Files modified:** `LLMService.swift`
- **Commit:** 34457e3

**5. [Rule 1 - Bug] HarperBridge.xcframework missing from worktree**
- **Found during:** First build attempt
- **Issue:** Worktree lacked the xcframework symlink/copy from main repo.
- **Fix:** Created symlink `HarperBridge.xcframework -> /Users/alex/Dev/opengram/HarperBridge.xcframework`. Not committed (xcframework is gitignored).
- **Files modified:** (filesystem only)

## Self-Check: PASSED

All key files found. Both task commits verified in git log.
