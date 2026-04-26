# OpenGram Architecture

> System-wide macOS grammar checker. Two-tier checking: Harper (Rust, instant, deterministic) + optional LLM (user-configured, style/clarity). Menu bar app, global hotkey, overlay UI rendered over target app windows.

## System Overview

```
                        +-------------------+
                        |   Menu Bar Icon   |  (StatusBarController + IconStateMachine)
                        +--------+----------+
                                 |
                   +-------------+-------------+
                   |        AppDelegate         |  Composition root (77 lines).
                   |  (lifecycle, DI wiring)    |  Delegates to CheckCoordinator.
                   +--+------+------+------+---+
                      |      |      |      |
         +------------+  +---+---+  |  +---+--------+
         |               |       |  |  |             |
   +-----v-----+  +-----v--+ +--v--v--v--------+  +-v--------------+
   | HotkeyMgr |  | TextMon| | CheckCoordinator|  | OverlayCtrl    |
   | (CGEvent   |  | (AX obs| | (hotkey, check  |  | (window, under |
   |  Tap)      |  |  + poll)|  pipeline, state)|  |  lines, popovr)|
   +------------+  +---+----+ +--+----------+--+  +---+------------+
                       |         |          |          |
                  +----v----+ +--v------+ +-v------+  |
                  |AXTextEng| |CheckOrch| |LLMSvc  |  |
                  |(extract, | |(Harper+ | |(OpenAI |  |
                  | write)   | | LLM)   | | compat)|  |
                  +----+-----+ +--------+ +--------+  |
                       |                               |
                  +----v---------+              +------v-------+
                  | AXAccessor   |              | BoundsValid. |
                  | (C API wrap) |              | (coord xform)|
                  +--------------+              +--------------+
```

## Data Flow

### Hotkey-Triggered Check (Primary Flow)

```
1. User presses Ctrl+Shift+G
2. HotkeyManager (CGEventTap) fires callback
3. CheckCoordinator gates on AppWhitelist (is target app allowed?)
4. AXTextEngine extracts text from focused element
   - Selection preferred, full text fallback, 100KB cap
5. CheckOrchestrator.runCheck() — two phases:
   Phase 1: Harper (sync, ~10ms)
     → GrammarSuggestion[] → mapped to Suggestion[]
     → onHarperComplete callback fires
   Phase 2: LLM (async, ~1-5s, if configured)
     → ParagraphExtractor scopes text (selection > paragraph > 2000 chars)
     → LLMService POST to /v1/chat/completions
     → LLMResponseDTO parsed → LLMStyleSuggestion[] → mapped to Suggestion[]
     → onLLMBatch callback fires per batch
     → onLLMFinished callback fires at end
6. CheckCoordinator routes suggestions to OverlayController
7. OverlayController renders:
   - Underlines (UnderlineView) positioned via BoundsValidator
   - Popover (SuggestionPopoverPanel + PopoverView) on underline click
   - LLM panel (LLMPanelController + LLMSuggestionPanel) below overlay
```

### Continuous Monitoring (TextMonitor Flow)

```
1. TextMonitor.start() subscribes to NSWorkspace activation notifications
2. On app focus → installOnFocusedElement():
   a. Whitelist gate
   b. Validate text element (role check)
   c. Install AXObserver for kAXValueChangedNotification
   d. Start poll timer if notification reliability unknown
3. On text change (notification or poll detection):
   a. 800ms debounce
   b. Extract text via AXTextEngine
   c. Route to CheckOrchestrator
4. Hybrid reliability detection (via ReliabilityDetector):
   - ReliabilityDetector.recordNotification() on AX notification
   - ReliabilityDetector.evaluatePollTick() on each poll
   - 5 consecutive matched ticks → .promoted → stop polling
   - Change without notification → .markedUnreliable → keep polling
5. On app switch → uninstall observer, reinstall on new app
```

### Suggestion Acceptance Flow

```
1. User clicks suggestion in popover
2. OverlayController.acceptSuggestion():
   a. Compute replacement text
   b. Try AXSelectedText write (preferred)
   c. Fallback: full AXValue write with range splice
   d. Reposition remaining underlines (scalar offset adjustment)
   e. Remove accepted suggestion from state
```

## Module Map

| Module | Directory | Purpose | Key Types |
|--------|-----------|---------|-----------|
| **App** | `OpenGram/App/` | Entry point, lifecycle, DI wiring, check pipeline | AppDelegate, CheckCoordinator, ConfigManager, AppWhitelist, AppState |
| **CheckEngine** | `OpenGram/CheckEngine/` | Two-tier grammar/style checking pipeline | CheckOrchestrator, HarperService, LLMService, Suggestion |
| **TextEngine** | `OpenGram/TextEngine/` | AX API text extraction and write-back | AXTextEngine, AXAccessor, AXCapabilityCache, TextContext |
| **Hotkey** | `OpenGram/Hotkey/` | Global hotkey detection via CGEventTap | HotkeyManager, EventTapBridge |
| **Shell** | `OpenGram/Shell/` | Menu bar icon, menu, state animation | StatusBarController, IconStateMachine, MenuBuilder |
| **SuggestionUI** | `OpenGram/SuggestionUI/` | Overlay rendering, popover, underlines | OverlayController, BoundsValidator, PanelPositioner, PopoverView, UnderlineView |
| **Logging** | `OpenGram/Logging/` | Unified os.log infrastructure | Log |
| **Permissions** | `OpenGram/Permissions/` | AX permission onboarding | PermissionGuide |
| **AppQuirks** | `OpenGram/AppQuirks/` | Per-app AX behavior workarounds | AppQuirksTable, AppQuirk |
| **TextMonitor** | `OpenGram/TextMonitor/` | Continuous text change detection | TextMonitor, ReliabilityDetector |
| **Generated** | `OpenGram/Generated/` | UniFFI-generated Harper bindings | HarperBridge.swift (auto-generated) |

## Dependency Graph (Module Level)

```
App ──────► CheckEngine ──► harper-bridge (Rust FFI)
 │              │
 │              └──► LLMService (URLSession)
 │
 ├──► TextEngine ──► AXAccessor (C API)
 │        │
 │        └──► AXCapabilityCache
 │
 ├──► Hotkey (CGEventTap)
 │
 ├──► Shell (NSStatusBar)
 │
 ├──► SuggestionUI ──► TextEngine (for write-back)
 │        │
 │        ├──► BoundsValidator ──► AXAccessor + AppQuirks
 │        │
 │        └──► PanelPositioner (shared positioning utility)
 │
 ├──► TextMonitor ──► TextEngine
 │        │
 │        ├──► CheckEngine
 │        │
 │        ├──► AXCapabilityCache
 │        │
 │        └──► ReliabilityDetector
 │
 ├──► Logging (os.log)
 │
 └──► Permissions
```

## Key Design Decisions

### Two-Tier Checking Architecture
Harper runs synchronously (~10ms) for instant grammar/spelling feedback. LLM runs asynchronously (1-5s) for style/clarity. Results merge via content-based diffing (SuggestionDiffEngine) to avoid tearing during incremental updates.

### AppDelegate → CheckCoordinator Separation
AppDelegate is a thin composition root (77 lines) that only handles lifecycle and dependency construction. CheckCoordinator owns the check pipeline: hotkey handling, suggestion state management, overlay/panel routing, LLM suggestion application. ConfigManager provides static access to LLM config (UserDefaults) and API keys (Keychain).

### Hybrid AX Notification + Polling
macOS AX notifications are unreliable across apps (some never fire, some fire inconsistently). TextMonitor uses a hybrid approach: installs AXObserver AND polls every 1s. ReliabilityDetector (extracted value type) tracks notification/poll correlation — promotes to notification-only after 5 consecutive matches. AppQuirksTable pre-classifies known-unreliable apps (e.g., Chrome).

### Actor Isolation for Check Pipeline
CheckOrchestrator, HarperService, and LLMService are Swift actors. This provides thread safety for concurrent Harper + LLM execution. LLM requests are shielded from cancellation via Task.detached to prevent orphaned network calls.

### AppKit Overlays (Not SwiftUI)
Overlay windows use AppKit NSPanel with `styleMask: []`, `backgroundColor: .clear`, `level: .floating`. SwiftUI cannot create transparent windows that layer over arbitrary third-party apps. Popovers and settings views use SwiftUI hosted inside AppKit containers.

### Content-Based Suggestion Matching
SuggestionDiffEngine matches suggestions by content (category + offset + replacement) not UUID. This allows stable identity across check cycles — critical for smooth diff-merge updates without popover flicker.

### PanelPositioner (Shared Utility)
Both SuggestionPopoverPanel and LLMPanelController use `PanelPositioner.origin(for:near:on:gap:)` for prefer-above/flip-below positioning with screen-edge clamping. Eliminates previous duplication.

### AXCallWatchdog
Some apps hang indefinitely on AX calls. AXCallWatchdog detects calls exceeding 0.8s, blocklists the app for 30s, and implements a busy guard to prevent concurrent AX calls.

### Unified Logging
All modules use `Log.logger(for:)` which returns an `os.Logger` scoped by category. Replaces scattered `print()` and `NSLog()` calls. Subsystem is always the app bundle identifier.

### Configurable Confidence Threshold
LLM confidence threshold (default: 9) is defined once in `LLMConfig.defaultConfidenceThreshold` and threaded through LLMPrompts (prompt text), LLMResponseDTO/LLMService parsing, and LLMRequestQueue provider-result filtering. Single source of truth.

## Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Language | Swift 6.0 | Strict concurrency enabled |
| Grammar Engine | harper-core 2.0.0 (Rust) | Via UniFFI 0.31.0 FFI bridge |
| UI Framework | AppKit (overlays) + SwiftUI (settings, popovers) | Mixed, by design |
| Text Access | Accessibility API (AXUIElement) | Requires `com.apple.security.accessibility` entitlement |
| Hotkey | CGEventTap | Global key interception |
| LLM | URLSession → OpenAI-compatible API | User-configured endpoint |
| Secrets | Keychain (via KeychainAccess 4.2.2) | API keys only |
| Logging | os.log (via Log utility) | Per-module category scoping |
| Build | Xcode 16+ / SPM | Xcode project is canonical build system |
| Platform | macOS 14.0+ (Sonoma) | Direct .dmg distribution (no App Store) |

## File Statistics

- **Source files:** 47 (excluding Generated/HarperBridge.swift)
- **Test files:** 31
- **Total test cases:** 274
- **Largest files:** OverlayController (~630), TextMonitor (~330), CheckCoordinator (~200)
- **Smallest composition root:** AppDelegate (77 lines)
