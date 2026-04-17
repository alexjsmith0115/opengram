---
phase: 18-paragraph-rephrase-card
plan: "08"
subsystem: verification
tags: [integration-tests, regression, flag-off, REPH-11, REPH-15, phase-18]
dependency_graph:
  requires: [18-01, 18-02, 18-03, 18-04, 18-05, 18-06, 18-07]
  provides: [RephraseCardLifecycleTests, OverlayControllerFlagOffRegressionTests, LLMPrompts REPH-11 superset assertion]
  affects: [LLMPrompts.systemPrompt]
tech_stack:
  added: []
  patterns:
    - Lifecycle integration tests cover hide vs dismiss vs accept state machine
    - Flag-off regression asserts byte-identical per-issue popover path for REPH-15
    - Prompt superset assertion enforces REPH-11 (grammar + spelling + clarity keywords)
key_files:
  created:
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardLifecycleTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerFlagOffRegressionTests.swift
  modified:
    - OpenGramTests/LLMPromptsTests.swift
    - OpenGram/CheckEngine/LLM/LLMPrompts.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "REPH-11 prompt gap patched in LLMPrompts.systemPrompt — added explicit grammar/spelling keywords so rephrase is Harper superset (D-21)"
  - "Task 4 (manual validation in Notes.app via computer-use MCP) deferred to Phase 19 UAT — precedent: Phase 16 Task 5"
  - "Lifecycle tests exercise observable state machine (cache status, hiddenParagraphScalarRange transitions) rather than full AX dispatch, which is covered by AXTextReplacerTests + OverlayControllerRephraseIntegrationTests"
metrics:
  duration: ~40 minutes (automated portion)
  completed: 2026-04-16
  tasks: 3 of 4 automated (Task 4 deferred)
  files: 5
  test_count_final: 441
---

# Phase 18 Plan 08: Final Integration + Checkpoint Summary

**One-liner:** Three automated integration suites landed (lifecycle, flag-off regression, REPH-11 prompt superset) with 441/441 tests green; Task 4 manual validation deferred to Phase 19 UAT.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RephraseCardLifecycleTests (REPH-07/08) | aa2cb5e | RephraseCardLifecycleTests.swift (NEW), pbxproj |
| 2 | Flag-off regression + REPH-11 prompt superset | 33d1420 | OverlayControllerFlagOffRegressionTests.swift (NEW), LLMPromptsTests.swift, LLMPrompts.swift |
| 3 | Full-suite regression baseline | f9de520 | Evidence commit: 441 tests green |
| 4 | Manual validation via computer-use MCP | DEFERRED | Deferred to Phase 19 UAT |

## What Was Built

### Task 1 — Lifecycle tests
`RephraseCardLifecycleTests` exercises the hide vs dismiss vs accept state machine through `OverlayController` + `LLMCheckScheduler` + `ParagraphSuggestionCache`:
- `hide_doesNotMutateCache` — showUnderlines after hideUnderlines leaves cache `.active`.
- `dismiss_marksCacheEntryDismissed` — `scheduler.markDismissed` flips cache to `.dismissed`.
- Observable state transitions verified via `hiddenParagraphScalarRange` and cache lookup.

### Task 2 — Flag-off regression + prompt superset
`OverlayControllerFlagOffRegressionTests` asserts per-issue popover path is byte-identical when `paragraphRephraseCardEnabled == false` — REPH-15.

`LLMPromptsTests.prompt_coversRephraseSuperset_REPH11` asserts the system prompt contains "grammar" + "spelling" + "clarity" keywords. Exposed a gap: prior prompt had none. Patched `LLMPrompts.systemPrompt` to explicitly state the rephrase must fix grammar + spelling as a Harper superset (D-21).

### Task 3 — Regression baseline
Full `xcodebuild test` run: 441/441 green across 67 suites. Pre-existing flakiness in `AXCallWatchdogTests.blocklistExpires` and `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit` — both pass in isolation; timing-sensitive, not phase-18 regressions.

### Task 4 — Deferred
Manual 12-step validation in Notes.app with screenshots via `computer-use` MCP. MCP not available in current session. Deferred to Phase 19 UAT per user decision and Phase 16 Task 5 precedent.

## Requirement Coverage

| Req | Covered by |
|-----|------------|
| REPH-01..06 | Prior plans (01-07) + existing unit tests |
| REPH-07 (dismiss) | `dismiss_marksCacheEntryDismissed` |
| REPH-08 (hide ≠ dismiss) | `hide_doesNotMutateCache` + existing `RephraseCardPanelControllerTests` |
| REPH-09 (underline hide) | `OverlayControllerHideUnderlinesTests` (18-06) |
| REPH-10 (Accept superset) | AXTextReplacerTests + prompt assertion |
| REPH-11 (prompt superset) | `prompt_coversRephraseSuperset_REPH11` |
| REPH-12 (display heuristic) | `DisplayHeuristicTests` (18-02) |
| REPH-13 (card UI) | `RephraseCardViewTests` (18-05) |
| REPH-14 (edit-closes) | `RephraseCardPanelControllerTests` subscription restore |
| REPH-15 (flag-off parity) | `OverlayControllerFlagOffRegressionTests` |

## Deferred Items

- **Task 4 manual validation** → Phase 19 UAT (the 12-step Notes.app interactive sequence with computer-use MCP screenshots).

## Pre-existing Flaky Tests (Tolerated)

- `AXCallWatchdogTests.blocklistExpires` — timing-sensitive; passes isolated.
- `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit` — timing-sensitive; passes isolated.
