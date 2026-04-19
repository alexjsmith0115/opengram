---
phase: 02-cancellable-bounds-queries
plan: "02"
subsystem: testing-infrastructure
tags: [testing, accessibility, mock, performance, infrastructure]
dependency_graph:
  requires: [02-01]
  provides: [SlowMockAXAccessor test helper]
  affects: [OpenGramTests/TestHelpers, OpenGram.xcodeproj]
tech_stack:
  added: []
  patterns: [wrapper-not-subclass, synchronous-sleep-for-cancellation-window, passthrough-properties]
key_files:
  created:
    - OpenGramTests/TestHelpers/SlowMockAXAccessor.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Wrapper pattern (not subclass) because MockAXAccessor is final"
  - "Thread.sleep via Duration.components decomposition — avoids NSDate-era convenience, stable since Swift 5.7"
  - "Passthrough computed properties (parameterizedAttributeValues, attributeValues) for test-setup parity without reaching into .wrapped"
  - "Sources build phase entry required — group-only registration produces dead file; Plan 02-03 tests would not compile"
metrics:
  duration: 12m
  completed: 2026-04-19T05:12:32Z
  tasks_completed: 3
  files_changed: 2
requirements: [PERF-03]
---

# Phase 2 Plan 02: SlowMockAXAccessor Test Helper Summary

`SlowMockAXAccessor`: AXAccessor wrapper injecting per-call `Duration` sleep, delegating to `MockAXAccessor`, enabling PERF-03 cancellation-window tests.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create SlowMockAXAccessor wrapper | 6266bbc | OpenGramTests/TestHelpers/SlowMockAXAccessor.swift |
| 2 | Register in pbxproj (group + file ref + Sources build phase) | 1d126eb | OpenGram.xcodeproj/project.pbxproj |
| 3 | Build + full test suite validation | — | (validation only) |

## Artifact Details

### OpenGramTests/TestHelpers/SlowMockAXAccessor.swift

`final class SlowMockAXAccessor: AXAccessor, @unchecked Sendable` — wraps `MockAXAccessor` (final, no subclassing). Stores `let wrapped: MockAXAccessor` + `let delay: Duration`. All 8 `AXAccessor` protocol methods implemented, each calling `sleep()` before delegating. Passthrough computed properties `parameterizedAttributeValues` + `attributeValues` allow test setup via `slow.parameterizedAttributeValues[...] = ...` without `.wrapped` indirection. `sleep()` decomposes `Duration` via `.components.seconds` + `.components.attoseconds / 1e18` → `Thread.sleep(forTimeInterval:)`.

### pbxproj registration

4 entries added:
- `PBXBuildFile`: `B10000010000000000000050` (SlowMockAXAccessor.swift in Sources)
- `PBXFileReference`: `B20000010000000000000050` (SlowMockAXAccessor.swift)
- `PBXGroup`: `B4000001000000000000000D` (TestHelpers — child of OpenGramTests root group)
- Sources build phase entry in `B60000010000000000000001`

`plutil -lint` exits 0. SlowMockAXAccessor.swift appears 4 times in pbxproj.

## Build + Test Results

`xcodebuild build`: BUILD SUCCEEDED — zero warnings.

`xcodebuild test`: 463 tests, 72 suites. 2 pre-existing failures (`AXCallWatchdogTests` timing-sensitive, confirmed present on prior commit) + 1 LLM integration timeout (localhost:1234 not running). Neither caused by this plan. New helper file compiles and is accessible to test target.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — SlowMockAXAccessor is complete infrastructure, no placeholder data flows.

## Threat Flags

None — test-only code, no production surface introduced.

## Self-Check

- [x] `OpenGramTests/TestHelpers/SlowMockAXAccessor.swift` exists
- [x] All 6 grep structure gates pass
- [x] `plutil -lint` exits 0
- [x] SlowMockAXAccessor.swift appears 4 times in pbxproj
- [x] TestHelpers group registered + referenced by OpenGramTests parent group
- [x] `xcodebuild build` exits 0, zero warnings
- [x] Commits 6266bbc + 1d126eb exist in git log

## Self-Check: PASSED
