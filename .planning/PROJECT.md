# OpenGram

## What This Is

A macOS menu bar app that provides system-wide grammar, spelling, and writing style correction across all applications. Uses a two-tier checking architecture: Harper (Rust grammar engine via UniFFI) for instant deterministic grammar/spelling checking, and an optional user-configured LLM for style and clarity suggestions. No subscriptions, no data leaving the device unless the user explicitly configures a cloud LLM provider.

## Core Value

Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions — entirely local by default, with no account or subscription required.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] On-demand grammar/spelling checking via global hotkey (Ctrl+Shift+G)
- [ ] Harper-powered deterministic grammar, spelling, and punctuation checking (instant, offline)
- [ ] LLM-powered style and clarity suggestions (optional, user-configured, on-demand)
- [ ] Suggestion overlay UI: underlines on flagged text, popover with suggestions on hover/click
- [ ] Accept/dismiss individual suggestions, with text replacement on accept
- [ ] Visual distinction between Harper (deterministic) and LLM (AI) suggestions
- [ ] Three-tier text extraction: AX API direct → clipboard fallback → manual paste
- [ ] Floating diff panel for apps without AX support (Chrome, Electron apps)
- [ ] OpenAI-compatible API backend for style checks (covers OpenAI, Ollama, LM Studio, llama.cpp)
- [ ] Settings UI: Harper rule toggles, LLM endpoint/key/model, hotkey config, custom dictionary
- [ ] Menu bar app with status indicator
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
| UniFFI over raw C FFI for Harper | Auto-generated type-safe Swift bindings, battle-tested by Mozilla, no manual memory management | — Pending |
| Clipboard fallback as primary UI path | 4/5 target apps (Chrome, Outlook, Word, Obsidian) have limited AX support | — Pending |
| On-demand only for POC (no live checking) | Live checking requires per-app text monitoring; hotkey flow proves the full pipeline with lower risk | — Pending |
| OpenAI-compatible API only for POC | Single implementation covers OpenAI, Ollama, LM Studio, llama.cpp; Anthropic deferred | — Pending |
| Default style prompt only for POC | Focus on clarity/brevity/tone; tone profiles deferred to v2 | — Pending |
| Manual semver (v0.0.1 → v0.1.0) | User-controlled version progression, no automated version tagging | — Pending |

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
*Last updated: 2026-04-13 after initialization*
