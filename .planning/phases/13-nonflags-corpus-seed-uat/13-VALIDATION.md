---
phase: 13
slug: nonflags-corpus-seed-uat
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-25
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Sourced from RESEARCH.md §Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Rust framework** | built-in `#[test]` + `cargo test` |
| **Rust config** | `harper-bridge/Cargo.toml` (convention-based discovery) |
| **Swift framework** | Swift Testing (`@Test` + `#expect`) |
| **Swift config** | `OpenGram.xcodeproj/project.pbxproj` test target |
| **Quick run (Rust)** | `cargo test --test nonflags_corpus --manifest-path harper-bridge/Cargo.toml` |
| **Quick run (Swift)** | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS' -only-testing:OpenGramTests/LLMServiceTests` |
| **Full suite (Rust)** | `cargo test --manifest-path harper-bridge/Cargo.toml` |
| **Full suite (Swift)** | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS'` |
| **Estimated runtime** | <5s (Rust nonflags suite); ~60s (full Swift suite) |

---

## Sampling Rate

- **After every task commit:** `cargo test --test nonflags_corpus` (<5s)
- **Per category fixture batch:** `cargo test --test nonflags_corpus nonflags_<category>`
- **Per Swift test commit:** `xcodebuild ... -only-testing:OpenGramTests/LLMServiceTests`
- **Before `/gsd-verify-work`:** Full Rust + Swift suites green
- **Phase gate:** Full suites green + UAT 3-scenario script approved (computer-use OR user reply)
- **Max feedback latency:** 5s (Rust quick) / 60s (Swift full)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 13-01-* | 01 | 1 | CLAR-21 | — | Empty harness compiles + zero-fixture pass | unit (Rust) | `cargo test --test nonflags_corpus` | ❌ W0 | ⬜ pending |
| 13-02-T1 | 02 | 2 | CLAR-21 | — | proper_nouns.txt fixtures produce zero lints | unit (Rust) | `cargo test --test nonflags_corpus nonflags_proper_nouns` | ❌ W0 | ⬜ pending |
| 13-02-T2 | 02 | 2 | CLAR-21 | — | quoted_code.txt fixtures produce zero lints | unit (Rust) | `cargo test --test nonflags_corpus nonflags_quoted_code` | ❌ W0 | ⬜ pending |
| 13-03-T1 | 03 | 3 | CLAR-21 | — | domain_terms.txt fixtures produce zero lints | unit (Rust) | `cargo test --test nonflags_corpus nonflags_domain_terms` | ❌ W0 | ⬜ pending |
| 13-03-T2 | 03 | 3 | CLAR-21 | — | retext_issues.txt fixtures produce zero lints + corpus total ≥100 | unit (Rust) | `cargo test --test nonflags_corpus` | ❌ W0 | ⬜ pending |
| 13-04-* | 04 | 4 | CLAR-21 | — | nonflags_meta_corpus_size assertion ≥100 | unit (Rust) | `cargo test --test nonflags_corpus nonflags_meta_corpus_size` | ❌ W0 | ⬜ pending |
| 13-05-* | 05 | 1 | CLAR-21 | — | LLMService drops `category=clarity` JSON | unit (Swift) | `xcodebuild ... -only-testing:OpenGramTests/LLMServiceTests/parseClarityCategoryDropped_CLAR21` | ❌ W0 | ⬜ pending |
| 13-06-T1 | 06 | 1 | CLAR-21 | — | CONTRIBUTING.md NonFlags rule + Build & Test header | doc | `grep -q "## Adding NonFlags Fixtures" CONTRIBUTING.md && grep -q "## Build & Test" CONTRIBUTING.md` | ❌ W0 | ⬜ pending |
| 13-06-T2 | 06 | 1 | CLAR-21 | — | PR template NonFlags checkbox | doc | `grep -q "NonFlags fixture" .github/PULL_REQUEST_TEMPLATE.md` | ❌ W0 | ⬜ pending |
| 13-07-T1 | 07 | 5 | CLAR-21 | — | Final build/test gates green + 13-VERIFICATION.md scaffolded | gate | `xcodebuild build && xcodebuild test && cargo test` | n/a | ⬜ pending |
| 13-07-T2 | 07 | 5 | CLAR-21 | — | UAT 3-scenario script approved | manual | computer-use MCP or user reply | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Plan numbering finalized: phase contains plans 13-01 through 13-07.*

---

## Wave 0 Requirements

- [ ] `harper-bridge/tests/nonflags_corpus.rs` — covers CLAR-21 zero-lint assertion across 4 categories
- [ ] `harper-bridge/tests/nonflags/proper_nouns.txt` — placeholder during scaffold; populated incrementally
- [ ] `harper-bridge/tests/nonflags/quoted_code.txt` — placeholder
- [ ] `harper-bridge/tests/nonflags/domain_terms.txt` — placeholder
- [ ] `harper-bridge/tests/nonflags/retext_issues.txt` — placeholder
- [ ] `OpenGramTests/CheckEngine/LLM/LLMServiceTests.swift` — augment with `parseClarityCategoryDropped_CLAR21` test
- [ ] `CONTRIBUTING.md` — create at repo root with `## Adding NonFlags Fixtures`
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` — create with NonFlags checkbox

Framework install: NOT NEEDED (Rust toolchain present; Swift Testing built into Xcode 16).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Notes.app: hotkey on "We need to utilize this tool in order to make a decision." → 2 solid-orange clarity underlines (`utilize`, `in order to`); Accept replaces, Dismiss suppresses | CLAR-21 (UAT-1) | Cross-app AX surface; computer-use MCP only path; Phase 12 pattern (likely user-driven fallback per `/Applications`-only blocker) | Launch dev build → open Notes → type sentence → Ctrl+Shift+G → screenshot → click `utilize` → Accept → re-fire → click `in order to` → Dismiss |
| TextEdit: master OFF suppresses clarity; sub-toggle ON surfaces Low-severity entries | CLAR-21 (UAT-2) | Cross-app AX + Settings panel toggle; live behavior only validates via real macOS UI | Open Settings → Clarity tab → master OFF → TextEdit → type sentence → fire hotkey → expect zero clarity. Toggle master ON, sub-toggle ON → fire hotkey → expect Low-severity entries |
| LLM `.tone`+`.rephrase` enabled → zero `.clarity` source entries surface end-to-end | CLAR-21 (UAT-3) | End-to-end LLM path through real network/provider; mock test covers DTO layer but UAT confirms full pipeline | Settings → LLM Provider → configure endpoint → enable tone+rephrase → trigger check → inspect popover for absence of `.clarity` source |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency <5s (Rust) / <60s (Swift)
- [ ] `nyquist_compliant: true` set in frontmatter (post-planning audit)

**Approval:** pending
</content>
