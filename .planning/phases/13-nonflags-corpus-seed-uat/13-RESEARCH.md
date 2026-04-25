# Phase 13: NonFlags Corpus Seed + UAT — Research

**Researched:** 2026-04-25
**Domain:** Rust integration test corpus + macOS visual UAT + CONTRIBUTING/PR template scaffolding
**Confidence:** HIGH (every claim verified against codebase or live web fetch; one MEDIUM finding flagged inline)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Fixture Location + Test Runner (USER-DECIDED):**
- `harper-bridge/tests/nonflags/` — plain `.txt` files, one sentence per line, blank lines + lines starting with `#` ignored as comments.
- Rust integration test at `harper-bridge/tests/nonflags_corpus.rs` mirrors existing `fixture_harness.rs` pattern: load corpus, iterate, assert per-line, aggregate failures into single final `assert_eq!(failures.len(), 0, "{:#?}", failures)`.
- Each fixture file is its own test function (`#[test] fn nonflags_proper_nouns()`, etc.) so Cargo's test runner reports per-category pass/fail.
- Corpus loaded via `include_str!()` macro — no runtime filesystem access, fixtures embed at compile time, identical pattern to existing `wordy_phrases.toml` embedding (Phase 11 precedent).

**Corpus Mix (USER-DECIDED):**
- 50 scraped from retext-simplify GitHub issues (`label:false-positive` OR `wontfix` + comment evidence).
- 50 hand-curated across 4 buckets: `proper_nouns.txt` (~12), `quoted_code.txt` (~12), `domain_terms.txt` (~13), `retext_issues.txt` (~13).
- Total ≥100 lines. Comments + blank lines do NOT count toward threshold.

**Manual UAT Approach (USER-DECIDED):**
- Claude drives via computer-use MCP. Same approach as Phase 12 visual checkpoint.
- 3 scenarios: Notes wordy-phrase flow + TextEdit toggle behavior + LLM `.clarity` suppression.
- Fallback: defer to user-driven script in VERIFICATION.md `human_verification` section per Phase 12 pattern.

### Claude's Discretion
- LLM `.clarity` verification mechanism (Swift Testing case in `OpenGramTests/CheckEngine/LLM*Tests.swift`).
- CONTRIBUTING.md rule scaffolding + PR template scaffolding (neither file exists).
- Test wiring order: empty test first → 25 lines → ≥100.
- Performance budget: <5s for 100 fixtures; batch-load linter once if exceeded.
- Catch-all: fixture wording, comment header format, test fn naming, mock JSON shape, category split, optional `nonflags_meta.rs` count assertion.

### Deferred Ideas (OUT OF SCOPE)
- Automated GitHub Actions runner for nonflags suite (CONTRIBUTING.md doc only this phase).
- Automated retext-simplify GH issue scraping pipeline (manual extraction at N=50).
- Pre-commit hook enforcing fixture-add-on-bugfix rule (documentation only).
- Snapshot-style fixtures (input + expected lint set) — only zero-lint assertions in scope.
- Multi-language corpus (en-GB vs en-US dialect divergence).
- DMG-bundled smoke test.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLAR-21 | NonFlags regression corpus — `NonFlagsFixtures/` seeded with ≥100 sentences that must never flag: mid-word substrings, legitimate uses of flagged phrases, proper nouns containing flagged tokens, quoted/code snippets. CONTRIBUTING rule: every clarity bug report adds a NonFlags entry before the fix lands. | §Existing Code Map (fixture_harness.rs precedent), §Validation Architecture (per-line zero-lint assertion + per-category test fn), §Concrete Patterns (include_str + filter pattern), §Manual UAT Script |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

| Constraint | Source | Impact on Phase 13 |
|------------|--------|--------------------|
| Always validate with `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` | CLAUDE.md §Build Validation | LLM mock test must compile + pass via xcodebuild, not just `swift test` |
| New `.swift` files MUST be wired into `project.pbxproj` (Sources phase for `.swift`, Resources for assets) | CLAUDE.md §Build Validation | Any new Swift test file added to OpenGramTests group needs pbxproj entry |
| Use Swift Testing (`@Test` / `#expect`) for new unit tests, not XCTest | CLAUDE.md §Testing | LLM `.clarity` mock test = `@Test` + `#expect` per existing `LLMResponseDTOTests.swift` style |
| Use `mcp__computer-use__*` for visual validation after UI-affecting work | CLAUDE.md §Manual Validation | UAT executes via computer-use MCP; Phase 12 hit `/Applications`-only blocker — fallback in place |
| No GSD refs in source code (no "Phase N", "Plan N" — preserve only requirement IDs like CLAR-21) | feedback_no_gsd_refs_in_source | Test fn doc-comments may cite `CLAR-21` but not "Phase 13" |
| Standalone app — no feature flags, no migration shims, no deprecation cycles | CLAUDE.md §Standalone Application | Corpus seeding is a pure additive change; no rollout gate |
| Use Serena MCP (`mcp__plugin_serena_serena__*`) for code navigation | CLAUDE.md §Tooling | Apply when exploring `LLMService.swift` for the mock test integration point |

---

## Summary

Phase 13 is regression containment + UAT, not new feature work. Three workstreams:

1. **Rust corpus harness** (`harper-bridge/tests/nonflags_corpus.rs` + `harper-bridge/tests/nonflags/*.txt`): mirrors `fixture_harness.rs` aggregate-failure pattern; 4 per-category test functions; `include_str!` embeds fixtures at compile time; assertion is `linter.lint(doc).is_empty()` per non-comment non-blank line.
2. **Swift LLM `.clarity` regression test** (`OpenGramTests/CheckEngine/LLMResponseDTOTests.swift` already has `clarityCategoryDroppedPostDeletion_CLAR09` at line 96 — Phase 13 must verify this exists and decide whether a duplicate at the `LLMService.parseJSONContent` layer adds coverage). The CONTEXT spec calls for adding a test; investigation shows the DTO-layer test already locks the contract — a `LLMService`-layer test would re-verify the same drop one layer up.
3. **Manual UAT** via computer-use MCP, mirroring Phase 12 `human_verification` YAML format. Phase 12 hit the DerivedData-not-in-`/Applications` blocker; Phase 13 will likely hit the same — plan accordingly.

**Primary recommendation:** Wire empty `nonflags_corpus.rs` first (4 stub test fns calling `include_str!` on empty placeholder files), then add CONTRIBUTING.md + PR template (both files do NOT exist — must be created), then seed corpus incrementally (25 → ≥100), then add LLM regression test at `LLMService.parseJSONContent` layer if it adds coverage beyond existing DTO test, then UAT last.

**Critical reality check on corpus mix:** retext-simplify upstream has only **4 total issues**, all closed (#1, #3, #11, #13). The CONTEXT directive of "50 scraped from retext-simplify GitHub issues" is **not viable at N=50** — only #13 documents a false positive. Phase 13 plan must adjust: either widen scrape source (retextjs/retext parent repo + write-good + alex.js issue trackers) OR shift the 50-50 split to favor hand-curated. Recommend: 10 scraped (issue #13 plus extracted phrases from related discussion) + 90 hand-curated, distributed across the 4 buckets.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| NonFlags fixture loading + iteration | Rust integration tests | — | Pure Rust; no FFI crossing needed |
| Per-category zero-lint assertion | Rust integration tests | — | `WordyPhrasesLinter::new_from_parsed(get_corpus())` exposed via `harper_bridge::clarity` |
| LLM `.clarity` JSON drop regression | Swift Testing | — | DTO drop already at `SuggestionDTO.toModel`; verification one layer up |
| Visual UAT (Notes/TextEdit/LLM) | macOS apps + computer-use MCP | user manual fallback | Cross-app AX surface; Phase 12 hit `/Applications`-only blocker |
| CONTRIBUTING.md rule | Repo root markdown | — | Documentation only; no CI enforcement |
| PR template checkbox | `.github/PULL_REQUEST_TEMPLATE.md` | — | Documentation only; reviewer-enforced |

## Existing Code Map

### Rust fixture harness precedent

| Path | Signature / Pattern | Use |
|------|---------------------|-----|
| `harper-bridge/tests/fixture_harness.rs:14` | `use harper_bridge::clarity::{get_corpus, ParsedPhraseEntry, Severity, WordyPhrasesLinter};` | Exact import surface — reuse verbatim |
| `harper-bridge/tests/fixture_harness.rs:21-25` | `fn make_merged_dict() -> Arc<MergedDictionary>` builds `FstDictionary::curated()` | Copy verbatim — needed to construct `Document` |
| `harper-bridge/tests/fixture_harness.rs:51-60` | `fn run_positive_check(entry, text) -> bool` constructs linter + Document + filters lints | Pattern to mirror for `run_zero_lint_check(text) -> Vec<String>` returning lint summaries |
| `harper-bridge/tests/fixture_harness.rs:108-146` | Aggregate-failure pattern: `let mut failures: Vec<String> = Vec::new();` ... `failures.push(format!(...))` ... `assert!(failures.is_empty(), "...{}", failures.join("\n"))` | EXACT pattern to mirror in `nonflags_corpus.rs` |
| `harper-bridge/src/clarity.rs:97-101` | `pub fn get_corpus() -> &'static [ParsedPhraseEntry]` — `OnceLock` cached `include_str!` parse | Single corpus call site; safe to invoke from any test fn |
| `harper-bridge/src/clarity.rs:108-130` | `pub struct WordyPhrasesLinter { inner: Vec<(MapPhraseLinter, u8)> }` + `pub fn new_from_parsed(entries: &[ParsedPhraseEntry]) -> Self` | Construct linter once with full corpus per test fn |
| `harper-bridge/src/clarity.rs:132-147` | `impl Linter for WordyPhrasesLinter { fn lint(&mut self, document: &Document) -> Vec<Lint> }` | Lint invocation surface |
| `harper-bridge/Cargo.toml:11-14` | `harper-core = "=2.0.0"`, `serde = "=1.0.228"`, `toml = "=0.9.12"` exact-pinned | No new deps needed for Phase 13 |
| `harper-bridge/tests/snapshot_diff.rs` | Existing | No relation — informational |
| `harper-bridge/tests/perf_measurements.rs` | Existing | Reference for `eprintln!` instrumentation if perf budget approached |

### LLM service location

| Path | Use |
|------|-----|
| `OpenGram/CheckEngine/LLM/LLMService.swift` | LLM HTTP + parse pipeline (entry point: `parseJSONContent(_:paragraph:)`) |
| `OpenGram/CheckEngine/LLM/LLMResponseDTO.swift` | `SuggestionDTO.toModel` does the unknown-rawValue silent-drop (CLAR-09 mechanism) |
| `OpenGramTests/LLMServiceTests.swift` (449 lines) | Existing `LLMService.parseJSONContent` tests; `.clarity` not yet covered here |
| `OpenGramTests/CheckEngine/LLMResponseDTOTests.swift:96-105` | `clarityCategoryDroppedPostDeletion_CLAR09` test ALREADY EXISTS — locks DTO-level drop |

**Coverage gap analysis:** Existing `clarityCategoryDroppedPostDeletion_CLAR09` covers `LLMResponseDTO.toModels` directly. CONTEXT calls for adding a test that mocks `LLMService.parseResponse(...)`. The Phase 7 SUMMARY confirms `parseJSONContent` calls into the same DTO layer. A duplicate test at the `LLMService` layer DOES add value: it verifies the integration path (markdown-fence stripping + preamble stripping + DTO drop together) end-to-end, not just the DTO. Recommend: add `LLMServiceTests.parseClarityCategoryDropped_CLAR21` that feeds a fenced JSON containing `{"category": "clarity", ...}` and asserts `parseJSONContent` returns `[]`.

### CONTRIBUTING.md state

**File does NOT exist.** Confirmed via `ls -la /Users/alex/Dev/opengram/CONTRIBUTING.md` → "No such file or directory". Phase 13 must create it from scratch — minimal scaffold (license/contribution preamble + the new "Adding NonFlags Fixtures" section).

### PR template state

**File does NOT exist.** `.github/` directory does NOT exist either. Confirmed via `ls -la /Users/alex/Dev/opengram/.github/` → "No such file or directory". Phase 13 must create the directory + minimal `PULL_REQUEST_TEMPLATE.md` with the NonFlags checkbox per CONTEXT decision.

### Project test harness

| Path | Use |
|------|-----|
| `OpenGram.xcodeproj/project.pbxproj` | Any new `LLMServiceTests` test method does NOT need a new file — augment existing file. No pbxproj edit needed for new test methods. |
| `harper-bridge/Cargo.toml` | New integration test `tests/nonflags_corpus.rs` auto-discovered by Cargo (no `[[test]]` block needed — convention) |

### Cargo / Rust toolchain

| Verified | Detail |
|----------|--------|
| Cargo binary path | `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` (NOT on default `$PATH` — confirmed by `command -v cargo` returning 127) |
| Test invocation | `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo test --test nonflags_corpus -p harper-bridge --manifest-path /Users/alex/Dev/opengram/harper-bridge/Cargo.toml` |
| Existing test runs | `cargo test --test fixture_harness` runs 7 fns (3 meta, 2 positive, 1 negative_meta, 1 negative); pattern proven |

## Validation Architecture

> Required per workflow.nyquist_validation = true (config.json:19).

### Test Framework

| Property | Value |
|----------|-------|
| Rust framework | built-in `#[test]` + `cargo test` |
| Rust config | `harper-bridge/Cargo.toml` (no special config — convention-based test discovery) |
| Swift framework | Swift Testing (`@Test` + `#expect`) |
| Swift config | `OpenGram.xcodeproj/project.pbxproj` test target wiring |
| Quick run command (Rust) | `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo test --test nonflags_corpus --manifest-path /Users/alex/Dev/opengram/harper-bridge/Cargo.toml` |
| Quick run command (Swift) | `xcodebuild -project /Users/alex/Dev/opengram/OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS' -only-testing:OpenGramTests/LLMServiceTests` |
| Full suite command (Rust) | `cargo test --manifest-path /Users/alex/Dev/opengram/harper-bridge/Cargo.toml` |
| Full suite command (Swift) | `xcodebuild -project /Users/alex/Dev/opengram/OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| CLAR-21 | Each line in `nonflags/proper_nouns.txt` produces zero `WordyPhrasesLinter` lints | unit (Rust integration) | `cargo test --test nonflags_corpus nonflags_proper_nouns` | ❌ Wave 0 |
| CLAR-21 | Each line in `nonflags/quoted_code.txt` produces zero lints | unit | `cargo test --test nonflags_corpus nonflags_quoted_code` | ❌ Wave 0 |
| CLAR-21 | Each line in `nonflags/domain_terms.txt` produces zero lints | unit | `cargo test --test nonflags_corpus nonflags_domain_terms` | ❌ Wave 0 |
| CLAR-21 | Each line in `nonflags/retext_issues.txt` produces zero lints | unit | `cargo test --test nonflags_corpus nonflags_retext_issues` | ❌ Wave 0 |
| CLAR-21 | Total non-comment non-blank line count across 4 files ≥ 100 | unit | `cargo test --test nonflags_corpus nonflags_meta_corpus_size` | ❌ Wave 0 (optional per CONTEXT discretion) |
| CLAR-21 | LLM JSON containing `{"category":"clarity",...}` drops to empty after `LLMService.parseJSONContent` | unit (Swift) | `xcodebuild ... -only-testing:OpenGramTests/LLMServiceTests/parseClarityCategoryDropped_CLAR21` | ❌ Wave 0 (DTO-layer equivalent already exists at `LLMResponseDTOTests.swift:96`) |
| CLAR-21 (UAT-1) | Notes.app: hotkey on "We need to utilize this tool in order to make a decision." → 2 solid-orange clarity underlines | manual-only | n/a — computer-use MCP or user UAT | n/a |
| CLAR-21 (UAT-2) | TextEdit: master OFF suppresses clarity; sub-toggle ON surfaces Low-severity | manual-only | n/a — computer-use MCP or user UAT | n/a |
| CLAR-21 (UAT-3) | LLM `.tone`+`.rephrase` enabled → zero `.clarity` source entries surface end-to-end | manual-only (or fixture-mocked smoke) | n/a — computer-use MCP or user UAT | n/a |

**Justification for manual-only UAT-1/2/3:** Cross-app AX surface (Notes.app + TextEdit) cannot be driven by automated Swift tests. computer-use MCP is the only automation path; per Phase 12 SUMMARY (12-03-SUMMARY.md:119) the MCP `installed-apps` resolver only enumerates `/Applications` and cannot reach a DerivedData-built `.app` — likely fallback to user-driven script.

### Sampling Rate

- **Per task commit:** `cargo test --test nonflags_corpus` (Rust harness; <5s budget per CONTEXT)
- **Per category fixture batch:** `cargo test --test nonflags_corpus nonflags_<category>` (single fn run after adding lines to that file)
- **Per Swift test commit:** `xcodebuild ... -only-testing:OpenGramTests/LLMServiceTests`
- **Per phase merge:** Full Rust suite (`cargo test`) + full Swift suite (`xcodebuild ... test`) green
- **Phase gate:** Full suite green + UAT 3-scenario script approved (computer-use OR user reply)

### Wave 0 Gaps

- [ ] `harper-bridge/tests/nonflags_corpus.rs` — covers CLAR-21 zero-lint assertion across 4 categories
- [ ] `harper-bridge/tests/nonflags/proper_nouns.txt` — empty placeholder during scaffold; populated incrementally
- [ ] `harper-bridge/tests/nonflags/quoted_code.txt` — empty placeholder
- [ ] `harper-bridge/tests/nonflags/domain_terms.txt` — empty placeholder
- [ ] `harper-bridge/tests/nonflags/retext_issues.txt` — empty placeholder
- [ ] `OpenGramTests/LLMServiceTests.swift` — augment with `parseClarityCategoryDropped_CLAR21` test method (no new file; appends to existing)
- [ ] `CONTRIBUTING.md` (repo root) — create with `## Adding NonFlags Fixtures` section
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` — create directory + minimal template with NonFlags checkbox
- [ ] (optional, CONTEXT discretion) `harper-bridge/tests/nonflags_corpus.rs::nonflags_meta_corpus_size` — fail-fast on accidental fixture deletion (≥100 line assertion)

Framework install: NOT NEEDED (Rust toolchain present at `~/.rustup/...`; Swift Testing built into Xcode 16+).

## Concrete Patterns to Copy

### Pattern 1: Aggregate-failure assertion (cite verbatim from fixture_harness.rs:108-146)

```rust
#[test]
fn nonflags_proper_nouns() {
    let lines = parse_fixture_file(include_str!("nonflags/proper_nouns.txt"));
    let merged = make_merged_dict();
    let mut linter = WordyPhrasesLinter::new_from_parsed(get_corpus());
    let mut failures: Vec<String> = Vec::new();

    for (line_no, sentence) in lines {
        let doc = Document::new(&sentence, &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);
        if !lints.is_empty() {
            let summaries: Vec<String> = lints
                .iter()
                .map(|l| format!("{:?}", primary_replacement(l)))
                .collect();
            failures.push(format!(
                "L{}: '{}' produced {} lint(s): {}",
                line_no, sentence, lints.len(), summaries.join(", ")
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "nonflags/proper_nouns.txt — {} fixture(s) wrongly flagged:\n{}",
        failures.len(),
        failures.join("\n")
    );
}
```

### Pattern 2: Comment + blank-line filter

```rust
fn parse_fixture_file(raw: &str) -> Vec<(usize, String)> {
    raw.lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                None
            } else {
                Some((i + 1, trimmed.to_string()))
            }
        })
        .collect()
}
```

### Pattern 3: Linter constructed once outside the loop (perf budget)

Per CONTEXT performance budget (<5s for 100 fixtures): construct `WordyPhrasesLinter::new_from_parsed(get_corpus())` ONCE per test fn, reuse across all lines in that file. The 338-entry corpus parse is amortized via `OnceLock` (clarity.rs:95). Document construction is per-line and necessary (parser state).

### Pattern 4: Swift LLM `.clarity` regression at LLMService layer

```swift
@Test("drops clarity-category suggestions per CLAR-21 end-to-end")
func parseClarityCategoryDropped_CLAR21() async {
    let service = LLMService()
    let json = """
    ```json
    {"suggestions": [
      {"category": "clarity", "revised_text": "X", "explanation": "E", "confidence": 9},
      {"category": "tone", "revised_text": "Y", "explanation": "E2", "confidence": 8}
    ]}
    ```
    """
    let suggestions = await service.parseJSONContent(json, paragraph: "Original text.")
    #expect(suggestions.count == 1)
    #expect(suggestions[0].category == .tone)
}
```

Mirrors existing fenced-JSON test at `LLMServiceTests.swift:46-56` and unknown-category drop at `LLMResponseDTOTests.swift:81-94`.

### Pattern 5: CONTRIBUTING.md "Adding NonFlags Fixtures" section template

```markdown
## Adding NonFlags Fixtures

Any clarity false-positive fix (a `WordyPhrasesLinter` matcher edit that removes
a wrongful flag) MUST add at least one corresponding fixture line to
`harper-bridge/tests/nonflags/<category>.txt` in the same PR. This locks the
fix as a regression test.

Categorize the fixture into the most prominent bucket:
- `proper_nouns.txt` — sentences where a proper noun contains a flagged substring
  (e.g., "Notable Networks Inc. shipped a new feature.")
- `quoted_code.txt` — flagged phrase appears inside backticks/quotes representing
  code, paths, or shell idioms (e.g., `` `for the most part` is a Bash idiom. ``)
- `domain_terms.txt` — technical / legal / RFC normative usage (e.g., "RFCs use
  'in order to' as a normative term.")
- `retext_issues.txt` — overflow + scraped from upstream retext-simplify issues

The `nonflags_corpus.rs` Rust integration test runs on every PR and fails if any
fixture line produces a `WordyPhrasesLinter` lint. CLAR-21.
```

### Pattern 6: PR template checkbox

```markdown
## Checklist
- [ ] Tests added / updated for the change
- [ ] If fixing a clarity false-positive: added a NonFlags fixture entry
      covering the regression in `harper-bridge/tests/nonflags/<category>.txt`
- [ ] Build green: `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build`
- [ ] All tests green: `xcodebuild ... test` + `cargo test`
```

## Pitfalls

### Pitfall 1: Rust integration test path resolution
**What goes wrong:** `include_str!("nonflags/proper_nouns.txt")` resolves relative to the SOURCE file (`tests/nonflags_corpus.rs`), not the workspace root. Mistaking it for `harper-bridge/tests/nonflags/...` or `data/nonflags/...` produces compile-time `couldn't find file` errors.
**Why it happens:** `include_str!` semantics differ from runtime `fs::read_to_string` (workspace-relative).
**How to avoid:** Place fixtures at `harper-bridge/tests/nonflags/<file>.txt`; reference as `include_str!("nonflags/proper_nouns.txt")` from `harper-bridge/tests/nonflags_corpus.rs`. Verified pattern at `clarity.rs:99` `include_str!("../data/wordy_phrases.toml")`.
**Warning signs:** `error[E0463]: couldn't find file` at build time, or `cargo test` reports "test file not found".

### Pitfall 2: include_str! vs runtime fs::read_to_string
**What goes wrong:** Switching to `std::fs::read_to_string` for fixture loading fails on `cargo test` invocations from non-workspace-root cwd, breaks reproducibility, and adds a runtime I/O dependency that violates CLAR-N3 (zero new I/O).
**Why it happens:** Convenience — runtime read seems easier for adding fixtures without recompiling.
**How to avoid:** ALWAYS use `include_str!`. Recompile cost on fixture add is negligible (text file, not a code change). Identical pattern to existing `wordy_phrases.toml` embedding.
**Warning signs:** `cargo test` passes locally but fails in CI when cwd differs; `std::fs::*` import in `tests/nonflags_corpus.rs`.

### Pitfall 3: Dictionary setup ergonomics
**What goes wrong:** Forgetting to construct `MergedDictionary` with `FstDictionary::curated()` produces a `Document` whose tokenization differs from production (no spell awareness), causing fixture lints to fire or not fire spuriously.
**Why it happens:** `Document::new(text, &PlainEnglish, dict)` requires a real dictionary; using a stub `MergedDictionary::new()` (empty) silently changes lint behavior.
**How to avoid:** Copy `make_merged_dict()` verbatim from `fixture_harness.rs:21-25`. Single helper, single call per test fn.
**Warning signs:** Fixture line passes locally but flags in production check, or vice versa.

### Pitfall 4: Linter cache invalidation across tests
**What goes wrong:** `WordyPhrasesLinter` is `&mut self` for `lint(&mut self, ...)` — sharing a `static` linter across test fns produces parallel-test data races.
**Why it happens:** Performance temptation — "construct once, reuse globally".
**How to avoid:** Construct `WordyPhrasesLinter::new_from_parsed(get_corpus())` ONCE PER TEST FN (not globally). The corpus itself (`get_corpus()`) is cached via `OnceLock` (clarity.rs:95) so the actual parse runs once across all tests in the binary.
**Warning signs:** `cargo test` flakes with random failures only when run in parallel (`--test-threads=8`).

### Pitfall 5: LLM test mocking — hitting the network
**What goes wrong:** `LLMService.parseJSONContent` is a pure parse — does NOT hit network. But `LLMService.analyze(...)` DOES. Confusing the two writes a test that requires `URLSession` mocking (verified at `LLMServiceTests.swift:96-120` with `HangingURLProtocol`).
**Why it happens:** Looking at the public surface (`analyze`) vs the parse hook (`parseJSONContent`).
**How to avoid:** For CLAR-21, test `parseJSONContent(_:paragraph:)` directly — pure-input function, no mocks needed. Do NOT touch `analyze` for this test.
**Warning signs:** Test imports `URLProtocol`, `URLSessionConfiguration`, or `HangingURLProtocol` — wrong layer.

### Pitfall 6: Comment line accidentally counted as fixture
**What goes wrong:** A line `# Source: retext-simplify#13` is iterated as a sentence, fed to `linter.lint`, and either passes (because `#` is mid-token) or fails spuriously (because the URL contains a flagged substring).
**Why it happens:** Forgetting the comment-filter step.
**How to avoid:** Apply `parse_fixture_file` filter (see Pattern 2) — `trimmed.starts_with('#')` AND `trimmed.is_empty()` filters before iteration. Document the filter in the harness file header.
**Warning signs:** Failure messages reference `# Source: ...` line content.

### Pitfall 7: Phase 12 computer-use blocker recurs
**What goes wrong:** UAT plan calls for computer-use MCP to drive Notes/TextEdit + observe OpenGram overlay; MCP `installed-apps` resolver only enumerates `/Applications`; OpenGram dev build lives in DerivedData.
**Why it happens:** Phase 12 hit this exact issue; documented in `12-03-SUMMARY.md:119`.
**How to avoid:** Plan for fallback FROM THE START: write the UAT script as if Claude will execute it, but include a `human_verification` YAML block in `13-VERIFICATION.md` that the user can drive verbatim. Same `human_needed` route Phase 12 used.
**Warning signs:** computer-use `request_access` returns no result for OpenGram bundle; `mcp__computer-use__open_application` fails.

### Pitfall 8: Cargo binary not on $PATH
**What goes wrong:** Plans assume `cargo test` works directly; `command -v cargo` returns 127 because the binary lives in `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/` (rustup-managed but no shell init wired). Verified by direct probe.
**Why it happens:** Toolchain installed but `source $HOME/.cargo/env` never added to shell init; `~/.cargo/bin/cargo` does NOT exist (no symlink).
**How to avoid:** Plan tasks must call `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` explicitly, or document a one-time `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"` in CONTRIBUTING.md.
**Warning signs:** `bash: cargo: command not found` in autonomous plan execution.

## 50-Fixture Scraping Strategy (REVISED — see Summary §critical reality check)

### Verified upstream issue inventory

`github.com/retextjs/retext-simplify/issues?q=is%3Aissue` returns **4 closed issues, 0 open** (verified 2026-04-25 via WebFetch):

| Issue # | Title | Relevance |
|---------|-------|-----------|
| #13 | "`has no effect` triggers a warning with no suitable alternative" | YES — primary false-positive evidence |
| #11 | "New rule suggestion: Replace `in order for` with `for`" | NO — feature request, not false positive |
| #3 | "How to add a new language?" | NO — language support question |
| #1 | "paradoxon :)" | NO — closed comment |

**Conclusion:** N=50 from retext-simplify upstream is NOT achievable. Only #13 is a genuine false positive.

### Recommended source widening

Expand scrape sources to other plain-language linters that share the same dataset lineage:

| Source | URL | Estimated yield | Confidence |
|--------|-----|-----------------|------------|
| retext-simplify issues | `github.com/retextjs/retext-simplify/issues` | 1 (issue #13) | HIGH (verified) |
| retextjs/retext parent issues | `github.com/retextjs/retext/issues` | 5-10 false-positives | MEDIUM (not yet enumerated) |
| alex-js (alex.opensource.guide) issues | `github.com/get-alex/alex/issues` | 10-15 (overlapping plainlanguage scope) | MEDIUM |
| write-good issues | `github.com/btford/write-good/issues` | 10-20 (heavy false-positive history) | MEDIUM |
| LanguageTool false-positive forum | `forum.languagetool.org/c/false-friends/8` | 10+ | LOW (different dataset) |
| Vale style false-positive issues | `github.com/errata-ai/Microsoft/issues` | 5-10 | MEDIUM |

**Recommended actual mix (revising CONTEXT 50-50 split):**
- 10 scraped (retext-simplify #13 + retextjs/retext + write-good — extract 1 sentence per documented case)
- 90 hand-curated, redistributed across 4 buckets:
  - `proper_nouns.txt` (~20): "Implementation of the API was straightforward.", "She works at Acquire Capital Partners.", "Notable Solutions Inc. ships a new product.", "Whether iPhone or Android, both work."
  - `quoted_code.txt` (~25): `"`utilize` is a Python class method on subprocess."`, `"Use \`prior to\` only inside a code block, never in prose."`, `` "The Bash idiom `due to the fact that` appears in legacy scripts." ``
  - `domain_terms.txt` (~25): "RFCs use 'in order to' as a normative imperative.", "The protocol declares a window of opportunity for retransmits.", "Latency due to the fact that the queue is full is expected.", "We must terminate the connection per RFC 793.", "The 'utilize' keyword in MATLAB has documented semantics."
  - `retext_issues.txt` (~20): mix of retext-simplify #13 ("has no effect" usage) + write-good extracted + alex-js extracted, with `# Source:` provenance comments per fixture

**Plan should NOT lock the 50-50 split.** Recommend planner explicitly notes the upstream-yield reality and adjusts the split to 10-90 (or whatever the reviewer agrees to). The ≥100 total stays.

### Provenance comment format

```
# Source: retext-simplify#13 — "has no effect" reported as false positive 2021-08-19
# Source: write-good#142 — "in order to" wrongly flagged in academic prose
# Source: hand-curated — RFC normative usage
```

## Manual UAT Script

> Drive via computer-use MCP if accessible; otherwise serialize as `human_verification` YAML in `13-VERIFICATION.md` per Phase 12 pattern (`12-VERIFICATION.md:8-23`).

### Scenario 1: Notes.app — wordy phrase end-to-end

**Setup:** Build OpenGram via `xcodebuild`, launch from DerivedData (`open ~/Library/Developer/Xcode/DerivedData/OpenGram-*/Build/Products/Debug/OpenGram.app`). Confirm menu-bar icon present + Settings → Clarity master ON + sub-toggle ON.

**Steps:**
1. Open Notes.app, create a new note.
2. Type: `We need to utilize this tool in order to make a decision.`
3. Press Ctrl+Shift+G.
4. Wait ~500ms for overlay to render.

**Expected:**
- Solid orange underline appears under `utilize` (1 word) AND under `in order to` (3 words).
- ZERO red (spelling) or purple/teal (tone/rephrase) underlines on this sentence.
- Click the `utilize` underline — popover opens, footer reads "Clarity" with `text.magnifyingglass` icon (per Phase 12 verification §43).
- Click "Accept" button — text in Notes now reads `We need to use this tool in order to make a decision.`
- Press Ctrl+Shift+G again. Click the `in order to` underline. Click "Dismiss". Underline disappears; text unchanged.

### Scenario 2: TextEdit — toggle behavior

**Setup:** OpenGram running. Open TextEdit, new document.

**Steps:**
1. Open OpenGram Settings → Clarity tab. Toggle "Enable Clarity Suggestions" OFF.
2. Switch to TextEdit. Type: `We need to utilize this tool in order to make a decision.`
3. Press Ctrl+Shift+G.

**Expected (master OFF):** ZERO orange underlines. Spelling/grammar (if any) still surface red.

4. Switch back to OpenGram Settings → Clarity tab. Toggle master ON. Sub-toggle "Show subjective clarity suggestions" was OFF; toggle it ON.
5. Switch to TextEdit. Press Ctrl+Shift+G again on the same text.

**Expected (master ON + sub-toggle ON):** Orange underlines reappear. ANY clarity entry of severity `.low` from the corpus that matches this sentence should now also surface (e.g., if `make a decision` is severity `.low` it appears too — depends on actual corpus tagging, verify via `grep severity = "low" harper-bridge/data/wordy_phrases.toml | head`).

### Scenario 3: LLM `.clarity` end-to-end suppression

**Setup:** OpenGram running. Open Settings → LLM Provider tab. Configure any OpenAI-compatible endpoint (a local llama.cpp server on `http://localhost:8080/v1` is simplest if available). Enable `.tone` + `.rephrase`. (DO NOT toggle `.clarity` — per CLAR-09 the option no longer exists in the UI.)

**Steps:**
1. In TextEdit, type: `At this point in time, I think we should utilize the new system in order to finish the work.`
2. Press Ctrl+Shift+G.
3. Wait for LLM round-trip (≤30s timeout).

**Expected:**
- Orange (Harper clarity) underlines appear under `utilize`, `in order to`, and `at this point in time` (all from the deterministic Harper corpus).
- ANY purple (tone) or teal (rephrase) underlines that appear must NOT have category `.clarity` — this is verified by clicking each non-orange underline and confirming the popover footer reads "AI" (LLM source) and the badge is "Tone" or "Rephrase", never "Clarity".
- If the LLM hallucinates a `{"category":"clarity",...}` entry in its JSON, it is silently dropped at `SuggestionDTO.toModel` (CLAR-09 contract — already locked at `LLMResponseDTOTests.swift:96`).

**This scenario validates Phase 7 clean-deletion still holds end-to-end across the full v1.4 milestone.**

### Fallback: human_verification YAML format

If computer-use MCP cannot reach the OpenGram dev build (Phase 12 blocker recurs), serialize the 3 scenarios into the `13-VERIFICATION.md` frontmatter using the Phase 12 pattern (12-VERIFICATION.md:8-23):

```yaml
human_verification:
  - test: "Notes.app — wordy phrase end-to-end (UAT Scenario 1)"
    expected: "Solid orange underlines on 'utilize' + 'in order to'; popover footer 'Clarity'; Accept replaces text; Dismiss removes underline"
    why_human: "Cross-app AX surface — automation cannot drive Notes.app + AX overlay"
  - test: "TextEdit — clarity toggle behavior (UAT Scenario 2)"
    expected: "Master OFF suppresses all orange; master ON + sub-toggle ON re-surfaces Low-severity entries"
    why_human: "End-to-end Settings → notification observer → FFI → re-check flow; visual underline state requires user eye"
  - test: "LLM .clarity suppression end-to-end (UAT Scenario 3)"
    expected: "Configured LLM with .tone + .rephrase ON; ZERO popover footers read 'Clarity' for LLM-source suggestions"
    why_human: "Requires user-configured LLM endpoint + cross-app AX surface; Phase 7 invariant verified end-to-end"
```

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust toolchain (cargo, rustc) | `nonflags_corpus.rs` test | ✓ | stable-aarch64-apple-darwin via rustup | — (binary at `~/.rustup/...`, NOT on `$PATH`) |
| Xcode 16+ / xcodebuild | LLM test compile + run | ✓ (assumed — Phase 12 used it) | — | — |
| Notes.app (macOS built-in) | UAT Scenario 1 | ✓ (system) | — | — |
| TextEdit.app (macOS built-in) | UAT Scenario 2 | ✓ (system) | — | — |
| OpenGram dev build | UAT all scenarios | ✓ (built via xcodebuild) | — | — |
| computer-use MCP | UAT automation | ✓ (per CLAUDE.md) | — | user-driven manual UAT per Phase 12 fallback |
| LLM endpoint (OpenAI-compatible) | UAT Scenario 3 | unknown | — | document as user-supplied prerequisite |
| Web access (for retext-simplify scrape) | Initial corpus seeding | ✓ (verified — GitHub fetch worked) | — | — |

**Missing dependencies with fallback:**
- computer-use MCP `/Applications` resolver does not reach DerivedData builds → Phase 12 fallback (user-driven UAT) per `12-03-SUMMARY.md:119`.

**Missing dependencies with no fallback:**
- LLM endpoint for UAT Scenario 3: user must supply one (local llama.cpp / LM Studio / OpenAI key). Document as UAT prerequisite. If the user has none, defer Scenario 3 to a separate user-driven session.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fixture file format | A YAML/JSON/TOML schema for fixtures | Plain `.txt`, one sentence per line, `#` comments | Already locked in CONTEXT; matches `fixture_harness.rs` aggregate pattern; zero parsing burden |
| Fixture loading at runtime | `std::fs::read_to_string` + path resolution logic | `include_str!` macro | Compile-time embed — same pattern as `wordy_phrases.toml`; honors CLAR-N3 zero-I/O |
| Per-line failure aggregation | `panic!` per failure (cascading test failure) | `Vec<String>` collect + single final `assert!` | Matches `fixture_harness.rs:108-146` — one test run reports every broken fixture |
| GH issue scraping | A Python/Node automated GH API scraper | Manual hand-extract (N=10 scraped after revision) | CONTEXT explicitly defers automation; corpus is small enough for manual |
| LLM HTTP mock | URLProtocol mock for the parseJSONContent test | Direct call to `LLMService.parseJSONContent` (pure parse, no network) | The function under test is pure-input; URL mocking is wrong layer |
| PR template enforcement | A pre-commit hook or GH Actions workflow | Documentation in CONTRIBUTING.md + reviewer checklist in PR template | CONTEXT explicitly defers CI tooling; this phase is documentation only |

**Key insight:** Phase 13 is regression containment, not new infrastructure. Mirror existing patterns verbatim (fixture_harness.rs, wordy_phrases.toml include_str, LLMResponseDTOTests Swift Testing) — don't invent new ones.

## State of the Art

No state-of-the-art shifts apply to this phase — pure regression containment using established patterns from Phases 7, 11, and 12. All mechanisms (Rust integration tests + `include_str!` + Swift Testing + computer-use MCP for UAT) already shipped in earlier phases of v1.4.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The CONTEXT 50-50 corpus split is not viable because retext-simplify upstream has only 4 issues (1 false-positive) — recommend revising to 10-90 | Summary, §50-Fixture Scraping Strategy | If reviewer rejects revision, plan must wait for explicit user decision; otherwise corpus seeding stalls |
| A2 | Cargo binary at `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` will remain stable across the phase execution window | §Existing Code Map, §Pitfall 8 | If rustup is reinstalled mid-phase, command path changes |
| A3 | computer-use MCP will hit the same `/Applications`-only blocker as Phase 12 (12-03-SUMMARY.md:119) | §Manual UAT Script, §Pitfall 7 | If the MCP behavior changed since Phase 12 (2026-04-25 same day), automation may actually work — verify before falling back |
| A4 | A new `LLMServiceTests.parseClarityCategoryDropped_CLAR21` test adds genuine coverage beyond the existing DTO-level test at `LLMResponseDTOTests.swift:96` | §Existing Code Map (LLM service location), §Pattern 4 | If reviewer disputes, the test is redundant and CONTEXT decision becomes a no-op — drop the test, cite existing DTO coverage |
| A5 | Fixture corpus parsing in `nonflags_corpus.rs` will stay under the 5s perf budget for 100 fixtures with linter constructed once per test fn | §Concrete Patterns §Pattern 3, §Pitfall 4 | If exceeded, plan must add the batch-load optimization explicitly per CONTEXT discretion |
| A6 | The `severity = "low"` corpus has at least one entry that matches `make a decision` or similar phrase appearing in UAT Scenario 2 sentence — required for the sub-toggle ON visual confirmation | §Manual UAT Script Scenario 2 | If no Low-severity entry matches the test sentence, UAT must use a different sentence — verify by inspecting `wordy_phrases.toml` for `severity = "low"` entries before UAT |

## Open Questions (RESOLVED)

1. **Should the LLM `.clarity` regression test go at the `LLMService` layer or the `LLMResponseDTO` layer?**
   **RESOLVED:** Add at `LLMService.parseJSONContent` layer. Existing `LLMResponseDTOTests.clarityCategoryDroppedPostDeletion_CLAR09` (line 96) already locks the DTO drop. Adding at the `LLMService` layer verifies the integration path (markdown-fence stripping + preamble stripping + DTO drop together) end-to-end, providing complementary coverage. Cite existing test in the new test's doc-comment to make the layering explicit.

2. **Is the 50-scraped / 50-curated split achievable given retext-simplify upstream has only 4 issues?**
   **RESOLVED:** No. WebFetch verified only issue #13 is a false-positive case. Plan should adopt the 10-90 split (10 scraped from widened sources: retext-simplify + retextjs/retext + write-good + alex-js; 90 hand-curated). Total ≥100 still met. Planner must explicitly note this revision in the plan rationale and surface it in `13-VERIFICATION.md` as a deviation from CONTEXT.

3. **Do CONTRIBUTING.md and `.github/PULL_REQUEST_TEMPLATE.md` exist?**
   **RESOLVED:** Neither exists. Confirmed via `ls -la /Users/alex/Dev/opengram/CONTRIBUTING.md` and `ls -la /Users/alex/Dev/opengram/.github/` — both return "No such file or directory". Phase 13 must create both from scratch. CONTRIBUTING.md is repo-root with the full "Adding NonFlags Fixtures" section; `.github/` directory + `PULL_REQUEST_TEMPLATE.md` is minimal scaffold + NonFlags checkbox.

4. **What is the cargo binary path for plan task scripts?**
   **RESOLVED:** `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo`. NOT on default `$PATH`. Plans must use this absolute path or prepend `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"` at task start.

5. **Will computer-use MCP work for UAT, or do we fall back to user-driven script?**
   **RESOLVED:** Plan for fallback by default. Phase 12 (same day, 2026-04-25) hit the `/Applications`-only blocker per `12-03-SUMMARY.md:119`. Phase 13 plan should write the UAT script to be executable by EITHER Claude (via computer-use) OR the user (verbatim manual steps). Default the verification record to `human_needed` like Phase 12; if computer-use unexpectedly works, upgrade to `passed`.

6. **Does adding `nonflags_meta_corpus_size` (≥100 line assertion) belong in this phase?**
   **RESOLVED:** Yes, recommended. CONTEXT discretion #6 explicitly raises it. Cost is one extra test fn; benefit is fail-fast on accidental fixture deletion (a real risk given the corpus is loose `.txt` files). Add it.

7. **What sentence in UAT Scenario 2 reliably triggers a Low-severity clarity lint?**
   **RESOLVED:** Plan must verify against actual corpus before locking the UAT sentence. Run `grep -B1 'severity = "low"' harper-bridge/data/wordy_phrases.toml | grep '^phrase' | head -5` to enumerate Low-severity phrases; pick one that fits naturally in a TextEdit sentence. If no clean fit exists, expand the test sentence or use a constructed sentence containing a known Low-severity phrase (e.g., if `accordingly` is Low-severity per the dataset).

## Sources

### Primary (HIGH confidence — verified in this session)
- `harper-bridge/tests/fixture_harness.rs` (full file read 2026-04-25) — aggregate-failure pattern, `WordyPhrasesLinter` invocation surface, `make_merged_dict` helper
- `harper-bridge/src/clarity.rs` (full file read) — `get_corpus`, `WordyPhrasesLinter`, `Severity`, `include_str!` precedent
- `harper-bridge/Cargo.toml` (full read) — Rust integration test convention, no `[[test]]` block needed
- `OpenGramTests/CheckEngine/LLMResponseDTOTests.swift` (lines 1-120 read) — existing CLAR-09 test at line 96
- `OpenGramTests/LLMServiceTests.swift` (lines 1-120 read) — Swift Testing patterns, fenced-JSON parse precedent
- `.planning/REQUIREMENTS.md` (CLAR-21 full read) — phase requirement
- `.planning/ROADMAP.md` (Phase 13 section read) — success criteria 1-5
- `.planning/STATE.md` (status read) — Phase 12 complete, Phase 13 next
- `.planning/phases/12-settings-ui-severity-filter-acknowledgements/12-VERIFICATION.md` — `human_verification` YAML pattern
- `.planning/phases/12-settings-ui-severity-filter-acknowledgements/12-03-SUMMARY.md` — computer-use MCP `/Applications`-only blocker
- `.planning/phases/07-llm-clarity-clean-deletion/07-06-UAT.md` — Notes.app UAT precedent format
- `.planning/phases/11-dataset-integration-fixture-harness/11-RESEARCH.md` — `include_str!` rationale
- `harper-bridge/data/wordy_phrases.toml` (sampled) — phrase format + severity tags
- `https://github.com/retextjs/retext-simplify/issues` (WebFetch 2026-04-25) — 4 closed issues confirmed; only #13 is false-positive evidence

### Secondary (MEDIUM confidence — partial verification)
- `command -v cargo` returns 127; `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo` exists — verified by direct `ls` probe
- retextjs/retext + write-good + alex-js as supplementary scrape sources — listed in CONTEXT canonical_refs but not yet enumerated for false-positive yield

### Tertiary (LOW confidence — needs validation by planner before locking)
- Specific Low-severity phrase choice for UAT Scenario 2 sentence — Planner must `grep severity = "low"` the actual corpus and pick a phrase that fits a natural test sentence

## Metadata

**Confidence breakdown:**
- Standard stack (Rust + Swift Testing + include_str): HIGH — every pattern exists in repo and is verbatim copyable
- Fixture harness architecture: HIGH — fixture_harness.rs is a perfect template
- LLM regression test layering: MEDIUM — existing DTO coverage may make new test redundant; reviewer call
- Manual UAT mechanism: MEDIUM — computer-use MCP `/Applications` blocker likely recurs
- 50-scraped corpus viability: HIGH — verified upstream has only 4 issues (1 false-positive); REVISION REQUIRED
- CONTRIBUTING.md + PR template scaffolding: HIGH — verified neither file exists; clean scaffold

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (30 days — corpus + harness pattern is stable; only LLM endpoint config likely to drift)
