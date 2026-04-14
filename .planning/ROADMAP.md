# Roadmap: OpenGram

## Overview

OpenGram is built in dependency order: the menu bar shell and text extraction pipeline come first because every other component depends on them. Harper wires into that pipeline next because the grammar engine is the core value and its byte offset handling must be proven correct before any UI coordinates are computed from its span data. The suggestion UI comes third — inline overlay for AX-direct apps and the floating diff panel for clipboard-mode apps (the primary path for Chrome, Outlook, Word, and Obsidian). LLM style suggestions follow once the UI can accept incremental updates. Settings close out the pipeline by surfacing configuration controls for everything that now exists.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Shell + Hotkey + Text Extraction** - Menu bar app fires global hotkey and extracts text from the frontmost app via the correct tier
- [ ] **Phase 2: Harper Grammar Engine** - Harper checks grammar, spelling, and punctuation via UniFFI xcframework with correct Unicode offsets
- [ ] **Phase 3: Suggestion UI** - Floating diff panel (primary) and inline overlay (AX apps) display and apply suggestions
- [ ] **Phase 4: LLM Style Suggestions** - Optional LLM style/clarity suggestions merged asynchronously with Harper results
- [ ] **Phase 5: Settings** - Full settings window wires user configuration live into the completed pipeline

## Phase Details

### Phase 1: Shell + Hotkey + Text Extraction
**Goal**: The app lives in the menu bar, a global hotkey fires from any application, and the correct text is extracted from the focused app using the right tier — AX direct for native Cocoa apps, clipboard round-trip for Electron and Microsoft apps
**Depends on**: Nothing (first phase)
**Requirements**: SHELL-01, SHELL-02, SHELL-03, SHELL-04, TEXT-01, TEXT-02, TEXT-03, TEXT-04, TEXT-05, TEXT-06, TEXT-07
**Success Criteria** (what must be TRUE):
  1. Pressing Ctrl+Shift+G in Notes extracts the selected text via AX API and logs a TextContext with extraction method "ax-direct"
  2. Pressing Ctrl+Shift+G in Chrome extracts text via clipboard round-trip (Cmd+C simulation), restores original clipboard, and logs a TextContext with extraction method "clipboard"
  3. Pressing Ctrl+Shift+G in Microsoft Word routes immediately to clipboard mode (not AX) based on bundle ID classification
  4. The menu bar icon shows idle/checking/result status and the CGEventTap re-enables itself automatically after sleep/wake or re-sign
  5. Accepting a suggestion writes corrected text back via AX write for AX-direct apps and clipboard paste for clipboard-mode apps
**Plans:** 5 plans

Plans:
- [x] 01-01-PLAN.md — Project scaffold + type contracts (Xcode project, protocols, data types)
- [x] 01-02-PLAN.md — Menu bar shell + first-launch UX (StatusBarController, MenuBuilder, PermissionGuide)
- [x] 01-03-PLAN.md — CGEventTap hotkey system (HotkeyManager, EventTapBridge, health-check loop)
- [x] 01-04-PLAN.md — AX text engine + capability cache (AXTextEngine, AXCapabilityCache)
- [x] 01-05-PLAN.md — Integration wiring + full-flow verification (AppDelegate wiring, manual test)

**UI hint**: yes

### Phase 2: Harper Grammar Engine
**Goal**: Harper checks text for spelling, grammar, and punctuation via a UniFFI xcframework and returns suggestion spans with Unicode-correct byte offset conversion, fast enough for interactive use
**Depends on**: Phase 1
**Requirements**: GRAM-01, GRAM-02, GRAM-03, GRAM-04, GRAM-05, GRAM-06, GRAM-07, GRAM-08, GRAM-09
**Success Criteria** (what must be TRUE):
  1. Harper identifies spelling, grammar, and punctuation errors in a test sentence and returns spans with correct Swift.String.Index positions for text containing emoji, accented characters, and CJK
  2. Harper returns results in under 50ms for a 500-word selection (measured on device, not simulated)
  3. Adding a word to the custom dictionary suppresses that word's false positive in subsequent checks, and the dictionary survives an app restart
  4. Changing dialect (American/British/Canadian/Australian) or disabling a rule category in settings takes effect on the next check
**Plans:** 3 plans

Plans:
- [ ] 02-01-PLAN.md — Rust toolchain + harper-bridge crate + xcframework build pipeline
- [ ] 02-02-PLAN.md — Swift service layer (Suggestion model, DictionaryStore, HarperService actor, Unicode conversion)
- [ ] 02-03-PLAN.md — AppDelegate wiring + integration tests for all GRAM requirements

### Phase 3: Suggestion UI
**Goal**: Users see errors highlighted in the target application and can accept or dismiss individual suggestions — transparent overlay with colored underlines and click-to-show popover for AX-direct apps
**Depends on**: Phase 2
**Requirements**: UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UI-07, UI-08, UI-09, UI-10, UI-11
**Success Criteria** (what must be TRUE):
  1. In Notes (AX-direct mode), colored underlines appear over the focused text field: solid red for spelling, solid blue for grammar+punctuation (two-color scheme per D-04)
  2. Clicking a suggestion underline shows a popover with the original text, replacement, explanation, and source badge (Harper checkmark)
  3. Clicking Accept in the popover replaces the flagged text in the target app via AX write-back; clicking Dismiss removes the underline without changing text; Add to Dictionary available for spelling
  4. Pressing Escape, clicking away from all suggestions, scrolling in the target app, or the target field losing focus dismisses all suggestion UI without changing text
  5. After accepting a suggestion, remaining underlines reposition using authoritative AX bounds re-query
**Plans:** 4 plans

Plans:
- [x] 03-01-PLAN.md — Overlay window + underline rendering + AX bounds query infrastructure
- [x] 03-02-PLAN.md — Popover panel + popover content view + target app observer + dismissal triggers
- [x] 03-03-PLAN.md — Accept/write-back + repositioning + AppDelegate integration + manual verification
- [x] 03-04-PLAN.md — Gap closure: fix scroll dismiss + underline repositioning after accept

**UI hint**: yes

### Phase 4: LLM Style Suggestions
**Goal**: An optional user-configured LLM delivers style and clarity suggestions that appear asynchronously after Harper results, with clear visual distinction, and the app remains fully functional when no LLM is configured
**Depends on**: Phase 3
**Requirements**: LLM-01, LLM-02, LLM-03, LLM-04, LLM-05, LLM-06, LLM-07
**Success Criteria** (what must be TRUE):
  1. With an Ollama endpoint configured, triggering a check shows Harper results immediately; LLM style suggestions (dashed purple/teal underlines or diff panel additions) appear within a few seconds with a loading indicator visible while in-flight
  2. LLM suggestions never include spelling, grammar, or punctuation issues (CheckOrchestrator hard-filters Harper-owned categories), and a malformed LLM JSON response does not crash or block the Harper results already on screen
  3. With no LLM provider configured, the hotkey flow completes normally using Harper results only — no error, no prompt, no degraded behavior
  4. The app correctly calls a user-configured OpenAI-compatible endpoint (Ollama, LM Studio, OpenAI, or custom URL) and the system prompt excludes Harper-flagged spans from LLM scope
**Plans**: TBD

### Phase 5: Settings
**Goal**: A tabbed settings window gives users full control over Harper rules, LLM provider configuration, and custom dictionary management; all settings persist across restarts and propagate live to the running pipeline
**Depends on**: Phase 4
**Requirements**: SET-01, SET-02, SET-03, SET-04, SET-05, SET-06
**Success Criteria** (what must be TRUE):
  1. Opening Settings shows three tabs (Harper, LLM, Behavior); toggling a Harper rule category or changing dialect takes effect on the next hotkey trigger without restarting the app
  2. Entering an LLM provider URL, API key, and model name then clicking Test Connection returns a visible success or failure result; the API key is stored in Keychain, not UserDefaults
  3. Adding or removing a word in the custom dictionary UI takes effect on the next Harper check; the change survives an app restart
  4. All settings (rule toggles, dialect, LLM endpoint, model name, hotkey) persist correctly across app restarts
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shell + Hotkey + Text Extraction | 5/5 | Complete | 2026-04-13 |
| 2. Harper Grammar Engine | 0/3 | Planned | - |
| 3. Suggestion UI | 3/4 | In Progress | - |
| 4. LLM Style Suggestions | 0/? | Not started | - |
| 5. Settings | 0/? | Not started | - |

### Phase 6: UX Polish — Underline Accuracy, Smart Text Replacement, and Grammarly-Style Popover

**Goal:** Production-grade underline positioning via bounds validation pipeline with AX watchdog, range-targeted text replacement that integrates with target app undo stacks, and Grammarly-style popover card with inline diff and click-to-accept interaction
**Requirements**: D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17, D-18, D-19
**Depends on:** Phase 5
**Plans:** 3 plans

Plans:
- [x] 06-01-PLAN.md — AXCallWatchdog + BoundsValidator + AppQuirksTable + UnderlineView cleanup
- [x] 06-02-PLAN.md — OverlayController rewrite (BoundsValidator integration, range-targeted accept, Tab/Enter removal)
- [x] 06-03-PLAN.md — Grammarly-style PopoverView + SuggestionPopoverPanel redesign + manual verification
