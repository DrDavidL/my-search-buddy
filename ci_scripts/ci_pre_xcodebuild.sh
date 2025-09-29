#!/bin/sh
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

if [ ! -f "Cargo.toml" ]; then
  echo "ci_pre_xcodebuild.sh must run from repo root"
  exit 1
fi

echo "Ensuring Rust targets are installed"
rustup target add x86_64-apple-darwin aarch64-apple-darwin

echo "Building finder-core for x86_64"
cargo build -p finder-core --release --target x86_64-apple-darwin

echo "Building finder-core for arm64"
cargo build -p finder-core --release --target aarch64-apple-darwin

UNIVERSAL_DIR="target/universal/release"
mkdir -p "$UNIVERSAL_DIR"
mkdir -p target/release

X86_LIB="target/x86_64-apple-darwin/release/libfinder_core.dylib"
ARM_LIB="target/aarch64-apple-darwin/release/libfinder_core.dylib"
UNIVERSAL_LIB="$UNIVERSAL_DIR/libfinder_core.dylib"

echo "Creating universal libfinder_core.dylib"
lipo -create -output "$UNIVERSAL_LIB" "$X86_LIB" "$ARM_LIB"

echo "Copying universal dylib to target/release"
cp "$UNIVERSAL_LIB" target/release/libfinder_core.dylib
