#!/bin/bash
# build-harper.sh -- Produces HarperBridge.xcframework from harper-bridge Rust crate.
# Invoke manually or as Xcode Run Script Build Phase.
set -euo pipefail

export PATH="$HOME/.cargo/bin:$(brew --prefix rustup)/bin:$PATH"

# xcode-select may point to CLT instead of Xcode.app; override for xcodebuild
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$REPO_ROOT/harper-bridge"
FRAMEWORK_NAME="HarperBridge"
OUT_DIR="$REPO_ROOT/$FRAMEWORK_NAME.xcframework"
SWIFT_OUT="$REPO_ROOT/OpenGram/Generated"

cd "$CRATE_DIR"

echo "Building harper-bridge for Apple Silicon..."
cargo build --target aarch64-apple-darwin --release

echo "Building harper-bridge for Intel Mac..."
cargo build --target x86_64-apple-darwin --release

echo "Generating Swift bindings..."
mkdir -p bindings/include bindings/Modules

cargo run --features cli --bin uniffi-bindgen-swift -- \
  --swift-sources \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings

cargo run --features cli --bin uniffi-bindgen-swift -- \
  --headers \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings/include

cargo run --features cli --bin uniffi-bindgen-swift -- \
  --modulemap --xcframework \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  bindings/include

echo "Creating universal binary..."
mkdir -p target/universal/release
lipo -create \
  target/aarch64-apple-darwin/release/libharper_bridge.a \
  target/x86_64-apple-darwin/release/libharper_bridge.a \
  -output target/universal/release/libharper_bridge.a

echo "Packaging xcframework..."
rm -rf "$OUT_DIR"
xcodebuild -create-xcframework \
  -library target/universal/release/libharper_bridge.a \
  -headers bindings/include \
  -output "$OUT_DIR"

echo "Fixing modulemap for SPM binaryTarget..."
MODULEMAP="$OUT_DIR/macos-arm64_x86_64/Headers/module.modulemap"
if [ -f "$OUT_DIR/macos-arm64_x86_64/Headers/harper_bridge.modulemap" ]; then
  mv "$OUT_DIR/macos-arm64_x86_64/Headers/harper_bridge.modulemap" "$MODULEMAP"
fi
sed -i '' 's/^framework module harper_bridge/module harper_bridgeFFI/' "$MODULEMAP"

echo "Copying Swift bindings to project..."
mkdir -p "$SWIFT_OUT"
cp bindings/harper_bridge.swift "$SWIFT_OUT/HarperBridge.swift"

echo "Done. Link $FRAMEWORK_NAME.xcframework in Xcode."
