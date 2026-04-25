# Contributing to OpenGram

OpenGram is a macOS-native, fully local grammar and writing-style tool. Engineering practices, build conventions, and style rules are defined in [`CLAUDE.md`](./CLAUDE.md) — read it before opening a PR. This document captures the contribution-specific rules: how to build and test, and how to extend the clarity matcher's NonFlags fixture corpus when fixing false positives.

## Build & Test

```bash
xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build
xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS'
~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo test --manifest-path harper-bridge/Cargo.toml
```

`swift build` is a CLI convenience only. The Xcode project (`OpenGram.xcodeproj/project.pbxproj`) is the canonical build system — SPM auto-discovers files and silently masks missing `pbxproj` references. Every new `.swift` file MUST be wired into `project.pbxproj` (file reference, group membership, and the appropriate build phase: Sources for `.swift`, Resources for `.plist`). A build is not "clean" unless `xcodebuild` succeeds for both the app and test targets.

Swift Testing (`@Test` / `#expect`) is mandatory for new unit tests — it ships with Xcode 16, runs tests in parallel by default, and produces clearer failures than XCTest. XCTest is retained only for UI tests, since Swift Testing does not yet support `XCUITest`.

## Adding NonFlags Fixtures

Any clarity false-positive fix — typically a `WordyPhrasesLinter` matcher edit that removes a wrongful flag — MUST add at least one corresponding fixture line to `harper-bridge/tests/nonflags/<category>.txt` in the same PR. The fixture locks the fix in place as a regression test: future changes to the matcher cannot silently re-introduce the wrongful flag without that test failing.

Pick the bucket that best describes why the phrase should not be flagged:

- `proper_nouns.txt` — proper nouns that contain a flagged substring. Example: `Notable Solutions Inc. shipped a new feature.`
- `quoted_code.txt` — flagged phrase appearing inside backticks, quotes, or code spans where it represents code, file paths, or shell idioms rather than prose. Example: ``The Bash idiom `due to the fact that` appears in legacy scripts.``
- `domain_terms.txt` — technical, legal, or RFC normative usage where the phrase is the term of art and rewriting would change meaning. Example: `RFC 793 declares 'in order to' as a normative imperative.`
- `retext_issues.txt` — overflow bucket and source for sentences scraped from upstream issue archives (`retext-simplify`, `retextjs/retext`, `write-good`, `alex-js`). Add a `# Source: <issue-ref>` provenance comment line directly above each scraped sentence so the origin stays auditable.

Format: one sentence per line. Blank lines and lines beginning with `#` are ignored, so use `#` for section headers and provenance comments. Add fixtures incrementally in batches and re-run the corpus tests after each batch with `cargo test --manifest-path harper-bridge/Cargo.toml --test nonflags_corpus` (the `nonflags_corpus` test target asserts that no fixture line produces a clarity flag).

Requirement: CLAR-21.

## Pull Requests

PRs use the template at [`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md). When the change touches the clarity matcher, the NonFlags fixture checkbox MUST be checked and the new fixture entry MUST appear in the same PR diff.
