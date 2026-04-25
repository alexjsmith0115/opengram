---
phase: 12-settings-ui-severity-filter-acknowledgements
plan: 03
subsystem: suggestion-ui
tags: [swiftui, settings-panel, appstorage, bundle-resource, mit-license, pbxproj, info-plist, swift-testing]

requires:
  - phase: 12-settings-ui-severity-filter-acknowledgements
    plan: 01
    provides: Notification.Name.clarityMasterDidChange (consumed by AppDelegate observer)
  - phase: 12-settings-ui-severity-filter-acknowledgements
    plan: 04
    provides: AcknowledgementsManager / source attribution layer (decoupled — Plan 03 only ships the UI shell + bundle resource)
provides:
  - "ClaritySettingsView — master toggle (clarityEnabled, default ON) + sub-toggle (clarityOpinionatedEnabled, default OFF)"
  - "ClaritySettingsView.notifyMasterChanged(center:) — injectable test seam for .clarityMasterDidChange"
  - "ClaritySettingsView.isSubToggleDisabled(masterOn:) — pure predicate mirroring .disabled() modifier"
  - "AboutSettingsView — version + scrollable bundled MIT license (init-injectable licenseText for tests)"
  - "AboutSettingsView.defaultCopyrightString — drift-guard constant matching Info.plist NSHumanReadableCopyright"
  - "OpenGram/Resources/THIRD_PARTY.txt — bundled plain-text MIT (retext-simplify) + plainlanguage.gov sections"
  - "5-tab SettingsView (LLM Provider / Clarity / Whitelisted Apps / Advanced / About) at 400×600"
  - "Info.plist NSHumanReadableCopyright (Debug + Release) — 'Copyright © 2026 OpenGram. Bundles retext-simplify dataset (MIT, © 2016 Titus Wormer).'"
affects:
  - "AppDelegate observer (already wired by Plan 01) — receives master-toggle posts on user interaction"
  - "Phase 12 v1.4 milestone surface — user-facing acknowledgements + clarity controls now visible"

tech-stack:
  added: []
  patterns:
    - "Drift-guard static constants on SwiftUI views (e.g. defaultCopyrightString, clarityEnabledKey) — assert against pbxproj/literals via Swift Testing"
    - "init(licenseText: String? = nil) injection pattern — keeps Bundle.main resolution out of unit tests (RESEARCH Pitfall 6: test bundle ≠ app bundle)"
    - "Pure-function test seams (isSubToggleDisabled, notifyMasterChanged) — mirror SwiftUI modifiers for assertion without ViewInspector"

key-files:
  created:
    - OpenGram/SuggestionUI/Settings/ClaritySettingsView.swift
    - OpenGram/SuggestionUI/Settings/AboutSettingsView.swift
    - OpenGram/Resources/THIRD_PARTY.txt
    - OpenGramTests/SuggestionUITests/ClaritySettingsViewTests.swift
    - OpenGramTests/SuggestionUITests/AboutSettingsViewTests.swift
  modified:
    - OpenGram/SuggestionUI/Settings/LLMSettingsView.swift
    - OpenGram.xcodeproj/project.pbxproj

key-decisions:
  - "Bundle license at app-level (Bundle.main + Resources phase), not test-level — tests inject licenseText explicitly via init"
  - "Drift-guard NSHumanReadableCopyright via @Test, not docs comment — pbxproj string + Swift constant must stay in sync at CI"
  - "Sub-toggle disabled state surfaced via static helper isSubToggleDisabled(masterOn:) — UI-SPEC §Validation Hooks #2 testable without UI runtime"
  - "Single combined commit for pbxproj + SettingsView refactor — xcodebuild only sees a coherent state once (avoids intermediate broken-target commits)"
  - "Frame bumped from 400×500 to 400×600 globally (panel hostingView + window contentRect + SettingsView frame) — license ScrollView needs the vertical room"

patterns-established:
  - "Settings tab integration pattern: new view file in Settings group + PBXBuildFile/PBXFileReference + tab entry in SettingsView TabView with SF Symbol — repeatable for future tabs"
  - "Bundle resource integration: PBXFileReference + PBXBuildFile + Resources PBXGroup + Resources build phase entry — repeatable for any future text/asset bundle"

requirements-completed: [CLAR-17, CLAR-19]

duration: ~12min (Tasks 1+2 autonomous; Task 3 manual deferred)
completed: 2026-04-25
---

# Phase 12 Plan 03: Settings UI (Clarity + About Tabs + Acknowledgements) Summary

**5-tab Settings panel with new Clarity (master+sub-toggle posting `.clarityMasterDidChange`) and About (version + bundled MIT license) tabs; Info.plist `NSHumanReadableCopyright` wired in Debug+Release; 8 unit tests green; manual visual checkpoint deferred to user (computer-use MCP cannot reach the dev-built .app outside /Applications).**

## Performance

- **Duration:** ~12 min (autonomous portion); manual checkpoint pending
- **Started:** 2026-04-25T06:24:00Z (Task 1 file scaffolding)
- **Autonomous portion completed:** 2026-04-25T06:28:22Z (Task 2 commit `b0555af`)
- **Tasks:** 3 total — 2 autonomous (file scaffold + pbxproj wiring), 1 manual checkpoint (deferred)
- **Files created:** 5
- **Files modified:** 2

## Accomplishments

- New `ClaritySettingsView` (67 lines) — `@AppStorage("clarityEnabled")` master + `@AppStorage("clarityOpinionatedEnabled")` sub-toggle; `.disabled(!clarityEnabled)` gates sub-toggle; hint opacity drops to 0.4 when master OFF; master `onChange` posts `.clarityMasterDidChange` via injectable `notifyMasterChanged(center:)` seam
- New `AboutSettingsView` (76 lines) — app name + `CFBundleShortVersionString` (fallback "Unknown") + Acknowledgements section with bordered scrollable `ScrollView` (`controlBackgroundColor` background, `separatorColor` 1pt overlay, 200–280pt height, `cornerRadius` 6); `init(licenseText: String? = nil)` keeps tests off `Bundle.main`
- New `OpenGram/Resources/THIRD_PARTY.txt` (39 lines) — plain-text retext-simplify MIT block + plainlanguage.gov public-domain section (verbatim copy from `THIRD_PARTY.md` minus markdown decoration)
- 8 new Swift Testing tests (4 Clarity + 4 About) — all green: drift-guard `@AppStorage` keys, default values, notification post via injected `NotificationCenter`, sub-toggle disabled predicate, license init paths, fallback string stability, `defaultCopyrightString` ↔ Info.plist drift guard
- `SettingsView` rebuilt as 5-tab `TabView` (LLM Provider / Clarity / Whitelisted Apps / Advanced / About) with SF Symbols (`brain`, `text.magnifyingglass`, `app.badge.checkmark`, `slider.horizontal.3`, `info.circle`); panel + view frames bumped to 400×600
- `pbxproj` wired in single commit: 5 PBXBuildFile + 5 PBXFileReference + new `Resources` PBXGroup inserted into `OpenGram` top-level group + `Settings` group children appended + Resources build phase + Sources build phase (app target) + Sources build phase (test target) + `INFOPLIST_KEY_NSHumanReadableCopyright` in Debug + Release configs
- Generated `Info.plist` confirmed: `NSHumanReadableCopyright` = `"Copyright © 2026 OpenGram. Bundles retext-simplify dataset (MIT, © 2016 Titus Wormer)."` (CLAR-19 satisfied)
- `THIRD_PARTY.txt` confirmed bundled at `OpenGram.app/Contents/Resources/THIRD_PARTY.txt`

## Task Commits

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Create ClaritySettingsView + AboutSettingsView + THIRD_PARTY.txt + tests | `bd80f65` | 5 created (3 swift, 1 txt, 2 tests) |
| 2 | Wire pbxproj + 5-tab SettingsView + Info.plist copyright | `b0555af` | 2 modified (LLMSettingsView.swift, project.pbxproj) |
| 3 | Manual visual validation via computer-use MCP (5 screenshots) | — | **deferred-to-user** |

## Files Created/Modified

**Created:**
- `OpenGram/SuggestionUI/Settings/ClaritySettingsView.swift` (67 lines) — master+sub-toggle view with notification post + drift-guard statics
- `OpenGram/SuggestionUI/Settings/AboutSettingsView.swift` (76 lines) — version + Acknowledgements ScrollView; init-injectable licenseText
- `OpenGram/Resources/THIRD_PARTY.txt` (39 lines) — plain-text MIT (retext-simplify) + plainlanguage.gov sections
- `OpenGramTests/SuggestionUITests/ClaritySettingsViewTests.swift` (36 lines) — 4 `@Test` funcs (keys, defaults, notify, sub-toggle disabled)
- `OpenGramTests/SuggestionUITests/AboutSettingsViewTests.swift` (26 lines) — 4 `@Test` funcs (init paths, fallback stability, copyright drift guard)

**Modified:**
- `OpenGram/SuggestionUI/Settings/LLMSettingsView.swift` — `LLMSettingsPanel.show()` frame 400×500 → 400×600 (hostingView + contentRect); `SettingsView` rebuilt as 5-tab TabView
- `OpenGram.xcodeproj/project.pbxproj` — 5 file refs + 5 build files + new Resources PBXGroup + Settings group children + Resources phase + Sources phases (app + tests) + 2 INFOPLIST_KEY_NSHumanReadableCopyright entries

## Verification

**Automated (Tasks 1+2):**
- `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build`: **BUILD SUCCEEDED** (full app + test bundle)
- `xcodebuild test -only-testing:OpenGramTests/ClaritySettingsViewTests -only-testing:OpenGramTests/AboutSettingsViewTests`: **8/8 PASS**
- `grep -c "ClaritySettingsView.swift in Sources" project.pbxproj` = 2; `AboutSettingsView.swift in Sources` = 2; `THIRD_PARTY.txt in Resources` = 2; `ClaritySettingsViewTests.swift in Sources` = 2; `AboutSettingsViewTests.swift in Sources` = 2; `INFOPLIST_KEY_NSHumanReadableCopyright` = 2 (Debug + Release)
- `plutil -p OpenGram.app/Contents/Info.plist | grep -i "human\|copyright"` → `"NSHumanReadableCopyright" => "Copyright © 2026 OpenGram. Bundles retext-simplify dataset (MIT, © 2016 Titus Wormer)."` (CLAR-19 verified)
- `find ~/Library/Developer/Xcode/DerivedData -name "THIRD_PARTY.txt" -path "*OpenGram.app*"` → `/Users/alex/Library/Developer/Xcode/DerivedData/OpenGram-drugppfgidnzvqckyrykquotwkyd/Build/Products/Debug/OpenGram.app/Contents/Resources/THIRD_PARTY.txt` (resource phase wired correctly)
- `grep -rn "GSD\|Phase 12\|Plan 0"` across all 3 new source files + bundled txt → **0 matches** (no GSD references leaked into source)

**Manual checkpoint (Task 3): DEFERRED-TO-USER**

The plan's checkpoint requires `mcp__computer-use__*` to drive the running app and capture 5 screenshots. The dev build resides at `/Users/alex/Library/Developer/Xcode/DerivedData/OpenGram-drugppfgidnzvqckyrykquotwkyd/Build/Products/Debug/OpenGram.app` — the computer-use MCP `installed-apps` resolver only enumerates apps in `/Applications`, so this autonomous session cannot grant access to a DerivedData binary. Manual visual validation per UI-SPEC §Validation Hooks must be performed by the user after this autonomous run.

User must capture and confirm these 5 states (verbatim from UI-SPEC §Validation Hooks):

1. **Settings panel — Clarity tab open.** Open Settings via menu bar → Click Clarity tab. Confirm: 5-tab strip in order (LLM Provider / Clarity / Whitelisted Apps / Advanced / About), both toggles render, frame is 400×600, no clipping.
2. **Clarity tab — master OFF.** Toggle "Enable Clarity Suggestions" OFF. Confirm: sub-toggle visually greyed (disabled), hint text under sub-toggle reduced opacity (~0.4).
3. **Clarity tab — both ON.** Toggle master back ON, then toggle "Show subjective clarity suggestions" ON. Confirm: both toggles render as active.
4. **About tab.** Click About tab. Confirm: "OpenGram" header, "Version X.Y.Z" line, Acknowledgements section, scrollable bordered ScrollView containing MIT license text starting with "The MIT License (MIT)" and including "Copyright (c) 2016 Titus Wormer". Scroll the box to confirm scrollability.
5. **Notes.app clarity badge.** Open Notes.app → type "Please utilize this for users." → trigger Ctrl+Shift+G. Confirm: solid orange underline under "utilize"; click/hover summons popover with footer reading "Clarity" + `text.magnifyingglass` icon.

To resume manual validation: `open /Users/alex/Library/Developer/Xcode/DerivedData/OpenGram-drugppfgidnzvqckyrykquotwkyd/Build/Products/Debug/OpenGram.app`. Reply "approved" to mark all 5 PASS, or list the deviations + file/line that needs revision.

## Requirements Addressed

- **CLAR-17** — Settings panel Clarity tab with master toggle + sub-toggle wired to `@AppStorage`; sub-toggle disabled-when-master-OFF state; master change posts `.clarityMasterDidChange` (consumed by AppDelegate observer from Plan 01). Drift-guarded constants + Swift Testing coverage.
- **CLAR-19** — Acknowledgements: `THIRD_PARTY.txt` bundled at `OpenGram.app/Contents/Resources/`; About tab renders the MIT license in a scrollable bordered box; `Info.plist` `NSHumanReadableCopyright` set in Debug + Release configs and verified at the built artifact level via `plutil -p`.

## Deviations from Plan

None during autonomous execution. Plan 03 Task 1 + Task 2 ran exactly as written (file scaffolding, pbxproj wiring, SettingsView refactor, Info.plist key, all 8 unit tests green on first run). Task 3 (computer-use checkpoint) was not skipped — it is deferred to the user because the autonomous session cannot reach a DerivedData-built .app via the computer-use MCP installed-apps resolver. Documented above for the user to complete.

## Self-Check: PASSED

- `OpenGram/SuggestionUI/Settings/ClaritySettingsView.swift`: FOUND
- `OpenGram/SuggestionUI/Settings/AboutSettingsView.swift`: FOUND
- `OpenGram/Resources/THIRD_PARTY.txt`: FOUND
- `OpenGramTests/SuggestionUITests/ClaritySettingsViewTests.swift`: FOUND
- `OpenGramTests/SuggestionUITests/AboutSettingsViewTests.swift`: FOUND
- Commit `bd80f65`: FOUND
- Commit `b0555af`: FOUND
- Bundled `OpenGram.app/Contents/Resources/THIRD_PARTY.txt`: FOUND
- Info.plist `NSHumanReadableCopyright`: FOUND with expected value
