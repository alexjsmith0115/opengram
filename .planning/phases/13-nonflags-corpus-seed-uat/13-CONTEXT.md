# Phase 13: NonFlags Corpus Seed + UAT - Context

**Gathered:** 2026-04-25
**Status:** Ready for planning
**Mode:** Smart discuss (3 grey areas user-decided; rest at Claude's Discretion)

<domain>
## Phase Boundary

Seed regression containment for clarity false positives pre-launch and validate the full v1.4 pipeline end-to-end in real macOS apps.

In scope:
- `harper-bridge/tests/nonflags/` directory with ≥100 sentences seeded as plain `.txt` files (one sentence per line) grouped by category — `proper_nouns.txt`, `quoted_code.txt`, `domain_terms.txt`, `retext_issues.txt`. Each line MUST produce zero `WordyPhrasesLinter` lints.
- New Rust integration test `harper-bridge/tests/nonflags_corpus.rs` mirroring `tests/fixture_harness.rs` pattern — iterates every fixture line, asserts zero lints, aggregates failures into one final assert with full per-line failure list.
- Corpus mix: 50 scraped from retext-simplify GitHub issue archive (filter for false-positive labels / discussion threads) + 50 hand-curated (proper-noun phrases, quoted-code snippets, domain-specific terms, idioms wrongly flagged in earlier dev cycles).
- `CONTRIBUTING.md` rule added: any clarity false-positive fix MUST add at least one corresponding `nonflags/` line in the same PR — enforced in PR template + reviewer checklist (no automated hook this phase).
- Manual UAT in Notes.app: hotkey-fire on text with known wordy phrases produces solid-orange clarity underlines; popover header reads "Clarity"; Accept replaces text; Dismiss suppresses.
- Manual UAT in TextEdit: clarity master OFF suppresses all clarity suggestions; opinionated sub-toggle ON surfaces Low-severity entries.
- Verify `.tone` + `.rephrase` LLM path produces zero `.clarity` suggestions (confirms Phase 7 clean-deletion still holds end-to-end). Mechanism: existing `LLMServiceTests` covers the deletion contract; Phase 13 adds an end-to-end smoke check via fixture or manual confirmation in Settings (LLM Provider configured → trigger check → inspect output for absence of `.clarity` source).

Out of scope:
- DMG packaging (no DMG script in repo per Phase 12 research)
- Automated CI runner setup (CONTRIBUTING.md is documentation, not CI tooling)
- New corpus categories beyond the 4 above
- Changes to `WordyPhrasesLinter` matcher logic (pure regression containment — if a fixture fails, fix the matcher in a follow-up phase, not Phase 13)

</domain>

<decisions>
## Implementation Decisions

### Fixture Location + Test Runner (USER-DECIDED)
- **`harper-bridge/tests/nonflags/`** — plain `.txt` files, one sentence per line, blank lines + lines starting with `#` ignored as comments.
- **Rust integration test** at `harper-bridge/tests/nonflags_corpus.rs` mirrors existing `fixture_harness.rs` pattern: load corpus, iterate, assert per-line, aggregate failures into single final `assert_eq!(failures.len(), 0, "{:#?}", failures)`.
- Each fixture file is its own test function (`#[test] fn nonflags_proper_nouns()`, etc.) so Cargo's test runner reports per-category pass/fail.
- Corpus loaded via `include_str!()` macro — no runtime filesystem access, fixtures embed at compile time, identical pattern to existing `wordy_phrases.toml` embedding (Phase 11 precedent).

### Corpus Mix (USER-DECIDED)
- **50 scraped** from retext-simplify GitHub issues:
  - Source: `github.com/retextjs/retext-simplify/issues` — filter `label:false-positive` OR closed issues with `wontfix` + comment evidence of legitimate use.
  - Scrape mechanism: hand-extract sentences (small N — manual is faster than wiring GH API for 50 items). Save provenance comment per file: `# Source: retext-simplify#NNN`.
  - Categorize during extraction into `retext_issues.txt` (mixed) or split into other files if natural fit.
- **50 hand-curated** across 4 buckets:
  - `proper_nouns.txt`: ~12 entries — "Notable persons live in our city.", "Several proper-noun company names contain wordy-phrase substrings."
  - `quoted_code.txt`: ~12 entries — code snippets quoted in prose: `"like \`for the most part\` is a Bash idiom."`, `"`Path/to/file/in your project` is a path."`
  - `domain_terms.txt`: ~13 entries — technical phrases that include wordy-phrase substrings: "The protocol uses a window of opportunity for retransmits.", "RFCs use 'in order to' as a normative term."
  - `retext_issues.txt`: ~13 entries (overflow from scraped + curated edge cases that don't fit other buckets).
- **Total ≥100 lines** across the 4 files. Counting comments + blank lines does NOT count toward the threshold.

### Manual UAT Approach (USER-DECIDED)
- **Claude drives via computer-use MCP.** Same approach as Phase 12 visual checkpoint — Claude launches the dev build, opens Notes.app + TextEdit, types test sentences, triggers Ctrl+Shift+G, captures screenshots, and reports outcomes. User confirms pass/fail at end.
- Visual UAT script (per ROADMAP success criteria 3 + 4):
  1. Notes.app: type "We need to utilize this tool in order to make a decision." → fire Ctrl+Shift+G → expect 2 solid-orange clarity underlines (`utilize`, `in order to`) → click "utilize" → popover header "Clarity" → click Accept → text replaced with "use" → re-fire hotkey → click "in order to" → click Dismiss → underline gone.
  2. TextEdit: open Settings → Clarity tab → master OFF → return to TextEdit → type same sentence → fire hotkey → expect zero clarity underlines (spelling/grammar still surface). → master ON, sub-toggle ON → fire hotkey → expect Low-severity clarity entries surface (any `.severity == .low` `.clarity` lint visible).
  3. LLM smoke: configure any LLM endpoint in Settings → LLM Provider → enable `.tone` and `.rephrase` → trigger check on test sentence → verify popover shows zero `.clarity` source entries from LLM (Phase 7 clean-deletion contract).
- Computer-use access path: bundle ID `com.opengram.app` not registered in `/Applications` — same blocker as Phase 12. UAT will require user to walk through script per Phase 12 pattern (Claude provides the script, user reports results).
- **Fallback if computer-use blocker reappears:** Defer all manual UAT to user-driven script in VERIFICATION.md `human_verification` section. Same `human_needed` route as Phase 12.

### LLM `.clarity` Verification Mechanism (Claude's Discretion)
- Add a Swift Testing case to `OpenGramTests/CheckEngine/LLM*Tests.swift` (find existing LLM tests dir) that:
  1. Mocks an LLM response containing a `.clarity`-style suggestion in the JSON payload.
  2. Asserts `LLMService.parseResponse(...)` (or equivalent) drops the entry — `category != .clarity` for any returned suggestion.
- This formalizes the contract from Phase 7 as a regression test rather than relying solely on visual confirmation.

### CONTRIBUTING.md Rule (Claude's Discretion)
- Add a new section after the existing testing rules: `## Adding NonFlags Fixtures`.
- Body: 2-3 sentences explaining when to add a fixture (any clarity false-positive bugfix), where to add it (`harper-bridge/tests/nonflags/<category>.txt`), and the categorization heuristic.
- PR template (if it exists at `.github/PULL_REQUEST_TEMPLATE.md`) gets a checkbox: `[ ] If fixing a clarity false-positive: added a NonFlags fixture entry covering the regression`. If no PR template exists, create a minimal one.

### Test Wiring Order (Claude's Discretion)
- Wire fixture infrastructure FIRST (empty `nonflags_corpus.rs` test that loads zero fixtures and trivially passes).
- Then add fixture files incrementally — at least 25 lines committed before declaring corpus seeding "started".
- Then full ≥100 corpus.
- Manual UAT runs LAST (after full corpus + LLM regression test land + cargo + xcodebuild green).

### Performance Budget (Claude's Discretion)
- Per existing CLAR-20 perf logging: total test runtime for the new `nonflags_corpus.rs` should stay under 5 seconds for 100 fixtures (each fixture invocation ~50ms ceiling against curated dictionary). If it exceeds 5s, batch-load the linter once outside the iteration loop.

### Claude's Discretion (catch-all)
- Exact fixture sentence wording (subject to honoring the false-positive intent — when in doubt, prefer real-world quotes over invented phrases)
- Comment header format inside each `.txt` file
- Test function naming convention (e.g., `nonflags_proper_nouns_no_lints`)
- LLM mock response JSON structure (mirror existing LLMServiceTests fixtures)
- Category split if a curated sentence fits multiple buckets — pick the most prominent feature
- Whether to add a `nonflags_meta.rs` integration test asserting the corpus is ≥100 lines (fail-fast on accidental fixture deletion)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Rust fixture infra (precedent)
- `harper-bridge/tests/fixture_harness.rs` — aggregate-failure-reporting pattern, `Vec<String>` collection + single final assert
- `harper-bridge/src/clarity/` — `WordyPhrasesLinter`, `get_corpus()`, `Severity` enum
- `harper-bridge/scripts/tests/fixtures/` — existing positive/negative fixture format precedent
- `harper-bridge/Cargo.toml` — Rust integration test convention

### Swift LLM clean-deletion contract (Phase 7)
- `OpenGram/CheckEngine/LLM/` — find existing LLM service files
- Phase 7 SUMMARY in `.planning/phases/07-llm-clarity-clean-deletion/`

### Phase 12 manual UAT precedent
- `.planning/phases/12-settings-ui-severity-filter-acknowledgements/12-VERIFICATION.md` — `human_verification` section format
- Phase 12 used `human_needed` status with 5-state visual checklist; Phase 13 mirrors this for UAT

### Project mandates
- `./CLAUDE.md` — xcodebuild not swift build, Swift Testing for unit tests, no GSD refs in source, computer-use MCP for visual validation, standalone-app contract (no migration shims)
- `./CONTRIBUTING.md` (if exists) OR `./README.md` — find existing contribution guidance
- `./.github/PULL_REQUEST_TEMPLATE.md` (if exists) — find existing PR checklist

### retext-simplify upstream
- `github.com/retextjs/retext-simplify/issues` — false-positive evidence corpus

</canonical_refs>

<specifics>
## Specific Ideas

- Fixture file format: plain `.txt`, one sentence per line, `#` comments allowed for provenance, blank lines ignored
- Test runner: Cargo integration test (`cargo test --test nonflags_corpus`)
- Iteration pattern: include_str! → split lines → filter (non-empty, non-comment) → for each: `linter.lint(line)` → if non-empty lints, push failure with line number + content + lint summary
- Final assert: `assert!(failures.is_empty(), "...")` with multi-line failure dump
- Per-category test functions for clear pass/fail granularity in `cargo test` output
- Manual UAT script per VERIFICATION.md `human_verification` section — 3 scenarios (Notes wordy-phrase flow, TextEdit toggle behavior, LLM .clarity suppression)

</specifics>

<deferred>
## Deferred Ideas

- Automated GitHub Actions runner for nonflags suite — out of scope (CONTRIBUTING.md doc only this phase)
- Automated retext-simplify GH issue scraping pipeline — manual extraction sufficient at N=50
- Pre-commit hook enforcing fixture-add-on-bugfix rule — documentation only
- Snapshot-style fixtures (input + expected lint set) — only zero-lint assertions in scope
- Multi-language corpus (en-GB vs en-US dialect divergence) — single dialect this phase
- DMG-bundled smoke test — packaging out of scope (no DMG script exists)

</deferred>

---

*Phase: 13-nonflags-corpus-seed-uat*
*Context gathered: 2026-04-25 via smart discuss (autonomous mode, 3 user decisions + Claude's Discretion)*
