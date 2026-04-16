# Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| App language | Swift 6 (Xcode 16+) | Strict concurrency enforced |
| Grammar engine | harper-core 2.0.0 (Rust) | Via UniFFI 0.31.0 bridge |
| FFI | UniFFI 0.31.0 | Must match exactly in Cargo.toml and CLI tool |
| Overlay windows | AppKit NSWindow | SwiftUI can't do transparent overlays over other apps |
| Settings / popover | SwiftUI | MenuBarExtra or NSStatusItem |
| HTTP (LLM calls) | URLSession | No Alamofire; single POST endpoint |
| Secure storage | KeychainAccess 4.2.2 | Never UserDefaults for secrets |
| Testing | Swift Testing (@Test/#expect) | Xcode 16 built-in; XCTest only for UI tests |

## Key SPM dependencies
- KeychainAccess 4.2.2

## Rust bridge
- Crate: `harper-bridge/`
- Output: `HarperBridge.xcframework` + `OpenGram/Generated/HarperBridge.swift`
- Build: `./build-harper.sh`
