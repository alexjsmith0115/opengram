## Project Intention

This project is **OpenGram**, a MacOS-specific active Grammar checker and writing style tool. The application is entirely local by default. There is no external API, logging, error reporting - anything. Users will be able to get realtime feedback on their writing. The application will highlight, underline, or otherwise indicate if the text the user has written contains grammar or spelling mistakes, and will suggesting writing improvements to improve the clarity, flow, and tone of the writing.

### Standalone Application — No Dependencies

OpenGram is a **fully standalone app**. No upstream services, no downstream consumers, no external API surface, no library clients. Every caller of every internal API is inside this repo.

Implications for architecture decisions:
- **No feature flags, no gated rollouts, no A/B toggles.** Ship changes directly. If a change is risky, stage it behind plan/review — not a runtime flag.
- **No backwards-compatibility shims.** Rename freely, delete freely, restructure freely. Update every call site in the same change.
- **No deprecation cycles.** If an API is wrong, replace it. Do not preserve the old version alongside the new.
- **No versioned public API.** Internal interfaces can change in any commit.
- **No migration layers for user data** beyond what actual users of shipped builds require — during development, wipe and reset freely.

*IMPORTANT*
## User Interaction
- Never assume the user is correct. Trust but verify all statements, using the code as a source of truth. When in doubt, ask the user for clarification.
- Prefer honesty over agreement, always. Treat the user as a peer. Do not pander, do not pull punches, do not be sycophantic. 
- **NEVER SAY "YOU ARE ABSOLUTELY CORRECT"**

## Tooling

Use Serena MCP tools (`mcp__plugin_serena_serena__*`) for codebase navigation — `find_symbol`, `get_symbols_overview`, `search_for_pattern`, `find_file`, `read_file` etc. Prefer these over Grep/Glob/Read/Bash when exploring code structure or symbols.

## Engineering Practices

- Before writing anything, read surrounding code, check `git log` for recent intentional changes, and search docs/GitHub issues/SO for known solutions. Understand the full architecture and constraints before proposing a design. Choose component boundaries and state ownership before writing JSX.
- Pre-existing failures are your responsibility. Fix broken tests/lint/build before moving on.

### Design

- Keep classes and functions small, clear, and with a singular purpose (SRP).
- If a fix introduces a new problem, stop. Re-examine the root cause. Two failed attempts means the approach is wrong, not that it needs more tweaking.
- If a recent commit renamed or restructured something, fix downstream code to match—never revert intentional work.
- No external consumers—never preserve a worse API to avoid updating callers you control.
- Every UI decision prioritizes clarity and usability.
- Match existing patterns — don't invent new ones when established ones exist.

### Build Validation

- **Always validate with `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build`, not `swift build`.** The Xcode project (`project.pbxproj`) is the canonical build system. SPM is a convenience for CLI but auto-discovers files, masking missing pbxproj references.
- When adding new source files, always add them to the Xcode project (`project.pbxproj`) — file references, group membership, and the appropriate build phase (Sources for `.swift`, Resources for `.plist`).
- A build is not "clean" unless `xcodebuild` succeeds for both the app and test targets.

### Testing

- Design all classes and functions with testability in mind. Use Dependency Injection liberally.
- Make sure all unit, integration, and E2E tests pass before considering a task complete.
- Every bugfix must include a regression test that would have caught the bug.
- Update all call sites, tests, types, and docs in the same change. No partial work, no TODO/FIXME/HACK comments. If the correct approach requires more code or refactoring, that is the right approach.

### Manual Validation

After any feature change or UI-affecting work, use the `computer-use` MCP to visually validate the running app:

1. Build and launch OpenGram (or confirm it's already running).
2. Take a screenshot to verify the UI renders correctly — check overlay positioning, popover appearance, menu bar icon, underline rendering, etc.
3. Interact with the app as a user would: trigger the hotkey, type text with errors, click suggestions, dismiss popovers.
4. Compare what you see against the expected behavior for the change you made.

This is not optional. Automated tests verify logic; manual validation catches visual regressions, layout bugs, and interaction issues that tests cannot. If the app can't be built or launched (e.g., missing dependencies), note the blocker — don't silently skip validation.

### Style

- Use comments sparingly. Comments should only exist to clarify a design choice/decision, not to explain what the code is doing. (WHY not WHAT)
- Remove unused code, obsolete files, and dead imports.
- Choose precise, descriptive names. A good name eliminates the need for a comment.
- No inlined logic that belongs in a helper, no duplicated code that should be shared, no unrelated concerns in one function.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**OpenGram**

A macOS menu bar app that provides system-wide grammar, spelling, and writing style correction across all applications. Uses a two-tier checking architecture: Harper (Rust grammar engine via UniFFI) for instant deterministic grammar/spelling checking, and an optional user-configured LLM for style and clarity suggestions. No subscriptions, no data leaving the device unless the user explicitly configures a cloud LLM provider.

**Core Value:** Press a hotkey in any app and get instant, accurate grammar corrections with optional AI-powered style suggestions — entirely local by default, with no account or subscription required.

### Constraints

- **Platform:** macOS 14.0+ (Sonoma) — AX API improvements, SwiftUI maturity
- **Language:** Swift (UI, AX, events) + Rust (Harper core via UniFFI)
- **UI Framework:** SwiftUI for settings, AppKit for overlay windows (SwiftUI can't do transparent overlays)
- **Distribution:** Direct .dmg download — avoids App Store sandboxing which cripples AX API access
- **Secret storage:** Keychain for API keys — never plaintext in UserDefaults/plist
- **Privacy:** No telemetry, no error reporting, no external API calls unless user configures LLM provider
- **Hotkey:** Ctrl+Shift+G (global, fires even when app isn't focused)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.x (Xcode 16+) | Primary application language: UI, AX API, event handling, LLM networking | The only real choice for macOS-native apps. Swift 6's strict concurrency catches data race bugs at compile time — critical when async LLM calls and synchronous Harper results merge in the same UI update. |
| Rust (via rustup) | 1.85+ (2024 edition) | Harper grammar engine compilation | Harper-core is Rust-only. Rust 1.85 ships the 2024 edition which is the current stable edition target. |
| harper-core | 2.0.0 | Grammar, spelling, punctuation checking | The grammar engine. v2.0.0 is current (released April 8, 2026 in the harper monorepo). Pin to this exact version — Harper's API stability is explicitly not a priority per their docs. |
| UniFFI | 0.31.0 | Rust → Swift binding generation | Mozilla's production-tested tool (Firefox iOS/Android). Generates type-safe Swift classes from annotated Rust, handles all memory management automatically. v0.31.0 released January 14, 2026. The alternative (manual C FFI) requires hand-managing raw pointers and is strictly worse. |
| AppKit | macOS 14.0+ | Transparent overlay windows, NSStatusItem menu bar | SwiftUI cannot create the zero-chrome transparent windows needed for inline underlines over other apps' text fields. AppKit NSWindow with `styleMask: []` and `backgroundColor: .clear` is the only path. |
| SwiftUI | macOS 14.0+ | Settings window, menu bar popover content | Settings UI maps naturally to SwiftUI's declarative style. Use `MenuBarExtra` (Ventura+) for the status item with SwiftUI content, or drop to NSStatusItem for custom left/right click behavior. |
| URLSession | Built-in | LLM API calls (OpenAI-compatible `/v1/chat/completions`) | No external dependency needed. URLSession's async/await API handles both JSON batch responses (POC) and SSE streaming (v2). Avoids pulling in Alamofire or similar for what amounts to a single POST endpoint. |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| KeychainAccess | 4.2.2 | Secure API key storage | Use this instead of raw SecItem calls. The raw Keychain C API is notoriously painful. KeychainAccess wraps it cleanly: `keychain["openai_key"] = value`. MIT licensed, Swift Package Manager. |
| xcframework (cargo plugin) | latest | Packages the UniFFI-compiled Rust static library into an .xcframework | Use during the `build-harper.sh` step. Handles multi-arch (arm64 + x86_64) bundling and platform slicing without manual lipo invocations. |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | IDE, Swift compiler, build system | Required for Swift 6 and macOS 14+ SDK. Run `swift build` for CLI checks, use Xcode for UI work. |
| rustup | Rust toolchain management | Install via `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh`. Provides `cargo` and `rustc`. Add `aarch64-apple-darwin` and `x86_64-apple-darwin` targets. |
| uniffi-bindgen | 0.31.0 | Generates HarperBridge.swift and HarperBridgeFFI.h from annotated Rust | Install via `cargo install uniffi-bindgen --version 0.31.0`. Must match the uniffi version in Cargo.toml exactly — version mismatch = build failure. |
| Swift Testing | Built into Xcode 16 | Unit testing framework | Prefer `@Test` / `#expect` (Swift Testing) over XCTest for new unit tests. Runs tests in parallel by default, better failure messages. Keep XCTest only for UI tests (Swift Testing doesn't support UI testing yet as of 2025). |
## Installation
# Rust toolchain
# UniFFI bindgen — must match Cargo.toml version
# Swift package dependencies (Package.swift)
# KeychainAccess
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| UniFFI 0.31.0 | Manual C FFI (cbindgen) | Only if UniFFI has a blocking bug. C FFI requires hand-written memory management and a maintained C header — strictly more work with no benefit. |
| UniFFI 0.31.0 | swift-bridge | If you never want Android support and prefer slightly more idiomatic Swift output. Much smaller community, less documentation, higher risk of abandonment. |
| UniFFI 0.31.0 | Subprocess (harper-cli) | Acceptable fallback for the POC if UniFFI build setup stalls. 100ms latency is tolerable for on-demand hotkey flow. Not viable for v2 real-time checking. |
| UniFFI 0.31.0 | harper-wasm via JavaScriptCore | Don't. ~200ms WASM cold start, JS↔Swift bridging overhead, no native filesystem access for dictionaries. |
| URLSession (built-in) | Alamofire | If you need request retry policies, response caching, or certificate pinning. Not needed here — single POST to a user-configured endpoint. |
| AppKit NSWindow | SwiftUI transparent window | SwiftUI 4+ can approximate transparent windows but lacks the level control needed to layer over arbitrary third-party apps. AppKit NSWindow with `level = .floating` and `isOpaque = false` is the correct tool. |
| KeychainAccess | Raw SecItem API | Only if you need entitlement-scoped keychain sharing across multiple app targets. For a single app, raw SecItem is four times the code for zero benefit. |
| Swift Testing | XCTest (for unit tests) | Keep XCTest only for UI tests (Swift Testing doesn't yet support XCUITest). For all unit/integration tests, Swift Testing is the current Apple recommendation. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| CocoaPods | Adds a global Ruby dependency, slow installs, generates a workspace mess. SPM handles every dependency this project needs. | Swift Package Manager |
| Third-party HTTP libraries (Alamofire, Moya) | The LLM integration is a single `/v1/chat/completions` POST. Adding a framework to wrap URLSession is premature complexity. | URLSession with async/await |
| UserDefaults for API keys | UserDefaults are stored in plaintext plist files readable by any process with filesystem access. | Keychain (via KeychainAccess) |
| App Store distribution | AX API requires `com.apple.security.accessibility` entitlement which App Store review routinely rejects for non-assistive-technology apps. Direct .dmg distribution sidesteps sandboxing entirely. | Direct .dmg + notarization |
| harper-wasm / JavaScriptCore bridge | All indirection, no benefit. Adds JSCore startup overhead and forces awkward JS↔Swift data marshalling. | UniFFI native bridge |
| MLX Swift (for POC) | MLX in-process inference is v2 scope. The POC uses OpenAI-compatible HTTP APIs. Pulling in MLX now adds build complexity with no POC benefit. | URLSession + user-configured LLM endpoint |
| Global NSEvent monitors (NSEvent.addGlobalMonitorForEvents) for hotkey | Cannot intercept or modify events. Requires Input Monitoring permission. For a hotkey that only needs to detect a key combo, this is fine — but document that users will see the Input Monitoring TCC prompt. | CGEventTap (preferred) or NSEvent global monitor (acceptable for simple hotkey) |
## Stack Patterns by Variant
- Use `NSWindow` with `styleMask: []`, `backgroundColor: .clear`, `isOpaque: false`, `level: .floating`
- Host a `CALayer`-based view for underline rendering — Core Graphics drawing with `NSBezierPath` for solid (Harper) and dashed (LLM) underlines
- Do NOT use SwiftUI here. SwiftUI views can't reliably render onto fully transparent backgrounds positioned over other apps' windows.
- Use `NSPanel` with `.nonactivatingPanel` behavior — shows without stealing focus from the target app
- Can embed a SwiftUI view via `NSHostingView` here since it's a self-contained panel, not an overlay
- Use SwiftUI exclusively. Settings maps perfectly to SwiftUI's declarative style.
- Use `@AppStorage` for non-sensitive preferences (rule toggles, hotkey config, dialect)
- Use KeychainAccess for API keys — never AppStorage/UserDefaults for secrets
- Use `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)` (AppKit) if you need custom left/right click behavior
- Use SwiftUI `MenuBarExtra` if a simple menu with a popover is sufficient (simpler code, less control)
- Set `button?.image?.isTemplate = true` for adaptive light/dark icon rendering
- Create a dedicated crate `harper-bridge/` that depends on `harper-core`
- Expose only what OpenGram needs: `HarperChecker` object with `check()`, `addToDictionary()`, `updateConfig()`
- Keep the bridge ~150 lines. Harper's full API surface is large; expose a minimal stable subset.
- Build both architectures, run uniffi-bindgen, use `lipo` to create a universal `.a`, package as `.xcframework`
- Use Swift's `URLSession.shared.data(for:)` for batch JSON responses (POC)
- Use `URLSession.shared.bytes(for:)` with `AsyncLineSequence` for SSE streaming (v2)
- Parse LLM JSON response with `JSONDecoder` into a `[LLMSuggestionDTO]` struct, then map to the unified `Suggestion` model
- Never parse character offsets from LLM output — search for `original` substring in source text to compute real `String.Index` offsets
## Version Compatibility
| Package | Compatible With | Notes |
|---------|-----------------|-------|
| uniffi 0.31.0 (Cargo.toml) | uniffi-bindgen 0.31.0 (CLI tool) | Must match exactly. uniffi-bindgen generates code that calls into the specific ABI of the uniffi runtime version. A mismatch produces a runtime panic, not a build error — hard to debug. |
| harper-core 2.0.0 | Rust 1.85+ | harper-core 2.0.0 is the current release as of April 2026. Pin to this tag in `harper-bridge/Cargo.toml`. |
| Swift 6 / Xcode 16 | macOS 14.0+ deployment target | Swift 6 strict concurrency is available from Xcode 16. The project targets macOS 14 (Sonoma) which requires Xcode 15+, but Xcode 16 is the recommended dev environment. |
| KeychainAccess 4.2.2 | macOS 10.12+ | No compatibility issues with macOS 14 target. |
| Swift Testing | Xcode 16+ | Swift Testing is bundled with Xcode 16. Do not add it as a separate SPM dependency — it's built in. |
## Sources
- UniFFI CHANGELOG (github.com/mozilla/uniffi-rs) — confirmed v0.31.0 released January 14, 2026 [HIGH confidence]
- harper GitHub releases (github.com/Automattic/harper) — confirmed v2.0.0 released April 8, 2026 [HIGH confidence]
- docs.rs/harper-core/latest — confirmed v2.0.0 is current docs version [HIGH confidence]
- docs.rs/uniffi/latest — confirmed v0.31.0 is current docs version [HIGH confidence]
- mozilla.github.io/uniffi-rs/latest/swift/xcode.html — XCFramework integration guidance [HIGH confidence]
- KeychainAccess GitHub + Swift Package Index — v4.2.2 confirmed [MEDIUM confidence — last release date unclear, repo active]
- WritingTools (github.com/theJayTea/WritingTools) — confirmed Swift + SwiftUI + AppKit + Accessibility is the production pattern for system-wide macOS writing tools [MEDIUM confidence — real-world validation]
- WebSearch (macOS menu bar best practices 2025) — AppKit NSStatusItem vs SwiftUI MenuBarExtra tradeoffs [MEDIUM confidence]
- Apple Developer Documentation — AX API, NSWindow, Keychain Services, URLSession [HIGH confidence]
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
