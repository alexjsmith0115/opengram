---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "03"
subsystem: CheckEngine/ParagraphStore + TextEngine
tags: [paragraph-splitter, ax-capability-cache, separator-probe, tdd, phase-20]
dependency_graph:
  requires: [20-01-PLAN.md]
  provides: [ParagraphSplitter, AXCapabilityCache.separator API]
  affects: [20-06-PLAN.md, 20-08-PLAN.md]
tech_stack:
  added: []
  patterns: [scalar-space walking for caret offset, JSONSerialization key detection for legacy format]
key_files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/Phase20ParagraphSplitter.swift
    - OpenGramTests/CheckEngine/ParagraphStore/Phase20ParagraphSplitterTests.swift
  modified:
    - OpenGram/TextEngine/AXCapabilityCache.swift
    - OpenGram/TextEngine/AXCapabilityCacheProtocol.swift
    - OpenGramTests/AXCapabilityCacheTests.swift
    - OpenGramTests/AXTextEngineTests.swift
    - OpenGramTests/TextMonitorTests.swift
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "Files renamed Phase20Paragraph* to avoid Xcode object-file collision with Phase 15 ParagraphSplitter.swift (same base name, both in same target)"
  - "AXCapabilityCacheTests separator tests added to existing file (not a new TextEngine subdir) — existing file already at root of OpenGramTests, consistent with prior art"
  - "Legacy format detection via JSONSerialization key probe (hasCapabilitiesKey) — CacheData custom init(from:) always succeeds via try? fallback, so legacy branch requires explicit key presence check"
  - "Separator probe stores empty string for whole-text-is-one-paragraph case; resolveSeparator skips cache on empty cached value (returns probed result)"
metrics:
  duration: "7 minutes"
  completed: "2026-04-18"
  tasks: 2
  files: 8
---

# Phase 20 Plan 03: Caret-Aware ParagraphSplitter + AXCapabilityCache Separator Persistence Summary

Caret-aware `ParagraphSplitter` (struct, `ParagraphStore` group) + D-05 separator probe persistence in `AXCapabilityCache`. Pure, deterministic, fully unit-tested.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extend AXCapabilityCache with separator probe persistence | 7437c73 | AXCapabilityCache.swift, AXCapabilityCacheProtocol.swift, AXCapabilityCacheTests.swift, AXTextEngineTests.swift, TextMonitorTests.swift |
| 2 | Create caret-aware ParagraphSplitter + test suite | 5486265 | Phase20ParagraphSplitter.swift, Phase20ParagraphSplitterTests.swift, project.pbxproj |

## Files Created / Modified

**Created:**
- `OpenGram/CheckEngine/ParagraphStore/Phase20ParagraphSplitter.swift` — `struct ParagraphSplitter: Sendable` with `split(text:bundleID:version:caretOffset:) -> ParagraphSet`
- `OpenGramTests/CheckEngine/ParagraphStore/Phase20ParagraphSplitterTests.swift` — 12 tests covering PLL-15a..g, caret identification, separator caching, emoji/CJK

**Modified:**
- `OpenGram/TextEngine/AXCapabilityCache.swift` — `CacheData` extended with `separators: [String: String]`, custom `init(from:)` with default `[:]`, `separatorEntries` state, `separator()/storeSeparator()` API, `loadFromDisk` legacy-format detection fix
- `OpenGram/TextEngine/AXCapabilityCacheProtocol.swift` — `separator(bundleID:version:)` + `storeSeparator(bundleID:version:separator:)` added
- `OpenGramTests/AXCapabilityCacheTests.swift` — `AXCapabilityCacheSeparatorTests` suite (6 tests) appended
- `OpenGramTests/AXTextEngineTests.swift` — `StubCapabilityCache` updated with stub separator methods
- `OpenGramTests/TextMonitorTests.swift` — `TMockCapabilityCache` updated with stub separator methods
- `OpenGram.xcodeproj/project.pbxproj` — Phase20ParagraphSplitter + Phase20ParagraphSplitterTests registered

## Separator Strategy Decisions

- Probe order: cache hit → use; cache miss → inspect text (`\n{2,}` → `"\n\n"`, `\n` → `"\n"`, neither → `""`)
- Empty probe (`""`) not persisted — self-corrects on next tick when user has typed separator text
- Cached empty string skipped in `resolveSeparator` (`!cached.isEmpty` guard) — prevents stale empty from locking out re-probe
- Separator values are literal strings only (`"\n\n"` or `"\n"`); `scanSeparatorRun` uses literal comparison, never regex on user-supplied values (T-20.03-01 threat mitigation)

## JSON Backward-Compat Notes

`CacheData.init(from:)` uses `try? c.decode(...) ?? [:]` for all three fields — any missing field defaults to empty dict, no crash.

Legacy flat `[String: Bool]` format: `CacheData.init(from:)` always succeeds (returns empty fields), so `loadFromDisk` must detect format before decoding. Fix: `JSONSerialization.jsonObject` key probe for `"capabilities"` key — if absent, route to legacy `[String: Bool]` decoder. Both legacy branches leave `separatorEntries = [:]`.

## Handoff Notes

**Plan 06** (`ParagraphSuggestionStore.reconcile`): call `splitter.split(text:bundleID:version:caretOffset:)` to produce `ParagraphSet` for reconciliation.

**Plan 08** (`TextMonitor` wiring): inject `ParagraphSplitter` (with `AXCapabilityCache`) via DI; call `split` on keystroke/focus events; pass resulting `ParagraphSet` to store.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Legacy flat-dict format not detected after CacheData custom decoder**
- **Found during:** Task 1 RED/GREEN — `legacyFlatDictJSONStillDecodes` test failed
- **Issue:** `CacheData.init(from:)` with `try?` fallbacks always succeeds, so `loadFromDisk` never reached the `else if legacy` branch for flat `{"key":true}` JSON
- **Fix:** Added `hasCapabilitiesKey` probe via `JSONSerialization.jsonObject` before attempting `CacheData` decode in `loadFromDisk`
- **Files modified:** `AXCapabilityCache.swift`
- **Commit:** 7437c73

**2. [Rule 3 - Collision] Xcode object-file name collision with Phase 15 ParagraphSplitter.swift**
- **Found during:** Task 2 first build attempt
- **Issue:** Both `ParagraphInfra/ParagraphSplitter.swift` and `ParagraphStore/ParagraphSplitter.swift` produce same `.stringsdata` artifact; Xcode rejects duplicate filenames in same target
- **Fix:** Renamed new files to `Phase20ParagraphSplitter.swift` / `Phase20ParagraphSplitterTests.swift`; updated all pbxproj references
- **Files modified:** `project.pbxproj` (filename references updated)
- **Commit:** 5486265

**3. [Rule 2 - Pattern] Suite name collision with Phase 15 ParagraphSplitterTests**
- **Found during:** Task 2 design — both Phase 15 and Phase 20 test files would produce `@Suite struct ParagraphSplitterTests`
- **Fix:** Named Phase 20 suite `Phase20ParagraphSplitterTests` to avoid ambiguity in test output
- **Commit:** 5486265

## Test Results

- `AXCapabilityCacheSeparatorTests`: 6/6 pass
- `Phase20ParagraphSplitterTests`: 12/12 pass (11 behavior + 1 bundleID carry-through)
- Full suite: 450/450 pass — no regressions

## Known Stubs

None — all data paths wired. `ParagraphSplitter.split` produces real `ParagraphSet` with real `ParagraphHash` values.

## Threat Flags

T-20.03-01 mitigated: `scanSeparatorRun` uses literal `"\n\n"` / `"\n"` comparison only; unknown separator values from tampered cache fall through to single-paragraph behavior (no regex execution on attacker-supplied data).

## Self-Check: PASSED

- Phase20ParagraphSplitter.swift: FOUND
- Phase20ParagraphSplitterTests.swift: FOUND
- AXCapabilityCache.swift: FOUND
- Commit 7437c73: FOUND
- Commit 5486265: FOUND
