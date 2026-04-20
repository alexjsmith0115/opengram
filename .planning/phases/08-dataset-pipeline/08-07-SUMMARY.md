---
phase: 08-dataset-pipeline
plan: "07"
subsystem: dataset-pipeline
tags: [dataset, gap-closure, inflection, overrides, pipeline-extension]
dependency_graph:
  requires: ["08-05"]
  provides: ["CLAR-04 inflection contract for utilize family", "add override op"]
  affects: ["Phase 10 matcher", "harper-bridge/data/wordy_phrases.toml"]
tech_stack:
  added: []
  patterns: ["add override op in overrides.toml", "TDD red/green for pipeline extension"]
key_files:
  created: []
  modified:
    - harper-bridge/scripts/build_wordy_phrases.py
    - harper-bridge/scripts/overrides.toml
    - harper-bridge/scripts/tests/test_overrides.py
    - harper-bridge/data/wordy_phrases.toml
decisions:
  - "add op chosen over upstream bump (would shift ids, break verification manifest)"
  - "add op chosen over post-pipeline append (would violate SC-1 byte-determinism)"
  - "utilized → used (past-tense pairs with past-tense replacement)"
  - "utilizes → use (3rd-person present pairs with base form, matches retext util→use convention)"
  - "severity=medium per D-07 single-source default; sources=[manual] per D-14 truthfulness"
metrics:
  duration: "~12 minutes"
  completed: "2026-04-20"
  tasks_completed: 2
  files_modified: 4
---

# Phase 8 Plan 7: CLAR-04 Inflection Gap Closure Summary

**One-liner:** Pipeline extended with `add` override op; `utilizes` + `utilized` added as own PhraseEntry rows (338 entries, SHA 5dd70d74, 37 tests green).

## What Was Done

Closed VERIFICATION gap: upstream retext-simplify@c7686ac ships only `utilize` + `utilization`. Phase 10 matcher requires all inflected forms as independent dataset entries per CLAR-04 / D-05. Two new entries added via the new `add` override op.

### Task 1 — Extend pipeline with `add` override op

**`build_wordy_phrases.py` changes:**

- `_VALID_OVERRIDE_KEYS` extended: `{"drop", "severity", "replacement", "dialects", "note", "add", "phrase", "sources"}`
- `load_overrides`: validates add-op shape — requires `phrase`, `replacement`, `sources`; `sources` must be non-empty list; `phrase` must derive to the keyed id (key/phrase drift guard, T-8-10)
- `apply_overrides`: collects add-op rows first, appends synthesized `PhraseEntry` dicts after mutate/drop loop; id-uniqueness re-check catches add-colliding-with-existing (T-8-11)
- Mutate-op rows forbidden from carrying `phrase`/`sources` (prevents provenance confusion)

**5 new `TestAddOp` tests (37 total, was 32):**
- `test_add_op_creates_new_entry_with_defaults` — minimal fields, severity defaults to medium, sources preserved
- `test_add_op_explicit_severity_honored` — explicit severity=high not overridden
- `test_add_op_id_collision_with_existing_raises` — SystemExit when add-op id matches sourced entry
- `test_add_op_missing_required_key_raises` — SystemExit on missing required fields
- `test_add_op_phrase_must_match_key` — SystemExit on key/phrase drift

### Task 2 — Add entries; regenerate

Two add-op rows appended to `overrides.toml`:
- `utilizes` → `use`, severity=medium, sources=["manual"]
- `utilized` → `used`, severity=medium, sources=["manual"]

Regenerated `wordy_phrases.toml`: 338 entries (336 + 2).

## Invariant Verification

| Check | Result |
|-------|--------|
| Entry count | 338 |
| `utilizes` present (phrase + id) | Yes |
| `utilized` present (phrase + id) | Yes |
| `utilize` preserved | Yes |
| `utilization` preserved | Yes |
| sources=["manual"] on new rows | Yes (2 matches) |
| severity="medium" on new rows | Yes |
| Byte-determinism (two-run SHA match) | PASS — `5dd70d74ab7aa6ac6c61e0bbd047f940660d12dfed8b77ddeada51586b5d6df8` |
| NFC invariant | PASS |
| Zero # JUDGMENT: comments | PASS |
| Bundle size (≤200KB) | 47935 bytes |
| TOML parseable | PASS |
| Test suite | 37/37 green |
| Existing 5 override rows untouched | Yes (append-only diff) |

## Decisions Made

- **`add` op over upstream bump:** bumping retext-simplify@c7686ac would shift entry ids, break SOURCES.sha256, re-trigger judgment curation across all 336 entries. Pipeline extension is narrower.
- **`add` op over post-pipeline append script:** a separate append script outside `build_wordy_phrases.py` would violate SC-1 byte-determinism (regenerability via single entry point).
- **`utilizes → use`:** 3rd-person present pairs with base form; matches upstream `utilize → use` convention. Phase 10 may revisit to `uses` if matcher ergonomics require it.
- **`utilized → used`:** past tense pairs with past-tense replacement — semantically precise.
- **`severity = "medium"`:** D-07 single-source default applies to manual entries (inherently single-source).
- **`sources = ["manual"]`:** D-14 truthfulness — these entries have no retext/plainlang provenance.

## Deviations from Plan

None — plan executed exactly as written.

## Hand-off to Phase 10

Phase 10 matcher may now rely on dataset-driven inflection for the full `utilize` family:
- `utilize` (id: `utilize`)
- `utilizes` (id: `utilizes`)
- `utilized` (id: `utilized`)
- `utilization` (id: `utilization`)

All four present as independent PhraseEntry rows in committed `wordy_phrases.toml`.

## Commits

- `71cd47c` — feat(08-07): extend pipeline with add override op + tests
- `034a77f` — feat(08-07): add utilizes + utilized entries; regenerate to 338 entries

## Self-Check: PASS
