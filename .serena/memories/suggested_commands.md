# Suggested Commands

## Build (canonical — always use this, not `swift build`)
```bash
xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build
```
SPM (`swift build`) auto-discovers files and masks missing pbxproj references — do not use for validation.

## Test
```bash
./scripts/test.sh
# or with filter:
./scripts/test.sh --filter SomeSuiteName
```

## Build Harper (Rust → xcframework)
```bash
./build-harper.sh
```
Run when harper-bridge Rust source changes. Outputs `HarperBridge.xcframework` and `OpenGram/Generated/HarperBridge.swift`.

## Launch app (after build)
Open via Xcode or:
```bash
open ~/Library/Developer/Xcode/DerivedData/OpenGram-*/Build/Products/Debug/OpenGram.app
```

## Git
```bash
git log --oneline -10
git status
git diff
```
