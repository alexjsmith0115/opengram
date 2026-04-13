# Phase 2: Harper Grammar Engine - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-13
**Phase:** 02-harper-grammar-engine
**Areas discussed:** Suggestion data contract, Custom dictionary behavior, Config change propagation, Edge cases & limits

---

## Suggestion Data Contract

| Option | Description | Selected |
|--------|-------------|----------|
| Best replacement only | Pick Harper's top-priority suggestion. One Accept button per underline. | |
| All replacements | Pass through all suggestions. Popover shows a list. | |
| Best + alternatives on expand | Top replacement default, 'More options' affordance. | |
| User: "do whatever grammarly does" | Grammarly-style: best shown prominently, all carried in data model. | ✓ |

**User's choice:** "Do whatever Grammarly does" — best replacement prominent, all replacements in data model for Phase 3 presentation.
**Notes:** User consistently references Grammarly as UX model.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Include rule ID | Each suggestion carries Harper's rule identifier. Enables 'Disable this rule'. | |
| Category only | Only broad category (spelling/grammar/punctuation). | ✓ |

**User's choice:** "Defer this to a later version" — category only for v1.
**Notes:** Rule-level toggling explicitly deferred to v2.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Three buckets (spelling, grammar, punctuation) | Matches REQUIREMENTS.md UI-02 three-color scheme. | |
| Pass through Harper's full category set | All LintKind variants preserved. | |
| User: two buckets | Spelling (red), grammar+punctuation (blue). | ✓ |

**User's choice:** "Spelling should be red, grammar and punctuation should both be blue. I think this is how Grammarly does it."
**Notes:** Overrides REQUIREMENTS.md UI-02. Punctuation merges with grammar under blue.

---

## Custom Dictionary Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Global dictionary | One dictionary for all dialects. | ✓ |
| Per-dialect dictionary | Separate dictionaries per dialect. | |

**User's choice:** Global dictionary (recommended option).
**Notes:** None.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Suggestion popover + Settings | Phase 3 popover 'Add to Dictionary' + Phase 5 full management. | ✓ |
| Settings only | Dictionary management exclusively in Settings. | |

**User's choice:** Suggestion popover + Settings (recommended option).
**Notes:** None.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Plain text file, one word per line | ~/Library/Application Support/OpenGram/dictionary.txt | ✓ |
| JSON file | Structured format with metadata. | |

**User's choice:** Plain text file (recommended option).
**Notes:** Matches Harper's own UserDictionary format.

---

## Config Change Propagation

| Option | Description | Selected |
|--------|-------------|----------|
| Next hotkey trigger | Changes saved to disk, picked up on next check. | ✓ |
| Immediate re-check | Auto re-run Harper on last extracted text. | |

**User's choice:** Next hotkey trigger (recommended option).
**Notes:** Matches Success Criteria #4 exactly.

---

| Option | Description | Selected |
|--------|-------------|----------|
| No effect on dictionary | Dictionary independent of dialect. | ✓ |
| Warn about dialect-specific words | Flag words that become standard in new dialect. | |

**User's choice:** No effect on dictionary (recommended option).
**Notes:** None.

---

## Edge Cases & Limits

**Pre-discussion research:** User asked "how does Grammarly and TextWarden handle this" before answering. Research findings:
- Grammarly: 100K char hard cap in editor, no pre-filtering for non-prose (flags URLs, breaks hyperlinks), spinning G icon during check.
- TextWarden: No hard limit, async above 1000 chars, zero Swift-side filtering (trusts Harper entirely), floating indicator shows loading/count.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Check all, no limit | Same as TextWarden. No truncation. Background queue for long text. | ✓ |
| Soft cap with warning | Check anyway but log diagnostic warning above threshold. | |

**User's choice:** Check all, no limit (recommended option).
**Notes:** None.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Trust Harper's parser | No pre-filtering. Delegate to Harper's PlainEnglish parser. | ✓ |
| Light pre-filter for obvious non-prose | Strip URLs/file paths before Harper. | |

**User's choice:** "Trust Harper for now but may revisit this in a later revision."
**Notes:** Acknowledged potential for false positives but wants to start simple.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Pipeline only — no UI yet | Produces [Suggestion] array. Console logging for dev. Phase 3 handles UI. | ✓ |
| Menu bar suggestion count | Show count in menu bar before Phase 3 exists. | |

**User's choice:** Pipeline only (recommended option).
**Notes:** None.

---

## Claude's Discretion

- UniFFI bridge crate structure and API surface
- xcframework build pipeline
- Unicode byte offset conversion
- HarperChecker lifecycle management
- Background queue strategy
- Swift-side Suggestion model struct
- Unicode test strategy

## Deferred Ideas

- Per-rule toggling from suggestion UI (v2)
- Non-prose pre-filtering (may revisit if false positives excessive)
- Dialect-aware dictionary warnings (decided unnecessary)
