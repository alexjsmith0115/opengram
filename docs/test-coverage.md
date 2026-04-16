# Test Coverage Analysis

Inventory of all test files, coverage gaps, and quality assessment.

---

## Overview

| Metric | Value |
|--------|-------|
| Test files | 31 |
| Approximate test cases | ~240 |
| Source files tested | ~30 of 42 (71%) |
| Source files untested | ~12 |
| Test-to-source line ratio | 0.69 |
| Testing framework | Swift Testing (`@Test`, `#expect`) |
| DI strategy | Protocol-based mocking |

---

## Test Inventory

### CheckEngine Tests

| Test File | Source | Tests | Quality | DI |
|-----------|--------|-------|---------|----|
| `ParagraphExtractorTests` | ParagraphExtractor | 6 | Good. Priority extraction, boundaries, empty, 2000-char cap | Pure functions |
| `LLMResponseDTOTests` | LLMResponseDTO | 8 | Excellent. Valid/malformed JSON, confidence filtering, unknown categories | Pure structs |
| `CheckOrchestratorTests` | CheckOrchestrator | 3 | Good. Harper-only, LLM completion on cancel, finished callback | StubGrammarChecker, SlowMockLLMProvider |
| `HarperServiceTests` | HarperService | 9 | Excellent. Spelling/grammar/punctuation, <50ms perf, dictionary, dialect, rules | DictionaryStore injected |
| `LLMServiceTests` | LLMService | 13 | Very good. JSON parsing variants, cancellation, network errors, config | URLProtocol mocks |
| `LLMPromptsTests` | LLMPrompts | 6 | Good. Non-empty, covers 3 categories, harper spans inclusion | Pure functions |
| `DictionaryStoreTests` | DictionaryStore | 5 | Good. Persistence, file creation, nonexistent → empty, overwrite | Temp file URLs |
| `SuggestionTests` | Suggestion | 8 | Good. Unicode offset conversion (ASCII, emoji, CJK), category mapping | Pure structs |
| `SuggestionDiffEngineTests` | SuggestionDiffEngine | 8 | Very good. Identical/add/remove/both/empty sets | Pure functions |

### SuggestionUI Tests

| Test File | Source | Tests | Quality | DI |
|-----------|--------|-------|---------|----|
| `OverlayControllerTests` | OverlayController | 31 | Excellent. Popover state, accept/dismiss/add-to-dict, write-back, reposition, escape | MockAXAccessor |
| `OverlayControllerDiffTests` | OverlayController.update() | 6 | Good. Diff-merge: identical, add, remove, fallback, empty, context change | MockAXAccessor |
| `BoundsValidatorTests` | BoundsValidator | 11 | Excellent. Zero/small/oversized bounds, NaN/infinity, Y-flip, AX errors, watchdog | MockAXAccessor |
| `PopoverViewTests` | PopoverView | 14 | Very good. Conditional rendering, callbacks, disclosure groups | Callback capture |
| `UnderlineViewTests` | UnderlineView | 16 | Good. Static helpers, entry storage, hit-test passthrough, suggestionAt | Direct assignment |
| `SuggestionPopoverPanelTests` | SuggestionPopoverPanel | 8 | Minimal. Window property assertions only | None |
| `OverlayWindowTests` | OverlayWindow | 7 | Minimal. Property checks only | None |
| `AXCallWatchdogTests` | AXCallWatchdog | 6 | Good. Unknown→false, timeout→blocklist, expiration, busy guard | Timing-based |
| `TargetAppObserverTests` | TargetAppObserver | 5 | Minimal. Lifecycle: init, install/uninstall idempotency | None |
| `BoundsForRangeTests` | (migrated) | 0 | Empty — tests moved to BoundsValidatorTests | — |

### TextEngine Tests

| Test File | Source | Tests | Quality | DI |
|-----------|--------|-------|---------|----|
| `AXTextEngineTests` | AXTextEngine | 13 | Very good. Extract selection/full/empty/untrusted, write stale, probe settable | MockAXAccessor, StubCapabilityCache |
| `AXCapabilityCacheTests` | AXCapabilityCache | 12 | Very good. Memory/disk, version-keyed, nil version, corrupt JSON | Injected fileURL |
| `TextContextTests` | TextContext | 4 | Minimal. Struct init and field access | None |

### Other Tests

| Test File | Source | Tests | Quality | DI |
|-----------|--------|-------|---------|----|
| `HotkeyManagerTests` | HotkeyManager | 10 | Good. Detection (exact modifiers, CapsLock), install/uninstall, health timer | None |
| `IconStateMachineTests` | IconStateMachine | 8 | Good. State transitions, auto-revert, pulse, silent fail | None |
| `MenuBuilderTests` | MenuBuilder | 10 | Good. Menu structure, disabled status, target-action, callbacks | None |
| `AppWhitelistTests` | AppWhitelist | 7 | Good. Defaults, add/remove persist, reset, isAllowed | Injected UserDefaults |
| `AppDelegateWiringTests` | AppDelegate | 7 | Good. Callback wiring: accept, dismiss, add-to-dict, state reset | MockAXAccessor, MockGrammarChecker |
| `TextMonitorTests` | TextMonitor | 14 | Good. Lifecycle, observer cleanup, role validation, debounce, watchdog skip | TMockAXTextEngine, TMockGrammarChecker |
| `LLMSettingsPanelTests` | LLMSettingsPanel | 2 | Minimal. Panel shows, floating level | None |
| `AppQuirksTests` | AppQuirksTable | 7 | Good. Decoding, backward compat, Chrome pre-classified, reliability storage | None |

### Integration Tests

| Test File | Source | Tests | Quality |
|-----------|--------|-------|---------|
| `TwoPhaseCheckFlowTests` | CheckOrchestrator (E2E) | 11 | Excellent. Harper→LLM ordering, whitelist blocking, batch callbacks, cancellation, network failure fallback |

---

## Untested Source Files

### High Priority (logic-bearing, no tests)

| File | Lines | Risk |
|------|-------|------|
| `LLMPanelController.swift` | 101 | UI controller with positioning logic (duplicated from SuggestionPopoverPanel) |
| `StatusBarController.swift` | 62 | Menu bar integration, state routing, flash on inactive hotkey |
| `LLMSuggestionPanel.swift` | 105 | SwiftUI panel rendering 1-3 suggestions |
| `InlineDiffView.swift` | 89 | LCS diff algorithm (O(m*n)) — pure logic, highly testable |
| `WhitelistSettingsView.swift` | 116 | Settings UI with mutations |
| `LLMSettingsView.swift` | 257 | Settings form, keychain ops, health check |

### Low Priority (thin wrappers, protocols, generated)

| File | Lines | Reason |
|------|-------|--------|
| `EventTapBridge.swift` | 15 | C callback bridge — 4 lines of logic |
| `PermissionGuide.swift` | 143 | UI-only, layout code |
| `OpenGramApp.swift` | 17 | Enum definition |
| `main.swift` | 7 | Entry point |
| `HarperBridge.swift` | 953 | Auto-generated by UniFFI |
| Protocol files (5) | ~70 | Interface-only, no logic |

---

## Test Infrastructure

### Strengths
- **Protocol-based DI** — MockAXAccessor, StubCapabilityCache, StubGrammarChecker, TMockAXTextEngine enable isolated unit tests
- **Factory helpers** — `makeSuggestion()`, `makeMonitor()` reduce test boilerplate
- **Test isolation** — Temp file URLs, unique UserDefaults suite names prevent cross-test pollution
- **Async testing** — Proper `Task`, cancellation, and delay handling in concurrent tests
- **Network mocking** — `URLProtocol` subclasses (FailingURLProtocol, HangingURLProtocol)

### Weaknesses
- **No shared mock library** — MockAXAccessor defined in multiple test files. Should extract to `TestHelpers/` directory
- **No UI snapshot tests** — Window properties tested but no visual rendering verification
- **No performance benchmarks** — Only HarperServiceTests has a timing assertion (<50ms). No benchmarks for bounds computation, diff engine, or overlay repositioning
- **Limited AX integration tests** — All AX code mocked. No tests against real AX elements (requires running app)
- **Minimal test for LLMSettingsPanel** — 2 tests, property-only

---

## Coverage Gaps by Risk

### Critical Path Gaps
1. **TextMonitor notification delivery** — Tests mock the engine but don't simulate actual AX notifications arriving. The hybrid notification/poll path is tested for debounce and lifecycle but not for the actual data flow.
2. **OverlayController rapid accept cycles** — 31 tests but no test for accepting 3+ suggestions in <100ms (scalar offset accumulation under pressure).
3. **AXTextEngine write failure recovery** — Tests cover stale element but not partial write (element becomes read-only mid-operation).
4. **LLMService streaming** — All tests use batch JSON responses. No streaming/SSE test coverage.

### Recommended Additions
1. Extract `TestHelpers/MockAXAccessor.swift` — shared across all test files
2. Add `InlineDiffViewTests` — LCS algorithm is pure logic, easy to unit test
3. Add `LLMPanelControllerTests` — positioning logic should match SuggestionPopoverPanel behavior
4. Add `StatusBarControllerTests` — state routing + flash behavior
5. Add performance benchmarks for BoundsValidator and SuggestionDiffEngine
6. Add multi-display test case for BoundsValidator coordinate flip
