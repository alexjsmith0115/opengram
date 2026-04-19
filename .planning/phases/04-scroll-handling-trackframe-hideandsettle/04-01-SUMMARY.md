---
phase: 04-scroll-handling-trackframe-hideandsettle
plan: 01
subsystem: appquirks
tags: [appquirks, scrollmode, plist, codable]

requires:
  - phase: prior-AppQuirks
    provides: AppQuirk Codable struct + AppQuirksTable singleton
provides:
  - ScrollMode enum (Codable, String-raw): trackFrame, hideAndSettle
  - AppQuirk.scrollMode optional field (nil resolves to hideAndSettle at call site)
  - AppQuirks.plist allowlist entries for com.apple.Notes, com.apple.TextEdit, com.apple.mail (scrollMode=trackFrame)
  - 5 unit tests covering injection, plist round-trip, bundled allowlist, defaults
affects: [04-02, 04-03, 04-04, 04-05]

tech-stack:
  added: []
  patterns:
    - "Add new optional Codable fields with `= nil` defaults so synthesized memberwise init keeps existing positional call sites compiling"

key-files:
  created: []
  modified:
    - OpenGram/AppQuirks/AppQuirksTable.swift
    - OpenGram/AppQuirks/AppQuirks.plist
    - OpenGramTests/AppQuirksTests.swift

key-decisions:
  - "AppQuirk Codable optional fields gain `= nil` inline defaults so existing positional initializers (3 prior tests) compile unchanged after scrollMode is added; alternative of updating all call sites was equivalent work but mutated unrelated tests"
  - "Tests appended to existing OpenGramTests/AppQuirksTests.swift rather than new file — file already registered in pbxproj, no project mutation needed"

patterns-established:
  - "Codable struct grows by adding `var x: T? = nil` fields, no decoder customization required — picked up automatically"

requirements-completed: [PERF-07]

duration: 12min
completed: 2026-04-19
---

# Phase 4 Plan 01: AppQuirks scrollMode Field Summary

**ScrollMode enum + per-app `scrollMode` AppQuirk field + Notes/TextEdit/Mail trackFrame allowlist with full test coverage.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-19T13:37:00Z
- **Completed:** 2026-04-19T13:49:21Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- `ScrollMode` enum (`String, Codable`): cases `trackFrame`, `hideAndSettle`
- `AppQuirk.scrollMode: ScrollMode?` field added (with `= nil` default; sibling fields also defaulted to keep existing 3 tests compiling)
- 3 plist entries added: `com.apple.Notes`, `com.apple.TextEdit`, `com.apple.mail` — each `scrollMode=trackFrame`
- 5 new tests in `AppQuirksTableScrollModeTests`: injected lookup, unknown bundle nil, plist round-trip, bundled allowlist, Chrome nil-scrollMode
- 8/8 tests pass in AppQuirks suites; build succeeds via `xcodebuild`

## Task Commits

1. **Task 1 RED — failing scrollMode tests:** `0d5be98` (test)
2. **Task 1 GREEN — ScrollMode enum + AppQuirk.scrollMode field:** `b59c86e` (feat)
3. **Task 2 — plist allowlist entries:** `9ae4381` (feat)

Task 3 (tests) merged into Task 1 RED commit since tests were authored first to drive the implementation; the GREEN commit and Task 2 commit completed the suite — all 5 tests pass after `9ae4381`.

## Files Created/Modified

- `OpenGram/AppQuirks/AppQuirksTable.swift` — added `ScrollMode` enum + `scrollMode` field; existing optional fields gained `= nil` inline defaults
- `OpenGram/AppQuirks/AppQuirks.plist` — added 3 trackFrame entries (Notes/TextEdit/Mail)
- `OpenGramTests/AppQuirksTests.swift` — appended `AppQuirksTableScrollModeTests` suite (5 tests)

## Decisions Made

- **`= nil` defaults on all AppQuirk optional fields:** Without inline defaults, Swift's synthesized memberwise initializer requires every property as a positional argument. Three pre-existing tests use the long positional form `AppQuirk(coordinateOffsetX: nil, coordinateOffsetY: nil, lineHeightFactor: nil, boundsStrategy: nil, notificationUnreliable: ...)`. Adding `scrollMode` without defaults would break them. With defaults, `AppQuirk(scrollMode: .trackFrame)` and the long positional form both compile.
- **Append to existing test file (not new file):** Plan offered both options; appending avoids `project.pbxproj` mutation and keeps related tests adjacent.

## Deviations from Plan

None — plan executed as written. The `= nil` default decision is documented in the plan's `<action>` step note ("Codable decoder picks up new field automatically") combined with the implicit constraint that existing tests must still compile.

## Issues Encountered

- Full-suite run flagged 2 failures in `AXCallWatchdogTests` (`shouldSkip returns true …after timeout` and `blocklist entry expires …`). Re-ran in isolation: both pass. Pre-existing time-based flake under parallel load, unrelated to scrollMode work and out of scope. No fix attempted.

## TDD Gate Compliance

- RED: `0d5be98` (`test(04-01): add failing tests for AppQuirk.scrollMode field`) — confirmed compile failure for missing field
- GREEN: `b59c86e` + `9ae4381` (`feat(04-01): …`) — 4/5 tests green after `b59c86e`, all 5 green after `9ae4381`
- REFACTOR: not needed — minimal additive change

## Next Phase Readiness

- `AppQuirksTable.shared.quirk(for: bundleID)?.scrollMode ?? .hideAndSettle` is the resolve pattern for downstream plans (introduced in 04-04 D-09).
- `ScrollMode` enum is the contract for OverlayController state machine in 04-02..04-04.
- No blockers.

## Self-Check: PASSED

- `OpenGram/AppQuirks/AppQuirksTable.swift` — FOUND, contains `enum ScrollMode: String, Codable` + `var scrollMode: ScrollMode?`
- `OpenGram/AppQuirks/AppQuirks.plist` — FOUND, `plutil -lint` OK, 3 trackFrame entries
- `OpenGramTests/AppQuirksTests.swift` — FOUND, contains `AppQuirksTableScrollModeTests` (5 `@Test`)
- Commit `0d5be98` — FOUND
- Commit `b59c86e` — FOUND
- Commit `9ae4381` — FOUND

---
*Phase: 04-scroll-handling-trackframe-hideandsettle*
*Completed: 2026-04-19*
