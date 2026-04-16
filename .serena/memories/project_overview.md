# OpenGram — Project Overview

macOS menu bar app providing system-wide grammar, spelling, and writing style correction across all applications.

## Core Value
Press Ctrl+Shift+G in any app → instant grammar corrections (Harper) + optional AI style suggestions (LLM). Entirely local by default. No account, no subscription.

## Architecture: Two-tier checking
1. **Harper** (Rust grammar engine via UniFFI) — deterministic grammar/spelling, instant
2. **LLM** (user-configured, optional) — style and clarity suggestions via OpenAI-compatible `/v1/chat/completions`

## Key constraints
- macOS 14.0+ only
- No telemetry, no external calls unless user configures LLM provider
- Distributed as direct .dmg (AX API requires entitlements incompatible with App Store sandboxing)
- API keys stored in Keychain (never UserDefaults/plist)
- Hotkey: Ctrl+Shift+G (global, via CGEventTap)
