---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: 09
subsystem: SuggestionUI / CheckEngine integration
tags: [overlay, store-subscription, llm, paragraph, integration]
requires: [20-06, 20-07]
provides: [20-10]
affects: [OverlayController, ParagraphSuggestionStore]
tech-stack:
  added: []
  patterns:
    - "AsyncStream `for await event in store.events` consumed on MainActor"
    - "Weak-self guarded Task loop + deinit cancel for actor→MainActor event bridge"
    - "Live-text range re-resolution via `text.range(of: originalText)` (Pitfall #3)"
key-files:
  created:
    - OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Production code (store DI + event handler + click routing + accept/dismiss store calls) landed pre-plan in aea982f / c460237 / 8fa2326 — Plan 09 adds missing test coverage only"
  - "Test fixture uses 8-confidence LLMStyleSuggestion (not 1) so the renderableSuggestions pipeline emits a non-nil Suggestion via mapToSuggestion"
  - "waitForLLMSuggestion polls controller.suggestions instead of fixed sleep — mapping pipeline has 3 async hops (queue task → finishInFlight → handleQueueResponse → eventContinuation.yield → OverlayController event loop)"
metrics:
  duration: ~25m
  completed: 2026-04-17
---

# Phase 20 Plan 09: OverlayController store subscription summary

Adds test coverage for the live store→overlay event bridge. Production code already committed in earlier waves; this plan closes the gap by registering a 4-test suite that exercises the subscription lifecycle, bundleID guard, live-text range re-resolution, and deinit cancel.

## Files modified

- `OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift` (created — 4 tests)
- `OpenGram.xcodeproj/project.pbxproj` (registered test file: PBXBuildFile + PBXFileReference + SuggestionUITests group + Tests Sources build phase)

## Test surface

| # | Test | Asserts |
|---|------|---------|
| 1 | `eventForCurrentBundleIDTriggersUpdate` | `store.reconcile(set:)` → canned LLM → store event → controller.suggestions contains `.source == .llm` |
| 2 | `eventForDifferentBundleIDNoOp` | Event for `otherApp` bundleID does not populate LLM suggestions in a `currentApp`-scoped controller |
| 3 | `llmRangeResolvedAgainstLiveText` | Re-resolved range maps to live-text indices, not the store's placeholder; `String(ctx.text[s.range]) == paragraph` |
| 4 | `deinitCancelsSubscription` | Drop strong controller, pause, no crash — weak-self guard exits the subscription loop |

## Key design decisions

1. **Poll, don't sleep.** `waitForLLMSuggestion` polls at 20 ms intervals up to 2 s. The pipeline has three async hops (queue task → `finishInFlight` → `handleQueueResponse` → event yield → MainActor event loop). A fixed 100 ms sleep would be flaky under CI load.
2. **Confidence 8, not 1.** `LLMStyleSuggestion.confidence = 1` still maps through `mapToSuggestion`, but using the typical 7+ production range exercises the real priority→UInt8 clamp path.
3. **Thread-safe `TextBox`.** Store's `textProvider: @Sendable (String) -> String?` runs on the store actor; NSLock avoids a MainActor hop for the verify-on-response check (matches Plan 06 `MainActorTextBox` pattern).
4. **Live re-resolution is the assertion.** The store's `mapToSuggestion` stores a placeholder `originalText.startIndex..<originalText.endIndex`; overlay re-resolves via `text.range(of:)` on every render. Test 3 verifies the resolved range round-trips to the original paragraph text in the live context.

## Acceptance criteria — PASS

| Criterion | Count | Status |
|-----------|-------|--------|
| `let store: ParagraphSuggestionStore?` | 1 | PASS |
| `storeSubscriptionTask` references | 3 | PASS |
| `func handleStoreEvent` | 1 | PASS |
| `func resolveLLMRanges` | 1 | PASS |
| `func mergeHarperAndLLM` | 1 | PASS |
| `await storeRef.markAccepted` | 1 | PASS |
| `await storeRef.markDismissed` | 1 | PASS |
| `suggestion.source == .llm` (click router) | 1 | PASS |
| `tryDispatchRephraseCard` | 5 (existing + new click route) | PASS |
| `AXObserverCreate` (none in overlay) | 0 | PASS |
| `xcodebuild build` | green | PASS |
| `OverlayControllerStoreSubscriptionTests` | 4/4 | PASS |
| Full suite (excluding pre-existing flake) | 488/488 in isolation | PASS |

## Deviations from plan

### Auto-fixed Issues

None — production code already in place from wave-2 commits.

### Adaptations

**1. [Adaptation] Production code already landed pre-plan.**
- **Found during:** Initial context read
- **Evidence:** `grep` of OverlayController.swift shows all target methods + edits present; git log shows commits `c460237` (20-07) and `aea982f` (scrub pass) introduced store DI, event handler, click routing, and accept/dismiss store calls.
- **Action:** Treated Plan 09 as test-coverage-only. Added the missing `OverlayControllerStoreSubscriptionTests.swift` + pbxproj registration.

**2. [Adaptation] Fixture signatures differ from plan template.**
- **Plan template:** `LLMConfig(baseURL: URL(...)!, model: "m", temperature: 0.2, timeoutSeconds: 30, isEnabled: true)`
- **Actual:** `LLMConfig(baseURL: "https://x.invalid", model: "m", enabledChecks: Set(LLMCheckType.allCases), temperature: 0.2, maxTokens: 100, requestTimeout: 30, confidenceThreshold: 1)` — matches the struct shipped in `OpenGram/CheckEngine/LLM/LLMConfig.swift`.

**3. [Adaptation] Pre-existing timing flake in legacy scheduler test.**
- **Test:** `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit`
- **Failure mode:** `firstCount → 0` under parallel load; passes in isolation.
- **Scope:** Pre-existing; legacy scheduler slated for deletion in Plan 10b. Not caused by Plan 09 changes.
- **Disposition:** Logged in deferred items. No fix here.

## Deferred items

| Category | Item | Status | Reason |
|----------|------|--------|--------|
| Test flake | `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit` — timing-dependent under parallel runner | Deferred | Legacy scheduler targeted for deletion in Plan 10b; fixing the flake there is cleaner than patching code slated for removal |

## Handoffs

- **Plan 10a — DisplayHeuristic + AdvancedSettingsView migration:** OverlayController store-subscription is live; 10a can treat `DisplayHeuristic`'s min thresholds as the only remaining legacy coupling before 10b deletes the scheduler.
- **Plan 10b — delete scheduler + `schedulerRef.markDismissed` + `hashForDismiss` + `legacyHash` + AppDelegate rewire:** Legacy bridge still present in `dismissClosure` (line 553 `await schedulerRef.markDismissed(...)`). Plan 10b removes it alongside `CardQualifier.legacyHash` and the `scheduler: LLMCheckScheduler?` init parameter.
- **Plan 10c — delete legacy scheduler/cache/config files:** Blocked on 10b; removes `LLMCheckScheduler.swift`, old paragraph cache, deprecated config types.

## Self-Check: PASSED

- `[FOUND]` `OpenGramTests/SuggestionUITests/OverlayControllerStoreSubscriptionTests.swift`
- `[FOUND]` commit `747bb62 test(20-09): add OverlayController store subscription integration tests`
- `[FOUND]` Production code already committed: `c460237`, `aea982f`, `8fa2326`
- `[PASS]` 4/4 new tests green
- `[PASS]` `xcodebuild build` green
- `[PASS]` All 10 grep acceptance criteria
