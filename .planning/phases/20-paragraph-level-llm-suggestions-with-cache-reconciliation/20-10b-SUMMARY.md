---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: 10b
subsystem: App composition root + Overlay
tags: [composition, migration, scheduler-removal, store-driven, cleanup]
requires:
  - MainActorTextBox (new)
  - OpenGramConfig (Plan 20-02)
  - ParagraphSuggestionStore (Plan 20-06)
  - LLMRequestQueue (Plan 20-05)
  - ParagraphSplitter (Plan 20-02)
  - TextMonitor 8-arg init (Plan 20-08)
  - OverlayController store subscription (Plan 20-09)
  - OverlayController.config: OpenGramConfig (Plan 20-10a)
provides:
  - AppDelegate composition root: queue + store + splitter + textBox + config
  - CheckCoordinator Harper-only hotkey path (LLM fan-out deleted)
  - OverlayController free of scheduler / legacyHash / hashForDismiss / hasher
affects:
  - OpenGram/App/AppDelegate.swift (rewired)
  - OpenGram/App/CheckCoordinator.swift (scheduler + llmTask removed)
  - OpenGram/App/MainActorTextBox.swift (new file)
  - OpenGram/SuggestionUI/Overlay/OverlayController.swift (scheduler scaffolding removed)
  - OpenGram.xcodeproj/project.pbxproj (MainActorTextBox registration)
  - OpenGramTests/AppDelegateWiringTests.swift (init signature updated)
  - OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift (legacyHash arg removed)
  - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift (scheduler arg removed)
tech-stack:
  added:
    - MainActorTextBox — NSLock-backed per-bundle live-text holder; actor-safe access from store
  patterns:
    - Composition root constructs queue + store, then `Task { await queue.setStore(store) }` fires before `textMonitor.start()`
    - textProvider closure captures [textBox] weakly; textBoxWriter writes on AX value/focus change
    - store.markDismissed is the sole dismiss transition path (scheduler mirror deleted)
key-files:
  created:
    - OpenGram/App/MainActorTextBox.swift
  modified:
    - OpenGram/App/AppDelegate.swift
    - OpenGram/App/CheckCoordinator.swift
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram.xcodeproj/project.pbxproj
    - OpenGramTests/AppDelegateWiringTests.swift
    - OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift
decisions:
  - MainActorTextBox placed in dedicated OpenGram/App/MainActorTextBox.swift matching existing one-type-per-file convention
  - hasher param deleted from OverlayController alongside legacyHash — became unused after scheduler removal (grep confirmed zero remaining callers)
  - Legacy LLMCheckScheduler + IncrementalConfig + ParagraphSuggestionCache files NOT deleted here — Plan 10c handles (preserved per plan scope)
  - RephraseCardLifecycleTests + LLMCheckScheduler* test files NOT modified — still exercise legacy scheduler which compiles in isolation; Plan 10c deletes them wholesale
metrics:
  duration: ~15min
  completed_date: 2026-04-17
  tasks: 1
  files_changed: 8
---

# Phase 20 Plan 10b: AppDelegate + CheckCoordinator + OverlayController Store-Driven Rewire Summary

AppDelegate composes `OpenGramConfig → LLMRequestQueue → ParagraphSuggestionStore → MainActorTextBox → TextMonitor → OverlayController → CheckCoordinator`. Hotkey path reduced to Harper-only; paragraph-LLM is event-driven via store subscription (D-04). Scheduler scaffolding removed from OverlayController. 487/489 tests green (2 pre-existing flakes documented below).

## Scope

Three source rewires + 3 test adapters:

1. **AppDelegate.applicationDidFinishLaunching** — rewritten to the store-driven composition. `LLMCheckScheduler(…)` construction deleted; `UserDefaultsIncrementalConfig()` construction deleted. `Task { await queue.setStore(store) }` fires before `textMonitor.start()`.
2. **CheckCoordinator** — `scheduler: LLMCheckScheduler` param + stored property deleted; `llmTask: Task?` field deleted; LLM fan-out branch of `handleHotkeyFired` (~45 lines) deleted. Harper-only path retained.
3. **OverlayController** — `scheduler: LLMCheckScheduler?` param + stored property deleted; `CardQualifier.legacyHash: UInt64` field deleted; `hashForDismiss` local deleted; `schedulerRef.markDismissed` call deleted; `hasher: ParagraphHashing` param + stored property + `hasher.hash(…)` call deleted (became unused after legacyHash removal). `store.markDismissed(hash:)` is now the sole dismiss transition path.

Legacy files retained (Plan 10c deletes): `LLMCheckScheduler.swift`, `IncrementalConfig.swift`, `ParagraphSuggestionCache.swift`, 5 scheduler test files, `RephraseCardLifecycleTests.swift`.

## AppDelegate Composition Diff

Before (simplified):
```swift
let scheduler = LLMCheckScheduler(
    splitter: DoubleNewlineSplitter(), hasher: Sha256ParagraphHasher(),
    cache: ParagraphSuggestionCache(), clock: SystemClock(),
    llm: llmService, configProvider: …, apiKeyProvider: …,
    incrementalConfig: UserDefaultsIncrementalConfig()
)
let textMonitor = TextMonitor(textEngine:, orchestrator:, capabilityCache:)
let overlayController = OverlayController(
    scheduler: scheduler, textMonitor: textMonitor, config: OpenGramConfig()
)
let coordinator = CheckCoordinator(
    textEngine:, orchestrator:, scheduler: scheduler,
    overlayController:, statusBarController:, appWhitelist:
)
```

After:
```swift
let config = OpenGramConfig()
let textBox = MainActorTextBox()
let queue = LLMRequestQueue(
    llm: llmService, configProvider: …, apiKeyProvider: …,
    timeoutProvider: { TimeInterval(config.llmRequestTimeoutSeconds) }
)
let splitter = ParagraphSplitter(capabilityCache: capabilityCache)
let store = ParagraphSuggestionStore(
    queue: queue, splitter: splitter, config: config,
    textProvider: { [textBox] bundleID in textBox.read(bundleID: bundleID) }
)
Task { await queue.setStore(store) }

let textMonitor = TextMonitor(
    textEngine: textEngine, orchestrator: orchestrator,
    capabilityCache: capabilityCache,
    store: store, splitter: splitter,
    textBoxWriter: { [textBox] bundleID, text in textBox.write(bundleID: bundleID, text: text) }
)
let overlayController = OverlayController(
    textMonitor: textMonitor, config: config, store: store
)
let coordinator = CheckCoordinator(
    textEngine:, orchestrator:,
    overlayController:, statusBarController:, appWhitelist:
)
```

## CheckCoordinator Before/After

**Removed:**
- `private let scheduler: LLMCheckScheduler`
- `private var llmTask: Task<Void, Never>?`
- `scheduler:` init parameter
- `llmTask?.cancel()` in `handleHotkeyFired`
- `~45-line LLM fan-out branch` starting at `let config = ConfigManager.currentLLMConfig(); guard config.isEnabled else { … }` through the closing brace of `llmTask = Task { … }`

**Retained:**
- Harper-only Task inside `handleHotkeyFired` (orchestrator.harperOnly(text:) → overlayController.show)
- `handleCheckComplete`, `handleLLMFinished`, `handleDismiss` TextMonitor callbacks
- `accumulatedSuggestions` / `lastSuggestions` tracking
- `wireOverlayCallbacks` (onAccept/onDismiss/onAddToDictionary/onDismissAll)

## OverlayController Grep Evidence

```
grep -c 'scheduler'       OpenGram/SuggestionUI/Overlay/OverlayController.swift = 0
grep -c 'legacyHash'      OpenGram/SuggestionUI/Overlay/OverlayController.swift = 0
grep -c 'hashForDismiss'  OpenGram/SuggestionUI/Overlay/OverlayController.swift = 0
grep -c 'LLMCheckScheduler' OpenGram/App/AppDelegate.swift      = 0
grep -c 'scheduler'         OpenGram/App/AppDelegate.swift      = 0
grep -c 'IncrementalConfig' OpenGram/App/AppDelegate.swift      = 0
grep -c 'scheduler'         OpenGram/App/CheckCoordinator.swift = 0
grep -c 'llmTask'           OpenGram/App/CheckCoordinator.swift = 0
grep -c 'MainActorTextBox'  OpenGram/App/AppDelegate.swift       = 2  (construct + 2 closure captures)
grep -c 'ParagraphSuggestionStore(' OpenGram/App/AppDelegate.swift = 1
grep -c 'LLMRequestQueue('   OpenGram/App/AppDelegate.swift      = 1
grep -c 'textBoxWriter:'     OpenGram/App/AppDelegate.swift      = 1
grep -c 'await queue.setStore' OpenGram/App/AppDelegate.swift    = 1
```

All plan gates satisfied.

## MainActorTextBox Design

NSLock-backed, `@unchecked Sendable`. Synchronous `read(bundleID:)` and `write(bundleID:text:)` methods. Stored in `OpenGram/App/MainActorTextBox.swift` (registered in pbxproj App group + Sources phase).

**Why NSLock not MainActor:** the store actor calls `textProvider(bundleID)` synchronously from inside response handling. Hopping to MainActor from an actor context requires `await`, forcing every store method into reentrant territory. NSLock is cheap (≤10 Hz write rate from AX notifications, equally cheap reads). Matches the actor-safe pattern used by AXCapabilityCache.

**Usage pattern:**
- AppDelegate captures `[textBox]` in both the store's `textProvider` closure (read) and TextMonitor's `textBoxWriter` closure (write). Strong capture of the `final class` reference — lives for app lifetime.
- TextMonitor.driveStoreOnValueChange + driveStoreOnFocusChange invoke `textBoxWriter?(bundleID, text)` on every AX value/focus change (Plan 08 already wired).

## Queue.setStore Race Analysis (T-20.10b-01)

Threat: `Task { await queue.setStore(store) }` is fire-and-forget. If TextMonitor's eager reconcile fires before the Task completes, and that reconcile causes queue.submit → queue.pump → llm.analyze → response callback, the callback would find store nil and no-op.

**Mitigation in practice:**
- AppDelegate's sync `applicationDidFinishLaunching` returns before any TextMonitor work runs (TextMonitor.start installs the AX observer, which dispatches async to MainActor). By the time the first AX notification fires, the awaiting setStore Task has queue-scheduled on the actor and completed.
- Worst case: first queue response before setStore completes → response callback finds store nil → `inFlightCancelled` never set but `store?.handleQueueResponse` is nil-guard skipped → pump() cleans up → one dropped response, no crash, no corruption.
- Subsequent reconciles re-submit the missed paragraph because no cache entry was created.

Not a correctness hazard. Accept.

## Handoff to Plan 10c

Plan 10b leaves these for Plan 10c deletion:

- **Source files:** `OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift`, `IncrementalConfig.swift`; `OpenGram/CheckEngine/ParagraphInfra/ParagraphSuggestionCache.swift`
- **Test files:** `LLMCheckSchedulerTests.swift`, `LLMCheckSchedulerCancellationTests.swift`, `LLMCheckSchedulerMarkDismissedTests.swift`, `CheckCoordinatorSchedulerIntegrationTests.swift`, `IncrementalConfigTests.swift`, `ParagraphSuggestionCacheTests.swift`, `RephraseCardLifecycleTests.swift` (tests scheduler.markDismissed directly)

All zero external callers post-10b. `xcodebuild build` confirms they compile in isolation.

Plan 10c also handles manual validation in Notes.app — full hotkey→rephrase flow under the new composition.

## Build + Test

- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — **BUILD SUCCEEDED**
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test` — 487/489 tests passing

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `hasher` param removed from OverlayController (was step 10 of plan as conditional)**

- **Found during:** Task 1 step D (OverlayController cleanup)
- **Issue:** Plan step 10 said keep `hasher` if still referenced elsewhere; after deleting `legacyHash` the only remaining `hasher.hash(…)` call at the qualifier build site was also deleted, leaving zero references.
- **Fix:** Deleted `hasher: ParagraphHashing` init param + stored property. Grep confirmed no external callers passed `hasher:`.
- **Files modified:** OpenGram/SuggestionUI/Overlay/OverlayController.swift
- **Commit:** a79754e

## Deferred Issues

**Pre-existing test flakes (not caused by this plan):**

1. `LLMCheckSchedulerCancellationTests.idleDebounceSeconds_liveReadHonoredWithoutReinit` — timing-flaky under parallel load (documented in STATE.md Phase 20-09, slated for deletion in Plan 10c)
2. `AXCallWatchdogTests.blocklist_entry_expires_after_blocklistDuration_and_shouldSkip_returns_false` — timing flake, intermittent (seen once, passed on rerun)

Both pre-existed Plan 10b. Scope boundary per CLAUDE.md: do NOT fix pre-existing unrelated failures in this plan.

## TDD Gate Compliance

Single-commit refactor plan. No RED/GREEN cycle — migration is a pure rewire of existing composition; tests adapted to new signatures stay green as regression coverage.

## Self-Check: PASSED

- OpenGram/App/MainActorTextBox.swift — FOUND
- OpenGram/App/AppDelegate.swift — FOUND (modified)
- OpenGram/App/CheckCoordinator.swift — FOUND (modified)
- OpenGram/SuggestionUI/Overlay/OverlayController.swift — FOUND (modified)
- Commit a79754e — FOUND in git log
- xcodebuild build — BUILD SUCCEEDED
- xcodebuild test — 487/489 passing (2 pre-existing flakes out of scope)
- MainActorTextBox pbxproj registrations = 4 (build file + file ref + group + sources phase) — FOUND
- Legacy LLMCheckScheduler.swift + IncrementalConfig.swift + ParagraphSuggestionCache.swift — EXIST (Plan 10c deletes)
