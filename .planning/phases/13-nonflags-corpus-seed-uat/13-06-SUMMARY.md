---
phase: 13-nonflags-corpus-seed-uat
plan: 06
subsystem: docs
tags: [contributing, pull-request-template, nonflags, regression-fixtures, governance]

requires:
  - phase: 13-nonflags-corpus-seed-uat
    provides: Empty nonflags_corpus harness wired with 4 per-category test fns and `harper-bridge/tests/nonflags/<category>.txt` directory layout (Plan 01)
provides:
  - Repo-root CONTRIBUTING.md with `## Adding NonFlags Fixtures` rule and 4-bucket guide
  - `## Build & Test` section codifying canonical xcodebuild + cargo commands
  - `.github/PULL_REQUEST_TEMPLATE.md` with NonFlags fixture checkbox cross-linking the rule
affects: [future-clarity-fp-fixes, contributor-onboarding, pr-review-workflow]

tech-stack:
  added: []
  patterns:
    - "Documentation-first governance: false-positive fixes require regression fixture in same PR (no CI gate yet, deferred)"
    - "PR template anchors checkbox text to a CONTRIBUTING.md heading via GitHub's auto-generated `#adding-nonflags-fixtures` slug"

key-files:
  created:
    - CONTRIBUTING.md
    - .github/PULL_REQUEST_TEMPLATE.md
  modified: []

key-decisions:
  - "Documentation-only enforcement of NonFlags fixture rule — automated CI gate explicitly deferred per CONTEXT"
  - "Build & Test commands cite full rustup-pinned cargo path in CONTRIBUTING.md, plain `cargo` in PR template (matches checkbox brevity)"
  - "All 4 buckets (proper_nouns, quoted_code, domain_terms, retext_issues) documented with one example sentence each to give contributors a copy-paste starting point"

patterns-established:
  - "GSD requirement IDs (CLAR-21) are the only acceptable planning ref in repo-root docs; phase/plan numbers stay in .planning/"
  - "PR template links to CONTRIBUTING.md sections via relative path `../CONTRIBUTING.md#anchor` (template lives in `.github/`)"

requirements-completed: [CLAR-21]

duration: 4min
completed: 2026-04-25
---

# Phase 13 Plan 06: Contributor Docs + NonFlags PR Workflow Summary

**Repo-root CONTRIBUTING.md + .github PR template land the NonFlags fixture rule: every clarity false-positive fix must add a corresponding `harper-bridge/tests/nonflags/<category>.txt` entry in the same PR.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-25T15:13:41Z
- **Completed:** 2026-04-25T15:15:46Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments

- Established repo-root CONTRIBUTING.md (no prior file existed) covering build/test commands and the NonFlags fixture contribution rule with all 4 bucket descriptions plus one example sentence each
- Bootstrapped `.github/` directory and PR template (no prior `.github/` existed) with 8 actionable checkboxes spanning xcodebuild, cargo, NonFlags fixture, GSD ref hygiene, pbxproj wiring, and visual validation
- Cross-linked the two files: PR template checkbox 2 deep-links to `CONTRIBUTING.md#adding-nonflags-fixtures` (GitHub auto-slug); CONTRIBUTING.md "Pull Requests" section points back to the template

## Task Commits

1. **Task 1: Create CONTRIBUTING.md at repo root** — `ff540c2` (docs)
2. **Task 2: Create .github/PULL_REQUEST_TEMPLATE.md** — `b3bb552` (docs)

**Plan metadata:** _(this commit)_

## Files Created/Modified

- `CONTRIBUTING.md` — New. Repo-root contribution guide. H1 "Contributing to OpenGram" + intro citing CLAUDE.md; H2 "Build & Test" with 3 fenced commands (xcodebuild build, xcodebuild test, cargo test) and pbxproj/Swift Testing notes; H2 "Adding NonFlags Fixtures" with 4 bucket bullets, format paragraph, `Requirement: CLAR-21.` footer; H2 "Pull Requests" linking the template.
- `.github/PULL_REQUEST_TEMPLATE.md` — New. H2 "Summary" placeholder; H2 "Test Plan" with 3 build/test checkboxes; H2 "Checklist" with 5 items (tests, NonFlags fixture link, GSD ref hygiene, pbxproj wiring, UI visual validation).

## Decisions Made

- **Doc-only enforcement.** No CI workflow added to verify a NonFlags fixture is present in PRs touching `WordyPhrasesLinter`. CONTEXT explicitly defers automated enforcement; the rule lives in CONTRIBUTING.md + PR checklist for now.
- **Bucket examples inline.** Each of the 4 bucket bullets ships with a one-line example sentence. Contributors don't have to read the existing `.txt` files to understand what belongs where.
- **Verbose cargo path in CONTRIBUTING.md, short path in PR template.** The contributing doc uses `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` (matches phase-13 conventions seen across recent commits); the PR template checkbox uses plain `cargo` for readability inside a checkbox line. Both invoke the same target.

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria (file existence, required grep matches, no `Phase 13` literal, ≥4 bucket names, ≥8 checkboxes) verified inline before each commit.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- CLAR-21 governance scaffolding complete. Future clarity false-positive PRs have a documented checklist anchor + concrete bucket guide.
- Phase 13 Plans 02–05 + 07 (corpus seeding, scrape script, UAT) can reference `CONTRIBUTING.md § Adding NonFlags Fixtures` directly from their plan/summary docs without redefining the rule.
- No blockers.

## Self-Check: PASSED

**Files verified:**
- `CONTRIBUTING.md` — FOUND
- `.github/PULL_REQUEST_TEMPLATE.md` — FOUND

**Commits verified:**
- `ff540c2` — FOUND in `git log`
- `b3bb552` — FOUND in `git log`

**Acceptance criteria verified inline before commit:**
- CONTRIBUTING.md: all 8 grep checks pass, 4 buckets present, no `Phase 13` literal
- PR template: all 5 grep checks pass, 8 checkboxes (≥8 required), no `Phase 13` literal

---
*Phase: 13-nonflags-corpus-seed-uat*
*Completed: 2026-04-25*
