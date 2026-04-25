# OpenGram

## What This Is

A macOS menu bar app that provides system-wide grammar, spelling, and writing style correction across all applications. Uses a two-tier checking architecture: Harper (Rust grammar engine via UniFFI) for instant deterministic grammar/spelling checking, and an optional user-configured LLM for style and clarity suggestions. No subscriptions, no data leaving the device unless the user explicitly configures a cloud LLM provider.

## Core Value

Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions — entirely local by default, with no account or subscription required.

## Requirements

### Validated

- ✓ Harper-powered deterministic grammar, spelling, and punctuation checking (instant, offline) — v1.0
- ✓ Suggestion overlay UI: underlines on flagged text, popover with suggestions on hover/click — v1.0
- ✓ Accept/dismiss individual suggestions, with text replacement on accept — v1.0
- ✓ LLM-powered style and clarity suggestions (optional, user-configured, on-demand) — v1.1
- ✓ Consolidated single LLM request with paragraph scoping — v1.1
- ✓ Unified LLM suggestion panel with inline diff, category labels, and Apply — v1.1
- ✓ App whitelist gates hotkey and TextMonitor on text-editing apps — v1.1
- ✓ Two-phase check flow: Harper instant → LLM async panel — v1.1
- ✓ Harper-only mode when LLM unconfigured — v1.1
- ✓ OpenAI-compatible API backend for style checks — v1.1
- ✓ Paragraph-level LLM suggestions with per-paragraph state machine + reconciliation (ParagraphSuggestionStore actor) — v1.2
- ✓ Unified Rephrase Card with additions-only diff + "What changed?" full-diff toggle + Accept/Dismiss — v1.2
- ✓ Qualifying-paragraph heuristic (min issue count / min word count / clarity-class) — v1.2
- ✓ Source-paragraph highlight while card visible; underlines hidden in card scope — v1.2
- ✓ Advanced Settings tab with live-read tunables (idle debounce, min issue count, min word count) — v1.2
- ✓ FIFO LLM request queue with 30s timeout + per-paragraph cancellation on edit — v1.2
- ✓ AXTextReplacer shared write primitive for accept paths — v1.2
- ✓ AX call queue: FIFO actor serializes AX bounds reads off main thread — v1.3 (PERF-01, PERF-02)
- ✓ Cancellable bounds queries: Task-based reposition cancels on accept/dismiss/scroll — v1.3 (PERF-03, PERF-04)
- ✓ Viewport cull + session-local rect cache: `lastKnownRects` powers scroll-time cull — v1.3 (PERF-05, PERF-06)
- ✓ Per-app scroll modes: `trackFrame` (Notes/TextEdit/Mail) + `hideAndSettle` (fallback); 3-miss 12ms-budget demotion; scroll-area AXObserver — v1.3 (PERF-07 through PERF-11)
- ✓ Zero-AX accept path: pre-shift cache invalidation preserves survivor rects; end-of-doc accepts = 0 AX calls — v1.3 (PERF-12)

### Active

**v1.4 Clarity Engine:**
- [ ] Harper-native `WordyPhrasesLinter` with first-token hashmap matcher
- [ ] ~500-entry phrase dataset (retext-simplify + write-good + plainlanguage.gov)
- [ ] Clarity rendered as solid orange (source `.harper`, category `.clarity`)
- [ ] Case preservation + inflection handling + word-boundary safety
- [ ] Severity levels (High/Medium default-on, Low default-off)
- [ ] Settings UI: clarity master toggle + opinionated sub-toggle
- [ ] `.clarity` case removed from `LLMCheckType` — clean replace, no flag/migration
- [ ] System prompt no longer requests clarity; LLM still handles `.tone`/`.rephrase`

**Carryover (pre-v1.4):**
- [ ] Three-tier text extraction: AX API direct → clipboard fallback → manual paste
- [ ] Floating diff panel for apps without AX support (Chrome, Electron apps)
- [ ] Settings UI: Harper rule toggles, hotkey config, custom dictionary (LLM settings done)
- [ ] Menu bar app with status indicator (basic done, needs polish)
- [ ] Custom dictionary for suppressing Harper false positives

### Out of Scope

- Real-time as-you-type checking — deferred to v2 (requires per-app text monitoring research)
- MLX in-process inference — deferred to v2
- App-specific adapters (VS Code, Electron special handling) — deferred to v2
- Tone/style profiles ("professional", "casual") — deferred to v2 (POC uses single default style)
- Multi-language support — deferred to v2+
- Automatic updates / distribution — deferred
- Anthropic-specific API provider — deferred (users can use OpenAI-compatible proxy)
- Live LLM-powered style checking — deferred to v2 (POC is on-demand only)

## Context

- **Target apps (primary user):** Chrome, Microsoft Outlook, Microsoft Word, Notes, Obsidian
- **App AX support reality:** Notes is native Cocoa (full AX). Chrome, Outlook, Word, and Obsidian have limited/unreliable AX text access. This means clipboard fallback (Tier 2) with the floating diff panel is the primary UI path for most daily-driver apps. Inline overlay is a bonus for native apps, not the baseline experience.
- **Harper integration research:** Detailed research completed (`planning/harper-integration-research.md`). UniFFI (Mozilla's Rust→Swift binding generator) is the recommended approach over raw C FFI. Fallback: bundle `harper-cli` as subprocess if UniFFI proves too painful.
- **Harper performance:** < 10ms per check for typical text, < 50MB memory, FST-compressed dictionary shipped in binary.
- **LLM scoping:** The LLM is never asked about grammar/spelling/punctuation (Harper owns those). LLM system prompt explicitly excludes Harper-owned categories. CheckOrchestrator hard-filters any LLM suggestions in Harper-owned categories.
- **Versioning:** Manual semver. Start at v0.0.1, increment bugfix versions until v0.1.0 POC is ready.

## Constraints

- **Platform:** macOS 14.0+ (Sonoma) — AX API improvements, SwiftUI maturity
- **Language:** Swift (UI, AX, events) + Rust (Harper core via UniFFI)
- **UI Framework:** SwiftUI for settings, AppKit for overlay windows (SwiftUI can't do transparent overlays)
- **Distribution:** Direct .dmg download — avoids App Store sandboxing which cripples AX API access
- **Secret storage:** Keychain for API keys — never plaintext in UserDefaults/plist
- **Privacy:** No telemetry, no error reporting, no external API calls unless user configures LLM provider
- **Hotkey:** Ctrl+Shift+G (global, fires even when app isn't focused)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| UniFFI over raw C FFI for Harper | Auto-generated type-safe Swift bindings, battle-tested by Mozilla, no manual memory management | Validated (Phase 2) |
| Clipboard fallback as primary UI path | 4/5 target apps (Chrome, Outlook, Word, Obsidian) have limited AX support | — Pending |
| On-demand only for POC (no live checking) | Live checking requires per-app text monitoring; hotkey flow proves the full pipeline with lower risk | — Pending |
| OpenAI-compatible API only for POC | Single implementation covers OpenAI, Ollama, LM Studio, llama.cpp; Anthropic deferred | ✓ Validated (v1.1) |
| Default style prompt only for POC | Focus on clarity/brevity/tone; tone profiles deferred to v2 | ✓ Validated (v1.1) |
| Manual semver (v0.0.1 → v0.1.0) | User-controlled version progression, no automated version tagging | — Pending |
| Consolidated LLM (3→1 request) | Single request with unified prompt covers clarity/tone/rephrase; reduces latency and malformed responses | ✓ Validated (v1.1) |
| NSPanel for LLM suggestions | Non-activating floating panel preserves focus in target app; SwiftUI content via NSHostingView | ✓ Validated (v1.1) |
| App whitelist (default 26 apps) | Bundle ID gating prevents checks in Terminal, Finder, etc.; user-editable via settings | ✓ Validated (v1.1) |
| NSHostingView.fittingSize for panel sizing | intrinsicContentSize unreliable before layout; fittingSize after layoutSubtreeIfNeeded is correct | ✓ Validated (v1.1) |
| ParagraphSuggestionStore (actor) supersedes LLMCheckScheduler | Store-based reconciliation with state machine handles async LLM results cleanly; scheduler+cache pattern required conditional logic on top of its own cache | ✓ Validated (v1.2 Phase 20) |
| Delete rollout flags wholesale at milestone close | Standalone app has no deployment risk; flags add cognitive load without operational benefit; "no deprecation cycles" per CLAUDE.md | ✓ Validated (v1.2 Phase 18.2 + 18.3) |
| Rephrase card as unconditional default UX | Single surface for paragraph-level LLM results eliminates dual-path (card + LLMPanelController) maintenance; legacy panel deleted | ✓ Validated (v1.2 Phase 18.2) |
| Replace Phase 19 dedicated UAT with per-phase manual checkpoints | 18.1 UAT + 18.2-03 + 18.3-04 each exercised the full pipeline in Notes.app; dedicated integration phase added no coverage | ✓ Validated (v1.2) |
| AXCallQueue actor FIFO for off-main-actor AX serialization | Actor isolation guarantees ordering without locks; `.shared` default DI keeps 27+ call sites compile-unchanged; boundsBatch cancels cooperatively via CancellationError | ✓ Validated (v1.3 Phase 1) |
| `applyBoundsCallCount` spy (Option C) for cancellation tests | Deterministic count-based assertion avoids wall-clock race; spy placed on AXCallQueue production boundary survives mock swap-outs | ✓ Validated (v1.3 Phase 2 + 5) |
| Per-app scroll modes via AppQuirks plist | `trackFrame` for Notes/TextEdit/Mail (CADisplayLink); `hideAndSettle` fallback for everything else; runtime demotion at 12ms × 3-miss threshold | ✓ Validated (v1.3 Phase 4) |
| `ScrollAreaObserver` on `kAXScrollAreaRole` ancestor catches programmatic scrolls | NSEvent scrollWheel misses arrow-key nav, find-nav, `scrollToVisible:` (~20% of scrolls); AXObserver fills gap mirroring TargetAppObserver retain/release discipline | ✓ Validated (v1.3 Phase 4) |
| Pre-shift cache invalidation preserves strictly-before survivors | Zero-AX accept path for end-of-doc edits becomes a cache-walk with no AX round-trip; `.textChanged` filter queries only uncached subset | ✓ Validated (v1.3 Phase 5) |
| Source-position regression lock when runtime is observationally invariant | Plan 06-01 zero-AX ordering delta is zero mathematically on strictly-before branch — asserting closure body text via `#filePath` substring match is the only test that catches re-inversion | ✓ Validated (v1.3 Phase 6) |

## Current State

**Shipped:** v1.3 (2026-04-19)
**Stack:** Swift 6 + Rust (Harper via UniFFI) + AppKit + SwiftUI
**LOC:** ~18k Swift (OpenGram + OpenGramTests combined)

v1.3 delivered Grammarly-quality scroll-following for native AX-friendly apps via a full overlay performance overhaul: `AXCallQueue` actor serializes AX reads off main thread, reposition campaigns run as cancellable `Task`s that cancel on accept/dismiss/scroll, per-suggestion `lastKnownRects` cache powers viewport cull during scroll, and per-app scroll modes (`trackFrame` CADisplayLink pump for Notes/TextEdit/Mail; `hideAndSettle` fade-reposition-fade elsewhere) adapt at runtime with a 3-frame-miss demotion at 12ms budget. Zero-AX accept path added for edits at document end via pre-shift cache invalidation. Phase 6 closed all 3 milestone-audit gaps (zero-AX early-bail ordering swap, `RepositionReason.initial` dead-case strip, PERF-01 scope clarification). All 12 PERF-XX requirements complete.

<details>
<summary>v1.2 (shipped 2026-04-19)</summary>

Paragraph-level LLM suggestions backed by `ParagraphSuggestionStore` (actor + per-paragraph state machine + reconciliation-on-tick) with unified Rephrase Card as unconditional default. Mid-milestone pivot replaced originally-planned `LLMCheckScheduler` + flag-gated architecture with store-based design (Phase 20). Rollout flags removed. Advanced Settings tab exposes live-read tunables. Phase 19 skipped — scope absorbed by per-phase UATs; rendered moot by Phase 20 rewrite.

</details>

<details>
<summary>v1.1 (shipped 2026-04-15)</summary>

Consolidated LLM integration: single request, paragraph scoping, unified suggestion panel with inline diff and Apply, app whitelist gating, and two-phase hotkey flow.

</details>

## Current Milestone: v1.4 Clarity Engine

**Goal:** Ship a rules-only Harper-native clarity detection layer powered by a ~500-entry curated phrase dataset, and hand off the `.clarity` dimension from the LLM to deterministic phrase rules. LLM `.tone`/`.rephrase` stay wired and untouched.

**Target features:**
- Harper-native `WordyPhrasesLinter` (first-token hashmap over Harper-tokenized input, ~500 phrase replacements)
- Clarity as distinct visual category (solid orange underline, source `.harper` replaces LLM dashed-orange)
- Case preservation, inflection handling, word-boundary safety
- Grammar > clarity priority on span overlap (via Harper's `remove_overlaps` + priority field)
- Per-rule toggles + severity levels (High/Medium default-on, Low default-off)
- `.clarity` removed from `LLMCheckType` — clean replace, no feature flag, no migration
- Dataset sourced from retext-simplify (MIT), write-good (MIT), plainlanguage.gov (US public domain); committed as TOML, compiled via `include_str!`

**Key context:**
- Full spec: [`.planning/CLARITY_ENGINE_SPEC.md`](CLARITY_ENGINE_SPEC.md)
- Non-functional items (≤5ms lint budget, ≤50ms total, ≤200KB dataset, offline, Unicode-safe) are **targets**, not hard requirements
- NO feature flags. NO migration layer. Clean replace per CLAUDE.md standalone-app philosophy.
- Visual reuses existing `CheckCategory.clarity` — source flips `.llm` (dashed) → `.harper` (solid)
- v1.3 carryover items (rapid-multi-accept cascade, inherited debug sessions, parallel-load flakes) **not** in scope

**v1.3 status:** ✅ Shipped 2026-04-19. See [`.planning/milestones/v1.3-ROADMAP.md`](milestones/v1.3-ROADMAP.md) for archive and [`.planning/milestones/v1.3-MILESTONE-AUDIT.md`](milestones/v1.3-MILESTONE-AUDIT.md) for audit.

**v1.4 progress (Phase 10 complete 2026-04-25):** Production `WordyPhrasesLinter` wired via `build_lint_group` dialect filter — 5-regime case preservation, word-boundary safety, dialect filtering all green (11/11 cargo tests, xcodebuild app + test SUCCEEDED). Spike + stub deleted atomically. CLAR-01, CLAR-03, CLAR-04, CLAR-05, CLAR-06 validated. Next: Phase 11 (Dataset Integration + Fixture Harness).

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone:**
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-25 — Phase 10 (Matcher Implementation) complete; production WordyPhrasesLinter shipped*
