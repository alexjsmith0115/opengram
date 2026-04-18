---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "01"
subsystem: CheckEngine/ParagraphStore
tags: [data-model, value-types, hashing, state-machine, swift-testing]
dependency_graph:
  requires: []
  provides:
    - ParagraphHash (bundleID+sha256 Hashable cache key)
    - ParagraphSet (snapshot of split paragraphs + caret position)
    - StoreEvent (AsyncStream event enum)
    - ParagraphSuggestionState (6-state machine enum)
    - ParagraphCacheEntry (value-type cache entry struct)
  affects:
    - Plans 05, 06 (ParagraphSuggestionStore actor)
    - Plans 07, 09 (OverlayController renderer)
tech_stack:
  added: []
  patterns:
    - "@unchecked Sendable on enum with Error associated value (actor-owned, immutable post-insert)"
    - "Full 64-char SHA-256 hex vs compressed UInt64 (prior Phase 15 approach)"
    - "Named Entry struct in ParagraphSet instead of inline tuple (tuple not Sendable across actor boundaries)"
key_files:
  created:
    - OpenGram/CheckEngine/ParagraphStore/ParagraphHash.swift
    - OpenGram/CheckEngine/ParagraphStore/ParagraphSet.swift
    - OpenGram/CheckEngine/ParagraphStore/StoreEvent.swift
    - OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionState.swift
    - OpenGram/CheckEngine/ParagraphStore/ParagraphCacheEntry.swift
    - OpenGramTests/CheckEngine/ParagraphStore/ParagraphHashTests.swift
  modified:
    - OpenGram.xcodeproj/project.pbxproj
decisions:
  - "@unchecked Sendable on ParagraphSuggestionState: Error is not Sendable; safe because values are actor-owned (LLMRequestQueue) and handed to store — never mutated after insertion"
  - "Full 64-char hex sha256 in ParagraphHash (not compressed UInt64): full hash eliminates collision risk at the cache key level; UInt64 prefix used by Phase 15 Sha256ParagraphHasher for a different purpose"
  - "ParagraphSet.Entry named struct not tuple: Swift tuples lack Sendable conformance across actor hops"
  - "normalize() in ParagraphHash is byte-identical to Sha256ParagraphHasher.normalize — both surfaces agree on same-paragraph semantics"
metrics:
  duration: "~10 minutes"
  completed: "2026-04-18T01:53:59Z"
  tasks_completed: 2
  files_created: 6
  files_modified: 1
---

# Phase 20 Plan 01: ParagraphStore Data Model Primitives Summary

**One-liner:** 5 pure value-type files establish the compile-stable contract surface for Phase 20's paragraph-level LLM cache — ParagraphHash (bundleID+SHA-256), ParagraphSet, ParagraphSuggestionState (6-state machine), ParagraphCacheEntry, StoreEvent — with 7-test Swift Testing suite.

## What Was Built

### Files Created

| File | What It Provides |
|------|-----------------|
| `ParagraphHash.swift` | `struct ParagraphHash: Hashable, Sendable` — `(bundleID, sha256)` cache key; normalize() matches Phase 15 hasher byte-for-byte |
| `ParagraphSet.swift` | `struct ParagraphSet: Sendable` — snapshot of split paragraphs + optional caret hash; uses named `Entry` struct for Sendable correctness |
| `StoreEvent.swift` | `enum StoreEvent: Sendable` — `.suggestionsChanged(bundleID:)` for `AsyncStream` event fan-out |
| `ParagraphSuggestionState.swift` | `enum ParagraphSuggestionState: @unchecked Sendable` — 6 states + `Kind` projection for test equality |
| `ParagraphCacheEntry.swift` | `struct ParagraphCacheEntry: @unchecked Sendable` — `let hash`, `let originalText`, `var state` |
| `ParagraphHashTests.swift` | 7-test `@Suite` covering hex format, whitespace normalization, case sensitivity, bundleID partitioning, determinism, escape hatch |

### pbxproj Changes

- New `ParagraphStore` PBXGroup under app `CheckEngine` group
- New `ParagraphStore` PBXGroup under test `CheckEngine` group
- 5 app source PBXFileReference + PBXBuildFile entries
- 1 test PBXFileReference + PBXBuildFile entry
- All wired into correct Sources build phases

## Handoff Interfaces for Plans 05 and 06

```swift
struct ParagraphHash: Hashable, Sendable {
    let bundleID: String
    let sha256: String
    init(bundleID: String, paragraphText: String)
    init(bundleID: String, sha256: String)   // escape hatch for tests
    static func sha256Hex(of text: String) -> String
}

struct ParagraphSet: Sendable {
    struct Entry: Sendable {
        let hash: ParagraphHash
        let text: String
    }
    let bundleID: String
    let paragraphs: [Entry]
    let caretParagraphHash: ParagraphHash?
}

enum ParagraphSuggestionState: @unchecked Sendable {
    case pending(submittedAt: Date)
    case ready(Suggestion)
    case readyEmpty
    case failed(Error)
    case dismissed
    case accepted
    var kind: Kind  // Equatable projection for tests
}

struct ParagraphCacheEntry: @unchecked Sendable {
    let hash: ParagraphHash
    let originalText: String
    var state: ParagraphSuggestionState
}

enum StoreEvent: Sendable {
    case suggestionsChanged(bundleID: String)
}
```

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — pure value types with no logic. No data flow to stub.

## Threat Flags

None — pure value types, no I/O, no trust boundary crossed (matches plan threat model).

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| ParagraphHashTests | 7 | All pass |
| Full suite | 425 | 424 pass; 1 pre-existing flaky test (`idleDebounceSeconds_liveReadHonoredWithoutReinit` in `LLMCheckSchedulerCancellationTests`) passes in isolation but flakes under full-suite LLM timeout contention — unrelated to this plan |

## Self-Check: PASSED

- `OpenGram/CheckEngine/ParagraphStore/ParagraphHash.swift` — FOUND
- `OpenGram/CheckEngine/ParagraphStore/ParagraphSet.swift` — FOUND
- `OpenGram/CheckEngine/ParagraphStore/StoreEvent.swift` — FOUND
- `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionState.swift` — FOUND
- `OpenGram/CheckEngine/ParagraphStore/ParagraphCacheEntry.swift` — FOUND
- `OpenGramTests/CheckEngine/ParagraphStore/ParagraphHashTests.swift` — FOUND
- Commit `481c048` (Task 1) — FOUND
- Commit `1965d16` (Task 2) — FOUND
- Build: `** BUILD SUCCEEDED **`
- Tests: 7/7 ParagraphHashTests pass
