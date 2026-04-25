---
phase: 10-matcher-implementation
plan: 01
subsystem: clarity
tags: [rust, harper-bridge, clarity, phrase-entry, corpus, map-phrase-linter]

requires:
  - phase: 09-rust-foundation
    provides: Severity enum, PRIORITY_HIGH/MEDIUM/LOW constants, severity_to_priority/from_priority helpers, MapPhraseLinter spike validation
provides:
  - PhraseEntry struct (phrase, replacement, severity, dialects) at module scope
  - CORPUS const slice with 21 entries (20 universal + 1 American-tagged "forthwith")
  - WordyPhrasesLinter struct + impl Linter at module scope (production wrapper coexists with stub + spike)
affects: [10-02-spike-promotion, 10-03-registration-swap, 10-04-gate-tests, 11-dataset-integration]

tech-stack:
  added: []
  patterns:
    - "Per-entry priority rewrite via Vec<(MapPhraseLinter, u8)> — overrides MapPhraseLinter's hardcoded priority=31"
    - "pub(crate) production surface in clarity.rs for build_lint_group consumption from lib.rs"
    - "Synthetic dialect-tagged corpus entry exercises Option<&'static [Dialect]> filter branch"

key-files:
  created: []
  modified:
    - harper-bridge/src/clarity.rs

key-decisions:
  - "PhraseEntry holds 'static str slices + Option<&'static [Dialect]> — const slice avoids heap until Phase 11 TOML parse"
  - "WordyPhrasesLinter::new takes &[PhraseEntry] — constructor-injection enables Plan 04 gate tests to instantiate with custom corpus"
  - "Production description() returns 'Wordy-phrase clarity linter — flags wordy phrases with simpler replacements per the curated corpus.' (replaces spike's 'Spike: …' string)"

patterns-established:
  - "Production phrase-matcher surface lives at module scope (not nested mod) — pub(crate) visibility for build_lint_group consumption"
  - "Stub + spike + production coexist atomically — registration swap deferred to Plan 03 to keep build green"

requirements-completed: [CLAR-01, CLAR-04, CLAR-15]

duration: ~2min
completed: 2026-04-25
---

# Phase 10 Plan 01: Add PhraseEntry + CORPUS + WordyPhrasesLinter Production Surface Summary

**PhraseEntry struct, 21-entry CORPUS const, and WordyPhrasesLinter wrapper land at module scope in clarity.rs — production surface coexists with spike + stub; build green throughout.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-25T00:58:35Z
- **Completed:** 2026-04-25T01:00:15Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- `PhraseEntry` struct declared at module scope with `Copy + Clone` derives, four fields: `phrase`, `replacement`, `severity`, `dialects: Option<&'static [Dialect]>`
- `CORPUS` const slice with 21 entries (20 universal verbatim from spike + 1 synthetic `forthwith` tagged `Some(&[Dialect::American])`)
- `WordyPhrasesLinter` struct + `impl Linter` at module scope — wraps `Vec<(MapPhraseLinter, u8)>`, rewrites `lint.priority` per entry to bypass MapPhraseLinter's hardcoded `31`
- `WordyPhrasesStubLinter` and `mod spike` intact — Plan 03 deletes them atomically
- `cargo test --lib` 7/7 green (5 baseline + 2 spike) throughout

## Task Commits

1. **Task 1: Add PhraseEntry struct + CORPUS const** — `d46f9eb` (feat)
2. **Task 2: Add WordyPhrasesLinter struct + impl Linter** — `28c579c` (feat)

## Files Created/Modified
- `harper-bridge/src/clarity.rs` — +86 lines: PhraseEntry struct, CORPUS const (21 entries), WordyPhrasesLinter struct + impl Linter, new imports (`harper_core::Dialect`, `harper_core::linting::MapPhraseLinter`)

## Decisions Made
- Followed plan verbatim. Block insertion location (after `severity_from_priority` fn closing brace, before existing `use harper_core::Document;`) preserves stub + spike untouched.
- Reused existing `Lint, LintKind, Linter, Suggestion` import at line 88 (now 88 post-insert) — no duplicate import added.

## Deviations from Plan

### Intermediate dead-code warnings

**1. [Documentation] Plan claim about `pub(crate)` silencing dead-code warning is not strictly correct**
- **Found during:** Task 1 verification
- **Issue:** Plan Test 1 (line 107) asserts `pub(crate)` visibility silences dead-code warnings on `PhraseEntry`/`CORPUS`. Rust dead-code lint still fires on `pub(crate)` items with no internal references.
- **Observed warnings (post-Task-2):** `struct PhraseEntry is never constructed`, `constant CORPUS is never used`, `associated function new is never used`, `unused import: MapPhraseLinter`
- **Resolution:** No code change — plan structure intentionally defers consumption to Plan 03 (which wires `WordyPhrasesLinter::new(CORPUS)` into `build_lint_group` in `lib.rs`). Adding `#[allow(dead_code)]` would just need removal in Plan 03.
- **Build status:** `cargo test --lib` exits 0 (warnings only, no errors). All 7 tests pass.
- **Note:** Plan success criterion "File compiles with no warnings" (line 285) is not satisfied during this intermediate plan — but it will be after Plan 03 wires CORPUS through `build_lint_group`. This is expected given the plan's "zero deletions, zero lib.rs changes" constraint.

---

**Total deviations:** 0 code deviations; 1 documentation note about expected intermediate warnings.
**Impact on plan:** None. Plan executed exactly as specified. Warnings clear after Plan 03 registration swap.

## Issues Encountered
None.

## Next Phase Readiness
- Plan 02 (spike test promotion) can read production `PhraseEntry`/`CORPUS`/`WordyPhrasesLinter` from module scope to drive promoted gate tests
- Plan 03 (atomic registration swap) can wire `WordyPhrasesLinter::new(CORPUS)` into `build_lint_group` and delete `WordyPhrasesStubLinter` + `mod spike` in single commit — production wrapper already proves it compiles
- Plan 04 (new gate tests) has a stable constructor signature `WordyPhrasesLinter::new(&[PhraseEntry])` for fixture-driven tests
- All 21 CORPUS entries verified via grep (`PhraseEntry {` count = 22 = 1 struct def + 21 entries)
- Synthetic `forthwith` entry verified: `Some(&[Dialect::American])` grep count = 1

## Self-Check: PASSED

**Files verified to exist:**
- `harper-bridge/src/clarity.rs` — FOUND (modified)
- `.planning/phases/10-matcher-implementation/10-01-SUMMARY.md` — FOUND (this file)

**Commits verified to exist in git log:**
- `d46f9eb` (Task 1) — FOUND
- `28c579c` (Task 2) — FOUND

**Acceptance criteria final state:**
- `pub(crate) struct PhraseEntry` count: 1 ✓
- `pub(crate) const CORPUS` count: 1 ✓
- `pub(crate) struct WordyPhrasesLinter` count: 1 ✓
- `impl Linter for WordyPhrasesLinter` count: 1 ✓
- `PhraseEntry {` count: 22 (1 struct + 21 entries) ✓
- `forthwith` count: 4 ✓
- `Some(&[Dialect::American])` count: 1 ✓
- `WordyPhrasesStubLinter` count: 4 (stub intact) ✓
- `Spike: MapPhraseLinter` count: 1 (spike intact) ✓
- `PriorityRewritingMapPhraseLinter` count: 5 (spike intact) ✓
- `cargo test --lib`: 7 passed; 0 failed ✓

---
*Phase: 10-matcher-implementation*
*Completed: 2026-04-25*
