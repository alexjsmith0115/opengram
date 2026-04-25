---
phase: 12-settings-ui-severity-filter-acknowledgements
plan: 01
subsystem: ui
tags: [swiftui, notificationcenter, userdefaults, harper, ffi, clarity, swift6-concurrency]

# Dependency graph
requires:
  - phase: 09-rust-foundation-mapphraselinter-spike
    provides: HarperService.setRuleEnabled(key:enabled:) FFI passthrough
  - phase: 10-matcher-implementation
    provides: WordyPhrases rule key registered in harper-bridge
provides:
  - Notification.Name.clarityMasterDidChange (rawValue "ClarityMasterDidChange")
  - AppDelegate.harperService stored property (was local let)
  - AppDelegate observer that maps notification → setRuleEnabled("WordyPhrases", _)
affects:
  - 12-02 (HarperService severity filter — same toggle ecosystem)
  - 12-03 (Settings UI — Clarity tab posts the notification this plan installs)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NotificationCenter observer install in applicationDidFinishLaunching, teardown in applicationWillTerminate (mirrors OpenGramConfig.didChangeNotification)"
    - "UserDefaults.standard.object(forKey:) as? Bool ?? <default> read pattern for @AppStorage-backed keys (avoids Pitfall 2 where .bool(forKey:) returns false for unset keys)"
    - "Capture HarperService actor directly (weak) in @Sendable observer closure — avoids cross-actor self capture under Swift 6 strict concurrency"

key-files:
  created:
    - OpenGramTests/SuggestionUITests/ClarityNotificationTests.swift
  modified:
    - OpenGram/CheckEngine/Suggestion.swift
    - OpenGram/App/AppDelegate.swift
    - OpenGramTests/AppDelegateWiringTests.swift
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "Capture harperService directly in observer closure (not self) to satisfy Swift 6 @Sendable / sending-parameter checks — AppDelegate is not Sendable, HarperService actor is."
  - "Read clarityEnabled via object(forKey:) as? Bool ?? true (not .bool(forKey:)) so the unset-key default matches the @AppStorage default of ON (Pitfall 2)."
  - "Synthetic-observer test pattern (Plan 01 Task 3 test_strategy) verifies dispatch logic on a fresh NotificationCenter; Plan 03 manual checkpoint #2 covers the AppDelegate install path end-to-end."

patterns-established:
  - "Cross-actor closure capture: prefer capturing the Sendable actor directly when the enclosing object is non-Sendable"
  - "AppDelegate notification observers paired with applicationWillTerminate teardown using stored NSObjectProtocol token"

requirements-completed:
  - CLAR-07

# Metrics
duration: ~10 min
completed: 2026-04-25
---

# Phase 12 Plan 01: Master Clarity Toggle Plumbing Summary

**Notification.Name.clarityMasterDidChange + retained AppDelegate.harperService + observer that calls `setRuleEnabled("WordyPhrases", <bool>)` on toggle, no relaunch.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-25T10:07:00Z (approx — worktree setup)
- **Completed:** 2026-04-25T10:17:37Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified) + pbxproj

## Accomplishments
- `Notification.Name.clarityMasterDidChange` extension added with stable rawValue `"ClarityMasterDidChange"` and drift-guard test
- `AppDelegate.harperService` promoted from local `let` to retained `private var` so observer can dispatch FFI calls post-launch
- Observer installed in `applicationDidFinishLaunching` → reads `clarityEnabled` from UserDefaults with `?? true` fallback → spawns Task to call `await harperService?.setRuleEnabled(key: "WordyPhrases", enabled: <value>)`
- Observer torn down in `applicationWillTerminate` (Pitfall 3 leak guard)
- Two synthetic-observer dispatch tests cover both default-fallback and explicit-false paths

## Task Commits

Each task committed atomically:

1. **Task 1: Add clarityMasterDidChange notification + drift-guard test** — `76cd51f` (test)
2. **Task 2: Promote AppDelegate.harperService + install observer** — `f8c30fd` (feat)
3. **Task 3: Observer-dispatch unit tests** — `9d4ca13` (test)

## Files Created/Modified
- `OpenGram/CheckEngine/Suggestion.swift` — Added `Notification.Name.clarityMasterDidChange` extension at end of file
- `OpenGram/App/AppDelegate.swift` — Promoted harperService to stored property, added clarityObserver, install/teardown wiring
- `OpenGramTests/AppDelegateWiringTests.swift` — Extended MockGrammarChecker with `ruleToggleCalls`, added 2 dispatch tests
- `OpenGramTests/SuggestionUITests/ClarityNotificationTests.swift` (new) — drift-guard test for notification name rawValue
- `OpenGram.xcodeproj/project.pbxproj` — PBXBuildFile + PBXFileReference + group child + Sources phase entries for new test file (IDs `B10000010000000000000202` / `B20000010000000000000202`)

## Decisions Made
- **Closure capture pattern:** Used `[weak harperService]` instead of `[weak self]` in the notification observer + spawned Task. Swift 6 strict concurrency rejected `self` capture across the `@Sendable` boundary because `AppDelegate` is not Sendable. `HarperService` is an actor (Sendable), so capturing it directly weak-references the only object the closure needs.
- **UserDefaults read style:** `object(forKey: "clarityEnabled") as? Bool ?? true` (not `.bool(forKey:)`) — the latter returns `false` for unset keys, which would silently disable Clarity on a fresh install before any toggle interaction. RESEARCH Pitfall 2 documents this hazard.
- **Test seam:** Tests verify the dispatch logic by mirroring AppDelegate's pattern on a fresh `NotificationCenter()` + injected `UserDefaults(suiteName:)`. AppDelegate is hard to instantiate in unit tests without lifecycle replay; Plan 03 manual checkpoint #2 covers the install-path gap end-to-end (per Task 3 test_strategy block).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict-concurrency violation on `[weak self]` capture in observer's spawned Task**
- **Found during:** Task 2 (initial build after applying the plan-prescribed observer code)
- **Issue:** Build failed with `error: passing closure as a 'sending' parameter risks causing data races between code in the current task and concurrent execution of the closure` and `warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure`. Plan-prescribed code captured `[weak self]` in the inner `Task { ... }`, but `AppDelegate` is not declared `Sendable`.
- **Fix:** Replaced both inner and outer captures with `[weak harperService]`. `HarperService` is an actor (Sendable by definition), and the closure only needs access to harperService — not any other AppDelegate state. The semantic intent is preserved: if AppDelegate has been deallocated, harperService will also have been (it's owned by AppDelegate's stored property), so the weak reference still nil-coalesces correctly.
- **Files modified:** `OpenGram/App/AppDelegate.swift`
- **Verification:** `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` exits 0 with no warnings related to the closure
- **Committed in:** `f8c30fd` (Task 2 commit — fix included before commit)

---

**Total deviations:** 1 auto-fixed (1 bug — Swift 6 concurrency)
**Impact on plan:** Fix is semantically equivalent to the plan's prescription; no scope change. Plan should be updated in retrospect to recommend capturing the actor directly rather than `[weak self]` for any AppDelegate observer that touches an actor.

## Issues Encountered
- None beyond the Swift 6 concurrency fix above.

## User Setup Required
None — no external service configuration, no env vars, no secrets. Pure intra-process wiring.

## Next Phase Readiness
- **Plan 12-02 ready:** HarperService severity filter post-processing can read the same `clarityEnabled` / `clarityOpinionatedEnabled` keys; the notification install pattern here is reusable if 12-02 needs reactive teardown of the filter.
- **Plan 12-03 ready:** ClaritySettingsView can post `.clarityMasterDidChange` on @AppStorage `.onChange` and the observer installed here will dispatch the FFI call. The literal `"clarityEnabled"` key string is now load-bearing in three places (AppDelegate observer, future Settings view @AppStorage, and the unit tests) — recommend a static constant when 12-03 lands to enable a drift-guard test similar to AdvancedSettingsViewTests.
- **No blockers.**

## Self-Check

Verifying claimed artifacts exist + commits landed:

- `OpenGram/CheckEngine/Suggestion.swift` — FOUND (modified)
- `OpenGram/App/AppDelegate.swift` — FOUND (modified)
- `OpenGramTests/AppDelegateWiringTests.swift` — FOUND (modified)
- `OpenGramTests/SuggestionUITests/ClarityNotificationTests.swift` — FOUND (created)
- `OpenGram.xcodeproj/project.pbxproj` — FOUND (modified)
- Commit `76cd51f` — FOUND
- Commit `f8c30fd` — FOUND
- Commit `9d4ca13` — FOUND

## Self-Check: PASSED

---
*Phase: 12-settings-ui-severity-filter-acknowledgements*
*Completed: 2026-04-25*
