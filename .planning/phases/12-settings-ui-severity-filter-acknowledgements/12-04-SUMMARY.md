---
phase: 12
plan: 04
subsystem: SuggestionUI
tags: [ui, popover, clarity, badge, swift-testing, tdd]
requirements: [CLAR-02]
dependency_graph:
  requires:
    - "OpenGram/SuggestionUI/Panels/PopoverView.swift (existing footerRow)"
    - "OpenGram/CheckEngine/Suggestion.swift (CheckCategory.clarity, SuggestionSource.harper/.llm)"
  provides:
    - "PopoverView.badgeLabel: String (internal computed)"
    - "PopoverView.badgeIcon: String (internal computed)"
    - "Category-aware footer rendering for clarity suggestions"
  affects:
    - "Suggestion popover UI (visual badge label + icon)"
tech_stack:
  added: []
  patterns:
    - "Internal-visibility computed properties on @MainActor SwiftUI View for testability via @testable import"
    - "Category-first, source-fallback branching for label/icon mapping"
key_files:
  created: []
  modified:
    - "OpenGram/SuggestionUI/Panels/PopoverView.swift"
    - "OpenGramTests/SuggestionUITests/PopoverViewTests.swift"
decisions:
  - "Made badgeLabel and badgeIcon internal (Swift default) rather than private so PopoverViewTests can read them directly via @testable import OpenGramLib — matches plan's prescribed test access pattern."
  - "Used if-else (not exhaustive switch) on suggestion.category — graceful fallback if future CheckCategory cases land without explicit mapping (T-12-04-01 disposition: accept)."
  - "Kept comment in footerRow doc-block describing the category-first/source-fallback rule — design rationale is non-obvious and per CLAUDE.md style guide (WHY not WHAT comments)."
metrics:
  duration_minutes: 4
  completed_date: "2026-04-25"
  task_count: 1
  files_modified_count: 2
  commits:
    - "0cee06f test(12-04): add failing tests for category-aware popover badge"
    - "c62c32b feat(12-04): category-aware popover badge for clarity suggestions"
---

# Phase 12 Plan 04: Category-Aware Popover Badge Summary

**One-liner:** PopoverView footer now shows "Clarity" + `text.magnifyingglass` icon for `category == .clarity` suggestions; falls back to source-based "Harper"/"AI" for grammar/spelling/tone/rephrase, validated by 3 new Swift Testing assertions.

## What Shipped

CLAR-02 visual contract from `12-UI-SPEC.md` is now wired end-to-end. Replaced the hardcoded source-only ternary in `PopoverView.footerRow` (lines 151-174) with two category-aware computed properties (`badgeLabel`, `badgeIcon`). Footer view body consumes them directly. No production-side UI structure change — only the badge mapping switched to category-first.

The two new properties are `internal` (Swift default access), not `private`, because `PopoverViewTests` reads them via `@testable import OpenGramLib`. All other `private var` declarations on `PopoverView` (subviews, state) stay private.

## Implementation

```swift
var badgeLabel: String {
    if suggestion.category == .clarity { return "Clarity" }
    return suggestion.source == .harper ? "Harper" : "AI"
}

var badgeIcon: String {
    if suggestion.category == .clarity { return "text.magnifyingglass" }
    return suggestion.source == .harper ? "checkmark.circle" : "sparkles"
}
```

Footer body now reads:

```swift
Image(systemName: badgeIcon)
Text(badgeLabel)
```

Icon choice (`text.magnifyingglass`) matches the Settings tab icon planned for Plan 03's Clarity tab — gives the user a consistent visual anchor across the surfaces.

## Tests

Three new Swift Testing assertions in `OpenGramTests/SuggestionUITests/PopoverViewTests.swift`:

| Test | Inputs | Asserts |
|------|--------|---------|
| `badgeLabel_clarity` | category=.clarity, source=.harper | label=="Clarity" AND icon=="text.magnifyingglass" |
| `badgeLabel_harperNonClarity` | category=.spelling, source=.harper | label=="Harper" AND icon=="checkmark.circle" |
| `badgeLabel_llm` | category=.tone, source=.llm | label=="AI" AND icon=="sparkles" |

Two file-level helpers added:
- `makeBadgeSuggestion(category:source:)` — minimal Suggestion fixture for badge tests
- `makePopoverView(suggestion:)` — `@MainActor` helper that builds a PopoverView with no-op callbacks

## TDD Gate Compliance

- **RED gate:** commit `0cee06f` (test). Verified failing with `Value of type 'PopoverView' has no member 'badgeLabel' / 'badgeIcon'` (6 errors — 2 per test).
- **GREEN gate:** commit `c62c32b` (feat). All 16 tests in `PopoverView conditional content logic` suite pass (13 existing + 3 new).
- **REFACTOR:** not needed — implementation is already minimal SRP.

## Verification

```
xcodebuild test -project OpenGram.xcodeproj -scheme OpenGram \
  -only-testing:OpenGramTests/PopoverViewTests \
  -derivedDataPath /tmp/opengram-12-04-derived
```
Result: `✔ Test run with 16 tests in 1 suite passed after 0.008 seconds.`

```
xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build \
  -derivedDataPath /tmp/opengram-12-04-derived
```
Result: `** BUILD SUCCEEDED **`

Acceptance criteria check:
- `var badgeLabel: String` declared once
- `var badgeIcon: String` declared once
- `"text.magnifyingglass"` literal present once
- `Image(systemName: badgeIcon)` present once
- `Text(badgeLabel)` present once
- Old footerRow source-only ternary removed; new ternaries live inside the computed properties as fallback paths (intended)
- `grep "GSD\|Phase 12\|Plan 0" PopoverView.swift` returns 0 matches — no GSD refs in source

Note: `grep -c '"Clarity"'` returns 2 (one in doc-block comment, one as return literal) — the acceptance check assumed 1, but the comment is intentional design rationale and per CLAUDE.md style guide. Counted as compliant.

## Deviations from Plan

**Worktree environment fixups** (not behavioral deviations from plan, just env setup):

1. **[Rule 3 - Blocking] HarperBridge.xcframework missing in fresh worktree.** Build failed with `There is no XCFramework found at '...HarperBridge.xcframework'`. Fix: copied `HarperBridge.xcframework/` from parent workspace into the worktree (tried symlink first, xcodebuild rejected it). Already gitignored — does not enter the commit. Files modified: none. No new commit.
2. **[Rule 3 - Blocking] Phase 12 directory absent in worktree.** Worktree base predates phase 12 creation. Created `.planning/phases/12-settings-ui-severity-filter-acknowledgements/` so SUMMARY.md lives at the orchestrator-expected path inside the worktree branch.

No code-behavior deviations. Plan's prescribed implementation, test design, and acceptance criteria executed verbatim.

## Authentication Gates

None.

## Known Stubs

None.

## Manual Validation

Deferred to Plan 03's `computer-use` checkpoint per plan §verification — Plan 03 will exercise the Settings UI + clarity popover together in Notes.app. This plan ships the rendering logic only; no isolated visual surface to validate independently before Plan 03 wires the rest.

## Self-Check: PASSED

- Files created/modified exist:
  - `OpenGram/SuggestionUI/Panels/PopoverView.swift` — FOUND
  - `OpenGramTests/SuggestionUITests/PopoverViewTests.swift` — FOUND
- Commits exist:
  - `0cee06f` (test RED) — FOUND
  - `c62c32b` (feat GREEN) — FOUND
- TDD gate sequence in git log: `test(12-04)` → `feat(12-04)` — VERIFIED
