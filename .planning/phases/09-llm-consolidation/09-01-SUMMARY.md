---
phase: "09-llm-consolidation"
plan: "09-01"
subsystem: "CheckEngine"
tags: ["llm", "foundation-types", "dto", "paragraph-extraction"]
dependency_graph:
  requires: []
  provides:
    - "LLMStyleSuggestion: paragraph-level suggestion model with Category enum"
    - "LLMResponseDTO: Codable DTO with confidence filtering and unknown-category dropping"
    - "ParagraphExtractor: text scoping utility for LLM input"
  affects:
    - "09-02 (LLM service refactor depends on these types)"
tech_stack:
  added: []
  patterns:
    - "Codable DTO with nested toModel() mapping and validation"
    - "Static utility enum for pure-function text processing"
key_files:
  created:
    - "OpenGram/CheckEngine/LLMStyleSuggestion.swift"
    - "OpenGram/CheckEngine/LLMResponseDTO.swift"
    - "OpenGram/CheckEngine/ParagraphExtractor.swift"
    - "OpenGramTests/CheckEngine/LLMResponseDTOTests.swift"
    - "OpenGramTests/CheckEngine/ParagraphExtractorTests.swift"
  modified:
    - "OpenGram.xcodeproj/project.pbxproj"
decisions:
  - "LLMResponseDTO uses a top-level {suggestions:[]} envelope rather than a bare array — matches the paragraph-level LLM prompt design in 09-02"
  - "ParagraphExtractor implemented as enum (not struct/class) to enforce no instantiation for a pure-function utility"
  - "CFRange location used as Unicode scalar offset (consistent with existing TextContext/Harper conventions)"
metrics:
  duration_minutes: 30
  completed_date: "2026-04-15"
  tasks_completed: 3
  tasks_total: 3
  files_created: 5
  files_modified: 1
---

# Phase 09 Plan 01: Foundation Types Summary

## One-liner

Paragraph-level LLM suggestion types — `LLMStyleSuggestion` model, `LLMResponseDTO` Codable DTO with confidence/category filtering, and `ParagraphExtractor` for selection/paragraph/fallback text scoping.

## What Was Built

Three dependency-free types consumed by the 09-02 LLM service refactor:

**`LLMStyleSuggestion`** — `Sendable` struct with `Category` enum (`clarity`, `tone`, `rephrase`), `originalText`, `revisedText`, `explanation`, and `confidence` (Int 1–10). Distinct from the range-based `Suggestion` model used by the overlay.

**`LLMResponseDTO`** — `Codable` struct wrapping `[SuggestionDTO]`. `SuggestionDTO.toModel(originalText:)` maps to `LLMStyleSuggestion`, filtering confidence < 7 and dropping unknown categories. `LLMResponseDTO.toModels(from:originalText:)` is the primary decoding entry point and throws on malformed JSON.

**`ParagraphExtractor`** — Static `extract(from:)` method with three-priority logic:
1. Non-empty selection from `TextContext.selectionRange` + `length > 0`
2. Newline-bounded paragraph around cursor (`selectionRange.location`)
3. `text.prefix(2000)` fallback

## Tests

257 tests pass (0 failures). New tests cover:
- `LLMResponseDTOTests`: valid 3-suggestion parse, empty array, confidence boundary (6 filtered / 7 kept), malformed JSON throws, missing required field throws, unknown category dropped, extra fields ignored
- `ParagraphExtractorTests`: selection priority, paragraph around cursor (middle/start/end), single-paragraph text, 2000-char cap, empty text

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

**Created files:**
- `OpenGram/CheckEngine/LLMStyleSuggestion.swift` — exists
- `OpenGram/CheckEngine/LLMResponseDTO.swift` — exists
- `OpenGram/CheckEngine/ParagraphExtractor.swift` — exists
- `OpenGramTests/CheckEngine/LLMResponseDTOTests.swift` — exists
- `OpenGramTests/CheckEngine/ParagraphExtractorTests.swift` — exists

**Commits:**
- `2846339` — feat(09-01): add LLMStyleSuggestion and LLMResponseDTO foundation types
- `fe71cc7` — feat(09-01): add ParagraphExtractor for text scoping
- `cbb4719` — test(09-01): add LLMResponseDTO and ParagraphExtractor tests

## Self-Check: PASSED
