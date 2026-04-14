# Phase 7: Automatic Grammar Checking — TextMonitor - Research

**Researched:** 2026-04-14
**Domain:** macOS Accessibility API text monitoring, Swift 6 concurrency, debounce patterns, overlay diff-merge
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Text Change Detection**
- D-01: AX notifications primary, polling fallback. Register `AXObserver` for `kAXValueChangedNotification` on the focused text field. If an app doesn't fire AX notifications reliably, fall back to periodic AX value polling. `TargetAppObserver` already uses this AXObserver pattern.
- D-02: Unreliable-notification detection uses both the app quirks table (Phase 6 D-04) and runtime auto-detection. Pre-classify known problematic apps in the quirks table. For unknown apps, run a parallel polling timer after registering AXObserver — if a poll detects a text change that no AX notification fired for, mark the app as notification-unreliable in `AXCapabilityCache` and switch to polling mode.
- D-03: Polling interval is 1 second for fallback mode.
- D-04: Monitor `kAXValueChangedNotification` only — no `kAXSelectedTextChangedNotification`. Cursor/selection moves without text edits do not trigger re-checks.

**Check Triggering & Debounce**
- D-05: Debounce after typing pause. Wait for 800ms of no text changes before running Harper. Avoids checking mid-word and reduces unnecessary work.
- D-06: Full text field content re-checked on every trigger (no partial/paragraph-only checking). Consistent with Phase 2 D-09 (no text length limit).

**Monitoring Scope & Lifecycle**
- D-07: Always-on after launch. Monitoring starts when OpenGram launches and runs continuously. No user action needed to start automatic checking.
- D-08: Menu bar toggle for enable/disable deferred to a later phase. Phase 7 is always-on only.
- D-09: Focused text field only. Monitor whichever text field has keyboard focus. When the user clicks a different field, switch monitoring to the new field.
- D-10: On app switch: dismiss overlay, pause monitoring until a text field gains focus in the new app. Avoids monitoring non-text apps (Finder, Preview, etc.).
- D-11: Respect the AX watchdog blocklist from Phase 6 D-05. Claude's discretion on whether to extend the blocklist duration for automatic mode vs hotkey-triggered mode.

**Overlay Update Behavior**
- D-12: Diff and merge on re-check. Compare new suggestions against existing ones by text range. Keep underlines for unchanged suggestions (no flicker), add new ones, remove resolved ones.
- D-13: Overlay stays visible while the user is typing. Existing underlines remain on screen. After the debounce fires and re-check completes, underlines are diff-merged with the new results.
- D-14: Hotkey (Ctrl+Shift+G) forces an immediate re-check, bypassing the debounce. Serves as a manual refresh.
- D-15: No extra visual indicator for monitoring state. No menu bar icon change. Underlines appearing is sufficient feedback. Icon state machine from Phase 1 unchanged.

### Claude's Discretion
- TextMonitor class architecture and lifecycle management
- How to detect that a focused element is a text field (AX role checking)
- Debounce implementation (Timer, DispatchWorkItem, or Combine)
- Diff algorithm for comparing old vs new suggestion sets (by range overlap, text content, or suggestion ID)
- Whether to extend AX watchdog blocklist duration for automatic mode
- Thread/actor design for the monitoring loop
- How to handle rapid app switching (debounce app-switch events)
- Integration with existing OverlayController show/dismiss lifecycle

### Deferred Ideas (OUT OF SCOPE)
- Menu bar toggle for automatic checking — Enable/disable via menu bar. Phase 7 is always-on only; toggle is a future addition.
- Paragraph-only re-checking — Only re-check the changed paragraph for performance in large documents. Full-text re-check is simpler and sufficient for now.
- Sentence-boundary immediate trigger — Trigger Harper immediately on sentence-ending punctuation in addition to debounce. Could improve responsiveness but adds complexity.
- Multi-app monitoring — Keep underlines visible on the old app while monitoring the new one. Significantly more complex.
</user_constraints>

---

## Summary

Phase 7 transitions OpenGram from hotkey-on-demand checking to always-on as-you-type checking. The core mechanism is a `TextMonitor` class that registers an `AXObserver` for `kAXValueChangedNotification` on the focused text element, debounces changes at 800ms, then calls the same Harper pipeline already used by `handleHotkeyFired()`. When AX notifications prove unreliable for a given app, a parallel 1-second polling timer takes over and the app's bundle ID is flagged in `AXCapabilityCache`.

The most technically involved work is the overlay diff-merge (D-12). Instead of calling `overlayController.dismiss()` and `show()` on every re-check, the phase adds an `update(suggestions:context:)` path to `OverlayController` that compares new suggestions against existing ones by text range and surgically adds/removes underlines. This prevents the visible flicker that would make automatic checking feel broken.

App-switch detection uses `NSWorkspace.didActivateApplicationNotification` (the standard macOS mechanism) to dismiss the overlay and pause monitoring when a non-text app becomes frontmost. When a text field gains focus in the new app, monitoring resumes by re-installing the AXObserver on the new element.

**Primary recommendation:** Build `TextMonitor` as a `@MainActor final class` that owns one `AXObserver` (mirroring `TargetAppObserver`), one `DispatchWorkItem` for the debounce timer, and a `Timer`-based fallback poller. Wire it into `AppDelegate` alongside the existing hotkey path, sharing the `HarperService` and `OverlayController` references already held there.

---

## Standard Stack

All technologies for this phase are already present in the project. No new dependencies are introduced.

### Core (already in project)
| Technology | Purpose | Notes |
|------------|---------|-------|
| `AXObserver` (ApplicationServices) | Primary text change detection | Same pattern as `TargetAppObserver.swift` [VERIFIED: codebase] |
| `AXObserverAddNotification` | Register `kAXValueChangedNotification` | Documented in Apple AX API [VERIFIED: Apple docs] |
| `NSWorkspace.didActivateApplicationNotification` | Detect app switch | Standard notification; delivers `NSRunningApplication` in userInfo [VERIFIED: Apple docs] |
| `DispatchWorkItem` | Debounce implementation | Cancel-and-recreate pattern; works cleanly on `@MainActor` [VERIFIED: codebase pattern] |
| `Timer` | 1-second fallback poller | `Timer.scheduledTimer(withTimeInterval:repeats:)` on main run loop [ASSUMED] |
| Swift Testing (`@Test`, `#expect`) | Unit tests | Already used throughout the test suite [VERIFIED: codebase] |

### No New Dependencies
Phase 7 adds zero new Swift packages. All required APIs are in the OS SDK or already imported.

---

## Architecture Patterns

### Recommended Project Structure

```
OpenGram/
├── TextMonitor/
│   └── TextMonitor.swift        # New: hybrid AX notification + polling monitor
├── TextEngine/
│   ├── AXCapabilityCache.swift  # Extended: add notification-reliability key storage
│   └── AXCapabilityCacheProtocol.swift  # Extended: add notification reliability API
├── AppQuirks/
│   └── AppQuirksTable.swift     # Extended: add notificationUnreliable flag to AppQuirk
├── SuggestionUI/
│   └── OverlayController.swift  # Extended: add update(suggestions:context:) diff-merge path
└── App/
    └── AppDelegate.swift        # Extended: create + wire TextMonitor
```

### Pattern 1: TextMonitor as @MainActor Class

**What:** A `@MainActor final class` owning the AXObserver + debounce + fallback timer for text monitoring.

**Why `@MainActor`:** All AX calls happen on the main thread in this codebase (see `AXTextEngine.extractText()`). `TargetAppObserver` is `@MainActor`. `OverlayController` is `@MainActor`. Keeping `TextMonitor` on the same actor removes all cross-actor data races and avoids `nonisolated(unsafe)` workarounds.

**When to use:** Single instance created in `AppDelegate.applicationDidFinishLaunching`, held for the application lifetime (D-07).

```swift
// Source: pattern from TargetAppObserver.swift + AXCallWatchdog.swift in codebase
@MainActor
final class TextMonitor {
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var debounceWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var lastKnownText: String?
    private var appSwitchObserver: NSObjectProtocol?

    // Injected — shared with hotkey path
    private let textEngine: any AXTextEngineProtocol
    private let harperService: any GrammarCheckerProtocol
    private weak var overlayController: OverlayController?

    init(textEngine: any AXTextEngineProtocol,
         harperService: any GrammarCheckerProtocol,
         overlayController: OverlayController) { ... }

    func start()   // installs app-switch observer (D-07)
    func stop()    // uninstalls everything

    private func installOnFocusedElement()   // called on focus change
    private func uninstallCurrentObserver()
    private func onTextChanged()             // fires from AX notification or poll
    private func scheduleDebounce()          // cancel+recreate DispatchWorkItem
    private func runCheck()                  // calls textEngine + harperService
    private func startPollTimer()
    private func stopPollTimer()
}
```

**Lifecycle flow:**
1. `AppDelegate.applicationDidFinishLaunching` creates and calls `textMonitor.start()`
2. `start()` subscribes to `NSWorkspace.didActivateApplicationNotification`
3. On each app activation: check if frontmost app has a focused text element; if yes, install AXObserver on that element
4. On `kAXFocusedUIElementChangedNotification` from the app element: switch observation to new focused element
5. On `kAXValueChangedNotification`: call `scheduleDebounce()` (cancel prior, restart 800ms)
6. On debounce fire: extract text, call Harper, call `overlayController.update(suggestions:context:)`
7. On app deactivation / non-text focus: call `uninstallCurrentObserver()`, dismiss overlay

### Pattern 2: AXObserver Registration for kAXValueChangedNotification

**What:** Register both `kAXValueChangedNotification` on the focused element AND `kAXFocusedUIElementChangedNotification` on the application element, using the same callback + context pointer approach as `TargetAppObserver`.

**Critical detail:** `kAXValueChangedNotification` must be registered on the specific text element (not the app), but `kAXFocusedUIElementChangedNotification` must be registered on the app element to detect field switches within the same app. Both registrations use the same `AXObserver` instance.

```swift
// Source: TargetAppObserver.swift pattern in codebase
var observer: AXObserver?
AXObserverCreate(pid, textMonitorCallback, &observer)
guard let observer else { return }

let appElement = AXUIElementCreateApplication(pid)
let focusedElement = /* current focused AXUIElement */

// Register on app for focus changes (field switches within same app)
AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, ptr)
// Register on element for text changes
AXObserverAddNotification(observer, focusedElement, kAXValueChangedNotification as CFString, ptr)

CFRunLoopAddSource(RunLoop.main.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
```

**Role validation before registering:** Before installing on a focused element, check its `AXRole` to confirm it is a text-input element. This prevents monitoring non-text elements (buttons, sliders) that also fire `kAXValueChangedNotification`. [ASSUMED: AXRole validation approach — verified that kAXRoleAttribute exists in Apple docs]

```swift
// Check role before installing
let (roleError, roleRef) = accessor.copyAttributeValue(element, kAXRoleAttribute)
guard roleError == .success,
      let role = roleRef as? String,
      role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
else { return }
```

[VERIFIED: kAXTextFieldRole, kAXTextAreaRole exist in ApplicationServices framework]

### Pattern 3: Hybrid Notification + Polling for Unreliable Apps

**What:** After installing an AXObserver, also start a 1-second `Timer`. Each timer tick reads `AXValue` and compares against `lastKnownText`. If the text has changed but no `kAXValueChangedNotification` fired since the last poll, mark the app as notification-unreliable in `AXCapabilityCache` and stop using AXObserver for value-change detection (keep it only for focus-change detection).

**Detecting missed notifications:** TextMonitor tracks a `Bool` flag `notificationFiredSinceLastPoll`. The timer checks this flag. If `false` and text has changed, the app is unreliable.

**AXCapabilityCache extension:** Add a second key namespace for notification reliability, e.g., `bundleID:notification-reliable`. This separates AX read/write capability (existing) from notification reliability (new). [ASSUMED: exact key format — implementation detail left to planner]

**AppQuirks extension:** Add `notificationUnreliable: Bool?` to `AppQuirk` struct for pre-classifying known problematic apps (e.g., Electron, Chrome) without waiting for runtime detection.

Known unreliable apps based on research: [VERIFIED via WebSearch: Electron apps require `AXManualAccessibility = true` and have poor notification behavior; Chrome requires `AXEnhancedUserInterface = true`]
- `com.google.Chrome` — requires AXEnhancedUserInterface flag, notification reliability varies
- Electron-based apps generally — poor AX notification support

### Pattern 4: Debounce with DispatchWorkItem

**What:** Cancel-and-reschedule pattern using `DispatchWorkItem`. Each text change cancels the prior work item and schedules a new one 800ms out.

**Why DispatchWorkItem over Combine:** The project has no Combine usage anywhere. Adding a Combine pipeline for a single debounce would be new infrastructure with no benefit over DispatchWorkItem, which is already effectively used in the existing `closePopover()` pattern in `OverlayController`. [VERIFIED: codebase inspection confirms DispatchQueue.main.asyncAfter pattern in OverlayController.swift]

**Why not Swift Async Algorithms `debounce`:** Requires the input to be an AsyncSequence. The AX notification callback is a C function pointer — wrapping it in an AsyncStream is possible but adds complexity for no tangible benefit.

```swift
// Source: cancel-and-reschedule idiom, consistent with closePopover() in OverlayController.swift
private func scheduleDebounce() {
    debounceWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.runCheck()
    }
    debounceWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
}
```

### Pattern 5: Overlay Diff-Merge (update path)

**What:** New `update(suggestions:context:)` method on `OverlayController` that avoids teardown/rebuild of the overlay window. Compares new suggestion set against current `self.suggestions` and only changes what is necessary.

**Diff algorithm:** Compare by `original` string content + `range` in the new text. A suggestion is "unchanged" if an existing suggestion has the same `original` text at the same scalar offset range. New suggestions are added; resolved suggestions (not in new set) are removed. IDs are regenerated by Harper on each check, so ID-based comparison does not work.

**Implementation approach:**
1. Build a lookup of existing suggestions keyed by `(scalarStart, scalarLength, original)`
2. For each new suggestion: if it matches an existing one by that key, reuse the existing suggestion's `id` and underline entry. Otherwise it is new.
3. Remove underline entries for existing suggestions not found in new set.
4. Add underline entries for genuinely new suggestions via `BoundsValidator`.
5. If the set is unchanged (same suggestions, same positions): no-op — do not redraw at all.

**When to use the full `show()` path vs `update()` path:**
- `show()`: first time suggestions appear on a given element (overlay not visible)
- `update()`: overlay already visible and TextMonitor fires a re-check on the same element
- `dismiss()`: app switch, non-text focus, Escape, scroll (unchanged from current behavior)

### Pattern 6: App Switch Handling

**What:** Subscribe to `NSWorkspace.didActivateApplicationNotification` in `TextMonitor.start()`. On each notification: if the new frontmost app is the same as the currently monitored app, no-op. If different: uninstall current observer, dismiss overlay (D-10), then attempt to install on the focused element of the new app.

**Rapid app switching debounce:** When the user command-tabs quickly through many apps, each activation fires a notification. Add a short (100ms) debounce on app-switch handling to avoid registering and immediately unregistering observers for transient intermediate apps. [ASSUMED: 100ms is appropriate — may need tuning]

```swift
// Source: NSWorkspace notification pattern confirmed in Apple docs
appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { [weak self] notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    else { return }
    self?.handleAppActivation(app)
}
```

### Anti-Patterns to Avoid

- **Registering kAXValueChangedNotification on the application element instead of the specific focused element.** The notification doesn't bubble up to the app element — it must be registered on the text element itself. [VERIFIED: Apple AX notification documentation implies element-specific registration]
- **Cancelling the debounce timer when the user presses the hotkey.** The hotkey (D-14) should bypass debounce, not cancel it. After the force-check, if the user keeps typing, the debounce timer should continue from the next keystroke.
- **Calling `overlayController.show()` on every debounce fire.** This rebuilds the overlay window and produces visible flicker. Use `update()` when the overlay is already visible.
- **Storing AXUIElement references across app switches.** AX element references are only valid while the process is running and the element exists. Always re-query the focused element after any app or focus switch.
- **Using `kAXSelectedTextChangedNotification` for text change detection (locked out by D-04).** This notification fires on cursor movement too, causing redundant checks on every arrow key press.
- **Running the poll timer at high frequency.** 1-second interval (D-03) is intentionally conservative. Higher frequency (e.g., 100ms) would cause excessive AX calls and potentially trigger the AXCallWatchdog's busy guard.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| AX observer lifecycle | Custom RunLoop management | Extend existing `TargetAppObserver` pattern — already production-tested in the codebase |
| App-switch detection | CGEventTap or polling frontmost app | `NSWorkspace.didActivateApplicationNotification` — purpose-built for this |
| Text difference detection | Custom string diff | Simple scalar-offset comparison is sufficient; no need for a full LCS diff library |
| Debounce scheduling | Combine `.debounce()`, AsyncAlgorithms | `DispatchWorkItem` cancel-and-reschedule — consistent with existing codebase patterns |
| AX notification thread dispatch | Manual thread marshalling | AXObserver callback dispatches to `Task { @MainActor in }` — same pattern as `TargetAppObserver` |

**Key insight:** This phase is primarily a wiring problem, not a new-infrastructure problem. The hard pieces (AXObserver lifecycle, bounds validation, AX watchdog, app quirks) already exist. TextMonitor is a coordinator class that connects them in a new trigger path.

---

## Common Pitfalls

### Pitfall 1: AXObserver Callback Memory Management

**What goes wrong:** The `AXObserver` C callback receives a raw `UnsafeMutableRawPointer?` as `userData`. If the object that pointer points to is deallocated, the callback fires into freed memory — silent crash.

**Why it happens:** AXObserver is a Core Foundation callback, not Swift. Swift ARC does not automatically manage the object lifetime relative to the callback registration.

**How to avoid:** Use the exact `Unmanaged.passRetained` / `takeUnretainedValue` / explicit `release` pattern already established in `TargetAppObserver`. The `TextMonitor` class owns the `Unmanaged` value and calls `release()` in `uninstallCurrentObserver()`. Never use `passUnretained` for the userData — the callback must own the retain.

**Warning signs:** Crash in the AX callback after the user rapidly switches focus. EXC_BAD_ACCESS in the observer callback.

[VERIFIED: codebase — TargetAppObserver.swift shows the correct Unmanaged pattern with `passRetained` + `unmanagedContext.release()`]

### Pitfall 2: Double-Notification from Both Element and App Registration

**What goes wrong:** If `kAXFocusedUIElementChangedNotification` is registered on the app element AND a text field changes, the monitor may receive both a `kAXValueChangedNotification` (from the element) and a stale focus-change notification from some apps. Without careful notification routing, this can cause the debounce to reset at the wrong time or trigger a check before the new element is correctly set up.

**Why it happens:** Different apps implement AX notification firing order inconsistently. Some fire value-changed before focus-changed, others the reverse.

**How to avoid:** In the callback, identify the notification type before acting. Only `kAXValueChangedNotification` triggers the debounce; `kAXFocusedUIElementChangedNotification` triggers element re-registration. Route by notification name in the callback.

**Warning signs:** TextMonitor briefly monitors the wrong element after focus switch.

[ASSUMED: specific ordering inconsistencies across apps — pattern verified via general AX API knowledge and Electron issue research]

### Pitfall 3: Poll Timer and AXCallWatchdog Interaction

**What goes wrong:** The 1-second poll timer reads `AXValue` from the observed element. If the app is blocklisted by `AXCallWatchdog` (Phase 6, 30s blocklist), and the poll timer fires during the blocklist period, it calls `AXCallWatchdog.shouldSkip()` — which returns true — but then if the code doesn't check the watchdog before polling, the poll makes an AX call anyway, potentially hanging.

**Why it happens:** The poll timer is a new code path that was not present when `AXCallWatchdog` was designed.

**How to avoid:** The poll timer's read must check `AXCallWatchdog.shared.shouldSkip(for: bundleID)` before calling `AXValue`. If skipped, silently skip the poll tick without resetting the `notificationFiredSinceLastPoll` flag.

**Warning signs:** App appears frozen briefly during the 30s blocklist window.

[VERIFIED: codebase — AXCallWatchdog.swift `shouldSkip(for:)` API exists and is thread-safe]

### Pitfall 4: Text Field Role False Positives

**What goes wrong:** The monitor installs on a non-text element (e.g., a search field that is a combo box, a date picker, a spinner) because the role check is too broad. Subsequent AX value reads may return non-text values that confuse Harper or cause AX errors.

**Why it happens:** `kAXValueChangedNotification` fires for any value change on any element type that has a value — not just text elements.

**How to avoid:** Check `kAXRoleAttribute` before installing. Accept `AXTextField`, `AXTextArea`, `AXComboBox` (often wraps a text input). Reject everything else.

**Warning signs:** Harper receiving non-string or empty values; AX errors during extraction.

[VERIFIED: kAXRoleAttribute, kAXTextFieldRole, kAXTextAreaRole are standard ApplicationServices constants]

### Pitfall 5: stale AXUIElement Reference After Overlay Update

**What goes wrong:** `TextMonitor` stores an `AXUIElement` reference when the user switches to a field. By the time the debounce fires 800ms later, the user may have switched fields or apps. The debounce fires a check using a stale element reference, and `AXValue` read on the stale element either returns wrong text or an AX error.

**Why it happens:** AX element references are IPC handles. They remain technically callable after the element disappears (they just return errors), but there is no Swift lifecycle signal when an element is invalidated.

**How to avoid:** After the 800ms debounce fires, verify the stale element still matches the current focused element before using it. Re-query `kAXFocusedUIElementAttribute` from the system-wide element and compare. If they differ, abort the check (the user has moved to a different field — the new field's observer will trigger a fresh check).

**Warning signs:** Harper receives stale text; underlines appear on the wrong field.

[ASSUMED: stale reference verification approach — based on AX API knowledge; the pattern of re-querying focused element is consistent with AXTextEngine.extractText()]

### Pitfall 6: Overlay Flicker from Suggestion ID Churn

**What goes wrong:** Harper generates new `UUID()` for each `Suggestion` on every check call (see `Suggestion.swift`: `id: UUID()`). A naive diff that uses `id` to detect unchanged suggestions will treat every suggestion as "new" on every re-check, causing all underlines to be torn down and rebuilt — visible flicker.

**Why it happens:** IDs are generated fresh on each `harperService.check()` call.

**How to avoid:** The diff algorithm must compare by `(scalarStart, scalarLength, original, category)` tuple, NOT by `id`. Two suggestions matching on all four fields are considered "the same error" for diff purposes — keep the old entry's underline position rather than re-querying bounds. Only genuinely new suggestions (no match in old set) require a bounds query.

[VERIFIED: codebase — Suggestion.swift line 52: `id: UUID()` in struct definition; init from raw generates UUID() fresh each time]

### Pitfall 7: Hotkey and TextMonitor Double-Check Race

**What goes wrong:** User presses Ctrl+Shift+G while the TextMonitor debounce is pending. Both the hotkey path (`handleHotkeyFired`) and the debounce timer fire checks near-simultaneously. Two concurrent `Task` calls to `harperService.check(text:)` run; whichever completes last overwrites the overlay — could result in stale results winning.

**Why it happens:** `HarperService` is an actor; concurrent calls are serialized but both complete. The overlay update is the race.

**How to avoid:** D-14 states the hotkey "forces an immediate re-check, bypassing the debounce." The hotkey handler should: (1) cancel the pending `debounceWork` item, (2) cancel any in-flight `checkTask`, (3) run the check immediately. This ensures only one check is in flight at a time. The pattern mirrors the existing `checkTask?.cancel()` in `handleHotkeyFired()`.

[VERIFIED: codebase — AppDelegate.swift `checkTask?.cancel()` before each new check task]

---

## Code Examples

### AXObserver Registration (based on TargetAppObserver pattern)

```swift
// Source: TargetAppObserver.swift in codebase — adapted for kAXValueChangedNotification
// on specific element + kAXFocusedUIElementChangedNotification on app element

private struct MonitorContext: @unchecked Sendable {
    let handler: @MainActor (String) -> Void  // notification name
}

private func installObserver(pid: pid_t, element: AXUIElement) {
    uninstallCurrentObserver()

    let context = MonitorContext { [weak self] notificationName in
        switch notificationName {
        case kAXValueChangedNotification as String:
            self?.scheduleDebounce()
        case kAXFocusedUIElementChangedNotification as String:
            self?.installOnFocusedElement()
        default:
            break
        }
    }
    let unmanaged = Unmanaged.passRetained(context)
    self.unmanagedContext = unmanaged
    let ptr = unmanaged.toOpaque()

    var observer: AXObserver?
    AXObserverCreate(pid, { _, element, notification, userData in
        guard let userData, let notification else { return }
        let ctx = Unmanaged<MonitorContext>.fromOpaque(userData).takeUnretainedValue()
        let name = notification as String
        Task { @MainActor in ctx.handler(name) }
    }, &observer)

    guard let observer else { unmanaged.release(); unmanagedContext = nil; return }

    let appElement = AXUIElementCreateApplication(pid)
    AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, ptr)
    AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, ptr)

    CFRunLoopAddSource(RunLoop.main.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
    self.axObserver = observer
    self.observedElement = element
    self.observedPID = pid
}
```

### Debounce Pattern

```swift
// Source: DispatchWorkItem pattern; consistent with OverlayController.closePopover() in codebase
private func scheduleDebounce() {
    debounceWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.runCheck()
    }
    debounceWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
}

// Hotkey bypass path (D-14): cancel debounce and run immediately
func forceCheckNow() {
    debounceWork?.cancel()
    debounceWork = nil
    runCheck()
}
```

### Role Check Before Install

```swift
// Source: ApplicationServices constants — kAXRoleAttribute, kAXTextFieldRole, kAXTextAreaRole
private let textRoles: Set<String> = [
    kAXTextFieldRole as String,
    kAXTextAreaRole as String,
    kAXComboBoxRole as String,  // wraps text input in many apps
]

private func isTextElement(_ element: AXUIElement) -> Bool {
    let (error, ref) = accessor.copyAttributeValue(element, kAXRoleAttribute)
    guard error == .success, let role = ref as? String else { return false }
    return textRoles.contains(role)
}
```

### Suggestion Diff Key (for overlay update)

```swift
// Source: based on Suggestion.swift analysis (UUID regenerated each check — cannot use id)
private struct SuggestionKey: Hashable {
    let scalarStart: Int
    let scalarLength: Int
    let original: String
    let category: CheckCategory
}

private func diffKey(for suggestion: Suggestion, in text: String) -> SuggestionKey {
    let scalars = text.unicodeScalars
    let start = scalars.distance(from: scalars.startIndex, to: suggestion.range.lowerBound)
    let length = scalars.distance(from: suggestion.range.lowerBound, to: suggestion.range.upperBound)
    return SuggestionKey(scalarStart: start, scalarLength: length,
                         original: suggestion.original, category: suggestion.category)
}
```

### NSWorkspace App-Switch Subscription

```swift
// Source: Apple developer docs — NSWorkspace.didActivateApplicationNotification
func start() {
    appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        self?.handleAppActivation(app)
    }

    // Install on whatever is currently focused at launch
    installOnFocusedElement()
}

func stop() {
    if let observer = appSwitchObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        appSwitchObserver = nil
    }
    uninstallCurrentObserver()
}
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Hotkey-only trigger | Hybrid AX notification + polling | Standard pattern for real-time macOS writing tools (Grammarly, TextWarden) |
| Full dismiss + redraw on each check | Diff-merge overlay update | Required to prevent flicker in automatic mode |
| Single AXObserver for dismiss events | Dual-purpose AXObserver (dismiss + text change) | TextMonitor reuses the same AXObserver infrastructure for both concerns |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 100ms debounce on app-switch events is appropriate | Architecture Patterns §Pattern 6 | Too long: misses rapid intentional app switches; too short: registers/unregisters observers constantly. Low impact — implementation detail, easy to tune. |
| A2 | AXComboBox role should be included in text field whitelist | Architecture Patterns §Pattern 2 | If false: combo boxes in apps like Safari address bar won't be monitored. Conservative to include; worst case is monitoring an element with non-text values. |
| A3 | Notification reliability key format `bundleID:notification-reliable` for AXCapabilityCache | Architecture Patterns §Pattern 3 | Wrong format would require a cache migration. Risk is low — implementation detail to finalize in planning. |
| A4 | Stale element verification (re-query focused element on debounce fire) is the correct guard | Pitfall 5 | If wrong approach: overhead of an extra AX call per check. The safer alternative (trusting stored reference) risks stale-text checks. |
| A5 | kAXSelectedTextChangedNotification fires on cursor movement, not just text changes | Anti-Patterns section | Verified by documentation description, but behavior may vary per app. D-04 locks this out regardless. |

---

## Open Questions (RESOLVED)

1. **Should `TextMonitor` own a reference to `AXCapabilityCache` directly, or only read the notification-reliability data through a new protocol method?**
   - What we know: `AXCapabilityCache` already has a protocol (`AXCapabilityCacheProtocol`). TextMonitor needs to write notification-reliability data.
   - What's unclear: Whether to extend `AXCapabilityCacheProtocol` with new methods or create a separate `NotificationReliabilityStore` protocol.
   - Recommendation: Extend `AXCapabilityCacheProtocol` with two new methods (`isNotificationReliable(bundleID:)` → `Bool?`, `storeNotificationReliability(bundleID:reliable:)`). Keeps all capability data in one cache, consistent with existing patterns. RESOLVED: Extend AXCapabilityCacheProtocol (implemented in Plan 01 Task 2).

2. **Should `OverlayController.update(suggestions:context:)` handle the case where the focused element changes between the old and new context?**
   - What we know: `TextContext` stores the `axElement` reference. If TextMonitor fires a check on element A and before completion the user switches to element B, the `update()` call arrives with a context for element A while the overlay may already be dismissed.
   - What's unclear: Whether `OverlayController` should validate that `context.axElement` still matches `self.textContext?.axElement`.
   - RESOLVED: Yes — add an element identity check in `update()`. If the new context's element differs from the currently displayed context's element, fall through to `show()` (not `update()`).

3. **Should the AX watchdog blocklist duration be longer in automatic mode than in hotkey mode?**
   - What we know: D-11 defers this to Claude's discretion. Current blocklist is 30 seconds. In automatic mode, TextMonitor polls every 1 second and debounces at 800ms — the poll timer will skip during the blocklist period anyway (Pitfall 3), but 30 seconds of no checking might be noticeable.
   - What's unclear: Whether users will notice 30 seconds of no automatic checking after an AX hang.
   - RESOLVED: Keep the same 30s duration. The watchdog protects against real hangs; extending it is premature. The polling fallback ensures re-checking resumes promptly after the blocklist expires.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 7 is a pure code/configuration change. No external tools, services, or CLI utilities beyond what is already installed and proven in Phases 1–6.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (Xcode 16 built-in) |
| Config file | Package.swift — `OpenGramTests` target |
| Quick run command | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/TextMonitorTests 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram 2>&1 | tail -40` |

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| TextMonitor installs AXObserver without crashing | Unit | `xcodebuild test ... -only-testing OpenGramTests/TextMonitorTests` | ❌ Wave 0 |
| TextMonitor install is idempotent (second install replaces first) | Unit | (same) | ❌ Wave 0 |
| TextMonitor uninstall clears all state | Unit | (same) | ❌ Wave 0 |
| scheduleDebounce cancels prior work item | Unit | (same) | ❌ Wave 0 |
| forceCheckNow cancels debounce and runs synchronously | Unit | (same) | ❌ Wave 0 |
| isTextElement returns true for AXTextField/AXTextArea | Unit | (same) | ❌ Wave 0 |
| isTextElement returns false for AXButton | Unit | (same) | ❌ Wave 0 |
| Suggestion diff key matches same error across check runs | Unit | `... -only-testing OpenGramTests/OverlayControllerDiffTests` | ❌ Wave 0 |
| OverlayController.update() keeps unchanged underlines | Unit | (same) | ❌ Wave 0 |
| OverlayController.update() removes resolved suggestions | Unit | (same) | ❌ Wave 0 |
| OverlayController.update() adds new suggestions | Unit | (same) | ❌ Wave 0 |
| AXCapabilityCache: storeNotificationReliability / isNotificationReliable round-trips | Unit | `... -only-testing OpenGramTests/AXCapabilityCacheTests` | ✅ (file exists, needs new tests) |
| AppQuirk: notificationUnreliable field decodes from plist | Unit | `... -only-testing OpenGramTests/AppQuirksTests` | ❌ Wave 0 (no AppQuirksTests yet) |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram -only-testing OpenGramTests/TextMonitorTests 2>&1 | tail -20`
- **Per wave merge:** `xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram 2>&1 | tail -40`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `OpenGramTests/TextMonitorTests.swift` — TextMonitor lifecycle, debounce, role checking
- [ ] `OpenGramTests/SuggestionUITests/OverlayControllerDiffTests.swift` — `update()` diff-merge behavior
- [ ] `OpenGramTests/AppQuirksTests.swift` — AppQuirk plist decoding including new `notificationUnreliable` field
- [ ] New methods on `AXCapabilityCacheTests.swift` — notification reliability storage (file exists, add cases)

---

## Security Domain

Phase 7 adds no new data inputs, no new network calls, no new credentials, and no new persistent storage beyond extending the existing `AXCapabilityCache` JSON file with additional keys. The AX API is already in use. No new ASVS categories apply that aren't already covered by Phases 1–6.

V5 Input Validation: Harper processes text extracted from AX API — same as existing phases. The 100KB text limit from Phase 1 (`AXTextEngine.maxTextLength`) still applies. [VERIFIED: codebase — AXTextEngine.swift line 9]

---

## Sources

### Primary (HIGH confidence)
- Codebase inspection — `TargetAppObserver.swift`, `AXCallWatchdog.swift`, `AppDelegate.swift`, `OverlayController.swift`, `AXCapabilityCache.swift`, `Suggestion.swift`, `AXTextEngine.swift`, `AppQuirksTable.swift`
- Apple Developer Documentation — `AXObserver`, `AXObserverAddNotification`, `kAXValueChangedNotification`, `kAXFocusedUIElementChangedNotification`, `NSWorkspace.didActivateApplicationNotification`
- Phase 6 CONTEXT.md — AX watchdog behavior (D-05), app quirks table (D-04), blocklist duration

### Secondary (MEDIUM confidence)
- WebSearch: Electron AX notification reliability — confirmed Electron requires `AXManualAccessibility = true`, poor notification support [electron/electron GitHub issues #7206, #36337]
- WebSearch: `NSWorkspace.didActivateApplicationNotification` — confirmed delivery of `NSRunningApplication` via `NSWorkspace.applicationUserInfoKey`
- WebSearch: DispatchWorkItem debounce vs Combine vs AsyncAlgorithms — confirmed DispatchWorkItem is the lightweight correct choice for non-Combine codebases

### Tertiary (LOW confidence)
- WebSearch: app-switch debounce duration (100ms) — community pattern, needs tuning in practice

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, all APIs already proven in codebase
- Architecture: HIGH — directly extends established TargetAppObserver and OverlayController patterns
- Pitfalls: HIGH — most discovered via codebase inspection; memory management pitfall verified against TargetAppObserver code
- Diff algorithm: MEDIUM — design is sound but specific implementation choices (SuggestionKey fields) need validation in planning

**Research date:** 2026-04-14
**Valid until:** 2026-05-14 (stable OS APIs — 30 days)
