## Summary

<!-- 1-3 sentences describing the change -->

## Test Plan

<!-- Commands run + outcome -->

- [ ] `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` — BUILD SUCCEEDED
- [ ] `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram test -destination 'platform=macOS'` — all tests passed
- [ ] `cargo test --manifest-path harper-bridge/Cargo.toml` — all tests passed

## Checklist

- [ ] Tests added or updated for this change
- [ ] If fixing a clarity false-positive: added a NonFlags fixture entry covering the regression in `harper-bridge/tests/nonflags/<category>.txt` (see [CONTRIBUTING.md § Adding NonFlags Fixtures](../CONTRIBUTING.md#adding-nonflags-fixtures))
- [ ] No GSD planning refs in source code (no "Phase N" / "Plan N"; requirement IDs like `CLAR-21` are fine)
- [ ] New `.swift` files wired into `OpenGram.xcodeproj/project.pbxproj`
- [ ] If UI-affecting: visual validation done (computer-use MCP or manual)
