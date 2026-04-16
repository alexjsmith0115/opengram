# Style and Conventions

## Swift
- Swift 6 strict concurrency — no data races at compile time
- SRP: small, focused classes and functions
- Dependency injection for testability
- No external consumers — update all callers when changing APIs
- AppKit for overlay/transparent windows; SwiftUI for settings/popovers
- `@AppStorage` for non-sensitive prefs; KeychainAccess for secrets

## Comments
- Sparse — only explain WHY, never WHAT
- No docstrings, no type annotations on unchanged code

## Naming
- Precise, descriptive — names eliminate need for comments

## No-nos
- No TODO/FIXME/HACK comments
- No unused code, dead imports, obsolete files
- No backwards-compat shims for internal callers
- No UserDefaults for secrets
- No `swift build` for validation (use xcodebuild)

## Adding new source files
Must add to `project.pbxproj`: file reference, group membership, build phase (Sources for .swift, Resources for .plist).

## UniFFI version discipline
uniffi version in `Cargo.toml` MUST match `uniffi-bindgen` CLI tool version exactly. Mismatch = runtime panic.
