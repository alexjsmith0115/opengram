---
phase: "13-tech-debt"
plan: "13-01"
subsystem: "app-wide"
tags: ["tech-debt", "settings", "llm", "apply", "harper-spans", "dead-code"]
dependency_graph:
  requires: ["12-01"]
  provides: ["whitelist-settings-reachable", "llm-apply-functional", "harper-spans-in-prompt", "dead-code-removed"]
  affects: ["LLMSettingsView", "AppDelegate", "CheckOrchestrator", "LLMService", "LLMProviderProtocol", "LLMStyleSuggestion", "LLMConfig"]
tech_stack:
  added: []
  patterns:
    - "TabView wrapping independent settings panes"
    - "awaiting checkTask before llmTask to ensure Harper spans are available"
    - "AXTextEngine.writeBack with adjusted TextContext.selectionRange for substring replace"
key_files:
  created: []
  modified:
    - "OpenGram/SuggestionUI/LLMSettingsView.swift"
    - "OpenGram/App/AppDelegate.swift"
    - "OpenGram/CheckEngine/LLMProviderProtocol.swift"
    - "OpenGram/CheckEngine/LLMService.swift"
    - "OpenGram/CheckEngine/CheckOrchestrator.swift"
    - "OpenGram/CheckEngine/LLMStyleSuggestion.swift"
    - "OpenGram/CheckEngine/LLMConfig.swift"
    - "OpenGramTests/CheckOrchestratorTests.swift"
    - "OpenGramTests/Integration/TwoPhaseCheckFlowTests.swift"
decisions:
  - "Tabbed settings (TabView) rather than scrollable single-form: WhitelistSettingsView is a distinct concern, a tab keeps the two panes independently navigable"
  - "llmTask awaits checkTask before reading Harper spans: avoids a concurrent read race; LLM start latency is negligible vs LLM inference time"
  - "replaceSubstring uses range(of:) on full text and constructs an adjusted TextContext with cfRange, then delegates to writeBack — reuses the existing write-back contract rather than duplicating AX write logic"
  - "ParagraphExtractor applied in CheckOrchestrator.runCheck, not TextMonitor — orchestrator owns the two-tier pipeline so it's the right place to scope LLM input"
metrics:
  duration: "~7 minutes"
  completed_date: "2026-04-15T21:56:12Z"
  tasks_completed: 4
  files_modified: 9
---

# Phase 13 Plan 01: Tech Debt Cleanup Summary

One-liner: Wired WhitelistSettingsView tab into settings, implemented LLM Apply via AX write-back, injected Harper spans into LLM prompt via task chaining, and removed the dead `checkCategory` bridge property.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Wire WhitelistSettingsView into tabbed settings window | 1532100 |
| 2 | Implement LLM panel Apply — write revised text back to target app | 75daa08 |
| 3 | Pass Harper spans to LLM prompt; apply ParagraphExtractor in orchestrator path | 460232c |
| 4 | Remove dead checkCategory property; update stale LLMCheckType comment | bdcdf25 |

## What Was Done

### Task 1 — WhitelistSettingsView in Settings

Introduced `SettingsView` (a `TabView`) that hosts `LLMSettingsView` and `WhitelistSettingsView` as tabs. `LLMSettingsPanel.show()` now presents `SettingsView` instead of the bare `LLMSettingsView`. Panel title changed to "OpenGram Settings", height increased from 320 to 500pt to accommodate the whitelist list.

### Task 2 — LLM Panel Apply

Two new methods on `AppDelegate`:

- `applyLLMSuggestion(_:)` — checks whether the `lastExtractedContext` had a user selection matching `originalText`; if so calls `textEngine.writeBack(context:replacement:)` directly; otherwise delegates to `replaceSubstring`.
- `replaceSubstring(originalText:revisedText:in:)` — searches the stored full text for the first occurrence of `originalText`, computes its Unicode scalar offset range, builds an adjusted `TextContext` with `selectionRange` covering that range, then calls `engine.writeBack(context:replacement:)`.

Both the hotkey path and TextMonitor `onLLMBatch` path are wired. The TextMonitor path also updates `lastExtractedContext` before showing the panel.

### Task 3 — Harper Spans in LLM Prompt

- `LLMProviderProtocol.analyze()` gains `harperSpans: [String]` parameter.
- `LLMService.analyze()` forwards spans to `LLMPrompts.systemPrompt(harperSpans:)` (which already had the injection logic).
- `CheckOrchestrator.runCheck()` extracts `harperResults.map { $0.original }` as spans and applies `ParagraphExtractor.extract(from:context)` for the paragraph sent to the LLM.
- `AppDelegate` hotkey Phase 2 captures `checkTask` as `harperCheckTask`, awaits it inside `llmTask` before reading `lastSuggestions`, ensuring spans are populated before the LLM request.

### Task 4 — Dead Code Removal

- Removed `LLMStyleSuggestion.Category.checkCategory` computed property — was a bridge to `CheckCategory` for the legacy overlay path removed in Phase 12.
- Updated `LLMCheckType` doc comment: removed the stale "will be removed in Phase 12" note; rewritten to describe its actual current purpose (per-category enable/disable for user settings).
- Updated three test mocks (`SlowMockLLMProvider`, `MockLLMProvider`, `FailingLLMProvider`) to conform to the updated `LLMProviderProtocol` signature.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] HarperBridge.xcframework missing in worktree**
- **Found during:** Task 1 build verification
- **Issue:** Worktree did not have the pre-built xcframework (build artifact, not tracked by git)
- **Fix:** Created symlink `HarperBridge.xcframework -> /Users/alex/Dev/opengram/HarperBridge.xcframework`
- **Files modified:** None (symlink only)

**2. [Rule 1 - Bug] `engine` reference in else-branch of guard-cast**
- **Found during:** Task 2 build
- **Issue:** `guard let engine = textEngine as? AXTextEngine else { return engine?.writeBack(...) }` — `engine` is out of scope in the else branch
- **Fix:** Changed to `textEngine?.writeBack(...)` to reference the property directly
- **Commit:** 75daa08

**3. [Rule 2 - Missing functionality] Test mocks not updated for new `harperSpans` parameter**
- **Found during:** Task 4 test run
- **Issue:** Three `LLMProviderProtocol` mocks in test targets failed to conform after protocol signature change
- **Fix:** Updated `SlowMockLLMProvider`, `MockLLMProvider`, `FailingLLMProvider` to accept `harperSpans: [String]` parameter
- **Commit:** bdcdf25

## Known Stubs

None — all wired functionality reaches live AX write-back paths.

## Self-Check: PASSED

- LLMSettingsView.swift: FOUND
- AppDelegate.swift: FOUND
- 13-01-SUMMARY.md: FOUND
- Commits 1532100, 75daa08, 460232c, bdcdf25: all present
