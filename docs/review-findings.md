# Code Review Findings

Systematic review of all source files. Findings organized by severity.

---

## P0 — Architecture / Structural

These are systemic issues affecting maintainability, testability, and reliability.

### F-01: AppDelegate is a God Object
**File:** `App/AppDelegate.swift` (383 lines, 22 private properties)
**Problem:** Single class owns: app lifecycle, hotkey routing, text extraction, grammar checking orchestration, LLM checking, suggestion display, suggestion acceptance, API key management, config management, whitelist gating, TextMonitor callbacks.
**Impact:** Untestable composition root. Every new feature requires touching AppDelegate. Callback chains nested 3+ levels deep with weak self captures.
**Recommendation:** Extract a `CheckCoordinator` that owns the check pipeline (extract → check → display). Extract a `ConfigManager` for LLM config/keychain access. AppDelegate should only do lifecycle + wire top-level dependencies.

### F-02: OverlayController SRP Violation
**File:** `SuggestionUI/OverlayController.swift` (655 lines)
**Problem:** Manages: overlay window lifecycle, underline rendering, popover coordination, suggestion acceptance (AX write-back), scalar offset tracking, keyboard monitoring (Escape), scroll dismissal, coordinate transforms (3 locations), animation state.
**Impact:** Most-changed file. Bugs in acceptance affect rendering and vice versa. Parallel arrays (suggestions + scalarOffsets) create fragile invariants.
**Recommendation:** Extract `SuggestionAcceptor` (acceptance logic + AX write-back + offset adjustment). Extract coordinate transforms to shared utility. Consider `OverlayLayoutEngine` for bounds/position computation.

### F-03: TextMonitor God Object
**File:** `TextMonitor/TextMonitor.swift` (430 lines, 17 state variables)
**Problem:** Combines: AX observer lifecycle, polling fallback, reliability detection, app-switch handling, task orchestration, callback dispatch, debouncing.
**Impact:** Complex state interactions. Multiple race condition vectors (see P1 findings). Hard to test individual behaviors in isolation.
**Recommendation:** Extract `ReliabilityDetector` (notification vs. poll tracking, promotion logic). Extract `AppFocusTracker` (app-switch detection, observer install/uninstall). TextMonitor becomes a thin coordinator.

### F-04: No Dependency Injection Container
**File:** `App/AppDelegate.swift`, `Shell/StatusBarController.swift`
**Problem:** All dependencies manually constructed in `applicationDidFinishLaunching`. StatusBarController creates `LLMSettingsPanel` inline. BoundsValidator created inline in OverlayController.
**Impact:** Can't swap implementations for testing without protocols (most have protocols, but wiring is still manual and tightly coupled).
**Recommendation:** Not necessarily a DI framework — a simple `AppServices` struct or factory methods would suffice. Key win: testable composition root.

---

## P1 — Concurrency / Safety

Race conditions, memory safety issues, and data integrity risks.

### F-05: TextMonitor UAF Risk on Concurrent Stop
**File:** `TextMonitor/TextMonitor.swift` (lines 170-192, 247)
**Problem:** `unmanagedContext` wraps MonitorContext via `Unmanaged.passRetained`. C callback (line 186-188) extracts and uses context. `stop()` calls `unmanaged.release()` (line 247). If callback fires during or after `stop()`, use-after-free.
**Impact:** Potential crash in production. Difficult to reproduce — requires specific timing of stop + AX notification delivery.
**Mitigation:** Add a `stopped` flag checked inside C callback dispatch. Or use a weak reference pattern instead of Unmanaged.

### F-06: TextMonitor Poll/Notification Race
**File:** `TextMonitor/TextMonitor.swift` (lines 263, 366, 382)
**Problem:** `notificationFiredSinceLastPoll` is read and written from both notification handler and poll timer without synchronization. Both run on main actor, so this is safe IFF both closures are actually dispatched to main — but the C callback bridge (line 186) uses `DispatchQueue.main.async`, which may interleave with `MainActor.run`.
**Impact:** Incorrect reliability detection — could mark app as unreliable when it's actually reliable (or vice versa). Causes unnecessary polling (battery drain) or missed changes.

### F-07: LLMService Actor State Issue
**File:** `CheckEngine/LLMService.swift`
**Problem:** `currentTask` stored on actor. `analyze()` cancels previous task and starts new one. But if two `analyze()` calls arrive in rapid succession, the second cancels the first's task, then both proceed to create new tasks. Actor serializes access, so this is actually safe — but the "cancel previous" pattern means the first caller's result is silently dropped.
**Impact:** Low severity in practice (CheckOrchestrator serializes calls), but the pattern is fragile.

### F-08: AXCapabilityCache Lock Gap
**File:** `TextEngine/AXCapabilityCache.swift` (lines 52-54)
**Problem:** `store()` unlocks NSLock on line 53, then calls `saveToDisk()` on line 54. Between unlock and save, another thread could modify the in-memory dict, making the persisted state inconsistent.
**Impact:** Stale cache on disk. Low severity — cache is reconstructable, but could cause unnecessary re-probing.

### F-09: HotkeyManager Callback Isolation
**File:** `Hotkey/HotkeyManager.swift`
**Problem:** `@unchecked Sendable`. C callback (`eventTapCallback`) is `nonisolated` but accesses `eventTap` property. If HotkeyManager is accessed from multiple threads, data race on `eventTap`.
**Impact:** Low in practice — callback only reads `eventTap` to check if tap is disabled. But if `uninstall()` runs concurrently, `eventTap` could be nil.

### F-10: TextMonitor Element Staleness in Poll Path
**File:** `TextMonitor/TextMonitor.swift` (lines 284-296 vs. poll path)
**Problem:** `runCheck()` validates that focused element matches observed element (CFEqual). But `pollForChanges()` reads `observedElement` without this validation. If element becomes invalid between installations, poll uses stale reference.
**Impact:** AX call on invalid element could hang or crash. Watchdog mitigates but doesn't prevent.

---

## P2 — Code Quality / Design

Issues affecting maintainability, DRY, and correctness.

### F-11: Positioning Logic Duplication
**Files:** `SuggestionUI/SuggestionPopoverPanel.swift`, `SuggestionUI/LLMPanelController.swift`
**Problem:** Both implement prefer-above/flip-below positioning with screen-edge clamping. ~20 lines duplicated.
**Recommendation:** Extract `PanelPositioner` utility or add positioning method to a shared protocol.

### F-12: Coordinate Transform Duplication
**File:** `SuggestionUI/OverlayController.swift` (lines 102-114, 252-258, 604-610)
**Problem:** Same AX → screen coordinate transform logic in `show()`, `update()`, and `repositionAfterAccept()`.
**Recommendation:** Extract to method on BoundsValidator or a standalone utility.

### F-13: Confidence Threshold Hardcoded in Multiple Places
**Files:** `CheckEngine/LLMPrompts.swift`, `CheckEngine/LLMResponseDTO.swift`
**Problem:** Confidence threshold appeared in both prompt text and DTO filtering. If changed in one place, other becomes inconsistent.
**Recommendation:** Define once in `LLMConfig` and reference from both locations.

### F-14: Silent Error Swallowing Throughout
**Files:** `CheckEngine/DictionaryStore.swift`, `TextEngine/AXCapabilityCache.swift`, `AppQuirks/AppQuirksTable.swift`, `SuggestionUI/LLMSettingsView.swift`
**Problem:** `try?` and empty catch blocks throughout. Errors are swallowed with no logging.
**Impact:** Debugging production issues is extremely difficult. User sees "nothing happened" with no way to diagnose.
**Recommendation:** Adopt `os.log` consistently. At minimum, log at `.error` level in catch blocks.

### F-15: Print/NSLog Debug Statements in Production
**Files:** `Hotkey/HotkeyManager.swift` (lines 41, 58, 62, 149), `SuggestionUI/LLMPanelController.swift` (line 63), `App/AppDelegate.swift` (multiple NSLog calls)
**Problem:** `print()` and `NSLog()` scattered in production code. No unified logging.
**Recommendation:** Replace with `os.log` Logger instances. Remove debug prints entirely.

### F-16: LLMConfig URL Construction Fragility
**File:** `CheckEngine/LLMConfig.swift` (lines 40-42)
**Problem:** Multiple `trimmingCharacters` operations on URL string. Doesn't use `URLComponents`.
**Impact:** Malformed user input could produce invalid URLs silently.
**Recommendation:** Use `URLComponents` for URL construction. Validate at input time in LLMSettingsView.

### F-17: AppWhitelist Serialization
**File:** `App/AppWhitelist.swift`
**Problem:** Bundle IDs stored as newline-separated string in UserDefaults. No deduplication, no validation.
**Recommendation:** Use `PropertyListEncoder` with `[String]` array. Or at minimum, `Set<String>` semantics with dedup on save.

### F-18: BoundsValidator Multi-Display Assumption
**File:** `SuggestionUI/BoundsValidator.swift` (line 265)
**Problem:** `flipCGRect()` uses `NSScreen.main` for coordinate flip. On multi-display setups, target app may be on non-primary screen.
**Impact:** Underlines positioned incorrectly on secondary displays.
**Recommendation:** Use `NSScreen.screens` to find screen containing the target rect.

### F-19: InlineDiffView LCS Performance
**File:** `SuggestionUI/InlineDiffView.swift`
**Problem:** LCS implementation is O(m*n) with explicit 2D array allocation. For typical suggestion lengths this is fine, but degrades on long paragraphs.
**Impact:** Low — suggestions are typically short. But worth noting.

### F-20: LLMService Brace-Matching Parser Fragility
**File:** `CheckEngine/LLMService.swift` (lines 198-230)
**Problem:** Fallback JSON parser uses brace-counting. Doesn't handle escaped quotes, nested objects, or string literals containing braces.
**Impact:** Could misparse LLM responses that contain code examples or JSON-in-strings.

### F-21: PermissionGuide Manual Frame Layout
**File:** `Permissions/PermissionGuide.swift` (143 lines)
**Problem:** 100+ lines of manual frame arithmetic (y-offset stacking). No Auto Layout, no SwiftUI.
**Impact:** Fragile layout. Any text length change requires manual coordinate adjustment.
**Recommendation:** Rewrite as SwiftUI view hosted in NSPanel (like other settings views).

### F-22: IconStateMachine Timer Safety
**File:** `Shell/IconStateMachine.swift` (lines 72-76, 89-91)
**Problem:** Timer closures use `MainActor.assumeIsolated` without null-checking `self`. If timer fires after object deallocation, crash.
**Impact:** Low — StatusBarController retains IconStateMachine for app lifetime. But defensive coding would use `[weak self]`.

### F-23: AppState Enum Possibly Unused
**File:** `App/OpenGramApp.swift`
**Problem:** `AppState` enum defined with `sfSymbolName` computed property. `sfSymbolName` returns same value for `.checking` and `.checkingLLM`. Not clear if this enum is actually used vs. IconStateMachine's own state.
**Impact:** Dead code or unnecessary indirection.

---

## P3 — Minor / Polish

### F-24: No VoiceOver Accessibility Labels
**File:** `SuggestionUI/PopoverView.swift`
**Problem:** No accessibility labels on interactive elements. VoiceOver users can't use suggestion popover.

### F-25: No i18n / Localization
**Files:** `Permissions/PermissionGuide.swift`, `Shell/MenuBuilder.swift`, all UI views
**Problem:** All user-facing strings hardcoded in English.

### F-26: MenuBuilder Inherits NSObject Unnecessarily
**File:** `Shell/MenuBuilder.swift`
**Problem:** Inherits `NSObject` only for `@objc` selector targets. Could use closure-based targets instead.

### F-27: Suggestion ID Non-Deterministic
**File:** `CheckEngine/Suggestion.swift`
**Problem:** `id = UUID()` in init — prevents deterministic test assertions on identity.

### F-28: LLMStyleSuggestion Missing Equatable/Hashable
**File:** `CheckEngine/LLMStyleSuggestion.swift`
**Problem:** No `Equatable` or `Hashable` conformance. Can't use in Set or compare in tests without manual field-by-field checks.

### F-29: DictionaryStore No Deduplication
**File:** `CheckEngine/DictionaryStore.swift` (line 42)
**Problem:** `save()` sorts but doesn't deduplicate. Repeated `addToDictionary()` calls grow file.

---

## Resolution Status

Findings addressed in the refactoring pass:

| Finding | Status | Resolution |
|---------|--------|------------|
| **F-01** AppDelegate god object | RESOLVED | Extracted CheckCoordinator (200 lines) + ConfigManager. AppDelegate → 77 lines |
| **F-02** OverlayController SRP | PARTIAL | Extracted `toLocalEntries()` helper, removed coordinate transform duplication. Still ~630 lines — accept logic tightly coupled to state |
| **F-03** TextMonitor god object | PARTIAL | Extracted ReliabilityDetector. TextMonitor → ~330 lines. Observer lifecycle + app-switching still interleaved |
| **F-04** No DI container | PARTIAL | CheckCoordinator is now a focused composition point. Still manual wiring, but concentrated in 1 place |
| **F-05** TextMonitor UAF risk | RESOLVED | Added `stopped` flag checked in MonitorContext handler before dispatching |
| **F-06** Poll/notification race | RESOLVED | ReliabilityDetector encapsulates state; both paths run on @MainActor |
| **F-08** AXCapabilityCache lock gap | NOTED | saveToDisk() snapshots under its own lock — documented the pattern |
| **F-10** Element staleness in poll | RESOLVED | pollForChanges() now validates focused element matches observed before AX read |
| **F-11** Positioning duplication | RESOLVED | Extracted PanelPositioner utility. Both panels use it |
| **F-12** Coordinate transform duplication | RESOLVED | Extracted `OverlayController.toLocalEntries()` — single implementation, 3 call sites |
| **F-13** Confidence threshold hardcoded | RESOLVED | Single source: `LLMConfig.defaultConfidenceThreshold`, threaded through prompts + DTO + service |
| **F-14** Silent error swallowing | PARTIAL | DictionaryStore now uses os.log. AXCapabilityCache, AppQuirksTable still silent (non-critical) |
| **F-15** Print/NSLog in production | RESOLVED | HotkeyManager, LLMPanelController, DictionaryStore switched to os.log. Log utility created |
| **F-16** LLMConfig URL construction | RESOLVED | Uses URLComponents instead of string trimming |
| **F-17** AppWhitelist serialization | RESOLVED | Array-based UserDefaults serialization (was newline-separated string) |
| **F-22** IconStateMachine timer safety | RESOLVED | Timer closures guard `self` before `MainActor.assumeIsolated` |
| **F-28** LLMStyleSuggestion missing Equatable | RESOLVED | Added `Equatable, Hashable` conformance |
| **F-29** DictionaryStore no deduplication | RESOLVED | `saveWords()` deduplicates via `Set` before sorting |

### Remaining Unresolved

| Finding | Severity | Reason |
|---------|----------|--------|
| **F-07** LLMService actor state | P1 | Low risk in practice — actor serializes access |
| **F-09** HotkeyManager callback isolation | P1 | Inherent to C callback bridge; documented |
| **F-18** BoundsValidator multi-display | P2 | Original code was correct — AX coords are always primary-display-relative |
| **F-19** InlineDiffView LCS performance | P2 | O(m*n) acceptable for typical suggestion lengths |
| **F-20** Brace-matching parser fragility | P2 | Fallback path — low probability of hitting edge cases |
| **F-21** PermissionGuide manual layout | P2 | UI-only, low change frequency |
| **F-23** AppState enum duplication | P3 | Used by IconStateMachine + StatusBarController — serves its purpose |
| **F-24** No VoiceOver labels | P3 | Accessibility pass planned for later |
| **F-25** No i18n | P3 | Localization planned for later |
| **F-26** MenuBuilder NSObject | P3 | Needed for @objc selectors |
| **F-27** Suggestion ID non-deterministic | P3 | Would break existing test patterns |
