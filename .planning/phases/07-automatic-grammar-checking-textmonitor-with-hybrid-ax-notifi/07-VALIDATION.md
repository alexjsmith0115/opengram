---
phase: 7
slug: automatic-grammar-checking-textmonitor-with-hybrid-ax-notifi
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-14
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 16+) |
| **Config file** | OpenGram.xcodeproj |
| **Quick run command** | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test -only-testing:OpenGramTests 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test 2>&1 \| tail -40` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick test command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | TM-05 | — | N/A | unit | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/SuggestionDiffEngineTests 2>&1 \| tail -20` | TDD task creates test file | pending |
| 07-01-02 | 01 | 1 | TM-05, TM-06 | T-07-01, T-07-02 | Cache data integrity | unit | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/AXCapabilityCacheTests -only-testing OpenGramTests/AppQuirksTests 2>&1 \| tail -20` | AXCapabilityCacheTests exists; AppQuirksTests created by TDD task | pending |
| 07-02-01 | 02 | 2 | TM-01, TM-02, TM-03, TM-04 | T-07-03, T-07-04, T-07-05 | Watchdog skip, Unmanaged safety, app-switch debounce | unit | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/TextMonitorTests 2>&1 \| tail -20` | TDD task creates test file | pending |
| 07-03-01 | 03 | 3 | TM-05 | T-07-07 | Diff-merge bounds query reduction | unit | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/SuggestionUITests/OverlayControllerDiffTests 2>&1 \| tail -20` | TDD task creates test file | pending |
| 07-03-02 | 03 | 3 | TM-01, TM-02, TM-03, TM-04, TM-06 | T-07-08, T-07-09 | Race prevention, stale element guard | build | `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build 2>&1 \| tail -5` | N/A (wiring task) | pending |
| 07-03-03 | 03 | 3 | TM-01 through TM-06 | — | N/A | manual | See Manual-Only Verifications | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

No Wave 0 plan needed. All TDD tasks (07-01-01, 07-01-02, 07-02-01, 07-03-01) create their own test files as part of the RED phase. Existing test infrastructure (Swift Testing, OpenGramTests target) is already in place.

*Existing infrastructure covers test framework and fixtures.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Underlines don't flicker during automatic re-check | D-12, D-13 | Visual — no automated way to verify underline stability | 1. Open TextEdit, type text with errors. 2. Wait for underlines. 3. Continue typing — existing underlines should not disappear/reappear. |
| Monitoring switches on app switch | D-10 | Requires real app switching | 1. Type in TextEdit (underlines appear). 2. Switch to another app. 3. Overlay dismisses. 4. Switch back — monitoring resumes. |
| AX notification fallback to polling | D-02 | Requires app with unreliable AX notifications | 1. Open Electron-based app. 2. Type text. 3. Verify grammar checking still works via polling fallback. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or are TDD tasks that self-create test files
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 not needed — TDD tasks self-contain test creation
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
