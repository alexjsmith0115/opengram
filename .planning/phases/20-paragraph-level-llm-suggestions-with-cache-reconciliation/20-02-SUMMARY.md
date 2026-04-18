---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: 02
subsystem: config
tags: [userdefaults, live-read, notification, swift-testing, config]

requires:
  - phase: 20-01
    provides: ParagraphStore group in pbxproj

provides:
  - OpenGramConfig struct with 8 UserDefaults-backed live-read tunables
  - postDidChange(to:) notification helper for hot-reload consumers
  - OpenGramConfigTests Swift Testing suite (7 tests)

affects:
  - 20-05: LLMRequestQueue — reads llmRequestTimeoutSeconds
  - 20-06: scheduler replacement — reads llmDebounceMs, minParagraphLength, minParagraphWordCount
  - 20-10: IncrementalConfig absorption — migrates DisplayHeuristic + AdvancedSettingsView onto this struct

tech-stack:
  added: []
  patterns:
    - "defaults.object(forKey:) as? T ?? default — distinguishes unset from user-set-zero (no integer(forKey:))"
    - "postDidChange(to:) injectable NotificationCenter — default .default, override in tests for isolation"
    - "@unchecked Sendable on UserDefaults-backed struct — matches UserDefaultsIncrementalConfig precedent"

key-files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/OpenGramConfig.swift
    - OpenGramTests/CheckEngine/ParagraphStore/OpenGramConfigTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "postDidChange takes injectable NotificationCenter param (default .default) — posting to .default in tests caused cross-suite interference that broke LLMCheckSchedulerCancellationTests and AXCallWatchdogTests"
  - "Notification test uses isolated NotificationCenter() — not NotificationCenter.default — to prevent cross-test pollution in parallel Swift Testing runner"

patterns-established:
  - "Config live-read: hold struct instance across test; mutate suite; read same instance — confirms no snapshot"
  - "NotificationCenter isolation in tests: new NotificationCenter() per test, pass as parameter"

requirements-completed: [PLL-12]

duration: 12min
completed: 2026-04-17
---

# Phase 20 Plan 02: OpenGramConfig Summary

**UserDefaults-backed OpenGramConfig struct with 8 live-read tunables (5 Phase-20 + 3 absorbed Phase-17 keys), postDidChange notification helper, and 7-test Swift Testing suite — all registered in pbxproj ParagraphStore group.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-18T01:50:00Z
- **Completed:** 2026-04-18T02:02:00Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments

- `OpenGramConfig` struct with 8 tunables, all reading via `defaults.object(forKey:) as? T ?? default` (no `integer(forKey:)` anti-pattern)
- Absorbs Phase 17 keys (`llmMinIssueCount`/`llmMinWordCount`/`llmIdleDebounceSeconds`) with identical string literals — `AdvancedSettingsView` `@AppStorage` continues to work without change
- `postDidChange(to:)` injectable for test isolation; production callers use default `.default`
- 7-test suite: defaults, Phase-17 absorption, live-read, unset-vs-zero, TimeInterval, notification, key-literal contract
- pbxproj: `OpenGramConfig.swift` + `OpenGramConfigTests.swift` in ParagraphStore group + Sources build phases

## 8 Tunables Reference (for Plan 10 cutover)

| Property | Key literal | Type | Default |
|----------|-------------|------|---------|
| `harperDebounceMs` | `harperDebounceMs` | Int | 300 |
| `llmDebounceMs` | `llmDebounceMs` | Int | 2000 |
| `llmRequestTimeoutSeconds` | `llmRequestTimeoutSeconds` | Int | 30 |
| `minParagraphLength` | `minParagraphLength` | Int | 30 |
| `minParagraphWordCount` | `minParagraphWordCount` | Int | 2 |
| `minIssueCount` | `llmMinIssueCount` | Int | 2 |
| `minWordCount` | `llmMinWordCount` | Int | 12 |
| `idleDebounceSeconds` | `llmIdleDebounceSeconds` | TimeInterval | 1.5 |

Note: `IncrementalConfig` / `UserDefaultsIncrementalConfig` are NOT deleted here. Plan 10 handles full absorption after `DisplayHeuristic` + `AdvancedSettingsView` migrate.

## Task Commits

1. **Task 1: Build OpenGramConfig with 8 live-read tunables + test suite** — `0928f3a` (feat)

**Plan metadata:** (pending)

## Files Created/Modified

- `OpenGram/CheckEngine/ParagraphStore/OpenGramConfig.swift` — struct + `postDidChange(to:)` extension
- `OpenGramTests/CheckEngine/ParagraphStore/OpenGramConfigTests.swift` — 7-test Swift Testing suite
- `OpenGram.xcodeproj/project.pbxproj` — file refs, group membership, Sources build phase entries for both files

## Decisions Made

- `postDidChange` takes injectable `NotificationCenter` (default `.default`) — posting to `.default` in tests caused cross-suite interference (LLMCheckSchedulerCancellationTests + AXCallWatchdogTests failed when run in parallel). Injectable param is a clean pattern matching existing DI conventions.
- Notification test uses fresh `NotificationCenter()` instance, not `.default`, to avoid polluting other test listeners.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NotificationCenter.default cross-test pollution**
- **Found during:** Task 1 (full suite run after targeted test passed)
- **Issue:** `postDidChange()` posting to `NotificationCenter.default` fired observers in `LLMCheckSchedulerCancellationTests` and `AXCallWatchdogTests` running in parallel — 432-test suite failed with 2 issues; isolated run passed
- **Fix:** Added `to center: NotificationCenter = .default` parameter; test uses isolated `NotificationCenter()` instance
- **Files modified:** `OpenGramConfig.swift`, `OpenGramConfigTests.swift`
- **Verification:** Full 432-test suite green
- **Committed in:** `0928f3a` (included in task commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug)
**Impact on plan:** Essential fix for test suite hygiene. `postDidChange(to:)` signature is strictly better — existing callers use `.default` unchanged.

## Issues Encountered

- `NotificationCenter.notifications(named:)` async sequence returns `Notification` which lacks `Sendable` conformance on macOS — required rewriting notification test to use `addObserver` + `withCheckedContinuation`. Resolved in same commit.

## Next Phase Readiness

- `OpenGramConfig` ready for Plans 05 (LLMRequestQueue) and 06 (scheduler) to consume
- `IncrementalConfig` untouched — Plan 10 handles cutover after all consumers migrate
- pbxproj ParagraphStore group clean for Plans 03/04/05/06

---
*Phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation*
*Completed: 2026-04-17*
