# Requirements: OpenGram

**Defined:** 2026-04-13
**Core Value:** Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions -- entirely local by default.

## v1 Requirements

Requirements for POC release (v0.1.0). Each maps to roadmap phases.

### App Shell

- [ ] **SHELL-01**: Menu bar icon displays current status (idle / checking / N suggestions)
- [ ] **SHELL-02**: Global hotkey (Ctrl+Shift+G) triggers grammar check from any app, even when OpenGram is not focused
- [ ] **SHELL-03**: CGEventTap includes health-check loop that re-enables the tap after app re-sign or sleep/wake
- [ ] **SHELL-04**: Menu bar dropdown shows recent activity and quick access to Settings

### Text Extraction

- [ ] **TEXT-01**: AX API direct read extracts selected text (or full field) from the focused element in native Cocoa apps
- [ ] **TEXT-02**: Clipboard round-trip fallback extracts text via simulated Cmd+C when AX API returns nil/empty
- [ ] **TEXT-03**: Clipboard fallback saves and restores original clipboard contents after round-trip
- [ ] **TEXT-04**: App classification table maps known bundle IDs to extraction tier (AX-direct vs clipboard-only)
- [ ] **TEXT-05**: TextContext struct captures: text, source app bundle ID, extraction method, selection range, element bounds
- [ ] **TEXT-06**: AX API direct write replaces text in the target app after user accepts a suggestion
- [ ] **TEXT-07**: Clipboard write-back pastes corrected text via simulated Cmd+V for clipboard-mode apps

### Grammar Checking

- [ ] **GRAM-01**: Harper checks text for spelling errors via UniFFI bridge to harper-core 2.0.0
- [ ] **GRAM-02**: Harper checks text for grammar errors (subject-verb agreement, articles, repeated words)
- [ ] **GRAM-03**: Harper checks text for punctuation errors (apostrophes, missing periods, commas, spacing)
- [ ] **GRAM-04**: Harper returns results in < 50ms for typical text selections
- [ ] **GRAM-05**: Unicode byte offset conversion correctly maps Harper UTF-8 offsets to Swift String.Index for all text including emoji, CJK, and accented characters
- [ ] **GRAM-06**: User can add words to a custom dictionary to suppress false positives
- [ ] **GRAM-07**: Custom dictionary persists across app restarts (stored in Application Support)
- [ ] **GRAM-08**: User can select English dialect (American, British, Canadian, Australian)
- [ ] **GRAM-09**: User can enable/disable individual Harper rule categories in settings

### Suggestion UI

- [ ] **UI-01**: Transparent overlay NSWindow draws colored underlines on flagged text for AX-direct apps
- [ ] **UI-02**: Solid underlines for Harper suggestions with two category colors: red=spelling, blue=grammar+punctuation (Phase 2 D-03 / Phase 3 D-04 override: punctuation merged with grammar under blue; original three-color scheme with orange=punctuation superseded)
- [x] **UI-03**: ~~Dashed underlines for LLM suggestions with category colors (purple=style, teal=clarity)~~ Superseded in v1.1 Phase 11 — dashed underlines replaced by unified LLM suggestion panel
- [ ] **UI-04**: Suggestion popover appears on hover/click showing: original text, suggested replacement, explanation
- [ ] **UI-05**: Popover displays source badge: "Harper" (checkmark) for deterministic, "AI" (sparkle) for LLM
- [ ] **UI-06**: User can Accept or Dismiss individual suggestions via popover buttons
- [ ] **UI-07**: Accepting a suggestion writes the correction back to the target app via the appropriate write-back method
- [x] **UI-08**: ~~Floating diff panel shows side-by-side original/corrected text for clipboard-mode apps~~ Dropped (D-01: no clipboard mode in Phase 3; revisit in v2 if clipboard extraction mode is added)
- [x] **UI-09**: ~~Floating diff panel "Apply" button replaces text via clipboard paste~~ Dropped (D-01: no clipboard mode in Phase 3; depends on UI-08)
- [ ] **UI-10**: Suggestion overlay dismisses on Escape, click-away, or when target field loses focus
- [ ] **UI-11**: Keyboard navigation: Tab cycles suggestions, Enter accepts, Escape dismisses

### LLM Style Checking

- [x] **LLM-01**: OpenAI-compatible API client calls POST /v1/chat/completions for style/clarity suggestions
- [x] **LLM-02**: System prompt instructs LLM to skip grammar/spelling/punctuation (Harper-owned categories)
- [ ] **LLM-03**: System prompt includes Harper-flagged spans so LLM avoids duplicating Harper's work
- [ ] **LLM-04**: CheckOrchestrator hard-filters any LLM suggestions in Harper-owned categories (spelling, grammar, punctuation)
- [x] **LLM-05**: Defensive JSON parser handles malformed LLM output without crashing the suggestion pipeline
- [x] **LLM-06**: LLM suggestions appear asynchronously after Harper results, with a loading indicator while in-flight — Validated in Phase 12: Integration & Testing
- [x] **LLM-07**: App remains fully functional when LLM is not configured or unreachable (Harper-only mode) — Validated in Phase 12: Integration & Testing

### v1.1 Enhancements

Requirements added in the v1.1 milestone (Phases 09–12). Implemented on top of the v1 base.

- [x] **LLMR-01**: Single consolidated LLM request per hotkey fire (replaces 3 per-category calls from Phase 09) — Validated in Phase 09
- [x] **LLMR-02**: Paragraph-scoped LLM input via ParagraphExtractor (selection → paragraph → first 2000 chars) — Validated in Phase 09
- [x] **LLMR-03**: App whitelist gates hotkey activation — only text-editing apps trigger a check — Validated in Phase 10
- [x] **LLMR-04**: Unified LLM suggestion panel with category labels and inline diff (replaces dashed underlays) — Validated in Phase 11

### v1.2 Incremental LLM Checking (Part A — Pipeline)

Requirements for the v1.2 milestone Part A. Gated by `@AppStorage` flag `llmIncrementalCheckingEnabled`. Harper tier is untouched. Source: `.planning/PRD-incremental-llm-checking.md`.

- [x] **INCR-01**: Paragraph splitter splits extracted text on double-newline boundaries with a splitter interface that allows per-bundleID overrides in the future (FR-1)
- [x] **INCR-02**: Paragraph hasher produces stable 64-bit hash that normalizes whitespace-only differences but distinguishes case and punctuation (FR-2)
- [x] **INCR-03**: LLM check fires when user idle ≥ `idleDebounceSeconds` (default 1.5s) OR focus leaves the text field, AND at least one paragraph hash differs from cache (FR-3)
- [x] **INCR-04**: Only paragraphs whose hash differs from cache are sent as targets; unchanged paragraphs are not included as targets (FR-4)
- [x] **INCR-05**: Each request includes immediately preceding and following paragraphs as context-only input; prompt instructs model to return suggestions for target paragraph only (FR-5)
- [x] **INCR-06**: Cache entries keyed on `(bundleID, paragraphHash)`; identical text across different fields shares cache hits (FR-6)
- [x] **INCR-07**: Cache entries track suggestion status `pending | active | dismissed`; dismissed entries do not resurface on refocus while hash is unchanged (FR-7)
- [x] **INCR-08**: In-flight LLM requests are tracked per paragraph; a paragraph's re-edit cancels and reissues only that paragraph's request, leaving other paragraphs' requests untouched (FR-8)
- [x] **INCR-09**: Returning focus to a previously-checked field with identical text issues zero LLM requests (underlines reposition via AX bounds only) (FR-9)
- [x] **INCR-10**: Cache eviction applies LRU cap of 500 entries per bundleID plus 30-minute TTL on unreferenced entries, triggered on insert (FR-10)
- [x] **INCR-11**: `LLMCheckScheduler` is a single coherent component owning splitter, hasher, cache, and per-paragraph cancellation; injected into `AppDelegate` via DI with the same call shape as current LLM call site (NFR-1, NFR-3)
- [x] **INCR-12**: Existing substring-offset rule preserved — response handler searches `original` text within the paragraph and never trusts LLM-returned indices (NFR-7)
- [x] **INCR-13**: Paragraph splitting + hashing for 500-paragraph document completes in <10ms; cache lookups complete in <1ms; scheduler does not block the UI thread on LLM requests (NFR-6)
- [x] **INCR-14**: When `llmIncrementalCheckingEnabled` is off, `LLMCheckScheduler` falls back to full-text checks behaving identically to current implementation (rollout §10)

### v1.2 Paragraph Rephrase Card (Part B — UI)

Requirements for the v1.2 milestone Part B. Depends on Part A. Gated by `@AppStorage` flag `paragraphRephraseCardEnabled`. Source: `.planning/PRD-incremental-llm-checking.md`.

- [ ] **REPH-01**: When a paragraph's LLM suggestions qualify under REPH-02, they are presented as a single unified rephrase card merging all clarity and grammar issues for that paragraph, superseding per-issue popovers for that paragraph (FR-11)
- [ ] **REPH-02**: Paragraph qualifies for rephrase card when any of: ≥`minIssueCount` issues (default 2) OR contains ≥1 clarity/rephrase-class issue OR ≥`minWordCount` words (default 12) AND ≥1 LLM-returned issue (FR-12)
- [ ] **REPH-03**: While rephrase card is visible, the target paragraph in the source text field receives a subtle background highlight that does not modify the user's selection; highlight removed when card hides or dismisses (FR-13)
- [ ] **REPH-04**: Default card body shows full revised paragraph with new/changed text highlighted in mint-green background and unchanged text in neutral color (no strikethrough) (FR-14)
- [ ] **REPH-05**: "What changed?" toggle swaps the card body to a full diff view (~~removed~~ / **added** strikethrough); toggle state is per-card and not persisted; toggling does not reissue an LLM request (FR-15)
- [ ] **REPH-06**: Card header reflects merged issue categories: "Improve clarity" (clarity only), "Fix grammar" (grammar only), "Improve clarity and fix grammar" (both); spelling issues fold in silently (FR-16)
- [ ] **REPH-07**: Card exposes two actions only — Accept (primary, applies rephrase and updates paragraph hash + cache) and Dismiss (secondary, marks cache entry as `dismissed` per INCR-07) (FR-17)
- [ ] **REPH-08**: Clicking outside the card *hides* it without changing cache state (card can reappear on next trigger for unchanged paragraph); Dismiss button persists state; typing inside the target paragraph closes the card and removes the highlight (edit-closes) (FR-18)
- [ ] **REPH-09**: While the rephrase card is visible for a paragraph, all per-issue underlines (Harper + LLM) for that paragraph are hidden; the card is the sole interaction surface (FR-19)
- [ ] **REPH-10**: After Dismiss, Harper per-issue underlines for the paragraph reappear on the next check cycle; after Accept, no underlines appear (LLM fix is superset of Harper) (FR-19)
- [ ] **REPH-11**: LLM prompt addresses spelling, grammar, and clarity/style for the target paragraph (so the rephrase is a true superset of Harper) (FR-19)
- [ ] **REPH-12**: When more than one paragraph qualifies simultaneously, show only the card closest to the cursor; Accept/Dismiss does NOT auto-advance to the next qualifier (FR-21)
- [ ] **REPH-13**: Card styling — rounded-rect with teal accent border, thin vertical accent bar on leading edge, outlined Accept button, bold accent-color header (FR-20)
- [ ] **REPH-14**: Paragraphs not qualifying under REPH-02 fall back to existing per-issue popovers (regression — no change from current behavior for these paragraphs) (FR-12 fallback)
- [x] **REPH-15**: ~~When `paragraphRephraseCardEnabled` is off, all LLM suggestions use existing per-issue popover UI regardless of paragraph qualification (rollout §10)~~ Superseded: rollout flag removed in Phase 18.2; rephrase card is the unconditional default UX. Flag-off parity test suite deleted.

### v1.2 Settings

Requirements for the Advanced settings tab introduced in v1.2. Source: FR-22.

- [x] **SET-07**: New "Advanced" tab in Settings window exposes tunables `minIssueCount` (default 2), `minWordCount` (default 12), `idleDebounceSeconds` (default 1.5), persisted via `@AppStorage` (FR-22)
- [x] **SET-08**: Advanced tab provides a "Reset to defaults" action that restores all exposed values to their defaults (FR-22)
- [x] **SET-09**: Advanced tab displays a warning note at the top stating these settings are unstable and may change or disappear between versions (FR-22)
- [x] **SET-10**: Display heuristic (REPH-02) and scheduler debounce (INCR-03) read live values from settings — changes take effect on next evaluation without app restart (FR-22, testing)

### Settings

- [ ] **SET-01**: Settings window with tabs for Harper, LLM, and Behavior configuration
- [ ] **SET-02**: Harper tab: rule category toggles, custom dictionary management (add/remove words), dialect selector
- [ ] **SET-03**: LLM tab: provider preset selector (Ollama, LM Studio, OpenAI, Custom), endpoint URL, API key, model name
- [ ] **SET-04**: LLM tab: test connection button to verify provider configuration
- [ ] **SET-05**: API keys stored securely in macOS Keychain (never plaintext in UserDefaults/plist)
- [ ] **SET-06**: All settings persist across app restarts

### v1.3 Performance & Scroll-Tracking

Requirements for the v1.3 milestone. Bring overlay UX closer to Grammarly-quality scroll-following in native AX-friendly apps; degrade gracefully elsewhere. Phase numbering resets for v1.3 (phases 1–5). Source: `.planning/OPENGRAM_PERFORMANCE_SPEC.md`.

#### AX Queue (Task 1)

- [x] **PERF-01**: AX bounds reads are serialized through a FIFO actor queue off the main actor; concurrent read requests execute in order without being dropped under burst load (Spec Task 1)
- [x] **PERF-02**: `AXCallWatchdog.shouldSkip` no longer returns true due to an in-flight call for non-blocklisted apps; hang detection and per-app blocklist behavior are preserved (Spec Task 1)

#### Cancellable Bounds (Task 2)

- [x] **PERF-03**: Each bounds reposition campaign runs inside a cancellable `Task`; a new `scheduleReposition` call cancels the previous one before its bounds are applied (Spec Task 2)
- [x] **PERF-04**: Accepting a suggestion, dismissing the overlay, and receiving a scroll event each cancel any pending reposition before proceeding (Spec Task 2)

#### Viewport Cull + Rect Cache (Task 3)

- [x] **PERF-05**: Per-suggestion last-known screen rects are cached on every successful bounds application and cleared on `dismiss()` and on an accepted suggestion's ID (Spec Task 3)
- [x] **PERF-06**: Scroll-driven repositions (`.scrollDuring`, `.scrollSettled`) query only suggestions whose cached rects intersect the padded visible element bounds; `.initial` and `.textChanged` repositions query all suggestions regardless of cache (Spec Task 3)

#### Scroll Handling (Task 4)

- [x] **PERF-07**: Scroll mode per target app is resolved from `AppQuirks.plist`; `com.apple.Notes`, `com.apple.TextEdit`, and `com.apple.mail` use `trackFrame`; all other apps default to `hideAndSettle` (Spec Task 4)
- [x] **PERF-08**: `hideAndSettle` fades underlines to 0 on the first scroll event, debounces until scrolling stops, repositions on settle, then fades underlines back to 1 (Spec Task 4)
- [x] **PERF-09**: `trackFrame` drives reposition off a `CADisplayLink` pump while scroll events arrive; the pump stops and emits one `onIdle` when no event arrives within `idleTimeout` (Spec Task 4)
- [x] **PERF-10**: Three consecutive `trackFrame` frames exceeding the 12ms frame budget demote the current overlay session to `hideAndSettle` until dismiss (Spec Task 4)
- [x] **PERF-11**: A scroll-area `AXObserver` on the focused element's nearest `kAXScrollAreaRole` ancestor catches programmatic scrolls (arrow keys, find-navigation, `scrollToVisible:`) via `kAXScrolledVisibleChildrenChangedNotification` (Spec Task 4)

#### Session-Local Mirror (Task 5)

- [ ] **PERF-12**: On accept, cached rects are preserved for suggestions strictly before the edit site; rects for overlapping and shifted (after-edit) suggestions are invalidated; `.textChanged` reposition queries only the invalidated suggestions (Spec Task 5)

## v2 Requirements

Deferred to future release. Not in current roadmap.

### Enhanced Checking

- **ENH-01**: Real-time as-you-type grammar checking (Harper runs on text change events)
- **ENH-02**: Live LLM-powered style checking (debounced, fires on typing pause)
- **ENH-03**: Confidence threshold slider for filtering low-confidence LLM suggestions
- **ENH-04**: Editable LLM system prompt for power users

### Providers

- **PROV-01**: Dedicated AnthropicProvider for Anthropic's native API format
- **PROV-02**: MLX in-process inference for zero-latency local style suggestions

### Usability

- **USE-01**: Tone/style profiles ("professional", "casual", "academic")
- **USE-02**: Manual paste fallback (Tier 3) when clipboard fails
- **USE-03**: "Accept All Grammar Fixes" batch action (Harper-only)
- **USE-04**: App-specific adapters (VS Code, Electron special handling)
- **USE-05**: Hotkey reconfiguration in settings

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Plagiarism detection | Requires sending text to external database -- contradicts privacy-first value |
| AI text generation | Different product category; distracts from core correction use case |
| Multi-language support | Harper currently supports English only; significant investment |
| Writing statistics/tracking | Requires storing writing history; feature creep from core correction |
| Per-app rule configuration | Settings complexity; not validated need |
| Autocorrect/auto-apply | High false positive risk; destroys trust without explicit user confirmation |
| Browser extension | Clipboard fallback achieves same goal without separate extension codebase |
| Automatic updates | Distribution concern, not a product feature for POC |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHELL-01 | Phase 1 | Pending |
| SHELL-02 | Phase 1 | Pending |
| SHELL-03 | Phase 1 | Pending |
| SHELL-04 | Phase 1 | Pending |
| TEXT-01 | Phase 1 | Pending |
| TEXT-02 | Phase 1 | Pending |
| TEXT-03 | Phase 1 | Pending |
| TEXT-04 | Phase 1 | Pending |
| TEXT-05 | Phase 1 | Pending |
| TEXT-06 | Phase 1 | Pending |
| TEXT-07 | Phase 1 | Pending |
| GRAM-01 | Phase 2 | Pending |
| GRAM-02 | Phase 2 | Pending |
| GRAM-03 | Phase 2 | Pending |
| GRAM-04 | Phase 2 | Pending |
| GRAM-05 | Phase 2 | Pending |
| GRAM-06 | Phase 2 | Pending |
| GRAM-07 | Phase 2 | Pending |
| GRAM-08 | Phase 2 | Pending |
| GRAM-09 | Phase 2 | Pending |
| UI-01 | Phase 3 | Pending |
| UI-02 | Phase 3 | Pending (two-color per D-04) |
| UI-03 | Phase 11 | Superseded (v1.1) |
| UI-04 | Phase 3 | Pending |
| UI-05 | Phase 3 | Pending |
| UI-06 | Phase 3 | Pending |
| UI-07 | Phase 3 | Pending |
| UI-08 | Phase 3 | Dropped (D-01: no clipboard mode) |
| UI-09 | Phase 3 | Dropped (D-01: no clipboard mode) |
| UI-10 | Phase 3 | Pending |
| UI-11 | Phase 3 | Pending |
| LLM-01 | Phase 09 | Complete |
| LLM-02 | Phase 09 | Complete |
| LLM-03 | Phase 4 | Pending |
| LLM-04 | Phase 4 | Pending |
| LLM-05 | Phase 09 | Complete |
| LLM-06 | Phase 12 | Complete |
| LLM-07 | Phase 12 | Complete |
| SET-01 | Phase 5 | Pending |
| SET-02 | Phase 5 | Pending |
| SET-03 | Phase 5 | Pending |
| SET-04 | Phase 5 | Pending |
| SET-05 | Phase 5 | Pending |
| SET-06 | Phase 5 | Pending |

| LLMR-01 | Phase 09 | Complete |
| LLMR-02 | Phase 09 | Complete |
| LLMR-03 | Phase 11 | Complete |
| LLMR-04 | Phase 11 | Complete |

| INCR-01 | Phase 15 | Complete |
| INCR-02 | Phase 15 | Complete |
| INCR-03 | Phase 16 | Complete |
| INCR-04 | Phase 16 | Complete |
| INCR-05 | Phase 16 | Complete |
| INCR-06 | Phase 15 | Complete |
| INCR-07 | Phase 15 | Complete |
| INCR-08 | Phase 16 | Complete |
| INCR-09 | Phase 16 | Complete |
| INCR-10 | Phase 15 | Complete |
| INCR-11 | Phase 16 | Complete |
| INCR-12 | Phase 15 | Complete |
| INCR-13 | Phase 16 | Complete |
| INCR-14 | Phase 16 | Complete |
| REPH-01 | Phase 18 | Pending |
| REPH-02 | Phase 18 | Pending |
| REPH-03 | Phase 18 | Pending |
| REPH-04 | Phase 18 | Pending |
| REPH-05 | Phase 18 | Pending |
| REPH-06 | Phase 18 | Pending |
| REPH-07 | Phase 18 | Pending |
| REPH-08 | Phase 18 | Pending |
| REPH-09 | Phase 18 | Pending |
| REPH-10 | Phase 18 | Pending |
| REPH-11 | Phase 18 | Pending |
| REPH-12 | Phase 18 | Pending |
| REPH-13 | Phase 18 | Pending |
| REPH-14 | Phase 18 | Pending |
| REPH-15 | Phase 18 → Superseded 18.2 | Superseded |
| SET-07 | Phase 17 | Complete |
| SET-08 | Phase 17 | Complete |
| SET-09 | Phase 17 | Complete |
| SET-10 | Phase 17 | Complete |

| PERF-01 | v1.3 Phase 1 | Complete |
| PERF-02 | v1.3 Phase 1 | Complete |
| PERF-03 | v1.3 Phase 2 | Complete |
| PERF-04 | v1.3 Phase 2 | Complete |
| PERF-05 | v1.3 Phase 3 | Complete |
| PERF-06 | v1.3 Phase 3 | Complete |
| PERF-07 | v1.3 Phase 4 | Complete (04-01: AppQuirks resolution + plist allowlist; 04-04: resolveScrollMode + show()-time effectiveScrollMode resolution) |
| PERF-08 | v1.3 Phase 4 | Complete (04-04: hideAndSettle handler + fade primitive + hideSettleTimer debounce + applyBounds .scrollSettled fade-in branch) |
| PERF-09 | v1.3 Phase 4 | Complete (04-02: ScrollTracker class; 04-04: OverlayController.show() trackFrame mode tracker install + handleScrollTick/handleScrollIdle wire) |
| PERF-10 | v1.3 Phase 4 | Complete (04-04: recordFrameCost + 12ms budget threshold + 3-miss limit + decay-on-good-frame + demoteToHideAndSettle session conversion) |
| PERF-11 | v1.3 Phase 4 | Complete (04-03: ScrollAreaObserver class; 04-04: findScrollAreaAncestor 10-level walk + show()-time install on nearest kAXScrollAreaRole ancestor + handleScrollEvent dispatch) |
| PERF-12 | v1.3 Phase 5 | Pending |

**Coverage:**
- v1 requirements: 44 total (UI-08, UI-09 dropped per D-01; 42 active)
- v1.1 requirements: 4 (LLMR-01 through LLMR-04)
- v1.2 requirements: 33 (INCR-01..14, REPH-01..15, SET-07..10)
- v1.3 requirements: 12 (PERF-01..12)
- Mapped to phases: 93
- Dropped: 2 (UI-08, UI-09)
- Superseded: 1 (UI-03 replaced by LLMR-04)
- Unmapped: 0

---
*Requirements defined: 2026-04-13*
*Last updated: 2026-04-18 -- v1.3 Performance & Scroll-Tracking requirements added (PERF-01..12)*
