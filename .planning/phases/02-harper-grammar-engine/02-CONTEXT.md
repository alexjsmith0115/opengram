# Phase 2: Harper Grammar Engine - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Harper checks text for spelling, grammar, and punctuation via a UniFFI xcframework and returns suggestion spans with Unicode-correct byte offset conversion, fast enough for interactive use. This phase builds the Rust bridge crate, the xcframework build pipeline, the Swift-side checker service, the custom dictionary, and the config propagation — but produces NO user-visible UI. Phase 3 owns all suggestion display.

</domain>

<decisions>
## Implementation Decisions

### Suggestion Data Contract
- **D-01:** Grammarly-style replacements — best replacement shown prominently, but all Harper replacements carried in the data model so Phase 3 can decide presentation (e.g., "More options" affordance).
- **D-02:** No rule ID per suggestion for v1. Category-only. Rule-level toggling deferred to v2.
- **D-03:** Two visual category buckets: **spelling (red)** and **grammar+punctuation (blue)**. This overrides REQUIREMENTS.md UI-02's three-color scheme (red/blue/orange) — punctuation merges with grammar under blue. Harper's finer LintKind variants (Repetition, WordChoice, Formatting, Miscellaneous, etc.) all roll up into the grammar+punctuation bucket.

### Custom Dictionary
- **D-04:** Global dictionary shared across all dialects. No per-dialect dictionaries.
- **D-05:** "Add to Dictionary" available from suggestion popover (Phase 3) and full dictionary management in Settings (Phase 5). Phase 2 exposes the API; Phases 3 and 5 wire the UI.
- **D-06:** Plain text file, one word per line: `~/Library/Application Support/OpenGram/dictionary.txt`. Matches Harper's own UserDictionary format.

### Config Change Propagation
- **D-07:** Dialect and rule category changes take effect on the **next hotkey trigger**. Changes saved to disk immediately, but no re-check of currently visible suggestions.
- **D-08:** Changing dialect has no effect on the custom dictionary. Dictionary is fully independent of dialect selection.

### Edge Cases & Limits
- **D-09:** No text length limit. Check all extracted text regardless of size. For text above a performance threshold, run Harper on a background queue. Menu bar already shows "checking" state from Phase 1.
- **D-10:** Trust Harper's PlainEnglish parser for non-prose filtering (URLs, code, file paths). No Swift-side pre-filtering. May revisit in a later revision if false positives are excessive.
- **D-11:** Phase 2 is pipeline-only — no user-visible output. Produces a `[Suggestion]` array consumed by Phase 3. AppDelegate logs results to console for development/testing.

### Claude's Discretion
- UniFFI bridge crate structure and API surface design
- xcframework build pipeline (build-harper.sh, lipo, uniffi-bindgen)
- Unicode byte offset (UTF-8) → Swift String.Index conversion implementation
- HarperChecker lifecycle (create new vs reconfigure on config change)
- Background queue strategy for long text
- Swift-side Suggestion model struct design (beyond the decisions above)
- Test strategy for Unicode edge cases (emoji, CJK, accented chars, combined marks)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Harper Integration
- `planning/harper-integration-research.md` — UniFFI bridge design, Harper API surface, GrammarSuggestion struct proposal, build pipeline, performance benchmarks
- `planning/initial_design.prd` — Original product design document with full architecture

### Phase 1 Context
- `.planning/phases/01-shell-hotkey-text-extraction/01-CONTEXT.md` — AX-only extraction decisions, silent-fail pattern, TextContext struct, write-back approach

### Requirements
- `.planning/REQUIREMENTS.md` §Grammar Checking (GRAM-01 through GRAM-09) — all nine requirements mapped to this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `OpenGram/TextEngine/TextContext.swift` — The data contract from Phase 1. Harper receives `context.text: String` and returns suggestions with byte offsets that map back to positions in this text.
- `OpenGram/App/AppDelegate.swift:handleHotkeyFired()` — The integration point. Currently extracts text and logs it. Phase 2 wires Harper check between extraction and the (future) UI display.
- `OpenGram/Shell/IconStateMachine.swift` — Menu bar state machine with `.checking` state already implemented. Used for long-text feedback.

### Established Patterns
- Swift 6 strict concurrency (`@Sendable`, `nonisolated(unsafe)` for AXUIElement)
- `@MainActor` for UI-touching code in AppDelegate
- Protocol-based dependency injection (`AXTextEngineProtocol`, `HotkeyManagerProtocol`, `AXCapabilityCacheProtocol`)
- SPM-based build with `OpenGramLib` library target and separate `OpenGramTests`

### Integration Points
- `AppDelegate.handleHotkeyFired()` — where Harper plugs in after text extraction
- `TextContext.text` — the String input to Harper
- `TextContext.selectionRange` / `TextContext.elementBounds` — needed by Phase 3 for positioning suggestions, Phase 2 preserves these
- `Package.swift` — will need a new dependency or xcframework integration for the Harper bridge

</code_context>

<specifics>
## Specific Ideas

- Category mapping explicitly follows Grammarly's visual pattern: spelling=red, everything else=blue. User referenced Grammarly as the UX model for multiple decisions.
- TextWarden's approach validated as reference implementation: no text limits, trust Harper's parser, async for long text.
- Non-prose filtering may be revisited in a later revision — user acknowledged Harper might need help but wants to start with trusting its parser.
- The "Add to Dictionary" action in the suggestion popover (Phase 3) means the Phase 2 bridge API must expose an `addToDictionary(word:)` method, not just `check(text:)`.

</specifics>

<deferred>
## Deferred Ideas

- **Per-rule toggling from suggestion UI** — "Disable this rule" action in popover. Requires rule ID in suggestion data model. Deferred to v2.
- **Non-prose pre-filtering** — Swift-side URL/code/path stripping before Harper. May revisit if false positive rates are excessive in real-world use.
- **Dialect-aware dictionary warnings** — Flagging custom dictionary words that become standard in a new dialect. Decided as unnecessary complexity.

### Requirements Impact
- **UI-02** (three-color underlines): Adjusted from three colors (red/blue/orange) to two (red/blue). Punctuation merged with grammar under blue. This affects Phase 3 implementation.

</deferred>

---

*Phase: 02-harper-grammar-engine*
*Context gathered: 2026-04-13*
