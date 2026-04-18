---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "05"
subsystem: CheckEngine/ParagraphStore
tags: [actor, queue, llm, serialization, cancellation, timeout, tdd]
dependency_graph:
  requires: [20-01, 20-02, 20-04]
  provides: [LLMRequestQueue, LLMRequestQueueStore]
  affects: [20-06-ParagraphSuggestionStore]
tech_stack:
  added: []
  patterns: [actor-FIFO-queue, weak-store-reference, inFlightCancelled-flag, callback-protocol-circular-dep-break]
key_files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/LLMRequestQueue.swift
    - OpenGram/CheckEngine/ParagraphStore/LLMRequestQueueStoreProtocol.swift
    - OpenGramTests/CheckEngine/ParagraphStore/LLMRequestQueueTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "`inFlightCancelled` bool flag set on `cancel(hash:)` — suppresses `handleQueueResponse` callback at Task completion without racily clearing `inFlight`"
  - "Callback protocol `LLMRequestQueueStore` breaks Plan 05 ↔ Plan 06 init-time circular dependency; store set post-init via `setStore(_:)`"
  - "Queue delivers raw `[LLMStyleSuggestion]`; Plan 06 store maps to `Suggestion` — queue has no knowledge of `Suggestion` type"
  - "Test `makeQueue` uses `LLMConfig.default` — plan template used wrong constructor shape (URL not String, missing `enabledChecks`); adapted to real type"
metrics:
  duration: "151s"
  completed_date: "2026-04-18"
  tasks_completed: 1
  files_changed: 4
---

# Phase 20 Plan 05: LLMRequestQueue Actor + Callback Protocol Summary

One-liner: FIFO one-in-flight LLM request queue with 30s timeout and cancel-silent-to-store semantics, backed by a narrow callback protocol that breaks the Plan 05 ↔ 06 circular dependency.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement LLMRequestQueueStoreProtocol + LLMRequestQueue actor | 998fcde | LLMRequestQueue.swift, LLMRequestQueueStoreProtocol.swift, LLMRequestQueueTests.swift, project.pbxproj |

## Key Design Decisions

**1. `inFlightCancelled` flag — suppresses store callback on cancel**

`cancel(hash:)` sets `inFlightCancelled = true` and calls `task.cancel()` but does NOT clear `inFlight`. The Task's own completion closure (`finishInFlight`) checks the flag, skips `store?.handleQueueResponse(...)`, then clears `inFlight` and calls `pump()`. This avoids a race between `cancel()` clearing `inFlight` and a concurrent `submit()` seeing the queue as idle too early.

**2. Callback protocol breaks init-time circularity**

`ParagraphSuggestionStore` (Plan 06) will hold a `LLMRequestQueue` and the queue needs to call back into the store. If both were set at init, each would need the other already built. The `LLMRequestQueueStore` protocol + `setStore(_:)` post-init call (Plan 10 AppDelegate composition) sidesteps this entirely.

**3. Raw `[LLMStyleSuggestion]` delivery**

Queue knows nothing about `Suggestion`, `ParagraphHash` state transitions, or cache. It receives `[LLMStyleSuggestion]` from `LLMProviderProtocol.analyze(target:...)` and forwards them to the store as `.success([...])`. Plan 06's store maps these to `Suggestion` and updates the state machine.

**4. Test `LLMConfig` adaptation**

Plan template used `LLMConfig(baseURL: URL(...), model:, temperature:, timeoutSeconds:, isEnabled:)` which doesn't match the real struct (baseURL is `String`, fields differ). Tests use `LLMConfig.default` instead — functionally equivalent for queue purposes.

## Handoff to Plan 06

`ParagraphSuggestionStore` must:
1. Conform to `LLMRequestQueueStore` and implement `handleQueueResponse(hash:bundleID:result:) async`
2. Call `queue.setStore(self)` at init tail (or Plan 10 AppDelegate wiring)
3. On `.success(suggestions)` → map to `Suggestion`, update state machine to `.ready`
4. On `.failure(TimeoutError)` → transition state to `.failed`

## Handoff to Plan 10

AppDelegate creates `LLMRequestQueue` and `ParagraphSuggestionStore` independently, then:
```swift
await queue.setStore(store)
```
Both actors are fully constructed before this call — no init-time circular dependency.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMConfig constructor mismatch in test template**
- **Found during:** Task 1 implementation
- **Issue:** Plan template used `LLMConfig(baseURL: URL(string:)!, model:, temperature:, timeoutSeconds:, isEnabled:)` — real `LLMConfig` has `baseURL: String`, no `timeoutSeconds` field, uses `enabledChecks: Set<LLMCheckType>` not `isEnabled: Bool`
- **Fix:** Changed `makeQueue` factory to use `LLMConfig.default` — functionally equivalent for queue testing
- **Files modified:** `LLMRequestQueueTests.swift`
- **Commit:** 998fcde

## Threat Flags

None — no new network endpoints, auth paths, or schema changes beyond what the plan's threat model covers (T-20.05-01..05). Confirmed: no `logger.*(target|paragraph)` calls in `LLMRequestQueue.swift`.

## Self-Check: PASSED

- `OpenGram/CheckEngine/ParagraphStore/LLMRequestQueue.swift` — FOUND
- `OpenGram/CheckEngine/ParagraphStore/LLMRequestQueueStoreProtocol.swift` — FOUND
- `OpenGramTests/CheckEngine/ParagraphStore/LLMRequestQueueTests.swift` — FOUND
- Commit 998fcde — FOUND
- `LLMRequestQueueTests` 6/6 passing — VERIFIED
- Build green — VERIFIED
