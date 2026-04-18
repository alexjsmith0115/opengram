---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "04"
subsystem: CheckEngine/ParagraphStore
tags: [timeout, concurrency, swift-testing, tdd]
dependency_graph:
  requires: []
  provides: [withTimeout, TimeoutError]
  affects: [LLMRequestQueue (Plan 05)]
tech_stack:
  added: []
  patterns: [withThrowingTaskGroup race pattern, @Sendable @escaping operation closure]
key_files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/WithTimeout.swift
    - OpenGramTests/CheckEngine/ParagraphStore/WithTimeoutTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - withThrowingTaskGroup race: operation + sleep tasks race; first winner returned; defer cancelAll cleans the loser
  - guard let winner = group.next() guards against impossible-nil; fallback throws TimeoutError
metrics:
  duration: "5 min"
  completed_date: "2026-04-17"
  tasks_completed: 1
  files_changed: 3
---

# Phase 20 Plan 04: withTimeout Primitive Summary

`withTimeout(seconds:operation:)` free function + `TimeoutError` struct: standard Swift Concurrency race primitive for bounding LLM requests at 30s in Plan 05's `LLMRequestQueue`.

## What Was Built

- `WithTimeout.swift`: `withThrowingTaskGroup` race — operation task vs sleep deadline task. `defer { group.cancelAll() }` ensures loser is cancelled on any exit path. `@Sendable @escaping` operation + `T: Sendable` constraint satisfies Swift 6 strict concurrency.
- `WithTimeoutTests.swift`: 5 Swift Testing tests — fast-path returns value, slow operation throws `TimeoutError`, operation error propagates unchanged, caller `Task.cancel()` propagates cancellation, `Void` return type works.
- pbxproj: both files registered in ParagraphStore group (app + test Sources).

## Behavior Guarantees

| Scenario | Outcome |
|---|---|
| Operation completes before deadline | Returns operation result |
| Operation exceeds deadline | Throws `TimeoutError` |
| Operation throws before deadline | Propagates operation error (not `TimeoutError`) |
| Caller cancels enclosing Task | `CancellationError` or `TimeoutError` (group cancel races) |
| `Void` return | Compiles and works — `T` inferred as `Void` |

## Handoff to Plan 05

`LLMRequestQueue.pump` wraps each LLM call:
```swift
try await withTimeout(seconds: config.llmRequestTimeoutSeconds) {
    try await llmClient.analyze(...)
}
```
No import needed — `withTimeout` is in the same `OpenGramLib` module.

## TDD Gate Compliance

- RED: `test(20-04)` commit `43f9804` — failing tests (WithTimeout.swift absent)
- GREEN: `feat(20-04)` commit `33029b4` — all 5 tests pass

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

Files exist:
- `OpenGram/CheckEngine/ParagraphStore/WithTimeout.swift` — FOUND
- `OpenGramTests/CheckEngine/ParagraphStore/WithTimeoutTests.swift` — FOUND

Commits:
- `43f9804` — test(20-04) RED
- `33029b4` — feat(20-04) GREEN

## Self-Check: PASSED
