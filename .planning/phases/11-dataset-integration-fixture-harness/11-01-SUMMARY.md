---
phase: 11
plan: "01"
subsystem: harper-bridge/clarity
tags: [rust, toml, serde, oncelock, corpus, parse-infrastructure]
dependency_graph:
  requires: []
  provides: [ParsedPhraseEntry, parse_wordy_phrases, get_corpus, PARSED_CORPUS]
  affects: [harper-bridge/src/clarity.rs]
tech_stack:
  added: [serde@1, toml@0.9]
  patterns: [OnceLock parse-once cache, serde Deserialize for TOML]
key_files:
  created: []
  modified:
    - harper-bridge/Cargo.toml
    - harper-bridge/src/clarity.rs
decisions:
  - "ParsedPhraseEntry uses owned String fields (not &'static str) — TOML-parsed heap data"
  - "severity_from_str defaults unknown strings to Medium — safe fallback for dataset additions"
  - "dialect_from_str returns None for unknown dialects and they are filtered out — silent skip is correct for new dialect tags"
  - "parsed_corpus_handle() test-only accessor exposes OnceLock for single-init pointer-stability proof without prod-code counters"
  - "PartialEq derived on ParsedPhraseEntry for round-trip test equality assertions"
metrics:
  duration: "~8min"
  completed: "2026-04-25"
  tasks_completed: 2
  files_modified: 3
---

# Phase 11 Plan 01: TOML Parse Infrastructure Summary

**One-liner:** serde+toml deps promoted from transitives; ParsedPhraseEntry owned-String struct + OnceLock-cached get_corpus() wired to include_str! of wordy_phrases.toml.

## What Was Built

### Deps (harper-bridge/Cargo.toml)

Both were already compiled transitives in Cargo.lock — zero new compile units added:

```toml
serde = { version = "1", features = ["derive"] }
toml = "0.9"
```

### New Types + Functions (harper-bridge/src/clarity.rs)

**Serde structs (crate-private):**
- `TomlFile { entries: Vec<TomlPhraseEntry> }` — top-level TOML document shape
- `TomlPhraseEntry` — per-entry serde target; `sources`, `id`, `note` fields ignored (no field = skip); `dialects` defaults to `None` via `#[serde(default)]`

**Public types:**
- `ParsedPhraseEntry { phrase: String, replacement: String, severity: Severity, dialects: Option<Vec<Dialect>> }` — owned, heap-allocated; `PartialEq + Clone + Debug`

**Private helpers:**
- `severity_from_str(s: &str) -> Severity` — `"high"` → High, `"low"` → Low, else → Medium
- `dialect_from_str(s: &str) -> Option<Dialect>` — maps `"en-US"/"American"`, `"en-GB"/"British"`, `"en-CA"/"Canadian"`, `"en-AU"/"Australian"`, `"en-IN"/"Indian"`; unknown → None (filtered out)

**Public API:**
- `parse_wordy_phrases(toml_str: &str) -> Vec<ParsedPhraseEntry>` — synchronous parse + map
- `static PARSED_CORPUS: OnceLock<Vec<ParsedPhraseEntry>>` — process-global once-init cache
- `get_corpus() -> &'static [ParsedPhraseEntry]` — calls `get_or_init` on first call, lock-free read thereafter
- `parsed_corpus_handle()` (`#[cfg(test)]`) — exposes `&'static OnceLock<...>` for pointer-stability test

### OnceLock Pointer-Stability Proof

`corpus_parsed_exactly_once` test: calls `get_corpus()` once, records `as_ptr()`, calls 100 more times, asserts `as_ptr()` unchanged. Single allocation = single parse. No prod-code counters needed — `OnceLock::get()` returns `Some` only after init.

## Test Counts

| Snapshot | Count |
|----------|-------|
| Prior (Phase 10) | 11 |
| New (Plan 01) | 3 |
| **Total** | **14** |

New tests:
- `parse_wordy_phrases_round_trip` — minimal inline TOML with unknown fields (`sources`, `id`) skipped, dialects None
- `parse_wordy_phrases_real_dataset_338_entries` — `include_str!` parse asserts len == 338
- `corpus_parsed_exactly_once` — OnceLock pointer equality across 102 calls, len == 338

## Deviations from Plan

None — plan executed exactly as written.

The plan specified `#[derive(Clone, Debug)]` on `ParsedPhraseEntry`; added `PartialEq` as well (needed for `assert_eq!(parsed[0].severity, Severity::High)` in round-trip test). This is a trivial additive derive, not a deviation from intent.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. `include_str!` bakes TOML at compile time — no runtime file I/O introduced. `toml::from_str` panics on malformed input; acceptable because the input is compile-time bundled (T-11-01 in plan threat model: accepted).

## Self-Check: PASSED

- FOUND: harper-bridge/Cargo.toml
- FOUND: harper-bridge/src/clarity.rs
- FOUND: commit a1fb91e
