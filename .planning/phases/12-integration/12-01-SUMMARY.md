---
phase: "12-integration"
plan: "12-01"
subsystem: "hotkey-flow"
tags: ["integration", "whitelist", "llm-panel", "two-phase-check"]
dependency_graph:
  requires: ["09-02", "10-01", "11-01"]
  provides: ["two-phase-hotkey-flow", "whitelist-gate", "llm-panel-wiring"]
  affects: ["AppDelegate", "CheckOrchestrator", "TextMonitor", "StatusBarController"]
tech_stack:
  added: []
  patterns: ["two-phase async check", "LLMPanelController for style results", "whitelist gate before extraction"]
key_files:
  created: []
  modified:
    - "OpenGram/App/AppDelegate.swift"
    - "OpenGram/CheckEngine/CheckOrchestrator.swift"
    - "OpenGram/TextMonitor/TextMonitor.swift"
    - "OpenGram/Shell/StatusBarController.swift"
    - "OpenGramTests/CheckOrchestratorTests.swift"
decisions:
  - "LLM results go to LLMPanelController (not overlay) — hardFilter and mapStyleSuggestions removed since range-based dedup only mattered for overlay rendering"
  - "flashInactive uses direct alphaValue + DispatchQueue.main.asyncAfter to avoid Swift 6 concurrency warnings from NSAnimationContext closures"
  - "onLLMBatch callback type changed from [Suggestion] to [LLMStyleSuggestion] end-to-end — TextMonitor updated alongside CheckOrchestrator"
metrics:
  duration_minutes: 6
  completed_date: "2026-04-15T21:23:39Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 5
---

# Phase 12 Plan 01: Core Wiring Summary

## One-liner

Two-phase hotkey flow with AppWhitelist gate, Harper instant overlay, and async LLMPanelController for style suggestions.

## What Was Built

**Task 1 — AppDelegate + StatusBarController**

- Added `llmPanelController: LLMPanelController`, `appWhitelist: AppWhitelist`, and `llmTask: Task<Void, Never>` to AppDelegate
- Rewrote `handleHotkeyFired()` with:
  1. Whitelist gate: checks frontmost app bundle ID against AppWhitelist before any text extraction; calls `statusBarController.flashInactive()` and returns if blocked
  2. Dismisses existing overlay and LLM panel
  3. Phase 1 (`checkTask`): Harper check on full text — shows underlines immediately
  4. Phase 2 (`llmTask`): `ParagraphExtractor.extract()` → `llmService.analyze()` → `LLMPanelController.show()` anchored to element bounds
  5. LLM failure is non-fatal — Harper results always shown; LLM panel silently omitted on failure
- Added `StatusBarController.flashInactive()`: dims icon to 0.2 alpha then restores after 300ms

**Task 2 — CheckOrchestrator + cascade**

- Changed `onLLMBatch` callback type from `([Suggestion], TextContext)` to `([LLMStyleSuggestion], TextContext)` in CheckOrchestrator, TextMonitor, and AppDelegate
- Removed `mapStyleSuggestions` and `hardFilter` — no longer needed since LLM results bypass the overlay entirely
- Background TextMonitor LLM checks now surface via `llmPanelController.show()` in AppDelegate's `onLLMBatch`
- Updated `CheckOrchestratorTests`: removed 4 `hardFilter` tests (testing removed functionality), fixed `llmBatches` type to `[LLMStyleSuggestion]`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 concurrency warnings in flashInactive()**
- **Found during:** Task 1
- **Issue:** `NSAnimationContext.runAnimationGroup` closures are nonisolated in Swift 6, causing warnings when accessing `@MainActor`-isolated `button.animator()` and `alphaValue`
- **Fix:** Replaced NSAnimationContext animation with direct `button.alphaValue = 0.2` + `DispatchQueue.main.asyncAfter` restore — matches the existing `applyIcon` pattern in the same file
- **Files modified:** `OpenGram/Shell/StatusBarController.swift`
- **Commit:** 1023961

**2. [Rule 1 - Bug] Test failures from removed hardFilter**
- **Found during:** Task 2
- **Issue:** 4 `hardFilter` tests and 1 type mismatch (`[Suggestion]` vs `[LLMStyleSuggestion]`) broke the test target when `hardFilter` was removed
- **Fix:** Removed the 4 `hardFilter` tests (they tested deleted functionality) and updated `llmBatches` type to `[[LLMStyleSuggestion]]`
- **Files modified:** `OpenGramTests/CheckOrchestratorTests.swift`
- **Commit:** d0aa607

**3. [Rule 3 - Blocking] Missing HarperBridge.xcframework in worktree**
- **Found during:** Task 1 first build attempt
- **Issue:** The worktree doesn't have the compiled xcframework — it's a build artifact in the main repo
- **Fix:** Created symlink `HarperBridge.xcframework -> /Users/alex/Dev/opengram/HarperBridge.xcframework`
- **Commit:** N/A (filesystem-only fix)

## Self-Check: PASSED

- AppDelegate.swift: FOUND
- StatusBarController.swift: FOUND
- CheckOrchestrator.swift: FOUND
- SUMMARY.md: FOUND
- Commit 1023961 (Task 1): FOUND
- Commit d0aa607 (Task 2): FOUND
