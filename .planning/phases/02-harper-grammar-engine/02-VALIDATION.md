---
phase: 2
slug: harper-grammar-engine
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-13
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 16) |
| **Config file** | OpenGram/Tests/ |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HarperServiceTests` |
| **Full suite command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HarperServiceTests`
- **After every plan wave:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-T1 | 02-01 | 1 | GRAM-01, GRAM-02, GRAM-03, GRAM-05, GRAM-08, GRAM-09 | T-02-01, T-02-02 | Pin exact crate versions | build | `cd harper-bridge && cargo check` | harper-bridge/src/lib.rs | pending |
| 02-01-T2 | 02-01 | 1 | GRAM-01, GRAM-02, GRAM-03, GRAM-05 | T-02-03 | Script runs user-level only | build | `test -f HarperBridge.xcframework/Info.plist && grep -q "class HarperChecker" OpenGram/Generated/HarperBridge.swift && echo PASS` | build-harper.sh | pending |
| 02-02-T1 | 02-02 | 2 | GRAM-05 | — | N/A | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SuggestionTests` | OpenGramTests/SuggestionTests.swift | pending |
| 02-02-T2 | 02-02 | 2 | GRAM-05, GRAM-06, GRAM-07 | T-02-05, T-02-06 | Actor isolation; atomic file write | build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` | OpenGram/CheckEngine/HarperService.swift | pending |
| 02-03-T1 | 02-03 | 3 | GRAM-01, GRAM-04, GRAM-08 | T-02-08, T-02-09 | Log count only; async execution | build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` | OpenGram/App/AppDelegate.swift | pending |
| 02-03-T2 | 02-03 | 3 | GRAM-01, GRAM-02, GRAM-03, GRAM-04, GRAM-06, GRAM-07, GRAM-08, GRAM-09 | T-02-10 | Test-only temp paths | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "HarperServiceTests\|DictionaryStoreTests"` | OpenGramTests/HarperServiceTests.swift, OpenGramTests/DictionaryStoreTests.swift | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] Fix 144 pre-existing compile errors in test suite (broken @testable import) — addressed in 02-02 Task 1
- [ ] Install Rust toolchain via `brew install rustup` — addressed in 02-01 Task 1
- [ ] Build harper-bridge xcframework and link into Xcode project — addressed in 02-01 Task 2
- [ ] Run `cargo doc` to discover FlatConfig keys and resolve Open Questions — addressed in 02-01 Task 1 Step 7

*Wave 0 must complete before any phase 2 plan can execute.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 50ms performance on device | GRAM-04 | Timing varies by hardware, simulator not representative | Run check on 500-word text, measure via `ContinuousClock` delta in HarperServiceTests |
| Dictionary survives app restart | GRAM-07 | Requires app lifecycle testing | Add word, quit app, relaunch, verify word still suppressed |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending execution
