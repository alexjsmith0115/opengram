---
phase: 11
plan: "04"
subsystem: harper-bridge/tests
tags: [snapshot, regression, clarity, golden-file]
dependency_graph:
  requires: [11-02]
  provides: [golden-snapshot-regression]
  affects: [CI]
tech_stack:
  added: []
  patterns: [golden-file-snapshot, comment-strip-reader]
key_files:
  created:
    - harper-bridge/tests/snapshot_diff.rs
    - harper-bridge/tests/golden_clarity_snapshot.txt
  modified: []
decisions:
  - "Golden file contains human-readable header comments; test strips '#' lines before comparison — header is for developers, not the assertion"
  - "All 5 locked entries emit priority=200 (Severity::High) — wordy_phrases.toml severities are all 'high'; plan interface table listed 'at the present time' as medium but TOML is source of truth"
  - "Case-preserving replacements: 'At the present time' → 'At present' (sentence-case) per MapPhraseLinter behavior; golden locks this as canonical"
metrics:
  duration: "~5 min"
  completed: "2026-04-25"
  tasks_completed: 1
  files_changed: 2
---

# Phase 11 Plan 04: Snapshot Diff Golden File Summary

**One-liner:** Golden snapshot regression locking 5 clarity entries (utilize, in order to, at the present time, a number of, additional) via sorted `sentence|replacement|priority` lines; CI fails on any drift.

## What Was Built

`harper-bridge/tests/snapshot_diff.rs` — integration test with two functions:
- `build_snapshot()` — instantiates `HarperChecker::new("US", [])`, runs `check()` on 5 locked sentences, filters `SuggestionCategory::Clarity` lints, formats as `sentence|replacement|priority` lines, sorts ascending, returns string with trailing newline
- `golden_snapshot_five_entries` — reads `tests/golden_clarity_snapshot.txt`, strips `#` comment lines, asserts equality with `build_snapshot()` output; panics with actionable message if file missing or content differs
- `print_snapshot` (`#[ignore]`) — diagnostic helper, prints actual output for golden regeneration

`harper-bridge/tests/golden_clarity_snapshot.txt` — committed expected output with header:
```
# Golden snapshot for 5 locked clarity entries.
# Update this file only when wordy_phrases.toml changes intentionally.
# To regenerate: cargo test --test snapshot_diff -- --ignored print_snapshot --nocapture
# Then paste the printed lines below (replacing everything after this header).
At the present time, we need it.|At present|200
Please utilize this document.|use|200
We need a number of solutions.|many|200
We need additional resources.|added|200
We should in order to finish early.|to|200
```

## Per-Sentence Lint Count

| Sentence | Clarity Lints | Replacement | Priority |
|----------|---------------|-------------|----------|
| `Please utilize this document.` | 1 | use | 200 |
| `We should in order to finish early.` | 1 | to | 200 |
| `At the present time, we need it.` | 1 | At present (sentence-case) | 200 |
| `We need a number of solutions.` | 1 | many | 200 |
| `We need additional resources.` | 1 | added | 200 |

No multi-emission; each sentence emits exactly one Clarity lint.

## Drift Verification Log

**Corrupt golden → test red:**
```
echo "X" >> harper-bridge/tests/golden_clarity_snapshot.txt
cargo test --test snapshot_diff ... golden_snapshot_five_entries

test result: FAILED. 0 passed; 1 failed
thread panicked: assertion failed: Snapshot mismatch — ...
  left:  "...We should in order to finish early.|to|200\nX\n"
  right: "...We should in order to finish early.|to|200\n"
```

**Revert → test green:**
```
# restored golden file
cargo test --test snapshot_diff ... golden_snapshot_five_entries
test result: ok. 1 passed; 0 failed
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan interface table listed 'at the present time' severity as medium (priority 220)**
- **Found during:** Task 1 — print_snapshot output showed priority=200 for all 5 entries
- **Issue:** Plan's interface table said `at the present time → at present | medium | 220` but wordy_phrases.toml line 380 has `severity = "high"` → priority 200
- **Fix:** Golden file locked to actual TOML-driven output (priority=200); TOML is source of truth per CLAUDE.md
- **Files modified:** golden_clarity_snapshot.txt (priority 200 for all 5 rows)
- **Commit:** 629e62d

**2. [Rule 2 - Missing functionality] Golden file header needed but raw compare would fail**
- **Found during:** Task 1 — first compare attempt failed because golden file comment lines were included in `read_to_string` output
- **Fix:** Test strips lines starting with `#` before asserting; humans can read the header; assertion still covers only data lines
- **Files modified:** snapshot_diff.rs
- **Commit:** 629e62d

## Test Count

- Before: 22 tests
- After: 23 tests (new: `golden_snapshot_five_entries`; `print_snapshot` is `#[ignore]`-gated, not counted)
- All 23 pass; 0 failures

## Self-Check: PASSED

- `harper-bridge/tests/snapshot_diff.rs` — FOUND
- `harper-bridge/tests/golden_clarity_snapshot.txt` — FOUND
- Commit `629e62d` — FOUND
- `grep 'fn golden_snapshot_five_entries\|fn build_snapshot' harper-bridge/tests/snapshot_diff.rs` → 2 matches
- `grep -E 'utilize|in order to|at the present time|a number of|additional' harper-bridge/tests/golden_clarity_snapshot.txt` → 5 matches
