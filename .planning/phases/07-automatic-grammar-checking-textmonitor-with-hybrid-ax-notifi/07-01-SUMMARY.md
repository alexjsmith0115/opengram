---
phase: 07-automatic-grammar-checking-textmonitor-with-hybrid-ax-notifi
plan: 01
subsystem: TextEngine, SuggestionUI, AppQuirks
tags: [diff-engine, ax-cache, app-quirks, tdd]
dependency_graph:
  requires: []
  provides:
    - SuggestionDiffEngine (consumed by Plans 02 and 03 for flicker-free overlay updates)
    - AXCapabilityCache.isNotificationReliable / storeNotificationReliability (consumed by Plan 02 TextMonitor)
    - AppQuirk.notificationUnreliable (consumed by Plan 02 TextMonitor for pre-classification)
  affects:
    - OpenGramTests/AXTextEngineTests.swift (StubCapabilityCache updated to conform to extended protocol)
tech_stack:
  added: []
  patterns:
    - SuggestionKey Hashable struct for UUID-free suggestion identity (scalar offset + original + category)
    - CacheData wrapper struct for multi-dictionary JSON persistence with backward compatibility
    - AppQuirk optional field extension pattern (Codable, nil = use default)
key_files:
  created:
    - OpenGram/SuggestionUI/SuggestionDiffEngine.swift
    - OpenGramTests/SuggestionDiffEngineTests.swift
    - OpenGramTests/AppQuirksTests.swift
  modified:
    - OpenGram/TextEngine/AXCapabilityCacheProtocol.swift
    - OpenGram/TextEngine/AXCapabilityCache.swift
    - OpenGram/AppQuirks/AppQuirksTable.swift
    - OpenGram/AppQuirks/AppQuirks.plist
    - OpenGramTests/AXTextEngineTests.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - Used CacheData wrapper struct (capabilities + notifications) in a single JSON file rather than a second file — avoids two disk reads on startup and keeps cache logic in one place
  - Notification reliability keyed by bundleID only (no version component) — AX notification behavior is app-wide, not version-specific
  - AppQuirk.notificationUnreliable is optional Bool? — nil means unknown/not pre-classified, preserving backward compatibility with existing plist entries
  - SuggestionKey uses scalar offsets from the parallel array (not recomputed from String.Index) — matches OverlayController's existing suggestionScalarOffsets pattern exactly
metrics:
  duration: ~4 minutes
  completed: 2026-04-14
  tasks_completed: 2
  files_created: 3
  files_modified: 7
---

# Phase 07 Plan 01: Data Layer — SuggestionDiffEngine, AXCapabilityCache Notification Reliability, AppQuirk notificationUnreliable

**One-liner:** UUID-free suggestion diff engine using scalar offset + category keys, plus AX notification reliability cache storage and known-unreliable app pre-classification via AppQuirks.plist.

## What Was Built

### Task 1: SuggestionDiffEngine

`OpenGram/SuggestionUI/SuggestionDiffEngine.swift` implements a diff algorithm for comparing old vs new suggestion sets without UUID comparison. Harper regenerates UUIDs on every check pass (RESEARCH.md Pitfall 6), so UUID-based comparison would mark every suggestion as changed even when nothing moved — causing unnecessary overlay flicker.

- `SuggestionKey: Hashable` — identity by `(scalarStart, scalarLength, original, category)`
- `SuggestionDiffResult` — `unchanged: [(oldIndex, newIndex)]`, `added: [Int]`, `removed: [Int]`
- `SuggestionDiffEngine.diff()` — O(n) via dictionary lookup on old set, iterates new set once
- 8 tests covering all edge cases: identical sets, additions, removals, changed original, changed category, empty old, empty new, both empty

### Task 2: AXCapabilityCache + AppQuirk Extensions

**Protocol extension** (`AXCapabilityCacheProtocol.swift`): added `isNotificationReliable(bundleID:)` and `storeNotificationReliability(bundleID:reliable:)`.

**Cache implementation** (`AXCapabilityCache.swift`):
- Added `notificationEntries: [String: Bool]` dictionary alongside existing `entries`
- Introduced `CacheData` wrapper struct `{ capabilities, notifications }` for single-file JSON persistence
- `loadFromDisk()` detects old flat `[String: Bool]` format and migrates transparently (backward compat)

**AppQuirk** (`AppQuirksTable.swift`): added `var notificationUnreliable: Bool?` — optional, backward compatible with all existing plist entries.

**AppQuirks.plist**: pre-classified `com.google.Chrome`, `com.microsoft.VSCode`, and `com.github.Electron` as `notificationUnreliable: true` (D-02).

**StubCapabilityCache** (`AXTextEngineTests.swift`): updated to conform to the extended protocol.

## Test Results

- 195/195 tests pass (full suite)
- 8 SuggestionDiffEngine tests: all green
- 8 Task 2 tests (3 AppQuirks + 5 notification reliability): all green
- BUILD SUCCEEDED

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] AppQuirksTests.swift referenced in pbxproj before Task 2 created it**
- **Found during:** Task 1 test run (build failed with "input file cannot be found")
- **Issue:** Both new test files were added to pbxproj in Task 1's pbxproj edit. AppQuirksTests.swift (Task 2's file) was referenced but didn't exist, blocking Task 1's test run.
- **Fix:** Created minimal compilable stub for AppQuirksTests.swift during Task 1, replaced with full implementation in Task 2.
- **Files modified:** OpenGramTests/AppQuirksTests.swift

**2. [Rule 3 - Blocking] HarperBridge.xcframework not present in worktree**
- **Found during:** First build attempt
- **Issue:** xcframework is gitignored (exceeds GitHub 100MB limit). Worktree doesn't inherit it.
- **Fix:** Copied xcframework from main repo into worktree directory.
- **Files modified:** HarperBridge.xcframework (binary, not committed)

## Known Stubs

None. All plan goals achieved with real implementations.

## Threat Flags

None. No new network endpoints, auth paths, or trust boundaries introduced. The `CacheData` JSON file remains in Application Support (user-writable) — consistent with T-07-01 accepted risk in the plan's threat model.

## Self-Check: PASSED

- FOUND: OpenGram/SuggestionUI/SuggestionDiffEngine.swift
- FOUND: OpenGramTests/SuggestionDiffEngineTests.swift
- FOUND: OpenGramTests/AppQuirksTests.swift
- FOUND commit: 907d290
- FOUND commit: da3b6a6
- PASS: No UUID comparison (`suggestion.id`) in SuggestionDiffEngine diff logic
