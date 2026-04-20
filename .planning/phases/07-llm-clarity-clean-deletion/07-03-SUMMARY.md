---
phase: 07-llm-clarity-clean-deletion
plan: 03
subsystem: Overlay / ParagraphStore / RephraseCard
tags: [refactor, call-site-fix, clean-replace, CLAR-09, CLAR-10]
requires:
  - "Plan 07-02 (enum + prompt deletions)"
provides:
  - "OverlayController switch fixed post-clarity-delete"
  - "ParagraphSuggestionStore switch fixed + CLAR-10 audit comment"
  - "RephraseCardViewModel switch fixed + D-22 scrub"
  - "DisplayHeuristic predicate fixed"
  - "CheckCategory.clarity docstring rewritten (case preserved for Harper)"
affects:
  - "Xcode app target build — plan-03 files all clean; only ConfigManager.swift:16 + LLMSettingsView remain (Plan 04 scope)"
tech_stack:
  added: []
  patterns: [compiler-driven-refactor, clean-replace-no-shim]
key_files:
  modified:
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift
    - OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift
    - OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift
    - OpenGram/CheckEngine/Suggestion.swift
  created: []
decisions:
  - "D-13 amended: default: return nil REMAINS — CheckCategory still has .clarity (Harper owns it)"
  - "D-14: synthetic Suggestion placeholders at OverlayController:1049+:1075 keep .clarity (CheckCategory, not LLMStyleSuggestion.Category)"
  - "D-15: ParagraphSuggestionStore switch exhaustive on {tone, rephrase} post-delete; no default"
  - "D-16: RephraseCardViewModel switch exhaustive post-delete"
  - "D-17: DisplayHeuristic rephrase-only always-qualifies"
  - "D-20 amended: Suggestion.swift CheckCategory.clarity docstring 'Rules-based clarity lint (Harper WordyPhrases)' — 'from Phase 10' stripped per no-GSD-refs rule"
  - "D-22 scrub: RephraseCardViewModel doc no longer references 'D-22' — decision IDs are planning-internal"
  - "D-07: one-line 'in-memory only — CLAR-10 audit 2026-04-19' comment above ParagraphSuggestionStore actor decl"
metrics:
  duration_minutes: 5
  tasks_completed: 2
  files_modified: 5
  completed: 2026-04-20
---

# Phase 7 Plan 3: LLM Clarity Clean-Deletion — Call-Site Fixes Summary

Fixed five non-UI-settings call sites broken by Plan 07-02 enum deletion. Added CLAR-10 audit comment. Rewrote CheckCategory.clarity docstring (case preserved for Harper Phase 10). Scrubbed D-22 decision-ID from source comments.

## Changes

### Task 1 — OverlayController + ParagraphSuggestionStore (commit `09bb694`)

**`OpenGram/SuggestionUI/Overlay/OverlayController.swift`**
- Line 894 switch on `s.category` (CheckCategory): dropped `case .clarity: cat = .clarity` arm.
- `default: return nil` PRESERVED — CheckCategory still has `.spelling`, `.grammarPunctuation`, `.clarity` (Harper owns the last).
- Synthetic `Suggestion(...)` placeholders at lines 1049 + 1075 (`category: .clarity`) UNCHANGED per D-14 (CheckCategory, decorative, boundsValidator only consumes `range`).

**`OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift`**
- Line 205 switch on `pick.category` (LLMStyleSuggestion.Category): dropped `case .clarity: category = .clarity` arm. Switch exhaustive on `{tone, rephrase}` post-delete.
- Line 12 above `actor ParagraphSuggestionStore:` added one-line comment `// in-memory only — CLAR-10 audit 2026-04-19` documenting D-07 audit finding (no disk I/O, CLAR-10 conditional purge clause not triggered).

### Task 2 — RephraseCardViewModel + DisplayHeuristic + Suggestion docstring (commit `3690a3d`)

**`OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift`**
- `checkCategory(from:)` switch dropped `case .clarity: return .clarity` arm; now exhaustive on `{tone -> .clarity, rephrase -> .rephrase}` (tone still collapses to clarity CheckCategory for header purposes).
- Doc comment rewrite strips `D-22` token per CLAUDE.md no-GSD-refs-in-source rule (decision IDs are planning-internal, not requirement IDs).

**`OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift`**
- Line 10 predicate `$0.category == .clarity || $0.category == .rephrase` → `$0.category == .rephrase`. Rephrase-only always-qualifies.

**`OpenGram/CheckEngine/Suggestion.swift`**
- Lines 42-43 `CheckCategory.clarity` docstring rewritten: `LLM: wordiness, redundancy, complex structure -- rendered orange` → `Rules-based clarity lint (Harper WordyPhrases). Orange underline.`
- "Phase 10" token stripped per planner callout 2 + CLAUDE.md no-GSD-refs rule.
- Enum case + `UnderlineView.swift:82 case .clarity: return .systemOrange` wiring untouched (Harper Phase 10 will emit).

## Deviations from Plan

None beyond planner-callout amendments already baked into plan text (D-13 default-arm-stays, D-20 "Phase 10" strip, D-22 decision-ID scrub). Plan executed exactly as written.

## Build Status

Ran `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` post-task-2. Only remaining error:

```
/Users/alex/Dev/opengram/OpenGram/App/ConfigManager.swift:16:133: error: type 'LLMCheckType' has no member 'clarity'
```

Expected and scope-locked to Plan 07-04 (D-11 `ConfigManager.swift:16` enabledChecks read delete + D-18 `LLMSettingsView` toggle removal). LLMSettingsView errors will surface once ConfigManager clears.

All five Plan 07-03 files compile clean. App target compile will succeed after Plan 07-04 runs. Tests remain broken per Plan 07-05 scope.

## Acceptance Criteria (All Pass)

Task 1:
- `grep -n "case .clarity: cat = .clarity" OverlayController.swift` → 0 matches
- `grep -n "case .clarity:.*category = .clarity" ParagraphSuggestionStore.swift` → 0 matches
- `grep -c "default: return nil" OverlayController.swift` → ≥1 (preserved)
- `grep -c "category: .clarity" OverlayController.swift` → exactly 2 (D-14 synthetic placeholders intact)
- `grep -c "in-memory only — CLAR-10 audit 2026-04-19" ParagraphSuggestionStore.swift` → exactly 1
- ParagraphSuggestionStore switch: only `.tone` and `.rephrase` arms, no default

Task 2:
- `grep -c "D-22" RephraseCardViewModel.swift` → 0
- `grep -c "Phase 10" Suggestion.swift` → 0
- `grep -c "Phase 7" Suggestion.swift` → 0
- `grep -c "from Phase" Suggestion.swift` → 0
- `grep -c "Harper WordyPhrases" Suggestion.swift` → exactly 1
- `grep -c "Rules-based clarity lint" Suggestion.swift` → exactly 1
- `grep -c "case .clarity: return" RephraseCardViewModel.swift` → 0
- `grep -c "case .tone: return .clarity" RephraseCardViewModel.swift` → exactly 1
- `grep -n ".category == .clarity" DisplayHeuristic.swift` → 0
- `grep -c ".category == .rephrase" DisplayHeuristic.swift` → exactly 1
- `grep -c "case clarity" Suggestion.swift` → exactly 1 (case survives)

## Threat Flags

None. T-07-06 (stale `.clarity`) mitigated by preserved `default: return nil`. T-07-07 (unexpected rawValue in RephraseCardViewModel) mitigated by exhaustive 2-case switch at compile time. T-07-08 (`CLAR-10` comment) accepted — requirement ID, no secrets, allowed per CLAUDE.md.

## Self-Check: PASSED

- FOUND: `OpenGram/SuggestionUI/Overlay/OverlayController.swift` (switch fixed, synthetic placeholders intact, `default: return nil` preserved)
- FOUND: `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift` (switch exhaustive, CLAR-10 audit comment present)
- FOUND: `OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift` (switch exhaustive, no D-22 refs)
- FOUND: `OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift` (rephrase-only predicate)
- FOUND: `OpenGram/CheckEngine/Suggestion.swift` (docstring rewritten, case preserved, no Phase N tokens)
- FOUND: commit `09bb694` (Task 1)
- FOUND: commit `3690a3d` (Task 2)
- Build validation: only ConfigManager.swift:16 remains (Plan 07-04 scope) — Plan 03 files all compile.
