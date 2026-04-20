---
phase: 08-dataset-pipeline
plan: "03"
subsystem: dataset-pipeline
tags: [python, dataset, parsers, retext-simplify, plainlanguage]
dependency_graph:
  requires:
    - harper-bridge/scripts/build_wordy_phrases.py (Plan 02 infrastructure)
    - harper-bridge/scripts/tests/fixtures/tiny-retext.js
    - harper-bridge/scripts/tests/fixtures/tiny-plainlang.md
  provides:
    - parse_retext_js (standalone function in build_wordy_phrases.py)
    - parse_plainlang_md (standalone function in build_wordy_phrases.py)
  affects:
    - Plan 04 (wires parsers into build() + merge + override passes)
tech_stack:
  added: []
  patterns:
    - Bounded regex parsing (VERBOSE + DOTALL; no nested quantifiers per T-8-05)
    - D-22 first-replacement-only via split(",")[0] and next(r for r in replacements if r)
    - D-23 dirty-dozen detection via bold-bold row (`**x** | **y**`)
    - D-24 omit:true → note="Upstream also supports deletion."
    - P-1 curly apostrophe via normalize_text (already in module)
    - P-8 compound left-side split on comma into N entries sharing replacement
key_files:
  created: []
  modified:
    - harper-bridge/scripts/build_wordy_phrases.py (151 lines added; 245 → 396 total)
decisions:
  - "Appended both parsers as standalone functions after _discover_source_shas; build() left exactly as Plan 02 stub per B2 scope narrowing"
  - "Header-row skip uses 'Don' in left_raw check (robust to curly apostrophe in raw source before normalize_text)"
metrics:
  duration: "~3 min"
  completed: "2026-04-20T00:00:00Z"
  tasks_completed: 2
  files_created: 0
  files_modified: 1
---

# Phase 08 Plan 03: Parser Functions — parse_retext_js + parse_plainlang_md Summary

Regex-based parsers for retext-simplify JS and plainlanguage.gov markdown added to build_wordy_phrases.py as standalone functions; D-22/D-23/D-24/P-1/P-8 semantics verified at parser layer; build() unchanged from Plan 02 stub.

## Parser Function Signatures

```python
def parse_retext_js(text: str) -> list[dict]:
    """Parse retext-simplify patterns.js into list of entry dicts.
    Handles D-22 (first replacement only) + D-24 (omit:true → first-non-empty + note).
    Bounded regex only — no ReDoS surface (no nested quantifiers).
    """

def parse_plainlang_md(text: str) -> list[dict]:
    """Parse plainlanguage.gov use-simple-words-phrases.md into entry dicts.
    D-22: multi-replacement rows take first replacement only.
    D-23: bold-bold rows (dirty dozen) flagged for severity bump.
    P-1: curly apostrophes flattened via normalize_text.
    P-8: compound left cell splits into N entries.
    """
```

## Supporting Regex Constants Added

| Constant | Purpose |
|----------|---------|
| `_RETEXT_ENTRY_RE` | Match `'key': { body }` or `key: { body }` blocks |
| `_RETEXT_REPLACE_LIT_RE` | Extract string literals from `replace: [...]` array |
| `_RETEXT_OMIT_RE` | Detect `omit: true` in entry body |
| `_RETEXT_REPLACE_ARR_RE` | Locate `replace: [...]` block in body |
| `_YAML_FM_RE` | Strip YAML front-matter (`---\n...\n---\n`) |
| `_PIPE_ROW_RE` | Match `left | right` pipe-table rows |
| `_BOLD_WRAP_RE` | Detect `**cell**` bold wrapping (D-23) |

Helper: `_strip_bold(cell) -> tuple[str, bool]`

## Fixture Entry Counts (Parser-Level Verification)

| Parser | Fixture | Expected | Actual |
|--------|---------|----------|--------|
| `parse_retext_js` | `tiny-retext.js` | 5 | 5 |
| `parse_plainlang_md` | `tiny-plainlang.md` | 6 | 6 |

### Semantic Assertions Verified

**parse_retext_js:**
- `'a number of'` → replacement `"many"` (D-22: first of `['many', 'some']`)
- `abundance` bare identifier key parsed correctly
- `'be advised'` omit:true → `_omit=True`, `replacement="please"`, `note="Upstream also supports deletion."` (D-24)
- All 5 entries: `sources=["retext-simplify"]`, `dirty_dozen=False`

**parse_plainlang_md:**
- `addressees` → `dirty_dozen=True` (bold-bold row, D-23)
- `assist, assistance` → 2 entries both with `replacement="aid"` (P-8 compound split + D-22 first of `aid, help`)
- `don't` (curly apostrophe in raw source) → phrase `"don't"` straight apostrophe (P-1 via normalize_text)
- All 6 entries: `sources=["plainlanguage.gov"]`

## build() Unchanged from Plan 02 (B2 Fix)

`grep -c "parse_retext_js\|parse_plainlang_md" harper-bridge/scripts/build_wordy_phrases.py` returns exactly `2` — only the two `def` lines. Zero call sites inside `build()`. The stub:

```python
entries: list[dict] = []  # Plans 03/04 populate via parse → merge → override.
```

is unmodified.

## Tests That Remain RED After Plan 03

These tests call `build()` and expect populated entries — they stay RED until Plan 04 wires parsers + merge + override into `build()`:

| Test | Why RED |
|------|---------|
| `test_omit_handling.py::TestOmitHandling::test_omit_entry_uses_first_replace` | Calls `build()` → empty entries |
| `test_dedup.py` | Calls `build()` → no entries to dedup |
| `test_severity.py` | Calls `build()` → no entries to tag |
| `test_byte_determinism.py` | Calls `build()` → empty output, wrong bytes |
| `test_overrides.py` | Calls `build()` → no entries to override |
| `test_schema.py` | Calls `build()` → empty entries, schema assertions fail |
| `test_nfc.py::test_output_bytes_are_nfc` | Calls `build()` → empty output |
| `test_toml_emitter.py::test_output_is_tomllib_parseable` | Calls `build()` → no `[[entries]]` blocks |
| `test_toml_emitter.py::test_field_order_matches_d12` | Calls `build()` → no entries |

## Deviations from Plan

None — plan executed exactly as written. Both parsers implemented as specified; build() untouched.

## Hand-off: Plan 04

Plan 04 adds `merge_and_dedup`, `tag_severity`, `flag_judgment_calls`, `apply_overrides` and wires all four passes + both parsers into `build()`. The `entries: list[dict] = []` stub becomes `entries = merge_and_dedup(parse_retext_js(...), parse_plainlang_md(...))`. All RED tests above go GREEN.

## Self-Check: PASSED

- harper-bridge/scripts/build_wordy_phrases.py: FOUND (396 lines)
- Commit df7d204 (feat(08-03) parsers): FOUND
- parse_retext_js fixture: 5 entries verified
- parse_plainlang_md fixture: 6 entries verified
- build() call-site count: 2 (def lines only)
