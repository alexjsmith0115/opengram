---
phase: 08-dataset-pipeline
plan: "05"
subsystem: dataset-pipeline
tags: [python, dataset, vendoring, curation, sha256, toml]
dependency_graph:
  requires:
    - harper-bridge/scripts/build_wordy_phrases.py (Plans 02-04 — full pipeline)
    - harper-bridge/scripts/sources/ (this plan creates)
    - harper-bridge/scripts/overrides.toml (this plan creates)
  provides:
    - harper-bridge/scripts/sources/retext-simplify-c7686ac.js (vendored, 17KB, MIT)
    - harper-bridge/scripts/sources/plainlanguage-fd76947.md (vendored, 6KB, US PD)
    - harper-bridge/scripts/sources/SOURCES.sha256 (sha256sum-format manifest)
    - harper-bridge/scripts/overrides.toml (curated — 5 Rule-2 judgment entries resolved)
    - harper-bridge/data/wordy_phrases.toml (generated, committed, 336 entries, 47516 bytes)
  affects:
    - Plan 06 (THIRD_PARTY.md — reads same source provenance)
    - Phase 9 (PhraseEntry Rust struct — consumes D-12 schema from committed TOML)
    - Phase 11 (include_str! wire-up + fixture harness keyed by id field)
tech_stack:
  added: []
  patterns:
    - Vendored source at pinned SHA + sha256sum-format manifest (SOURCES.sha256)
    - _discover_source_shas accepts both .js and .json extension (fix for real data)
    - Rule-2 judgment entries (verbose filler phrases) curated as severity override, not dropped
key_files:
  created:
    - harper-bridge/scripts/sources/retext-simplify-c7686ac.js
    - harper-bridge/scripts/sources/plainlanguage-fd76947.md
    - harper-bridge/scripts/sources/SOURCES.sha256
    - harper-bridge/scripts/overrides.toml
    - harper-bridge/data/wordy_phrases.toml
  modified:
    - harper-bridge/scripts/build_wordy_phrases.py (_discover_source_shas .js fix)
decisions:
  - "336 entries (not 450-510) — actual source overlap is 70% (220/313 phrases shared), research estimated 25%. Real data count; no pipeline fix needed."
  - "All 5 Rule-2 judgment entries kept (not dropped) — they are textbook verbose-filler phrases (because of the fact that, due to the fact that, etc.) with clear, concise replacements."
  - "Both-source judgment entries (due to the fact that, in view of the above) restored to severity=high. Single-source entries restored to medium."
  - "_discover_source_shas regex extended to match .js extension (plan specified .js; code had .json — Rule 1 fix)."
requirements-completed: [CLAR-14, CLAR-15]
duration: ~12min
completed: "2026-04-20"
---

# Phase 08 Plan 05: Real data vendored — retext-simplify@c7686ac + plainlanguage.gov@fd76947, 336-entry byte-deterministic wordy_phrases.toml

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-20T19:19:00Z
- **Completed:** 2026-04-20T19:31:07Z
- **Tasks:** 4 (Task 3 auto-approved — autonomous curation override active)
- **Files modified:** 6

## Accomplishments

- Vendored retext-simplify patterns.js at c7686ac (17KB) and plainlanguage.gov at fd76947 (6KB); SOURCES.sha256 manifest computed and verified
- Ran build pipeline against real sources: 336 entries, 47516 bytes, byte-deterministic (SHA a3357d94...)
- Curated all 5 judgment-flagged entries into overrides.toml; zero `# JUDGMENT:` comments remain
- 32/32 unittest suite green; NFC invariant + TOML parseable + header format all confirmed

## Task Commits

1. **Task 1: Vendor sources + SOURCES.sha256** — `8ec3d7d` (chore)
2. **Task 2: Empty overrides + pre-curation TOML** — `b69e582` (chore)
3. **Task 3: Curate overrides — 5 judgment flags resolved** — `7f08874` (chore)
4. **Task 4: Final invariant sweep** — `71fff5d` (chore)

## Files Created/Modified

- `harper-bridge/scripts/sources/retext-simplify-c7686ac.js` — vendored retext-simplify patterns.js at pinned commit (17044 bytes)
- `harper-bridge/scripts/sources/plainlanguage-fd76947.md` — vendored plainlanguage.gov word list at pinned commit (6204 bytes)
- `harper-bridge/scripts/sources/SOURCES.sha256` — sha256sum-format integrity manifest; verifiable via `shasum -a 256 -c`
- `harper-bridge/scripts/overrides.toml` — curated overrides for 5 Rule-2 judgment entries; severity restored; notes added
- `harper-bridge/data/wordy_phrases.toml` — committed generated dataset: 336 entries, 47516 bytes, zero JUDGMENT comments
- `harper-bridge/scripts/build_wordy_phrases.py` — minor fix: `_discover_source_shas` regex now accepts `.js` extension (was `.json` only)

## Curation Decisions Table (Task 3 Auto-Pass)

All 5 judgment-flagged entries triggered D-11 Rule 2 (replacement >3 tokens shorter than phrase). None were dropped — all are textbook verbose-filler phrases with unambiguous concise replacements.

| id | Rule | Op | Rationale |
|----|------|----|-----------|
| `because of the fact that` | Rule 2 (5→1 tokens) | `severity = "medium"` | Classic filler; single source; clear improvement. Keep. |
| `due to the fact that` | Rule 2 (5→1 tokens) | `severity = "high"` | Both sources confirm; severity downgrade reversed. |
| `in light of the fact that` | Rule 2 (6→1 tokens) | `severity = "medium"` | Classic filler; single source; clear improvement. Keep. |
| `in view of the above` | Rule 2 (5→1 tokens) | `severity = "high"` | Both sources confirm; severity downgrade reversed. |
| `owing to the fact that` | Rule 2 (5→1 tokens) | `severity = "medium"` | Classic filler; single source; clear improvement. Keep. |

Conservative default used: no `drop = true` for any Rule-2 entry because all are genuine clarity wins per anti-fluff philosophy.

## Source Statistics

| Metric | Value |
|--------|-------|
| retext-simplify entries parsed | 313 |
| plainlanguage.gov entries parsed | 243 |
| Overlap (both sources) | 220 |
| retext-only entries | 93 |
| plainlang-only entries | 23 |
| Post-dedup total | 336 |
| Entries with severity=high | — (see TOML) |
| JUDGMENT flags resolved | 5/5 |
| Final TOML size | 47516 bytes |
| Byte-determinism SHA | a3357d949cf5f61798623237de78f6e19b3a6e1c6dfc4832d87289d8db26f888 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_discover_source_shas` regex matched `.json` not `.js`**
- **Found during:** Task 1 (vendoring)
- **Issue:** `build_wordy_phrases.py` line 195 had `r"retext-simplify-([0-9a-f]+)\.json$"` but the plan specifies `.js` extension (matching upstream `lib/patterns.js`). The build pipeline's file-picker on line 217 correctly matches `.js`, but SHA discovery would have emitted `retext_sha = "test"` (fallback) in the header for real runs.
- **Fix:** Regex extended to `r"retext-simplify-([0-9a-f]+)\.(js|json)$"` — accepts both for forwards compatibility.
- **Files modified:** `harper-bridge/scripts/build_wordy_phrases.py`
- **Verification:** Header correctly emits `retext-simplify@c7686ac` after fix.
- **Committed in:** `8ec3d7d` (Task 1 commit)

### Data Finding (not a code bug)

**Entry count 336 vs plan estimate 450-510:**
- Actual source overlap is 220/313 = 70% (research doc estimated ~80-100 = ~25%)
- The real pinned commits happen to share substantially more phrases than estimated
- 336 is the correct real-data count; no pipeline issue
- 47516 bytes is well within the 200KB budget (23% utilization)
- All 32 tests pass; plan success criteria (other than the count estimate) are met

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug in SHA discovery regex), 1 data finding (entry count lower than estimate)
**Impact on plan:** SHA discovery fix necessary for correct TOML header. Entry count difference is a real-data finding — the dataset is valid and all invariants hold.

## Issues Encountered

None beyond the deviations documented above.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundaries introduced. Vendored files are static, offline-only. SHA256 manifest (T-8-01) and size guard (T-8-08) mitigations confirmed active per PLAN threat register.

## Known Stubs

None — all data is real, from vendored upstream sources. No hardcoded empty values or placeholders in generated TOML.

## Next Phase Readiness

- Plan 06 (THIRD_PARTY.md): vendored source provenance (commit SHAs, license) now committed — ready
- Phase 9 (PhraseEntry Rust struct): `harper-bridge/data/wordy_phrases.toml` committed at D-12 schema; struct can be defined against it
- Phase 11 (include_str! wire-up): committed TOML with stable `id` field ready for fixture harness

## Self-Check

Files created/committed:

- `harper-bridge/scripts/sources/retext-simplify-c7686ac.js`: FOUND (17044 bytes)
- `harper-bridge/scripts/sources/plainlanguage-fd76947.md`: FOUND (6204 bytes)
- `harper-bridge/scripts/sources/SOURCES.sha256`: FOUND
- `harper-bridge/scripts/overrides.toml`: FOUND (5 override entries)
- `harper-bridge/data/wordy_phrases.toml`: FOUND (47516 bytes, 336 entries)

Commits:
- 8ec3d7d: FOUND (Task 1)
- b69e582: FOUND (Task 2)
- 7f08874: FOUND (Task 3)
- 71fff5d: FOUND (Task 4)

Zero JUDGMENT comments: CONFIRMED
NFC invariant: CONFIRMED
Byte-determinism: CONFIRMED (SHA a3357d94...)
32/32 tests: GREEN

## Self-Check: PASSED

---
*Phase: 08-dataset-pipeline*
*Completed: 2026-04-20*
