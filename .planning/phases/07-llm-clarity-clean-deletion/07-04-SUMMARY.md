---
phase: 07-llm-clarity-clean-deletion
plan: 04
subsystem: Settings UI / ConfigManager
tags: [refactor, settings-ui, userdefaults-read, clean-replace, CLAR-09]
requires:
  - "Plan 07-02 (enum + prompt deletions)"
  - "Plan 07-03 (call-site fixes at OverlayController, ParagraphSuggestionStore, RephraseCardViewModel, DisplayHeuristic, Suggestion.swift)"
provides:
  - "LLMSettingsView without Clarity Toggle + without @AppStorage(\"llmEnableClarity\")"
  - "ConfigManager enabledChecks closure reading llmEnableTone + llmEnableRephrase only"
  - "App target compiles clean after 02+03+04 land"
affects:
  - "Xcode app target build — now green (xcodebuild BUILD SUCCEEDED)"
  - "User-facing Settings (Check types row: Tone + Rephrase only)"
  - "Runtime LLMConfig.enabledChecks (no .clarity possible — enum + UI + reader all aligned)"
tech_stack:
  added: []
  patterns: [clean-replace-no-shim, per-bool-AppStorage-isolation]
key_files:
  modified:
    - OpenGram/SuggestionUI/Settings/LLMSettingsView.swift
    - OpenGram/App/ConfigManager.swift
  created: []
decisions:
  - "D-18: Clarity Toggle + @AppStorage(\"llmEnableClarity\") removed from LLMSettingsView"
  - "D-19: Reset button Set(LLMCheckType.allCases) unchanged — auto-shrinks to {.tone, .rephrase}"
  - "D-11: ConfigManager line 16 llmEnableClarity read deleted; siblings retain default-true-when-absent semantics"
  - "D-09: Dormant llmEnableClarity UserDefaults bool left on disk — no migration, no removeObject, standalone-app contract"
metrics:
  duration_minutes: ~3
  tasks_completed: 2
  files_modified: 2
  completed: 2026-04-20
---

# Phase 7 Plan 4: LLM Clarity Clean-Deletion — Settings UI + ConfigManager Summary

Removed the last two user-facing and runtime `.clarity` references: the Settings Toggle + `@AppStorage` binding in `LLMSettingsView`, and the `llmEnableClarity` UserDefaults read in `ConfigManager.enabledChecks`. Dormant UserDefaults bool left on disk per D-09. App target now compiles clean.

## Changes

### Task 1 — LLMSettingsView Clarity Toggle removal (commit `370d189`)

**`OpenGram/SuggestionUI/Settings/LLMSettingsView.swift`**
- Deleted line 78 `@AppStorage("llmEnableClarity") private var enableClarity: Bool = true`.
- Deleted Clarity Toggle row (2 lines) from the "Check types" `HStack`. Resulting HStack holds Tone + Rephrase Toggles only.
- Reset button (line ~233, now 230) `enabledChecks: Set(LLMCheckType.allCases)` UNCHANGED per D-19 — set auto-shrinks to `{.tone, .rephrase}` (2 members) post Plan 07-02 enum deletion.
- No `UserDefaults.removeObject(forKey: "llmEnableClarity")` call added — D-09 contract: dormant bool stays on disk.
- Sibling `enableTone` + `enableRephrase` declarations + Toggle rows intact.

### Task 2 — ConfigManager llmEnableClarity read deletion (commit `c2a50e0`)

**`OpenGram/App/ConfigManager.swift`**
- Deleted line 16 of the `enabledChecks` closure:
  ```swift
  if defaults.object(forKey: "llmEnableClarity") == nil || defaults.bool(forKey: "llmEnableClarity") { checks.insert(.clarity) }
  ```
- Sibling `llmEnableTone` + `llmEnableRephrase` per-bool reads retained with "default-true when key absent" semantics.
- No launch-time cleanup code added — D-09 / D-11 contract.

## Build Status

`xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → **BUILD SUCCEEDED** (app target).

Pre-Plan-04 state: ConfigManager.swift:16 was the only remaining `type 'LLMCheckType' has no member 'clarity'` error. Post-Plan-04: app target compiles clean end-to-end. Tests remain broken per Plan 07-05 scope (D-21 test surgery enumeration not in this plan).

## Acceptance Criteria (All Pass)

Task 1 (LLMSettingsView):
- `grep -c "llmEnableClarity" LLMSettingsView.swift` → 0
- `grep -c "enableClarity" LLMSettingsView.swift` → 0
- `grep -c "\"Clarity\"" LLMSettingsView.swift` → 0
- `grep -c "enableTone" LLMSettingsView.swift` → 2 (decl + Toggle)
- `grep -c "enableRephrase" LLMSettingsView.swift` → 2
- `grep -c "Set(LLMCheckType.allCases)" LLMSettingsView.swift` → 1 (reset button)
- `grep -c "removeObject(forKey: \"llmEnableClarity\")" LLMSettingsView.swift` → 0

Task 2 (ConfigManager):
- `grep -c "llmEnableClarity" ConfigManager.swift` → 0
- `grep -c "checks.insert(.clarity)" ConfigManager.swift` → 0
- `grep -c "llmEnableTone" ConfigManager.swift` → 2
- `grep -c "llmEnableRephrase" ConfigManager.swift` → 2
- `grep -c "removeObject" ConfigManager.swift` → 0

## Deviations from Plan

None — plan executed exactly as written.

## Threat Flags

None. T-07-09 (dormant bool on disk) accept disposition holds — local plist, non-sensitive bool, no PII. T-07-10 (user tampering with plist to force `llmEnableClarity = true`) remains inert: ConfigManager no longer reads the key and `LLMCheckType.clarity` enum case is deleted — type-system gate prevents coercion. T-07-11 (stale toggle rendering) mitigated by `@AppStorage` binding deletion + Toggle row removal; visual verification deferred to Plan 06 UAT.

## Self-Check: PASSED

- FOUND: `OpenGram/SuggestionUI/Settings/LLMSettingsView.swift` (0 llmEnableClarity / enableClarity / "Clarity" refs; 1 `Set(LLMCheckType.allCases)` preserved)
- FOUND: `OpenGram/App/ConfigManager.swift` (0 llmEnableClarity refs; tone + rephrase reads intact)
- FOUND: commit `370d189` (Task 1)
- FOUND: commit `c2a50e0` (Task 2)
- Build validation: `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` → BUILD SUCCEEDED
- Dormant `llmEnableClarity` UserDefaults key: NOT deleted (D-09 compliance — no `removeObject` call anywhere)
