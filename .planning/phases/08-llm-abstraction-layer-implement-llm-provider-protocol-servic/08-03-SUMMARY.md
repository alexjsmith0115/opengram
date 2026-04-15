---
phase: 08-llm-abstraction-layer
plan: 03
subsystem: suggestion-ui
tags: [llm, swiftui, keychain, testing, settings-ui]

requires:
  - phase: 08-01
    provides: LLMService, LLMConfig, LLMPrompts, LLMProviderProtocol
  - phase: 08-02
    provides: CheckOrchestrator with hardFilter, runCheck

provides:
  - LLMSettingsPanel: NSPanel manager for SwiftUI LLM settings view
  - LLMSettingsView: SwiftUI form with endpoint URL, Keychain API key, check toggles, temperature slider, test connection
  - MenuBuilder.onSettingsTapped callback connecting settings menu item to panel
  - StatusBarController owns LLMSettingsPanel and wires the callback
  - Full test suite: LLMServiceTests (11), LLMPromptsTests (5), CheckOrchestratorTests (5)
  - KeychainAccess registered as XCRemoteSwiftPackageReference in project.pbxproj

affects: [08-settings-integration, phase-05-tabbed-settings]

tech-stack:
  added: [KeychainAccess registered in pbxproj as XCRemoteSwiftPackageReference]
  patterns: [NSPanel+NSHostingView for SwiftUI-in-AppKit panels, onSettingsTapped callback pattern, TextContext.stub() test factory]

key-files:
  created:
    - OpenGram/SuggestionUI/LLMSettingsView.swift
    - OpenGramTests/LLMServiceTests.swift
    - OpenGramTests/LLMPromptsTests.swift
    - OpenGramTests/CheckOrchestratorTests.swift
  modified:
    - OpenGram/Shell/MenuBuilder.swift
    - OpenGram/Shell/StatusBarController.swift
    - OpenGramTests/MenuBuilderTests.swift
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "Used onSettingsTapped callback on MenuBuilder (not AppDelegate selector) to avoid cross-file ownership conflicts — StatusBarController owns the panel and wires the callback in init"
  - "KeychainAccess added as XCRemoteSwiftPackageReference in pbxproj — was in Package.swift only before, which masked the missing registration for xcodebuild"
  - "StubGrammarChecker defined locally in CheckOrchestratorTests to avoid cross-file test dependency on AppDelegateWiringTests.MockGrammarChecker"
  - "MenuBuilderTests updated to expect Unicode ellipsis (U+2026) in settings title — intentional change to match macOS convention"

requirements-completed: [LLM-01, LLM-02, LLM-03, LLM-04, LLM-05, LLM-07]

duration: 25min
completed: 2026-04-15
---

# Phase 08 Plan 03: LLM Settings UI and Test Suite Summary

**LLMSettingsView NSPanel with Keychain API key storage, test connection indicator, and 21-case test suite covering JSON parsing, prompts, and orchestrator dedup**

## Performance

- **Duration:** 25 min
- **Started:** 2026-04-15T03:10:00Z
- **Completed:** 2026-04-15T03:36:00Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- LLMSettingsView SwiftUI form with all UI-SPEC fields: endpoint URL, API key (SecureField, Keychain-backed), check type toggles, temperature slider with hints, Test Connection with inline icon+text indicators, Save button
- LLMSettingsPanel class wrapping view in NSPanel following PermissionGuide pattern
- MenuBuilder gains `onSettingsTapped: (() -> Void)?` callback; settings item uses Unicode ellipsis and `,` key equivalent
- StatusBarController owns `LLMSettingsPanel` and wires callback in `init()`
- KeychainAccess properly registered in `project.pbxproj` as `XCRemoteSwiftPackageReference` (was SPM-only before)
- 11 LLMServiceTests: clean JSON, markdown fences, preamble strip, brace-match fallback, garbage, empty string, config defaults, isEnabled variants, chatCompletionsURL
- 5 LLMPromptsTests: non-empty per type, grammar-skip clause, JSON-only instruction, harper spans inclusion/exclusion
- 5 CheckOrchestratorTests: hardFilter overlap, non-overlap, empty harper ranges, empty LLM list, Harper-only nil LLM (LLM-07)
- All 236 tests pass

## Task Commits

1. **Task 1: LLMSettingsView + MenuBuilder + StatusBarController + pbxproj** - `fa8fa3e` (feat)
2. **Task 2: LLMServiceTests + LLMPromptsTests + CheckOrchestratorTests** - `458f99a` (test)

## Files Created/Modified

- `OpenGram/SuggestionUI/LLMSettingsView.swift` — LLMSettingsPanel + LLMSettingsView with full UI-SPEC layout
- `OpenGram/Shell/MenuBuilder.swift` — Added `onSettingsTapped` callback, Unicode ellipsis title, `,` key equivalent
- `OpenGram/Shell/StatusBarController.swift` — Added `settingsPanel`, wired `onSettingsTapped` in `init()`
- `OpenGramTests/LLMServiceTests.swift` — 11 test cases (JSON parsing + config)
- `OpenGramTests/LLMPromptsTests.swift` — 5 test cases (prompt content verification)
- `OpenGramTests/CheckOrchestratorTests.swift` — 5 test cases + TextContext.stub() + StubGrammarChecker
- `OpenGramTests/MenuBuilderTests.swift` — Updated to expect Unicode ellipsis in settings title
- `OpenGram.xcodeproj/project.pbxproj` — New file refs, build phase entries, KeychainAccess SPM registration

## Decisions Made

- `onSettingsTapped` callback on MenuBuilder avoids AppDelegate ownership conflict between parallel plans
- `StubGrammarChecker` defined locally in test file avoids coupling to AppDelegateWiringTests
- KeychainAccess `XCRemoteSwiftPackageReference` added to pbxproj — Package.swift SPM entry existed but was never wired into the Xcode project, causing build failure on first import

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed MenuBuilderTests title mismatch caused by Unicode ellipsis change**
- **Found during:** Task 2 test run
- **Issue:** `MenuBuilderTests.swift` expected `"Settings..."` (ASCII 3 dots) but MenuBuilder now uses `"Settings\u{2026}"` (Unicode ellipsis) as specified in the plan
- **Fix:** Updated `MenuBuilderTests.swift` line 44 to match the new Unicode ellipsis title
- **Files modified:** `OpenGramTests/MenuBuilderTests.swift`
- **Commit:** `458f99a`

**2. [Rule 3 - Blocking] KeychainAccess missing from project.pbxproj**
- **Found during:** Task 1 build verification
- **Issue:** `import KeychainAccess` in LLMSettingsView.swift failed — KeychainAccess was in Package.swift for SPM CLI but was never registered as an `XCRemoteSwiftPackageReference` in project.pbxproj
- **Fix:** Added `XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency`, `packageProductDependencies` on OpenGram target, `packageReferences` on project, and `PBXBuildFile` for the framework product
- **Files modified:** `OpenGram.xcodeproj/project.pbxproj`
- **Commit:** `fa8fa3e`

## Known Stubs

None — all fields are wired to live storage (AppStorage for non-secrets, KeychainAccess for API key).

## Threat Flags

No new security-relevant surface beyond what was specified in the plan's threat model (T-08-10 through T-08-12 all addressed: SecureField masking, Keychain storage, AppStorage acceptance for non-secrets).

## Self-Check

Verifying claims:

- `OpenGram/SuggestionUI/LLMSettingsView.swift` — exists
- `OpenGramTests/LLMServiceTests.swift` — exists
- `OpenGramTests/LLMPromptsTests.swift` — exists
- `OpenGramTests/CheckOrchestratorTests.swift` — exists
- Commit `fa8fa3e` — exists
- Commit `458f99a` — exists
- All 236 tests pass — confirmed by xcodebuild TEST SUCCEEDED

## Self-Check: PASSED
