---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "08"
subsystem: TextMonitor / ParagraphSuggestionStore integration
tags: [text-monitor, paragraph-store, di, ax-observer, pll-04, pll-06, pll-09]
dependency_graph:
  requires: [20-03, 20-06]
  provides: [TextMonitor store/splitter/textBoxWriter DI, keystroke-invalidate hook, focus-change eager-reconcile hook]
  affects: [OpenGram/TextMonitor/TextMonitor.swift, OpenGramTests/TextMonitorTests.swift]
tech_stack:
  added: []
  patterns: [nil-defaulted DI params for backward compat, #if DEBUG test seam, Task { await actor } async hop]
key_files:
  modified:
    - OpenGram/TextMonitor/TextMonitor.swift
    - OpenGramTests/TextMonitorTests.swift
decisions:
  - "Store/splitter/textBoxWriter params default nil so all existing 5-arg call sites (tests, AppDelegate before Plan 10) compile unchanged"
  - "caretOffset resolved via context.selectionRange.map { Int($0.location) } in both drive methods — single pattern, both PLL-06 call sites"
  - "textBoxWriter tied to store guard: absent store means no write — simpler, single-wire semantics"
  - "#if DEBUG triggerEagerReconcileForTesting follows Phase 15/16 convention for internal test seams"
  - "LLMConfig init uses real field names (baseURL: String, enabledChecks:, maxTokens:, requestTimeout:, confidenceThreshold:) — plan fixture assumed wrong signature, fixed inline"
  - "StubLLM uses NSLock instead of OSAllocatedUnfairLock — OSAllocatedUnfairLock not imported in test target without explicit os import; NSLock already present in file"
metrics:
  duration: 189s
  completed: 2026-04-17
  tasks_completed: 1
  files_modified: 2
---

# Phase 20 Plan 08: TextMonitor Store/Splitter DI + Phase 20 Hooks Summary

TextMonitor extended with ParagraphSuggestionStore + ParagraphSplitter DI; keystroke fires invalidateDisplayed (PLL-04), focus change fires eager reconcile (PLL-09), caret offset resolved from TextContext.selectionRange in both paths (PLL-06), textBoxWriter hook wired for Plan 10 MainActorTextBox consumer.

## Tasks

| Task | Description | Commit | Status |
|------|-------------|--------|--------|
| 1 | Extend TextMonitor init + store/splitter hooks + tests | 862d2f3 | Complete |

## What Was Built

### TextMonitor.swift changes

Three new stored properties added after `watchdog`:
- `store: ParagraphSuggestionStore?`
- `splitter: ParagraphSplitter?`
- `textBoxWriter: (@Sendable (String, String) -> Void)?`

Init extended from 5 params to 8 — new three default to `nil` so all existing call sites unchanged.

Two new private methods:
- `driveStoreOnValueChange()` — called from `handleValueChanged()` after debounce schedule; calls `store.invalidateDisplayed(bundleID:currentSet:)` via `Task { await … }`. No reconcile, no queue submit.
- `driveStoreOnFocusChange()` — called from `installObserver(pid:element:bundleID:)` after poll timer decision; calls `store.reconcile(set:)` via `Task { await … }`. Bypasses Harper debounce.

Both methods:
1. Guard on `store != nil && splitter != nil` — nil store is silent no-op
2. Guard on `extractText()` returning non-empty text
3. Resolve `caretOffset: Int? = context.selectionRange.map { Int($0.location) }`
4. Call `textBoxWriter?(bundleID, text)` before dispatching Task

`#if DEBUG` test seam `triggerEagerReconcileForTesting()` invokes `driveStoreOnFocusChange()` directly.

### D-03 preservation evidence

```
grep -c 'AXObserverCreate' OpenGram/TextMonitor/TextMonitor.swift
→ 1
```
Single observer, no second observer created.

### Caret-offset resolution evidence

```
grep -c 'context.selectionRange.map { Int($0.location) }' OpenGram/TextMonitor/TextMonitor.swift
→ 2
```
Both `driveStoreOnValueChange` and `driveStoreOnFocusChange` independently resolve caret offset.

### Test seam acceptance evidence

Release build: `** BUILD SUCCEEDED **` — `triggerEagerReconcileForTesting` is excluded from production builds by `#if DEBUG`.

## Tests

5 new tests in `TextMonitorStoreIntegrationTests` suite:

| Test | Requirement | Result |
|------|-------------|--------|
| valueChange drives invalidate only — no LLM requests fired | PLL-04 | PASS |
| focusChange drives eager reconcile — LLM request fires | PLL-09 | PASS |
| focusChange routes caret offset so caret paragraph is skipped | PLL-06 | PASS |
| valueChange invokes textBoxWriter with bundleID and text | textBoxWriter contract | PASS |
| nil store — keystroke and eager reconcile do not crash | nil-guard | PASS |

All 16 existing TextMonitor tests still pass. Full suite unaffected.

## textBoxWriter Contract (Plan 10 handoff)

`textBoxWriter` is a `@Sendable (bundleID: String, text: String) -> Void` closure. AppDelegate (Plan 10) passes:
```swift
textBoxWriter: { bundleID, text in textBox.write(bundleID: bundleID, text: text) }
```
where `textBox` is a `MainActorTextBox` (NSLock-backed). This lets `ParagraphSuggestionStore.textProvider` read fresh text synchronously without a MainActor hop.

## Plan 10 Handoff

AppDelegate builds `TextMonitor` with the 8-arg init, supplying real `store:`, `splitter:`, and `textBoxWriter:` values. No further TextMonitor edits needed in Plan 10.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMConfig init signature mismatch in test fixture**
- **Found during:** Task 1 (first test build)
- **Issue:** Plan fixture used `LLMConfig(baseURL: URL(...), model:, temperature:, timeoutSeconds:, isEnabled:)` — actual struct has `baseURL: String`, `enabledChecks: Set<LLMCheckType>`, `maxTokens: Int`, `requestTimeout: TimeInterval`, `confidenceThreshold: Int`
- **Fix:** Used `LLMConfig(baseURL: "https://x.invalid", model: "m", enabledChecks: Set(LLMCheckType.allCases), temperature: 0.2, maxTokens: 512, requestTimeout: 5, confidenceThreshold: 7)`
- **Files modified:** OpenGramTests/TextMonitorTests.swift

**2. [Rule 1 - Bug] OSAllocatedUnfairLock not in scope in test target**
- **Found during:** Task 1 (first test build)
- **Issue:** Plan fixture used `OSAllocatedUnfairLock` in StubLLM — requires `import os` which was absent; NSLock already imported via Foundation
- **Fix:** Replaced with `NSLock` + `lock.withLock { }` pattern, matching existing TextBoxSpy in same file
- **Files modified:** OpenGramTests/TextMonitorTests.swift

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. AX text extraction path unchanged — `driveStoreOnValueChange/FocusChange` consume existing `extractText()` output, no new AX API surface.

## Self-Check: PASSED

- `OpenGram/TextMonitor/TextMonitor.swift` — exists, contains all 8 required patterns
- `OpenGramTests/TextMonitorTests.swift` — exists, contains `TextMonitorStoreIntegrationTests`
- Commit `862d2f3` — verified in git log
- 5/5 new tests pass, 16/16 existing tests pass
- Release build clean (`triggerEagerReconcileForTesting` excluded)
