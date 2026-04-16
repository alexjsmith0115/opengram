# OpenGram Module Reference

Detailed breakdown of each module: files, types, responsibilities, dependencies, and design notes.

---

## App (`OpenGram/App/`)

Entry point, dependency wiring, and check pipeline coordination.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `main.swift` | 7 | — | NSApplication setup, accessory activation policy, AppDelegate install |
| `OpenGramApp.swift` | 17 | `AppState` enum | UI state machine (idle/checking/checkingLLM/done) + SF Symbol mapping |
| `AppDelegate.swift` | 77 | `AppDelegate` class | Thin composition root: lifecycle, dependency construction, callback wiring |
| `CheckCoordinator.swift` | ~200 | `CheckCoordinator` class | Check pipeline: hotkey handling, suggestion state, overlay/panel routing, LLM application |
| `ConfigManager.swift` | ~45 | `ConfigManager` enum | Static helpers for LLM config (UserDefaults) and API key (Keychain) |
| `AppWhitelist.swift` | 74 | `AppWhitelist` struct | Bundle ID whitelist for allowed apps. UserDefaults-backed (array serialization), 25 defaults |

### Dependencies
- AppDelegate creates all services, hands them to CheckCoordinator
- CheckCoordinator owns: overlayController, llmPanelController, statusBarController, suggestion state
- ConfigManager is stateless (static methods only)

### Design Notes
- AppDelegate is now a thin 77-line composition root (was 383 lines)
- CheckCoordinator extracted: hotkey routing, check pipeline, LLM suggestion application
- ConfigManager extracted: `currentLLMConfig()` and `currentAPIKey()` (previously duplicated)
- AppWhitelist uses array-based UserDefaults serialization (was newline-separated string)

---

## CheckEngine (`OpenGram/CheckEngine/`)

Two-tier grammar and style checking pipeline. Harper for deterministic grammar, LLM for style/clarity.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `GrammarCheckerProtocol.swift` | 9 | `GrammarCheckerProtocol` | DI contract: check, addToDictionary, setRuleEnabled |
| `HarperService.swift` | 25 | `HarperService` actor | Wraps HarperChecker (UniFFI). Maps raw suggestions to Suggestion model |
| `LLMProviderProtocol.swift` | 14 | `LLMProviderProtocol` | DI contract: analyze, healthCheck |
| `LLMService.swift` | 251 | `LLMService` actor | OpenAI-compatible client. 4-step resilient JSON parser. Request cancellation |
| `LLMConfig.swift` | 44 | `LLMCheckType` enum, `LLMConfig` struct | Non-secret LLM config (URL, model, checks, temperature, timeouts) |
| `LLMPrompts.swift` | 58 | `LLMPrompts` enum (namespace) | System/user prompt generation. Harper-span deduplication |
| `LLMResponseDTO.swift` | 46 | `LLMResponseDTO`, `SuggestionDTO` | DTO for OpenAI response parsing. Confidence filtering (>=7) |
| `LLMStyleSuggestion.swift` | 21 | `LLMStyleSuggestion` struct | Paragraph-level style suggestion (pre-range-resolution) |
| `CheckOrchestrator.swift` | 78 | `CheckOrchestrator` actor | Coordinates Harper → LLM pipeline. Callbacks for each phase |
| `DictionaryStore.swift` | 50 | `DictionaryStoreProtocol`, `DictionaryStore` struct | User dictionary persistence (~Library/Application Support/OpenGram/dictionary.txt) |
| `ParagraphExtractor.swift` | 78 | `ParagraphExtractor` enum (namespace) | Scopes text for LLM: selection > paragraph > first 2000 chars |
| `Suggestion.swift` | 98 | `CheckCategory`, `SuggestionSource`, `Suggestion` struct | Unified suggestion model. Unicode scalar → String.Index conversion |

### Protocols
- `GrammarCheckerProtocol: Sendable` — Harper abstraction
- `LLMProviderProtocol: Sendable` — LLM abstraction
- `DictionaryStoreProtocol` — dictionary storage abstraction

### Data Flow
```
TextContext ──► CheckOrchestrator
                  │
                  ├──► HarperService.check() ──► [Suggestion]
                  │         (via GrammarCheckerProtocol)
                  │
                  └──► LLMService.analyze() ──► [LLMStyleSuggestion] ──► [Suggestion]
                            (via LLMProviderProtocol)
                            │
                            ├── ParagraphExtractor (scope text)
                            ├── LLMPrompts (build request)
                            └── LLMResponseDTO (parse response)
```

### Design Notes
- CheckOrchestrator is an actor — thread-safe for concurrent Harper + LLM
- LLM task shielded from cancellation via `Task.detached` (prevents orphaned requests)
- Confidence threshold (>=7) hardcoded in both LLMPrompts and LLMResponseDTO (should be single source)
- LLMService has 4-step JSON parser: strip markdown → strip preamble → full decode → brace-matching fallback
- HarperService is thin (~25 lines) — good SRP

---

## TextEngine (`OpenGram/TextEngine/`)

Accessibility API abstraction for reading and writing text in arbitrary macOS apps.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `AXTextEngineProtocol.swift` | 17 | `AXTextEngineProtocol` | DI contract: extractText, writeBack, probeCapability |
| `AXTextEngine.swift` | 132 | `AXTextEngine` class | Core text extraction/write-back. 100KB limit. Capability probing |
| `AXAccessor.swift` | 92 | `AXAccessor` protocol, `SystemAXAccessor` struct | Thin wrapper over C AX API functions. Clean DI boundary |
| `AXCapabilityCacheProtocol.swift` | 15 | `AXCapabilityCacheProtocol` | DI contract for capability/notification caching |
| `AXCapabilityCache.swift` | 126 | `AXCapabilityCache` class | Per-bundleID+version capability cache. Disk persistence. NSLock for sync access |
| `TextContext.swift` | 23 | `TextContext` struct | Value object: extracted text + metadata + AXUIElement ref for write-back |

### Concurrency Model
- `AXTextEngine` is `@MainActor` — AX calls must happen on main thread
- `AXCapabilityCache` uses `NSLock` (not actor) — allows synchronous main-thread reads
- `AXAccessor` is `Sendable` — stateless wrapper
- `TextContext` carries `nonisolated(unsafe)` AXUIElement for cross-isolation write-back

### Design Notes
- Extraction priority: selection > full text > nil (100KB cap)
- Write-back prefers `kAXSelectedTextAttribute` (targeted), falls back to full `kAXValueAttribute` splice
- Capability probing tests if app supports `kAXValueAttribute` with `isAttributeSettable`
- Cache persists to `~/Library/Application Support/OpenGram/ax-cache.json`
- Backward-compat logic handles old flat dict → new struct format (migration debt)

---

## Hotkey (`OpenGram/Hotkey/`)

Global hotkey detection using CGEventTap. Fires even when OpenGram is not frontmost.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `HotkeyManagerProtocol.swift` | 12 | `HotkeyManagerProtocol` | DI contract: install, uninstall, onHotkeyFired callback |
| `HotkeyManager.swift` | 164 | `HotkeyManager` class | CGEventTap install, Ctrl+Shift+G detection, health monitoring |
| `EventTapBridge.swift` | 15 | Free function | C callback bridge: extracts HotkeyManager from Unmanaged, delegates |

### Design Notes
- Hotkey hardcoded: Ctrl+Shift+G (`kVK_ANSI_G = 0x05`)
- CGEventTap can silently disable after ~5s of macOS throttling — health timer auto-reinstalls
- Sleep/wake observer detects when tap needs re-registration
- `@unchecked Sendable` — callback bridge crosses isolation boundaries (documented trade-off)
- CapsLock flag explicitly filtered out of modifier check

---

## Shell (`OpenGram/Shell/`)

Menu bar presence: icon, menu, animated state transitions.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `StatusBarController.swift` | 62 | `StatusBarController` class | NSStatusItem owner. Routes state to IconStateMachine. Flash on inactive hotkey |
| `IconStateMachine.swift` | 104 | `IconStateMachine` class | 4-state machine (idle/checking/checkingLLM/done). Pulse animation, auto-revert timers |
| `MenuBuilder.swift` | 45 | `MenuBuilder` class | Builds NSMenu: status text, Settings, Quit. Target-action dispatch |

### State Machine
```
idle ──► checking ──► checkingLLM ──► done ──► idle (3s auto)
                          │                      ▲
                          └──────────────────────┘ (if LLM not configured)
```
- Pulse animation: 0.5s interval, opacity toggle
- Done → idle: 3s delay
- Silent fail → idle: 0.5s delay

---

## SuggestionUI (`OpenGram/SuggestionUI/`)

Overlay rendering, popover display, underline management, suggestion acceptance. Largest module.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `OverlayController.swift` | ~630 | `OverlayController` class | Window, underlines, popover, acceptance, AX write, event monitoring. Coordinate transforms extracted to `toLocalEntries()` helper |
| `BoundsValidator.swift` | 285 | `BoundsValidator` struct | AX bounds validation, coordinate flip, multi-line splitting, per-app quirks |
| `LLMSettingsView.swift` | 257 | `LLMSettingsView`, `LLMSettingsPanel` | SwiftUI settings form for LLM provider config. Keychain for API key |
| `PopoverView.swift` | 175 | `PopoverView`, `PopoverAnimationState` | SwiftUI popover card: inline diff, replacement, alternatives |
| `WhitelistSettingsView.swift` | 116 | `WhitelistSettingsView` | SwiftUI whitelist management UI |
| `LLMSuggestionPanel.swift` | 105 | `LLMSuggestionPanel` | SwiftUI panel showing 1-3 LLM style suggestions |
| `PanelPositioner.swift` | 30 | `PanelPositioner` enum | Shared prefer-above/flip-below positioning with screen-edge clamping |
| `LLMPanelController.swift` | ~75 | `LLMPanelController` class | NSPanel host for LLMSuggestionPanel. Uses PanelPositioner |
| `AXCallWatchdog.swift` | 98 | `AXCallWatchdog` class | Hang detection (>0.8s), app blocklist (30s), busy guard |
| `UnderlineView.swift` | 96 | `UnderlineEntry`, `UnderlineView` class | NSView: colored underlines. Dashed for LLM. Hit-test passthrough |
| `InlineDiffView.swift` | 89 | `InlineDiffView` | SwiftUI word-level LCS diff rendering |
| `TargetAppObserver.swift` | 83 | `TargetAppObserver`, `DismissContext` | AXObserver lifecycle for target app deactivation |
| `SuggestionDiffEngine.swift` | 68 | `SuggestionKey`, `SuggestionDiffResult`, `SuggestionDiffEngine` | Content-based suggestion matching for diff-merge updates |
| `SuggestionPopoverPanel.swift` | 61 | `SuggestionPopoverPanel` class | NSPanel: non-activating, positioned above/below underline |
| `OverlayWindow.swift` | 35 | `OverlayWindow` class | Transparent NSPanel for underline rendering |

### Key Abstractions
- **OverlayController**: Coordinates all UI. Owns window, underlines, popover, event monitors
- **BoundsValidator**: Translates AX coordinate space → screen space. Handles per-app quirks
- **PanelPositioner**: Shared positioning utility used by SuggestionPopoverPanel + LLMPanelController
- **SuggestionDiffEngine**: Enables incremental updates without UI tearing
- **AXCallWatchdog**: Protects against hanging AX calls (shared singleton)

### Design Notes
- AppKit for overlays (NSPanel with transparent background), SwiftUI for content views
- Positioning logic duplicated between SuggestionPopoverPanel and LLMPanelController
- OverlayController maintains parallel arrays (suggestions + scalarOffsets) — fragile invariant
- Coordinate transforms appear in 3 places within OverlayController (show/update/repositionAfterAccept)

---

## Logging (`OpenGram/Logging/`)

Unified os.log infrastructure replacing scattered print/NSLog calls.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `Log.swift` | 12 | `Log` enum | Factory for `os.Logger` instances scoped by category. Subsystem = bundle ID |

### Design Notes
- All modules use `Log.logger(for: "Category")` instead of `print()` or `NSLog()`
- CheckOrchestrator and LLMService already used os.log — now all modules do
- Categories match module names: "HotkeyManager", "DictionaryStore", "TextMonitor", etc.

---

## Permissions (`OpenGram/Permissions/`)

First-run accessibility permission onboarding.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `PermissionGuide.swift` | 143 | `PermissionGuide` class | Custom NSPanel with manual frame layout. CTA opens System Preferences |

### Design Notes
- Manual frame-based layout (100+ lines of y-offset stacking) — no Auto Layout
- Hardcoded English strings, no i18n
- Shown once if AX trust check fails at launch

---

## AppQuirks (`OpenGram/AppQuirks/`)

Per-app workarounds for AX API behavioral differences.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `AppQuirksTable.swift` | 54 | `AppQuirk` struct, `AppQuirksTable` class | Loads AppQuirks.plist. O(1) lookup by bundle ID |

### Quirk Fields
- `coordinateOffsetX/Y` — bounds correction
- `lineHeightFactor` — multi-line threshold
- `boundsStrategy` — rangeBounds vs skipMultiLine
- `notificationUnreliable` — pre-classified AX notification unreliability (e.g., Chrome)

### Design Notes
- Singleton (`AppQuirksTable.shared`)
- Loaded from bundled plist resource
- Silent failure if plist missing — no error logging

---

## TextMonitor (`OpenGram/TextMonitor/`)

Continuous text change detection using hybrid AX notification + polling.

### Files

| File | Lines | Types | Purpose |
|------|-------|-------|---------|
| `TextMonitor.swift` | ~330 | `TextMonitor` class | AX observer lifecycle, polling, debounce, app-switch handling |
| `ReliabilityDetector.swift` | ~50 | `ReliabilityDetector` struct | Tracks notification/poll correlation, promotes/demotes reliability |

### Internal State
- AX observer: `axObserver`, `observedElement`, `observedPID`, `observedBundleID`
- Change tracking: `debounceWork`, `pollTimer`, `lastKnownText`, `reliabilityDetector`
- App switching: `appSwitchObserver`, `appSwitchDebounce`
- Task management: `checkTask`, `unmanagedContext`
- Safety: `stopped` flag prevents UAF in C callback after stop()

### Flow
```
start() → subscribe to NSWorkspace.didActivateApplication
  → installOnFocusedElement()
    → whitelist gate
    → validate text element
    → install AXObserver (kAXValueChangedNotification)
    → start poll timer if reliability unknown

AX notification → handleValueChanged() → 800ms debounce → runCheck()
Poll (1s)       → pollForChanges()     → detect change  → runCheck()

runCheck() → verify element focus → extract text → CheckOrchestrator → callbacks
```

### Design Notes
- `@MainActor` — all AX calls must be on main thread
- Hybrid approach handles unreliable AX notifications across apps
- ReliabilityDetector encapsulates notification/poll tracking (was inline in TextMonitor)
- Pre-classified unreliable apps via AppQuirksTable
- `stopped` flag in MonitorContext handler prevents UAF on concurrent stop/callback
- Poll path validates element still focused before AX read (F-10 fix)
- 800ms debounce prevents rapid-fire checks during typing
- App-switch debounce: 100ms to allow focus to settle
