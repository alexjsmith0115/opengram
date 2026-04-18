---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: 10a
subsystem: SuggestionUI + Settings + Overlay
tags: [config, migration, openGramConfig, cleanup]
requires:
  - OpenGramConfig (Plan 20-02)
  - Suggestion.paragraphHash: ParagraphHash? (Plan 20-07)
provides:
  - DisplayHeuristic reading OpenGramConfig
  - AdvancedSettingsView reset posting didChangeNotification
  - OverlayController.config: OpenGramConfig parameter
affects:
  - OpenGram/App/AppDelegate.swift (OverlayController call site updated)
  - OpenGramTests/AppDelegateWiringTests.swift (OverlayController call site updated)
  - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift (OverlayController call site updated)
  - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardLifecycleTests.swift (OverlayController call site updated)
tech-stack:
  added: []
  patterns:
    - Inject UserDefaults via OpenGramConfig(defaults:) in tests (stop fake protocol structs)
    - Reset-closure broadcasts change via OpenGramConfig.postDidChange(to:) with injectable NotificationCenter
key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift
    - OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift
    - OpenGramTests/SuggestionUITests/AdvancedSettingsViewTests.swift
    - OpenGramTests/AppDelegateWiringTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift
    - OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardLifecycleTests.swift
decisions:
  - AdvancedSettingsView.resetDefaults(in:center:) takes injectable NotificationCenter so tests assert didChange posting on an isolated center without polluting .default
  - Tests migrated from IncrementalConfig stub protocol conformers to UserDefaults-suite backed OpenGramConfig(defaults:) — eliminates parallel fake-impl surface
  - Legacy IncrementalConfig protocol + UserDefaultsIncrementalConfig struct kept verbatim (still referenced by LLMCheckScheduler + 4 scheduler test files) — Plan 10b rewires, Plan 10c deletes
metrics:
  duration: ~10min
  completed_date: 2026-04-17
  tasks: 1
  files_changed: 9
---

# Phase 20 Plan 10a: DisplayHeuristic + AdvancedSettingsView + OverlayController → OpenGramConfig Summary

DisplayHeuristic, AdvancedSettingsView, and OverlayController's config parameter migrated onto OpenGramConfig. 9 files modified (3 source + 6 tests/downstream), 489/489 tests green, legacy IncrementalConfig type preserved for Plan 10c deletion.

## Scope

Three narrow migrations:

1. `DisplayHeuristic.config: any IncrementalConfig` → `DisplayHeuristic.config: OpenGramConfig`. No behavior change — field names (`minIssueCount`, `minWordCount`) exist on both.
2. `AdvancedSettingsView`: all `UserDefaultsIncrementalConfig.*` references → `OpenGramConfig.*`; reset closure now calls `OpenGramConfig.postDidChange(to: center)` so eager-rescheduling consumers can flush caches on reset.
3. `OverlayController` init parameter + stored property: `incrementalConfig: any IncrementalConfig` → `config: OpenGramConfig`. All 4 downstream call sites updated (AppDelegate + 3 test files).

Out-of-scope (Plan 10b / 10c): LLMCheckScheduler, CheckCoordinator, IncrementalConfig.swift file, ParagraphSuggestionCache.swift.

## Evidence — Grep acceptance

```
grep -c 'IncrementalConfig' OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift              = 0   ✓
grep -c 'OpenGramConfig' OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift                 = 2   ✓ (>=1)
grep -c 'UserDefaultsIncrementalConfig' OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift  = 0   ✓
grep -c 'OpenGramConfig.default' OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift         = 7   ✓ (>=3)
grep -c 'OpenGramConfig.postDidChange' OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift   = 1   ✓ (>=1)
grep -c 'self.incrementalConfig' OpenGram/SuggestionUI/Overlay/OverlayController.swift             = 0   ✓
grep -c 'private let config: OpenGramConfig' OpenGram/SuggestionUI/Overlay/OverlayController.swift = 1   ✓
grep -c 'config: OpenGramConfig = OpenGramConfig()' OpenGram/SuggestionUI/Overlay/OverlayController.swift = 1 ✓
grep -c 'UserDefaultsIncrementalConfig' OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift = 0 ✓
```

Legacy type survival confirmed: `OpenGram/CheckEngine/LLMCheckScheduler/IncrementalConfig.swift` still present — Plan 10c deletes it along with UserDefaultsIncrementalConfig after LLMCheckScheduler is removed in Plan 10b.

## Build + Test

- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — **BUILD SUCCEEDED**
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test` — **TEST SUCCEEDED**, 489/489 tests across 76 suites in 30.4s

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated 4 OverlayController call sites beyond plan's 3 named source files**

- **Found during:** Task 1 test compile
- **Issue:** Plan's file list named 3 source + 2 test files. Build-fail surfaced additional OverlayController call sites that use the renamed `config:` param: `AppDelegate.swift` (1 site), `AppDelegateWiringTests.swift` (1 site), `OverlayControllerRephraseIntegrationTests.swift` (2 sites), `RephraseCardLifecycleTests.swift` (1 site).
- **Fix:** Updated all 5 additional sites to `config: OpenGramConfig()` (or test-suite `OpenGramConfig(defaults:)`). Scheduler-construction sites using `incrementalConfig:` kept verbatim — those belong to the scheduler's parameter, not OverlayController's, and are out of scope until Plan 10c deletes the scheduler.
- **Files modified:** OpenGram/App/AppDelegate.swift, OpenGramTests/AppDelegateWiringTests.swift, OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift, OpenGramTests/SuggestionUITests/RephraseCard/RephraseCardLifecycleTests.swift
- **Commit:** 69d553d

**2. [Rule 2 - Critical] AdvancedSettingsView.resetDefaults now broadcasts didChange notification**

- **Found during:** Task 1 Step C
- **Issue:** Plan's must_have includes "reset-to-defaults posts OpenGramConfig.didChangeNotification" but the source `resetDefaults(in:)` did not post. Without this, settings UI resets silently from the live-read-on-demand OpenGramConfig perspective, and no eager-rescheduling consumers can flush caches.
- **Fix:** Added `OpenGramConfig.postDidChange(to: center)` to `resetDefaults(in:center:)`. `center` defaults to `.default` for production; tests pass isolated `NotificationCenter()` to avoid cross-test pollution. Added regression test `resetDefaults_postsDidChangeNotification`.
- **Files modified:** OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift, OpenGramTests/SuggestionUITests/AdvancedSettingsViewTests.swift
- **Commit:** 69d553d

## TDD Gate Compliance

Single-commit plan — RED/GREEN cycle collapsed into one atomic refactor commit since migration is a pure type rename (same behavior, same field names). Regression test `resetDefaults_postsDidChangeNotification` added for the new Rule-2 didChange posting behavior.

## Handoff to Plan 10b

Plan 10a leaves the following intact for Plan 10b:

- `LLMCheckScheduler.swift` + `IncrementalConfig.swift` + `UserDefaultsIncrementalConfig` — untouched.
- `OverlayController.scheduler: LLMCheckScheduler?` property + `CardQualifier.legacyHash: UInt64` transitional bridge + the `scheduler.markDismissed(bundleID:hash:)` legacy call in the dismiss closure — all intact.
- 4 scheduler construction sites in tests (RephraseCardLifecycleTests, LLMCheckSchedulerTests, LLMCheckSchedulerCancellationTests, LLMCheckSchedulerMarkDismissedTests, CheckCoordinatorSchedulerIntegrationTests) still pass `incrementalConfig:` to the scheduler init — unchanged.

Plan 10b should: rewire AppDelegate (drop scheduler construction + pass store to OverlayController + drop textMonitor scheduler wiring), rewrite CheckCoordinator for Harper-only, remove `scheduler` + `legacyHash` + scheduler.markDismissed path from OverlayController.

Plan 10c then deletes `LLMCheckScheduler.swift`, `IncrementalConfig.swift`, `UserDefaultsIncrementalConfig` struct, `ParagraphSuggestionCache.swift`, and the 5 scheduler test files.

## Self-Check: PASSED

- OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift — FOUND
- OpenGram/SuggestionUI/Settings/AdvancedSettingsView.swift — FOUND
- OpenGram/SuggestionUI/Overlay/OverlayController.swift — FOUND
- OpenGramTests/SuggestionUITests/RephraseCard/DisplayHeuristicTests.swift — FOUND
- OpenGramTests/SuggestionUITests/AdvancedSettingsViewTests.swift — FOUND
- Commit 69d553d — FOUND in git log
- xcodebuild build — BUILD SUCCEEDED
- xcodebuild test — TEST SUCCEEDED, 489/489 green
