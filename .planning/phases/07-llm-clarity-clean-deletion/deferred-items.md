# Phase 7 Deferred Items

Items discovered during Phase 7 execution that are out-of-scope (pre-existing, unrelated to clarity deletion).

## Pre-existing Test Failures (fail solo — NOT parallel-load flakes)

### ScrollTrackerTests.onTick_firesAtLeastOnce + onIdle_firesExactlyOnce

- **File:** OpenGramTests/SuggestionUITests/Overlay/ScrollTrackerTests.swift
- **Symptom:** `ticks → 0) > 0` and `idleCount → 0) == 1` expectations fail
- **Solo behavior:** Still fails (confirmed on commit `57b8237` with clean working tree via stash)
- **Root cause guess:** CADisplayLink-based tests flaky in headless xcodebuild environment; may need stable run loop source (DispatchSourceTimer).
- **Discovery:** Plan 07-05 Task 4 full-suite validation surfaced alongside confirmed flakes.
- **Scope:** Pre-existing, unrelated to LLM `.clarity` deletion. Out of scope per plan Task 4.

### OverlayControllerScrollModeTests.hideAndSettle_scrollEventFadesUnderlines

- **File:** OpenGramTests/SuggestionUITests/OverlayControllerScrollModeTests.swift:66
- **Symptom:** `view.alphaValue → 1.0) == (0 → 0.0)` — animation not settled by test deadline
- **Solo behavior:** Still fails solo (confirmed post Plan 07-05)
- **Root cause guess:** Animation timing assumption; CAAnimation may not have completed within test window.
- **Discovery:** Plan 07-05 Task 4 full-suite validation.
- **Scope:** Pre-existing, unrelated to LLM `.clarity` deletion.

## Confirmed Parallel-Load Flakes (pass solo)

These pass when run in isolation — documented in STATE.md:

- `AXCallWatchdogTests.*` — pass solo (pre-existing, Phase 04-01 documented)
- `TextMonitorStoreIntegrationTests.keystrokeSchedulesDebouncedReconcile` — pass solo (pre-existing)
- `TextMonitorTests.keystrokeSchedulesDebouncedReconcile_LLMRequestFiresAfterDebounce` — pass solo (same debounce class)

No action required in Phase 7 — tracked in STATE.md.
