---
phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation
plan: "07"
subsystem: suggestion-ui + check-engine
tags: [swift, underline-view, suggestion-type, atomic-refactor, tdd]

requires:
  - phase: 20-01
    provides: ParagraphHash struct
  - phase: 20-06
    provides: ParagraphSuggestionStore + sha256Prefix8UInt64 shim (deleted here)

provides:
  - UnderlineView.colorForSuggestion — purple for LLM, category-color for Harper
  - UnderlineView.draw sorts LLM entries before Harper (z-order: Harper on top)
  - Suggestion.paragraphHash: ParagraphHash? — globally flipped, zero UInt64 residuals
  - sha256Prefix8UInt64 shim deleted from ParagraphSuggestionStore
  - CardQualifier.legacyHash: UInt64 — transitional bridge to scheduler.markDismissed (Plan 10b removes)

affects:
  - 20-09 (OverlayController now holds ParagraphHash for card-dedup and filter)
  - 20-10 (AppDelegate wires store; Suggestion type is clean ParagraphHash? everywhere)
  - Plan 10b (deletes legacyHash + scheduler.markDismissed call)
  - Plan 10c (deletes legacy LLMCheckScheduler + ParagraphSuggestionCache files wholesale)

tech-stack:
  added: []
  patterns:
    - "colorForSuggestion: source-first dispatch — LLM → purple override, Harper → category fallback"
    - "z-order sort: LLM entries drawn first (index 0), Harper drawn last (index 1) so Harper underlines render on top"
    - "legacyHash bridge: CardQualifier carries both ParagraphHash (new) and UInt64 (transitional) until Plan 10b removes scheduler"

key-files:
  created: []
  modified:
    - OpenGram/SuggestionUI/Overlay/UnderlineView.swift
    - OpenGram/CheckEngine/Suggestion.swift
    - OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift
    - OpenGram/SuggestionUI/Overlay/OverlayController.swift
    - OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift
    - OpenGramTests/SuggestionUITests/UnderlineViewTests.swift
    - OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift
    - OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift

key-decisions:
  - "Atomic single-task + single-commit: Plan 06's sha256Prefix8UInt64 shim only compiles against UInt64?; the moment Suggestion.paragraphHash flips to ParagraphHash?, the shim call site breaks. Merging color change + type flip into one commit eliminates the un-buildable intermediate window."
  - "legacyHash: UInt64 on CardQualifier: scheduler.markDismissed still expects UInt64 (legacy Phase 16 scheduler). Transitional field bridges the gap until Plan 10b deletes the scheduler and this field together."
  - "LLMCheckScheduler.rebase updated to ParagraphHash: Step F audit found active Suggestion(paragraphHash: UInt64) construction in LLMCheckScheduler.rebase(). Fixed inline per CLAUDE.md 'update all call sites in the same change'. LLMCheckScheduler now constructs ParagraphHash(bundleID: bundleID, paragraphText: paragraph.text) at the rebase call site."
  - "Log interpolation: ParagraphHash lacks CustomStringConvertible; switched log sites to hash.sha256 for os.log compatibility."

requirements-completed: [PLL-01a, PLL-01b, PLL-13]

duration: 15min
completed: 2026-04-18
---

# Phase 20 Plan 07: UnderlineView Color+Z-Order + Suggestion.paragraphHash Type Swap Summary

**Atomic color render layer (purple dashed LLM, Harper on top) + ParagraphHash type flip across all call sites in one commit — sha256Prefix8UInt64 shim deleted**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-04-18T02:49:32Z
- **Tasks:** 1 (atomic, Steps A-F in one commit)
- **Files modified:** 8

## Accomplishments

- `UnderlineView.colorForSuggestion` added: LLM → `.systemPurple`, Harper → `colorForCategory` fallback
- `draw(_:)` now sorts entries before rendering: LLM first (z=0), Harper second (z=1), so Harper underlines render on top of LLM underlines (PLL-01b / PLL-13)
- `Suggestion.paragraphHash` type flipped `UInt64?` → `ParagraphHash?` globally
- `sha256Prefix8UInt64` Plan 06 transient shim deleted from `ParagraphSuggestionStore.swift`
- `CardQualifier` updated: `hash: ParagraphHash` + `legacyHash: UInt64` (transitional, Plan 10b removes)
- `currentCardParagraphHash: ParagraphHash?` in `OverlayController`
- `LLMCheckScheduler.rebase` signature updated to `paragraphHash: ParagraphHash` — call site builds `ParagraphHash(bundleID: bundleID, paragraphText: paragraph.text)`
- 4 new UnderlineView tests: `colorForSuggestion_llm_returnsPurple`, `colorForSuggestion_harperSpelling_returnsRed`, `colorForSuggestion_harperGrammar_returnsBlue`, `draw_sortsLLMBeforeHarper`
- 479 total tests run; 1 pre-existing flaky test (`idleDebounceSeconds_liveReadHonoredWithoutReinit`) — identical to baseline

## Task Commits

1. **Task 1: Atomic UnderlineView color+z-order + Suggestion.paragraphHash flip** — `c460237` (feat)

## Files Created/Modified

- `OpenGram/SuggestionUI/Overlay/UnderlineView.swift` — `colorForSuggestion` helper + source-sorted draw loop
- `OpenGram/CheckEngine/Suggestion.swift` — `paragraphHash: ParagraphHash?` (was `UInt64?`)
- `OpenGram/CheckEngine/ParagraphStore/ParagraphSuggestionStore.swift` — `paragraphHash: hash` (full `ParagraphHash`); `sha256Prefix8UInt64` extension deleted
- `OpenGram/SuggestionUI/Overlay/OverlayController.swift` — `CardQualifier.hash: ParagraphHash` + `.legacyHash: UInt64`; `currentCardParagraphHash: ParagraphHash?`; hash computation; log interpolation fixed
- `OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift` — `rebase(paragraphHash: ParagraphHash)` + call site builds `ParagraphHash(bundleID:paragraphText:)`
- `OpenGramTests/SuggestionUITests/UnderlineViewTests.swift` — 4 new color/z-order tests added
- `OpenGramTests/SuggestionUITests/OverlayControllerRephraseIntegrationTests.swift` — `hash: ParagraphHash(bundleID:paragraphText:)` replacing `Sha256ParagraphHasher().hash()`
- `OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift` — `CardQualifier` construction updated with `hash: ParagraphHash` + `legacyHash: 0`

## Acceptance Criteria Verification

| Check | Result |
|-------|--------|
| `grep -c 'func colorForSuggestion' UnderlineView.swift` == 1 | 1 ✓ |
| `grep -c 'colorForSuggestion(entry.suggestion).setStroke'` == 1 | 1 ✓ |
| `grep -c 'colorForCategory(entry.suggestion.category).setStroke'` == 0 | 0 ✓ |
| `grep -c 'let paragraphHash: UInt64?' Suggestion.swift` == 0 | 0 ✓ |
| `grep -c 'let paragraphHash: ParagraphHash?' Suggestion.swift` == 1 | 1 ✓ |
| `grep -c 'sha256Prefix8UInt64' ParagraphSuggestionStore.swift` == 0 | 0 ✓ |
| `sha256Prefix8UInt64` repo-wide == 0 | 0 ✓ |
| `grep -c 'let hash: ParagraphHash' OverlayController.swift` >= 1 | 1 ✓ |
| `grep -c 'let legacyHash: UInt64' OverlayController.swift` == 1 | 1 ✓ |
| `grep -c 'currentCardParagraphHash: ParagraphHash?' OverlayController.swift` == 1 | 1 ✓ |
| Zero UInt64 residuals in active Suggestion construction | 0 ✓ |
| xcodebuild build green | ✓ |
| Full xcodebuild test — no new regressions (1 pre-existing flaky) | ✓ |
| UnderlineViewTests 4 new tests pass | ✓ |
| Single atomic commit (git log --stat) | c460237 ✓ |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMCheckScheduler.rebase constructed Suggestion with UInt64 paragraphHash**
- **Found during:** Step F legacy audit (Step E grep surfaced it)
- **Issue:** `LLMCheckScheduler.rebase(paragraph:paragraphHash:UInt64,...)` passed `paragraphHash: paragraphHash` (UInt64) into `Suggestion` init. Breaks at compile time when field flips to `ParagraphHash?`. Plan listed this as "fix inline if found" in Step F.
- **Fix:** Changed `rebase` signature to `paragraphHash: ParagraphHash`; call site builds `ParagraphHash(bundleID: bundleID, paragraphText: paragraph.text)` (bundleID available in `check(text:bundleID:)`).
- **Files modified:** `OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift`
- **Committed in:** c460237

**2. [Rule 1 - Bug] os.log interpolation of ParagraphHash requires CustomStringConvertible**
- **Found during:** Step D compile probe
- **Issue:** Two `Self.logger.info(...)` lines interpolated `hash` and `selected.hash` directly; `ParagraphHash` lacks `CustomStringConvertible` conformance, causing compile errors.
- **Fix:** Replaced `\(hash)` and `\(selected.hash)` with `\(hash.sha256, privacy: .public)` and `\(selected.hash.sha256, privacy: .public)`.
- **Files modified:** `OpenGram/SuggestionUI/Overlay/OverlayController.swift`
- **Committed in:** c460237

**3. [Rule 1 - Bug] MultiQualifierSelectionTests used `hash: 0` (Int literal) for CardQualifier**
- **Found during:** Step E test build (compile error)
- **Issue:** `MultiQualifierSelectionTests.makeQ` passed `hash: 0` which matched the old `UInt64` field. After CardQualifier gains `hash: ParagraphHash` + `legacyHash: UInt64`, this fails to compile (type mismatch + missing argument).
- **Fix:** Updated `makeQ` to build `ParagraphHash(bundleID: "com.test", paragraphText: text)` and pass `legacyHash: 0`.
- **Files modified:** `OpenGramTests/SuggestionUITests/MultiQualifierSelectionTests.swift`
- **Committed in:** c460237

## Legacy File Audit (Step F — DO NOT EDIT)

Files targeted for wholesale deletion in Plan 10c:
- `OpenGram/CheckEngine/LLMCheckScheduler/LLMCheckScheduler.swift` — uses `ParagraphCacheKey(paragraphHash: UInt64)` internally (separate struct, NOT `Suggestion.paragraphHash`). The `rebase` function was the one active `Suggestion(paragraphHash: UInt64)` site — fixed in Deviation #1 above.
- `OpenGram/CheckEngine/LLMCheckScheduler/IncrementalConfig.swift` — tunables only, no Suggestion construction. Unaffected.
- `OpenGram/CheckEngine/ParagraphInfra/ParagraphSuggestionCache.swift` — keyed on `ParagraphCacheKey.paragraphHash: UInt64` (its own internal field). Does NOT construct `Suggestion`. Unaffected.
- `OpenGramTests/CheckEngine/LLMCheckSchedulerTests.swift` + siblings — use `ParagraphCacheKey(paragraphHash: UInt64)` only, never construct `Suggestion(paragraphHash: <UInt64>)`. Unaffected.
- `OpenGramTests/CheckEngine/ParagraphInfra/ParagraphSuggestionCacheTests.swift` — same; `ParagraphCacheKey` construction only. Unaffected.

Acceptance grep confirms zero `Suggestion(…paragraphHash: <UInt64 variable>…)` construction across all legacy files post-fix.

## Why legacyHash Exists

`CardQualifier.legacyHash: UInt64` is a transitional field bridging this plan to Plan 10b. `OverlayController.tryDispatchRephraseCard` passes `hashForDismiss = selected.legacyHash` to `scheduler.markDismissed(bundleID:hash:UInt64)`. When Plan 10b removes the legacy scheduler and its `markDismissed` call, `legacyHash` is deleted alongside it. The primary `hash: ParagraphHash` field is what Plan 09 and beyond use for all card-dedup (WR-02) and filter logic.

## Known Stubs

None. All type changes are complete; no placeholder values in the render path.

## Handoffs

- **Plan 09:** `OverlayController` subscribes to `ParagraphSuggestionStore.events`. `renderableSuggestions(for:)` returns `[Suggestion]` with `paragraphHash: ParagraphHash?` — type is clean. LLM filter in `tryDispatchRephraseCard` compares `$0.paragraphHash == hash` (both `ParagraphHash`) — synthesized equality works correctly.
- **Plan 10a:** Settings migration — unaffected by this type change.
- **Plan 10b:** Deletes `scheduler.markDismissed` call + `legacyHash: UInt64` field from `CardQualifier`.
- **Plan 10c:** Deletes legacy `LLMCheckScheduler.swift`, `IncrementalConfig.swift`, `ParagraphSuggestionCache.swift` and their test files wholesale. Their internal `ParagraphCacheKey.paragraphHash: UInt64` field is separate from `Suggestion.paragraphHash` and does not affect the clean type system delivered here.

---
*Phase: 20-paragraph-level-llm-suggestions-with-cache-reconciliation*
*Completed: 2026-04-18*
