---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "06"
subsystem: check-engine
tags: [swift-actor, async-stream, paragraph-cache, reconciliation, tdd]

requires:
  - phase: 20-01
    provides: ParagraphHash, ParagraphSet, ParagraphSuggestionState, ParagraphCacheEntry, StoreEvent
  - phase: 20-02
    provides: OpenGramConfig (minParagraphLength, minParagraphWordCount)
  - phase: 20-03
    provides: ParagraphSplitter (verify-on-response re-split)
  - phase: 20-05
    provides: LLMRequestQueue, LLMRequestQueueStore protocol

provides:
  - actor ParagraphSuggestionStore — owns cache + reconcile state machine + event stream
  - sha256Prefix8UInt64 shim on ParagraphHash (temporary Plan06→Plan07 compat)
  - 14 Swift Testing tests covering 11 store-side PLL requirements

affects:
  - 20-07 (deletes sha256Prefix8UInt64 shim + flips Suggestion.paragraphHash to ParagraphHash?)
  - 20-08 (TextMonitor calls reconcile/invalidateDisplayed, writes MainActorTextBox)
  - 20-09 (OverlayController subscribes to store.events, reads renderableSuggestions, calls markDismissed/markAccepted)
  - 20-10 (AppDelegate wires store into TextMonitor + OverlayController)

tech-stack:
  added: []
  patterns:
    - "waitForKind actor-poll: tests poll store._cacheEntryKind directly (not llm.calls) to avoid two-async-hop race between LLM call completion and cache write"
    - "MainActorTextBox (NSLock-backed): thread-safe textProvider — same pattern ships in production Plan 10 wiring"
    - "verify-on-response: re-split via textProvider + ParagraphSplitter before accepting queue response"

key-files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift
    - OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "textProvider closure (NSLock-backed MainActorTextBox) for verify-on-response: store re-reads live text synchronously without MainActor hop — avoids actor reentrancy issues"
  - "Suggestion.range is a placeholder (originalText.startIndex..<endIndex): Plan 09 re-resolves against live AX text at render time (Pitfall #3 — cached String.Index invalid across mutations)"
  - "sha256Prefix8UInt64 shim: temporary UInt64 compression so Plan 06 compiles against existing Suggestion.paragraphHash: UInt64?; Plan 07 deletes shim + flips field to ParagraphHash? atomically"
  - "waitForKind polls store actor state directly: waiting on llm.calls.count has a two-async-hop race (queue actor → store actor → cache write); polling _cacheEntryKind is race-free"
  - "StubLLM.analyze has 1ms sleep: ensures cooperative thread pool can schedule queue Tasks under parallel full-suite execution"

requirements-completed: [PLL-03a, PLL-03b, PLL-03c, PLL-04, PLL-05, PLL-06, PLL-07, PLL-08a, PLL-08b, PLL-11, PLL-14]

duration: 35min
completed: 2026-04-17
---

# Phase 20 Plan 06: ParagraphSuggestionStore Summary

**Actor-owned paragraph cache with reconcile state machine, verify-on-response, and AsyncStream event bus — 14 tests covering all 11 store-side PLL requirements**

## Performance

- **Duration:** 35 min
- **Started:** 2026-04-17T22:00:00Z
- **Completed:** 2026-04-17T22:35:00Z
- **Tasks:** 1 (TDD: RED + GREEN combined)
- **Files modified:** 3

## Accomplishments

- `ParagraphSuggestionStore` actor ships: `reconcile`, `invalidateDisplayed`, `handleQueueResponse`, `markDismissed`, `markAccepted`, `renderableSuggestions`, test seams
- Verify-on-response re-splits live text via `textProvider` + `ParagraphSplitter` before accepting queue response (PLL-05)
- 14 tests passing in both isolation and full suite (462+ tests); pre-existing flaky test `idleDebounceSeconds_liveReadHonoredWithoutReinit` unaffected

## Task Commits

1. **Task 1: ParagraphSuggestionStore + tests** — `eb34015` (feat)

## Files Created/Modified

- `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift` — actor owning cache + reconciliation state machine + event stream; sha256Prefix8UInt64 shim
- `OpenGramTests/CheckEngine/ParagraphStore/ParagraphSuggestionStoreTests.swift` — 14 Swift Testing tests, MainActorTextBox, waitForKind helpers
- `OpenGram.xcodeproj/project.pbxproj` — both files registered (file refs + group membership + Sources build phases)

## Tested Behaviors → PLL Requirements

| Test | PLL |
|------|-----|
| reconcileNewParagraphSubmitsOnce | PLL-03a |
| reconcileReadyEntryDoesNotResubmit | PLL-03b |
| reconcilePendingEntryDoesNotResubmit | PLL-03c |
| invalidateDisplayedDoesNotSubmit | PLL-04 |
| handleResponseHashNotInSetDropsAndEvicts | PLL-05 |
| reconcileCaretParagraphSkipped | PLL-06 |
| reconcileParagraphLeavesWhilePendingCancelsAndEvicts | PLL-07 |
| reconcilePerBundleIsolation | PLL-08a/b |
| readyEmptyPreventsResubmit | PLL-14 |
| markDismissedTransitionsToDismissed | PLL-11 store-side |
| markAcceptedTransitionsToAccepted | PLL-11 store-side |
| renderableSuggestionsFilterByLiveSetAndReadyState | render surface |
| reconcileSkipsShortParagraphs | minParagraphLength guard |
| reconcileEmitsEvent | AsyncStream event emission |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMConfig constructor mismatch in test**
- **Found during:** Task 1 (test compilation)
- **Issue:** Plan's code snippet used `LLMConfig(baseURL: URL(...), model:, temperature:, timeoutSeconds:, isEnabled:)` — actual struct has `(baseURL: String, model:, enabledChecks:, temperature:, maxTokens:, requestTimeout:, confidenceThreshold:)`
- **Fix:** Updated test factory to match actual LLMConfig memberwise init
- **Committed in:** eb34015

**2. [Rule 1 - Bug] Two-async-hop race in test wait conditions**
- **Found during:** Task 1 (full-suite run — 3 tests failed that passed in isolation)
- **Issue:** Tests waited for `llm.calls.count == 1` before checking cache state. But after the LLM call, two more async hops remain before the cache writes: `finishInFlight` on the queue actor, then `handleQueueResponse` on the store actor. Under full-suite parallel execution, polling saw the LLM called but the cache still `.pending`.
- **Fix:** Replaced `wait(until: { llm.calls.count == N })` with `waitForKind(store:hash:equals:)` and `waitForKind(store:hash:notPending:)` — polls `_cacheEntryKind` directly on the store actor, which only returns the new state after the full transition completes
- **Committed in:** eb34015

---

**Total deviations:** 2 auto-fixed (1 constructor mismatch, 1 race in test wait logic)
**Impact on plan:** Both required for correctness; no scope creep.

## Issues Encountered

- Swift Testing parallel execution causes thread starvation for tasks that have no suspension point in the stub. Added `try? await Task.sleep(for: .milliseconds(1))` to `StubLLM.analyze` to guarantee a cooperative yield. This matches the pattern in `LLMRequestQueueTests`.

## Known Stubs

- `Suggestion.range` stored in cache is a placeholder (`originalText.startIndex..<endIndex`). Plan 09 re-resolves against live AX text at render time. Intentional per CONTEXT.md §Pitfall #3 — never trust cached `String.Index` across text mutations.

## Handoffs

- **Plan 07:** Delete `sha256Prefix8UInt64` extension on `ParagraphHash` from `ParagraphSuggestionStore.swift`. Flip `Suggestion.paragraphHash` field from `UInt64?` to `ParagraphHash?` atomically.
- **Plan 08:** `TextMonitor` injects store and calls `reconcile(set:)` on debounce tick and `invalidateDisplayed(bundleID:currentSet:)` on every AX value-change. TextMonitor writes `MainActorTextBox` (same NSLock-backed pattern as in tests) on every focus/value change — store's `textProvider` closure reads from it.
- **Plan 09:** `OverlayController` subscribes to `store.events` AsyncStream, calls `renderableSuggestions(for:)` on each event, calls `markDismissed(hash:)` / `markAccepted(hash:)` on user interaction. Re-resolves `Suggestion.range` against live AX text before rendering.

## Next Phase Readiness

- `ParagraphSuggestionStore` actor complete; all 11 store-side PLL requirements test-covered
- `LLMRequestQueueStore` conformance wired; queue delivers to store via callback protocol
- Plan 07 can proceed immediately (atomic field-type swap)

---
*Phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation*
*Completed: 2026-04-17*
