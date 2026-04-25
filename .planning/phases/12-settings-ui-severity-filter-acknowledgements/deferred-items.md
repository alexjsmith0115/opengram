# Deferred Items — Phase 12

## Pre-existing test failures (full-suite run during Plan 12-02 verification)

The following 6 test failures exist on the base branch (commit 6b1f45e) and are
unrelated to Plan 12-02's HarperService severity-filter work. They were observed
when running the full `xcodebuild test` suite as the wave-merge verification gate
required by Plan 12-02. Plan 12-02 only touches HarperService.swift +
HarperServiceTests.swift; the failures below are in AX/scroll/LLM subsystems.

| Test | Suite | File | Likely cause |
|------|-------|------|--------------|
| `shouldSkipReturnsTrueForBundleIDAddedToBlocklistAfterTimeout` | AXCallWatchdog | AXCallWatchdogTests.swift:22 | timing-sensitive blocklist expiry test |
| `blocklistEntryExpiresAfterBlocklistDurationAndShouldSkipReturnsFalse` | AXCallWatchdog | AXCallWatchdogTests.swift:32 | timing-sensitive blocklist expiry test |
| `onTickFiresAtLeastOnceWhileNoteScrollEventIsCalledPeriodically` | ScrollTracker | ScrollTrackerTests.swift:55 | timing-sensitive tick scheduling |
| `onIdleFiresExactlyOnceAfterIdleTimeoutElapsesWithNoNewEvents` | ScrollTracker | ScrollTrackerTests.swift:67 | timing-sensitive idle detection |
| `hideAndSettleScrollEventFadesUnderlinesTo0AndSetsFaded` | OverlayController scroll mode | OverlayControllerScrollModeTests.swift:66 | timing/animation alpha-value race |
| LLM target test (cancellation/timeout flows) | LLMService | (multiple) | `localhost:1234` LLM endpoint not running in test env |

All HarperService tests (15/15, including the 5 new severity-filter +
WordyPhrases tests) PASS. Full app build (`xcodebuild build`) succeeds.

These failures are out-of-scope for Plan 12-02 per execute-plan.md scope-boundary
rules. They should be addressed in their own plans.
