---
phase: 09-rust-foundation-mapphraselinter-spike
plan: 05
subsystem: ffi
tags: [uniffi, rust, swift, harper, severity, clarity, xcframework]

requires:
  - phase: 09-rust-foundation-mapphraselinter-spike plan 04
    provides: WordyPhrasesStubLinter + build_lint_group + Rust FFI surface (Severity, SuggestionCategory::Clarity)

provides:
  - Regenerated HarperBridge.swift with public enum Severity, case clarity, public var severity: Severity?
  - XCFramework rebuilt as universal binary (arm64 + x86_64)
  - Suggestion struct gains severity: Severity? field with default-nil designated init
  - init?(from:in:) exhaustive switch covering .spelling/.grammarPunctuation/.clarity + severity population
  - D-14 amended in 09-CONTEXT.md with D-14-AMEND collision rationale
  - ClarityFFITests.stubRoundTrip GREEN (CLAR-11 end-to-end Swift round-trip proof)

affects: [phase-10-matcher-implementation, phase-11-dataset-integration, phase-12-settings-ui]

tech-stack:
  added: []
  patterns:
    - "UniFFI-generated Severity reused directly — no hand-declared Swift mirror to avoid module-scope collision"
    - "Struct designated init inside body suppresses synthesized memberwise to allow severity: Severity? = nil default"
    - "GrammarSuggestion.severity: nil required in test fixtures constructing UniFFI records directly"

key-files:
  created: []
  modified:
    - OpenGram/Generated/HarperBridge.swift
    - OpenGram/CheckEngine/Suggestion.swift
    - OpenGramTests/SuggestionTests.swift
    - .planning/phases/09-rust-foundation-mapphraselinter-spike/09-CONTEXT.md

key-decisions:
  - "D-14-AMEND: UniFFI generates public enum Severity in same OpenGramLib module scope — declaring a second Swift enum Severity in Suggestion.swift causes name collision. Resolution: use the UniFFI-generated type directly. D-14 intent (first-class Severity in scope with Sendable/Equatable/Hashable) satisfied by generated declaration."
  - "Suggestion designated init placed inside struct body (not extension) to suppress synthesized memberwise init and provide severity: Severity? = nil default without redeclaration conflict."

requirements-completed: [CLAR-11]

duration: 9min
completed: 2026-04-24
---

# Phase 9 Plan 05: UniFFI Regen + Swift Severity Round-Trip Summary

**UniFFI bindings regenerated with Severity + .clarity + severity? field; Swift Suggestion extended with exhaustive category switch; ClarityFFITests.stubRoundTrip GREEN through full FFI stack**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-24T23:38:18Z
- **Completed:** 2026-04-24T23:47:00Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- build-harper.sh ran clean; HarperBridge.swift regenerated with `public enum Severity`, `case clarity` on SuggestionCategory, `public var severity: Severity?` on GrammarSuggestion
- XCFramework rebuilt as universal binary (arm64 + x86_64)
- 09-CONTEXT.md D-14 amended with D-14-AMEND note explaining UniFFI collision discovery and resolution
- Suggestion.swift gained `severity: Severity?` field, explicit designated init (severity defaults to nil), and exhaustive category switch covering `.clarity`
- ClarityFFITests.stubRoundTrip passes: category == .clarity, severity == .medium, primaryReplacement == "FLAGGED"
- xcodebuild app + test targets compile clean; 493/496 tests pass (3 pre-existing timing flakes, unchanged)

## Task Commits

1. **Task 1: Run build-harper.sh to regenerate HarperBridge.swift and XCFramework** - `b9dd70c` (feat)
2. **Task 2: Amend 09-CONTEXT.md D-14** - `cd7b887` (docs)
3. **Task 3: Extend Suggestion.swift with severity field + .clarity arm** - `a5fe33e` (feat)

## Files Created/Modified

- `OpenGram/Generated/HarperBridge.swift` — UniFFI shim regenerated: adds Severity enum, clarity case, severity? field (+113/-3 lines)
- `OpenGram/CheckEngine/Suggestion.swift` — severity field + designated init + exhaustive category/severity switches
- `OpenGramTests/SuggestionTests.swift` — added `severity: nil` to 4 GrammarSuggestion constructions (required field in regenerated UniFFI record)
- `.planning/phases/09-rust-foundation-mapphraselinter-spike/09-CONTEXT.md` — D-14 amended with D-14-AMEND

## Decisions Made

- **D-14-AMEND:** UniFFI generates `public enum Severity` in `OpenGramLib` module scope. Declaring a second `enum Severity` in `Suggestion.swift` (same module) causes "invalid redeclaration" compile error. Resolution: use the generated type directly. D-14 intent (first-class Severity in scope with Sendable/Equatable/Hashable) satisfied by the generated declaration. Original D-14 wording replaced; D-14-AMEND appended as audit trail.
- **Init placement:** Explicit designated init goes inside the struct body, not an extension. An extension init with the same signature as the synthesized memberwise init produces "invalid redeclaration of synthesized memberwise init" error. Placing it in the struct body suppresses the synthesized version and allows the `severity: Severity? = nil` default.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated SuggestionTests.swift GrammarSuggestion constructors to pass severity: nil**
- **Found during:** Task 3 (test run after Suggestion.swift edits)
- **Issue:** UniFFI regen added `severity: Option<Severity>` as a required field on `GrammarSuggestion`. SuggestionTests.swift constructs `GrammarSuggestion` directly in 4 places without `severity:` — compile error: "missing argument for parameter 'severity'"
- **Fix:** Added `severity: nil` to all 4 `GrammarSuggestion(...)` call sites in SuggestionTests.swift
- **Files modified:** `OpenGramTests/SuggestionTests.swift`
- **Verification:** xcodebuild test target compiles; all SuggestionModelTests pass
- **Committed in:** `a5fe33e` (part of Task 3 commit)

**2. [Rule 1 - Bug] Moved Suggestion designated init inside struct body (not extension)**
- **Found during:** Task 3 (first build attempt)
- **Issue:** Extension init with same signature as synthesized memberwise init triggers "invalid redeclaration of synthesized memberwise" + "ambiguous use" errors
- **Fix:** Moved the explicit init inside the struct body, which suppresses the synthesized version
- **Files modified:** `OpenGram/CheckEngine/Suggestion.swift`
- **Verification:** BUILD SUCCEEDED; severity: nil default works at all existing call sites
- **Committed in:** `a5fe33e` (part of Task 3 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — compile bugs)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered

None beyond the two auto-fixed compile issues above.

## Next Phase Readiness

- CLAR-11 end-to-end Swift round-trip complete and tested
- Plan 06 (MapPhraseLinter spike) already executed per STATE.md
- Plan 07 (spike report) is next
- HarperBridge.xcframework not tracked in git (gitignored) — must be rebuilt from source via build-harper.sh

---
*Phase: 09-rust-foundation-mapphraselinter-spike*
*Completed: 2026-04-24*
