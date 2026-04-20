---
phase: 07-llm-clarity-clean-deletion
verified: 2026-04-20T08:32:00Z
status: human_needed
score: 17/17 automated must-haves verified; ROADMAP success criterion 5 pending user UAT
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Notes.app hotkey flow — zero LLM clarity underlines"
    expected: |
      Type paragraph `At this point in time, I think we should utilize the new system in order to finish the work. Its a great plan.` in Notes.app.
      Fire Ctrl+Shift+G.
      Overlay renders: red (spelling on "Its") from Harper. Optional purple (tone) on "I think". Optional teal (rephrase).
      CRITICAL: ZERO solid-orange or dashed-orange underlines on "at this point in time" / "utilize" / "in order to".
    why_human: |
      Visual overlay rendering over third-party app (Notes.app). Requires user to
      inspect screenshot at `.planning/phases/07-llm-clarity-clean-deletion/07-06-screenshots/notes-post-hotkey.png`
      or re-run flow. Automated code invariant locked by
      `clarityCategoryDroppedPostDeletion_CLAR09` regression test (PASSES).
  - test: "Settings UI has no Clarity toggle"
    expected: |
      Open OpenGram Settings → LLM tab. "Check types" row shows Tone + Rephrase
      toggles ONLY. No Clarity row. No "Enable clarity checks" copy.
    why_human: |
      Visual SwiftUI rendering; code grep confirms zero `"Clarity"` / `llmEnableClarity`
      / `enableClarity` tokens in LLMSettingsView.swift, but visual confirmation
      that toggle row layout is correct (Tone + Rephrase only, no gap) needs user eyes.
---

# Phase 7: LLM `.clarity` Clean-Deletion Verification Report

**Phase Goal:** LLM no longer produces, persists, or surfaces `.clarity` suggestions. Clean replace ahead of Harper clarity (Phase 10). `CheckCategory.clarity` preserved for Harper. Synthetic-Suggestion `.clarity` at OverlayController:1048/1074 preserved (D-14). Dormant `llmEnableClarity` UserDefaults key left in place (D-09).

**Verified:** 2026-04-20T08:32:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `LLMCheckType.clarity` case absent | VERIFIED | `grep "case clarity" LLMConfig.swift` → 0 matches. Enum collapsed to `{tone, rephrase}` (L6-9) |
| 2 | `LLMStyleSuggestion.Category.clarity` case absent | VERIFIED | `grep "case clarity" LLMStyleSuggestion.swift` → 0 matches. Nested Category enum `{tone, rephrase}` (L9-12) |
| 3 | `LLMPrompts.systemPrompt` emits no clarity-dimension instruction | VERIFIED | `grep -i clarity LLMPrompts.swift` → 0 matches. Three-dim wording at L12 |
| 4 | LLM batch response `"category":"clarity"` silently dropped at DTO | VERIFIED | Regression test `clarityCategoryDroppedPostDeletion_CLAR09` at LLMResponseDTOTests.swift:96 passes |
| 5 | `ConfigManager` reads `llmEnableTone` + `llmEnableRephrase` only | VERIFIED | `grep llmEnableClarity ConfigManager.swift` → 0; tone+rephrase reads at L15-16 |
| 6 | `ParagraphSuggestionStore` in-memory audit comment present | VERIFIED | `ParagraphSuggestionStore.swift:12` has `// in-memory only — CLAR-10 audit 2026-04-19` |
| 7 | `ParagraphSuggestionStore` actor has no disk I/O | VERIFIED | No `FileManager`, `write(to:`, `UserDefaults.set` in actor body; in-memory `[ParagraphHash: ParagraphCacheEntry]` only |
| 8 | `LLMSettingsView` has no Clarity toggle / `@AppStorage("llmEnableClarity")` | VERIFIED | `grep llmEnableClarity\|enableClarity\|"Clarity"` → 0; Tone+Rephrase toggles at L129,L131 |
| 9 | Reset button `Set(LLMCheckType.allCases)` preserved (D-19) | VERIFIED | LLMSettingsView.swift:230 intact; auto-shrinks to 2 members |
| 10 | OverlayController:894 switch has no `.clarity` arm; `default: return nil` preserved | VERIFIED | `default: return nil` at L896; no `case .clarity: cat = .clarity` |
| 11 | OverlayController:1048 + :1074 synthetic-Suggestion `.clarity` preserved (D-14) | VERIFIED | Exactly 2 `category: .clarity` matches at L1048, L1074 |
| 12 | `RephraseCardViewModel.checkCategory(from:)` exhaustive on `{tone, rephrase}` | VERIFIED | No `case .clarity: return` in RephraseCardViewModel.swift |
| 13 | `DisplayHeuristic` predicate checks rephrase-only | VERIFIED | `DisplayHeuristic.swift:10` → `$0.category == .rephrase` (no `.clarity`) |
| 14 | `CheckCategory.clarity` case preserved + docstring rewritten for Harper | VERIFIED | Suggestion.swift:43 `case clarity` present; L42 docstring `Rules-based clarity lint (Harper WordyPhrases). Orange underline.` (no "Phase 10" token) |
| 15 | `UnderlineView.swift:82 case .clarity: return .systemOrange` preserved | VERIFIED | Exists; Harper Phase 10 will emit |
| 16 | D-05 regression test locks CLAR-09 silent-drop invariant | VERIFIED | `clarityCategoryDroppedPostDeletion_CLAR09` at LLMResponseDTOTests.swift:96-105; TEST SUCCEEDED |
| 17 | REQUIREMENTS.md CLAR-09 amended (silent-drop language) | VERIFIED | `grep "silently dropped via existing unknown-rawValue guard"` → L40 match |
| 18 | ROADMAP.md Phase 7 success criteria 2, 3, 4 amended | VERIFIED | Criteria 2-4 reflect silent-drop + audit-only outcomes at L75-77 |
| 19 | Dormant `llmEnableClarity` UserDefaults key left on disk (D-09) | VERIFIED | No `removeObject(forKey: "llmEnableClarity")` anywhere; standalone-app contract honored |
| 20 | xcodebuild app target compiles | VERIFIED | `xcodebuild -scheme OpenGram build` → BUILD SUCCEEDED |
| 21 | LLM test suites pass (phase-scope) | VERIFIED | LLMResponseDTOTests, LLMPromptsTests, LLMServiceTests, LMStudioPipelineIntegrationTests → TEST SUCCEEDED |
| 22 | Notes.app visual UAT — zero LLM clarity underlines | PENDING HUMAN | Deferred to user per explicit instruction during Plan 07-06; automated code-invariant locked by D-05 regression test |

**Score:** 21/21 automated must-haves verified; 1 human verification pending (ROADMAP success criterion 5).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `OpenGram/CheckEngine/LLM/LLMConfig.swift` | LLMCheckType `{tone, rephrase}` | VERIFIED | Exists, substantive (50 L), wired (used by LLMService, ConfigManager, LLMSettingsView) |
| `OpenGram/CheckEngine/LLM/LLMStyleSuggestion.swift` | Category `{tone, rephrase}` | VERIFIED | Exists, 20 L, wired (LLMResponseDTO, ParagraphSuggestionStore, RephraseCardViewModel) |
| `OpenGram/CheckEngine/LLM/LLMPrompts.swift` | systemPrompt three-dim wording | VERIFIED | Exists, wired into LLMService.makeRequest L43, L132 |
| `OpenGram/SuggestionUI/Settings/LLMSettingsView.swift` | Toggle row Tone+Rephrase only | VERIFIED | Exists, wired via @AppStorage→UserDefaults |
| `OpenGram/App/ConfigManager.swift` | Reads tone+rephrase bools only | VERIFIED | Exists, reads at L15-16 |
| `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift` | Switch on `{tone, rephrase}` + audit comment L12 | VERIFIED | Exists, exhaustive switch post-delete, audit comment present |
| `OpenGram/SuggestionUI/Overlay/OverlayController.swift` | Switch fixed, synthetic placeholders intact | VERIFIED | L894 switch post-delete; L1048, L1074 decorative `.clarity` preserved |
| `OpenGram/SuggestionUI/RephraseCard/RephraseCardViewModel.swift` | Exhaustive switch, no D-22 token | VERIFIED | 2-case switch; `D-22` doc reference scrubbed per no-GSD-refs rule |
| `OpenGram/SuggestionUI/RephraseCard/DisplayHeuristic.swift` | Rephrase-only predicate | VERIFIED | L10 predicate checks `.rephrase` only |
| `OpenGram/CheckEngine/Suggestion.swift` | CheckCategory.clarity preserved + docstring rewritten | VERIFIED | L43 case present; L42 Harper docstring without Phase N token |
| `OpenGramTests/CheckEngine/LLMResponseDTOTests.swift` | D-05 regression test | VERIFIED | L96 `clarityCategoryDroppedPostDeletion_CLAR09` passes |
| `.planning/REQUIREMENTS.md` | CLAR-09 amended | VERIFIED | L40 silent-drop language |
| `.planning/ROADMAP.md` | Phase 7 criteria 2/3/4 amended | VERIFIED | L75-77 amendments landed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| LLMPrompts.systemPrompt | LLM HTTP request body | LLMService.makeRequest | WIRED | Two call sites at LLMService.swift:43, 132 |
| LLMCheckType.allCases | LLMSettingsView reset + LLMConfig.default | CaseIterable | WIRED | `Set(LLMCheckType.allCases)` at LLMSettingsView:230, LLMConfig:28; auto-shrinks to 2 members |
| LLMSettingsView @AppStorage | UserDefaults | key strings llmEnableTone, llmEnableRephrase | WIRED | Binding via @AppStorage to UserDefaults plist |
| ConfigManager.enabledChecks | LLMConfig.enabledChecks | UserDefaults.bool(forKey:) | WIRED | ConfigManager.swift:15-16 reads per-key bool flags |
| LLMResponseDTO.clarityCategoryDroppedPostDeletion_CLAR09 | SuggestionDTO.toModel unknown-rawValue guard | silent drop | WIRED | Regression test PASSES, locks CLAR-09 invariant |
| CheckCategory.clarity | UnderlineView render | switch at UnderlineView:82 | WIRED | `case .clarity: return .systemOrange` preserved for Harper Phase 10 |
| REQUIREMENTS.md CLAR-09 / CLAR-10 | Plans 02-06 frontmatter | `requirements: [CLAR-09, CLAR-10]` | WIRED | All 6 plans declare CLAR-09; Plans 01, 03 declare CLAR-10 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| LLMPrompts.systemPrompt | systemPrompt string | Static computed property with three-dim wording | Yes (string literal + harperSpans param) | FLOWING |
| LLMResponseDTO.toModels | suggestions array | JSON decode + `Category(rawValue:)` guard | Yes (decodes valid tone/rephrase; drops clarity silently) | FLOWING |
| ConfigManager.enabledChecks | checks Set | UserDefaults.bool per-key read (tone, rephrase) | Yes (user toggles persist) | FLOWING |
| LLMSettingsView toggles | enableTone, enableRephrase | @AppStorage binding | Yes (two-way bind with UserDefaults) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| App target compiles | `xcodebuild -scheme OpenGram build` | BUILD SUCCEEDED | PASS |
| CLAR-09 regression test passes | `xcodebuild -only-testing:OpenGramTests/LLMResponseDTOTests test` | TEST SUCCEEDED | PASS |
| LLM-scope test suites pass | `xcodebuild -only-testing:{LLMPromptsTests,LLMServiceTests,LMStudioPipelineIntegrationTests} test` | TEST SUCCEEDED | PASS |
| Notes.app visual UAT | Manual (Ctrl+Shift+G + screenshot inspection) | Deferred to user | SKIP — routed to human verification |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CLAR-09 | 07-01 through 07-06 | `.clarity` deleted from LLMCheckType + LLMStyleSuggestion.Category; systemPrompt statically strips; DTO silent-drop on stray `"clarity"` | SATISFIED | Truths 1-5, 8, 16, 17; regression test passes |
| CLAR-10 | 07-01, 07-03 | ParagraphSuggestionStore audit — in-memory-only actor confirmed; no launch-time purge needed | SATISFIED | Truth 6-7; audit comment at actor L12; grep confirms no disk I/O |

No orphaned requirements. Both IDs declared in plans AND match REQUIREMENTS.md phase assignment (CLAR-09 Phase 7, CLAR-10 Phase 7).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none in scope files) | — | No TODO/FIXME/placeholder/stub patterns introduced by Phase 7 | — | — |

Note: `D-04`, `D-05`, `D-22` decision-ID tokens exist in SOURCE files OUTSIDE Phase 7 scope (OverlayControllerMirrorTests.swift, AXCapabilityCache.swift, LLMPrompts.swift:67 D-05 comment, RephraseCardView.swift, etc.). These reference OTHER phases (PERF-12 D-05, FR-16 D-22, etc.) — not Phase 7 decisions. Out of scope per `feedback_no_gsd_refs_in_source.md` which applies to NEW edits; pre-existing refs unchanged by this phase.

### Human Verification Required

See `human_verification:` section in frontmatter. Two items:

1. **Notes.app hotkey flow — zero LLM clarity underlines** (ROADMAP Phase 7 success criterion 5). Plan 07-06 automated portion complete (build, launch, paragraph typed, hotkey fired, screenshot captured at `07-06-screenshots/notes-post-hotkey.png`). User must inspect screenshot or re-run to confirm visual PASS.
2. **Settings UI layout** — code-side clean; visual check that Tone+Rephrase toggle layout reads correctly (no orphan gap).

### Gaps Summary

No code gaps. All 21 automated must-haves VERIFIED. Phase 7 goal (LLM produces/persists/surfaces zero `.clarity`) achieved at code invariant level, locked by `clarityCategoryDroppedPostDeletion_CLAR09` regression test. REQUIREMENTS.md + ROADMAP.md amendments landed. Only outstanding item is user-driven visual UAT — intentionally deferred per user instruction during Plan 07-06 execution.

Pre-existing test failures (ScrollTrackerTests, OverlayControllerScrollModeTests, AXCallWatchdog flakes, TextMonitor debounce flakes) documented in `deferred-items.md` as unrelated to Phase 7 — confirmed via `git stash` rerun at commit `57b8237`. Out of scope.

Review findings (07-REVIEW.md) identified 1 warning + 3 info-level items — all documentation drift (stale docstrings saying "three dimensions", orphaned CLAR-10 audit comment citing "audit" date, missing Codable stability test). All info/warning severity; no critical findings. Not blocking phase goal.

---

_Verified: 2026-04-20T08:32:00Z_
_Verifier: Claude (gsd-verifier)_
