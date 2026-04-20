---
phase: 07-llm-clarity-clean-deletion
plan: 01
subsystem: docs
tags: [requirements, roadmap, clarity, llm, doc-amendment]

requires:
  - phase: 06-gap-closure-zero-ax-ordering-scope-cleanup
    provides: v1.3 shipped — standalone-app clean-replace contract honored
provides:
  - CLAR-09 silent-drop language canonicalised in REQUIREMENTS.md
  - Phase 7 ROADMAP success criteria 2/3/4 amended to silent-drop + audit-only outcomes (no decoder fallback)
affects: [07-02, 07-03, 07-04, 07-05, 07-06]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "D-04 canonicalised: LLM `.clarity` DTO decode uses existing unknown-rawValue silent-drop — no log, no defense-in-depth code"
  - "D-10 canonicalised: ROADMAP Phase 7 criterion 3 recast from archived-value Codable fallback test to audit-only (no archived LLMConfig/Set<LLMCheckType> path in production)"
  - "ROADMAP Phase 7 criterion 4 recast from conditional launch-time purge to audit-only (ParagraphSuggestionStore in-memory-only actor, purge clause not triggered)"

patterns-established:
  - "Doc-first amendment: spec/contract edits land before code plans cite them — keeps requirement traceability graph honest"

requirements-completed: [CLAR-09, CLAR-10]

duration: 4min
completed: 2026-04-20
---

# Phase 7 Plan 01: Doc Amendments Summary

**REQUIREMENTS.md CLAR-09 sub-bullet strikes `log and drop` → replaced with silent-drop via existing `SuggestionDTO.toModel` unknown-rawValue guard; ROADMAP.md Phase 7 success criteria 2/3/4 recast to silent-drop + in-memory-only-actor audit-only outcomes — no decoder fallback, no conditional purge**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-20T07:50:17Z
- **Completed:** 2026-04-20 (execution time)
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- CLAR-09 amended in REQUIREMENTS.md (D-04): silent-drop language replaces defense-in-depth log
- ROADMAP Phase 7 criterion 2 amended: drop-logged → silently dropped via existing unknown-rawValue guard
- ROADMAP Phase 7 criterion 3 amended (D-10): archived-value Codable fallback test → audit-only, no decoder fallback needed
- ROADMAP Phase 7 criterion 4 amended: conditional launch-time purge → audit confirms in-memory-only actor (no disk I/O)

## Task Commits

Each task committed atomically:

1. **Task 1: Amend REQUIREMENTS.md CLAR-09 sub-bullet (D-04)** — `c0de96c` (docs)
2. **Task 2: Amend ROADMAP.md Phase 7 success criteria 2, 3, 4 (D-10)** — `ed7a51a` (docs)

## Exact Text Diffs Applied

### `.planning/REQUIREMENTS.md` line 40 (CLAR-09 sub-bullet 2)

**Before:**
```
- `LLMStyleSuggestion` decode failure on a `.clarity` category is the filter (supersedes spec §7.3 L-03 defensive filter; log and drop at DTO → model mapping).
```

**After:**
```
- `LLMStyleSuggestion` decode failure on a `.clarity` category is the filter (supersedes spec §7.3 L-03 defensive filter; silently dropped via existing unknown-rawValue guard in `SuggestionDTO.toModel` — no log).
```

### `.planning/ROADMAP.md` Phase 7 Success Criteria 2, 3, 4

**Criterion 2 — Before:**
```
LLM batch responses carrying `"category":"clarity"` are drop-logged at DTO decode and never reach the overlay
```

**Criterion 2 — After:**
```
LLM batch responses carrying `"category":"clarity"` are silently dropped at DTO decode via the existing unknown-rawValue guard and never reach the overlay
```

**Criterion 3 — Before:**
```
`@AppStorage`-backed `LLMConfig` Codable path survives an archived value referencing the deleted enum case (fallback `init(from:)` verified in unit test)
```

**Criterion 3 — After:**
```
Audit documents that no archived `LLMConfig`/`Set<LLMCheckType>` path exists in production; `ConfigManager` reads individual bool keys, never a serialised `Set<LLMCheckType>`; no decoder fallback needed.
```

**Criterion 4 — Before:**
```
`ParagraphSuggestionStore` persistence audited — if entries persist across launches, a launch-time purge removes any `category == .clarity` rows before first render
```

**Criterion 4 — After:**
```
`ParagraphSuggestionStore` audit confirms in-memory-only actor (no disk I/O); CLAR-10's conditional purge clause not triggered; audit artifact is one-line code comment at actor declaration.
```

Criteria 1 and 5 untouched.

## Files Created/Modified

- `.planning/REQUIREMENTS.md` — CLAR-09 sub-bullet 2 amended (silent-drop)
- `.planning/ROADMAP.md` — Phase 7 success criteria 2, 3, 4 amended (silent-drop + audit-only)

## Decisions Made

None during execution — plan applied D-04 + D-10 verbatim from 07-CONTEXT.md.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Commits `.planning/` → initial `git add` rejected by `.gitignore` (repo untracked `.planning/` in commit `5ebddf6`). Resolved by using `git add -f`. Both task commits show `create mode 100644` because `.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md` were untracked prior. Force-add is correct path per plan-author's intent — GSD writes these doc files as part of plan execution.
- Acceptance-criterion string `clean replace commit` (on ROADMAP criterion 1) does not appear in ROADMAP.md; actual criterion 1 text uses "deletion commit". Criterion 1 content visually confirmed untouched by diff. Plan's acceptance-criterion string appears to be a typo/paraphrase — not a blocker.

## User Setup Required

None.

## Next Phase Readiness

- CLAR-09 amended text (silent-drop) lands before plan 07-05 adds D-05 regression test asserting silent-drop behavior
- ROADMAP Phase 7 criteria 3 + 4 amended text lands before plans 07-04 (ConfigManager) + 07-03 (ParagraphSuggestionStore audit comment) cite them
- Downstream plans 02-06 can now proceed with traceability to canonical requirement + success-criteria text

## Self-Check: PASSED

- Task 1 acceptance criteria:
  - `log and drop at DTO` → 0 matches ✓
  - `silently dropped via existing unknown-rawValue guard in \`SuggestionDTO.toModel\`` → 1 match ✓
  - `LLMPrompts.systemPrompt statically strips` → 1 match (line 39 verified via Read) ✓
- Task 2 acceptance criteria:
  - `drop-logged at DTO decode` → 0 matches ✓
  - `fallback init(from:) verified in unit test` → 0 matches ✓
  - `launch-time purge removes any` → 0 matches ✓
  - `silently dropped at DTO decode via the existing unknown-rawValue guard` → 1 match ✓
  - `no decoder fallback needed` → 1 match ✓
  - `in-memory-only actor (no disk I/O)` → 1 match ✓
- Commits `c0de96c` + `ed7a51a` present in `git log`
- Only `.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md` modified — no code files touched

---
*Phase: 07-llm-clarity-clean-deletion*
*Completed: 2026-04-20*
