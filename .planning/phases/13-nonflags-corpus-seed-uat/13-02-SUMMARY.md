---
phase: 13-nonflags-corpus-seed-uat
plan: 02
subsystem: testing
tags: [clarity, nonflags, regression-corpus, harper, wordy-phrases, fixtures]

requires:
  - phase: 13-nonflags-corpus-seed-uat
    provides: "Empty harness wired in 13-01 (parse_fixture_file + per-category test fns + include_str! linkage)"
provides:
  - "21 hand-curated proper-noun NonFlag fixture sentences"
  - "26 hand-curated quoted-code/path NonFlag fixture sentences"
  - "47-line first milestone toward ≥100-line corpus"
  - "Empirical map of MapPhraseLinter token-boundary behavior under separator types"
affects: [13-03, 13-04, 13-07]

tech-stack:
  added: []
  patterns:
    - "Multi-word wordy phrases hidden via separator-joined identifiers (in_order_to / X-In-Order-To / .in-order-to-modal) — interrupts contiguous-token matching"
    - "Single-word wordy phrases hidden via camelCase opaque Word tokens (subsequentSession, commenceModal, ceaseAndDesist, aforementionedPlugin) — cannot be hidden via underscore/hyphen/slash splitting"
    - "Bare prose words must avoid corpus single-word ban list (function, multiple, request, etc.) — they trigger lints regardless of nearby quoted content"

key-files:
  created: []
  modified:
    - "harper-bridge/tests/nonflags/proper_nouns.txt (21 fixture lines)"
    - "harper-bridge/tests/nonflags/quoted_code.txt (26 fixture lines)"

key-decisions:
  - "Single-word phrases under separator-split (subsequent_to_value → subsequent matched) require camelCase containment, not underscore/hyphen wrapping"
  - "Multi-word phrases tolerate any separator (underscore/hyphen/slash/dot) because contiguous-token match cannot bridge punctuation"
  - "Inflected forms (acquired, demonstrated, released) of single-word ban entries (acquire, demonstrate) do NOT match — MapPhraseLinter requires exact-form token equality"

patterns-established:
  - "Batch-of-5 validation protocol — append, run cargo test, cull/replace failures, advance — proven cost-effective vs bulk-append"
  - "Fixture inclusion rule: separator strategy depends on phrase arity (multi-word → any sep; single-word → camelCase only)"

requirements-completed: [CLAR-21]

duration: 6min
completed: 2026-04-25
---

# Phase 13 Plan 02: NonFlags Corpus Batch 1 Summary

**21 proper-noun + 26 quoted-code hand-curated NonFlag fixtures green; first milestone (47 lines) of ≥100-line CLAR-21 regression corpus locked.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-25T15:22:52Z
- **Completed:** 2026-04-25T15:28:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Seeded `harper-bridge/tests/nonflags/proper_nouns.txt` with 21 zero-lint fixture lines
- Seeded `harper-bridge/tests/nonflags/quoted_code.txt` with 26 zero-lint fixture lines
- All 4 `nonflags_corpus` test fns (`nonflags_proper_nouns`, `nonflags_quoted_code`, `nonflags_domain_terms`, `nonflags_retext_issues`) green
- Empirically mapped MapPhraseLinter token-boundary behavior — informs Plan 13-03 / 13-04 fixture authoring

## Task Commits

1. **Task 1: Seed proper_nouns.txt** — `8924f13` (test)
2. **Task 2: Seed quoted_code.txt** — `6a3ae4b` (test)

## Files Created/Modified

- `harper-bridge/tests/nonflags/proper_nouns.txt` — 21 hand-curated proper-noun NonFlag fixtures
- `harper-bridge/tests/nonflags/quoted_code.txt` — 26 hand-curated quoted-code/path NonFlag fixtures

## Decisions Made

- **Inflected-form safety:** `acquired`, `demonstrated`, `released`, `produces` did NOT trigger lints despite root forms (`acquire`, `demonstrate`) being in the corpus. MapPhraseLinter matches token-exact, not lemma. Future fixtures can freely use past-tense / -ing / -s forms of single-word ban entries.
- **Separator policy:** Multi-word ban phrases (`in order to`, `due to the fact that`) are safely hidden by ANY separator (`_`, `-`, `/`, `.`) since contiguous-token match cannot bridge punctuation. Single-word ban phrases (`subsequent`, `cease`, `commence`) split on every separator and require camelCase containment.
- **Bare prose word risk:** Sentences must NOT contain banned single words in unquoted prose (`function`, `multiple`, `request`, `currently`). Two failed lines triggered on prose words, not on the quoted identifier — easy to miss without batch testing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Fixture replacement] Replaced 6 plan-suggested fixture lines that triggered lints**

- **Found during:** Task 2 batches 1, 2, 3, 5
- **Issue:** Plan-suggested lines used patterns that did not survive Harper tokenization:
  - `` `utilize` `` keyword in prose — backticks do not mask single-word match
  - `at_this_point_in_time()` — phrase is in corpus AND prose contained banned word `function`
  - `subsequent_to_value` — single-word `subsequent` split on `_`
  - `subsequent_session=true` — same single-word split
  - `.commence-modal` — single-word `commence` split on `-`
  - `numerousItems<T>` — possibly camelCase split, plus prose `multiple`
  - `cease_and_desist.sh` — single-word `cease` split on `_`
  - `terminate_the_session.sh` — single-word `terminate` split on `_`
  - `ensure_state_of_being` — single-word `ensure` split on `_`
  - `X-Currently-Status` — single-word `currently` split on `-`
- **Fix:** Replaced with multi-word phrase containers (`/var/log/in_order_to.log`, `IN_THE_EVENT_OF`, `--prior-to-flag`) or camelCase opaque tokens (`subsequentSession`, `commenceModal`, `ceaseAndDesist`, `aforementionedPlugin`); rewrote prose to drop banned words (`request` → `call`, `function` removed)
- **Files modified:** harper-bridge/tests/nonflags/quoted_code.txt
- **Verification:** `cargo test --test nonflags_corpus nonflags_quoted_code` exits 0 with all 26 lines green
- **Committed in:** `6a3ae4b` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 fixture replacement — plan explicitly anticipated cull-and-replace via batch protocol)
**Impact on plan:** No scope change. Plan suggested batch-validation cull-and-replace explicitly; this deviation simply documents which suggested lines failed and the replacement strategy. The retained patterns (camelCase for single-word, separator-joined for multi-word) form a reusable rubric for plans 13-03 / 13-04.

## Issues Encountered

- `cargo` not on default PATH — required `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"` per shell command. Resolved per-invocation; no project-level fix needed.

## Build Validation

- `cargo test --test nonflags_corpus` — 4 passed, 0 failed
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — BUILD SUCCEEDED

## Next Phase Readiness

- Batch 1 milestone (≥45 combined lines) met at 47 lines — Plan 13-03 (domain_terms ≥30 + retext_issues ≥25 → ≥100 final) can begin
- Empirical separator-vs-camelCase rubric documented above guides 13-03 / 13-04 fixture authoring
- No blockers

## Self-Check: PASSED

- proper_nouns.txt exists at expected path: FOUND
- quoted_code.txt exists at expected path: FOUND
- Commit `8924f13`: FOUND
- Commit `6a3ae4b`: FOUND
- Fixture line counts: proper_nouns 21 ≥20, quoted_code 26 ≥25, combined 47 ≥45
- No `Phase` literal in any fixture file: confirmed via `grep -c Phase`

---
*Phase: 13-nonflags-corpus-seed-uat*
*Completed: 2026-04-25*
