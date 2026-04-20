---
phase: 08-dataset-pipeline
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - harper-bridge/scripts/build_wordy_phrases.py
  - harper-bridge/scripts/overrides.toml
  - harper-bridge/scripts/tests/test_overrides.py
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 08: Code Review Report (Plan 07 Gap Closure)

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Plan 07 gap closure extends `build_wordy_phrases.py` with a new `add` override op and registers two `PhraseEntry` rows (`utilizes`/`utilized`) in `overrides.toml`. The test file gains a `TestAddOp` class with five unit tests covering happy path, explicit severity, id collision, missing required keys, and phrase/key-drift validation.

No security issues. No critical bugs. Pipeline determinism preserved: add-op entries participate in the post-apply id-sort at `build()` step 7, so insertion order of overrides does not affect output. Path-traversal guards and the SHA256 manifest checker are unchanged from the prior review and remain sound.

Two warnings flag input-validation gaps on the new `add` op where malformed values in `overrides.toml` silently corrupt output rather than failing closed. Four info items call out a stale header comment, test coverage gaps, and a minor style issue.

Note: This review is scoped to the three files in Plan 07 gap closure. Prior phase-level findings (hardcoded date in `build()` step 9, dead `emit_toml` function, missing-manifest bypass, `assert` stripped under `-O`) from the earlier review remain open and are not duplicated here.

## Warnings

### WR-01: `add`-op `dialects` field not type-validated

**File:** `harper-bridge/scripts/build_wordy_phrases.py:614-615`
**Issue:** `apply_overrides` calls `list(ops["dialects"])` without confirming `ops["dialects"]` is a list. TOML allows a curator to write `dialects = "en-US"` (string) instead of `dialects = ["en-US"]` (array). `list()` on a string splits it into per-character elements — silent corruption producing `dialects = ["e", "n", "-", "U", "S"]` in the emitted TOML. `load_overrides` does not catch this either, so the malformed override flows all the way to the atomic write and poisons the output data file.
**Fix:** Validate in `load_overrides` alongside the existing `sources` check (around line 556-557):
```python
if ops.get("add") is True:
    for req in ("phrase", "replacement", "sources"):
        if req not in ops:
            raise SystemExit(f"Add-op override id={eid!r} missing required key: {req!r}")
    if not isinstance(ops["sources"], list) or not ops["sources"]:
        raise SystemExit(f"Add-op override id={eid!r}: sources must be non-empty list")
    if "dialects" in ops and not isinstance(ops["dialects"], list):
        raise SystemExit(
            f"Add-op override id={eid!r}: dialects must be list, got {type(ops['dialects']).__name__}"
        )
```

### WR-02: `add`-op `severity` accepts arbitrary strings

**File:** `harper-bridge/scripts/build_wordy_phrases.py:610`
**Issue:** `severity = ops.get("severity", "medium")` defaults correctly but performs no enum check. A curator-authored `severity = "garbage"` in `overrides.toml` flows through the pipeline into the output TOML unchanged. D-07 defines the canonical set as `{"low", "medium", "high"}`. The downstream Rust loader will either reject the malformed severity at deserialization time (noisy late failure) or accept it silently depending on how `PhraseEntry` deserializes — either way the build script should fail closed at override load time. Mutate-op `severity` at line 595-597 has the same gap.
**Fix:**
```python
_VALID_SEVERITIES = {"low", "medium", "high"}
```
Add one `load_overrides` validation clause that applies to both add- and mutate-op rows:
```python
if "severity" in ops and ops["severity"] not in _VALID_SEVERITIES:
    raise SystemExit(
        f"Override id={eid!r}: severity must be one of {sorted(_VALID_SEVERITIES)}, got {ops['severity']!r}"
    )
```

## Info

### IN-01: `overrides.toml` header comment omits new `add` op

**File:** `harper-bridge/scripts/overrides.toml:4`
**Issue:** The top-of-file comment enumerates valid ops as `Ops: drop | severity | replacement | dialects | note.` — it predates the `add` op and is now incorrect. Future curators reading this header will not know `add` is available.
**Fix:** Update to `Ops: drop | severity | replacement | dialects | note | add.` and document the add-op required-key shape (`phrase` + `replacement` + `sources`) inline as a one-line example.

### IN-02: Missing test coverage for add-op optional fields

**File:** `harper-bridge/scripts/tests/test_overrides.py:54-140`
**Issue:** `TestAddOp` covers happy path, explicit severity, collision, missing keys, and key drift — but has no case exercising add-op with `dialects` or `note`. The real `overrides.toml` (lines 46, 53) uses the `note` field on both `utilizes` and `utilized` entries, so this production code path ships untested.
**Fix:** Add two tests:
```python
def test_add_op_with_note_preserved(self):
    import tomllib
    tmp = FIXTURES / "tmp-add-note.toml"
    tmp.write_text(
        '[overrides."utilizes"]\n'
        'add = true\n'
        'phrase = "utilizes"\n'
        'replacement = "use"\n'
        'sources = ["manual"]\n'
        'note = "Inflected form."\n'
    )
    try:
        out = bwp.build(FIXTURES, tmp)
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["utilizes"]["note"], "Inflected form.")
    finally:
        tmp.unlink(missing_ok=True)

def test_add_op_with_dialects_preserved(self):
    import tomllib
    tmp = FIXTURES / "tmp-add-dialects.toml"
    tmp.write_text(
        '[overrides."utilizes"]\n'
        'add = true\n'
        'phrase = "utilizes"\n'
        'replacement = "use"\n'
        'sources = ["manual"]\n'
        'dialects = ["en-US"]\n'
    )
    try:
        out = bwp.build(FIXTURES, tmp)
        parsed = tomllib.loads(out.decode())
        by_id = {e["id"]: e for e in parsed["entries"]}
        self.assertEqual(by_id["utilizes"]["dialects"], ["en-US"])
    finally:
        tmp.unlink(missing_ok=True)
```

### IN-03: No test for forbidden-key validation on mutate-op rows

**File:** `harper-bridge/scripts/tests/test_overrides.py`
**Issue:** `load_overrides` raises when a mutate-op row carries `phrase` or `sources` (lines 566-570 of `build_wordy_phrases.py`). This guard prevents silent data drift when a curator forgets `add = true`. No test covers it, so a regression removing the guard would not fail CI.
**Fix:**
```python
def test_mutate_op_rejects_phrase_key(self):
    tmp = FIXTURES / "tmp-mutate-phrase.toml"
    tmp.write_text(
        '[overrides."utilize"]\n'
        'phrase = "utilize"\n'  # forbidden without add=true
        'severity = "high"\n'
    )
    try:
        with self.assertRaises(SystemExit):
            bwp.build(FIXTURES, tmp)
    finally:
        tmp.unlink(missing_ok=True)

def test_mutate_op_rejects_sources_key(self):
    tmp = FIXTURES / "tmp-mutate-sources.toml"
    tmp.write_text(
        '[overrides."utilize"]\n'
        'sources = ["manual"]\n'  # forbidden without add=true
    )
    try:
        with self.assertRaises(SystemExit):
            bwp.build(FIXTURES, tmp)
    finally:
        tmp.unlink(missing_ok=True)
```

### IN-04: Repeated `import tomllib` in every test method

**File:** `harper-bridge/scripts/tests/test_overrides.py:18, 25, 33, 40, 47, 58, 79, 89, 99, 113`
**Issue:** Every test method re-imports `tomllib` locally. Idiomatic Python places stdlib imports at module top. Ten repetitions add noise with no benefit — the import is always needed for add-op tests and is needed for four of five mutate-op tests.
**Fix:** Move `import tomllib` to the top of the module alongside `import unittest`. Remove all in-method imports.

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
