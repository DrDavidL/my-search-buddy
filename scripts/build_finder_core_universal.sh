#!/bin/sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="$HOME/.cargo/bin:$PATH"

if [ ! -f "Cargo.toml" ]; then
  echo "build_finder_core_universal.sh must run from repo root" >&2
  exit 1
fi

if command -v rustup >/dev/null 2>&1; then
  rustup target add x86_64-apple-darwin aarch64-apple-darwin >/dev/null
fi

echo "Building finder-core (x86_64)"
cargo build -p finder-core --release --target x86_64-apple-darwin

echo "Building finder-core (arm64)"
cargo build -p finder-core --release --target aarch64-apple-darwin

UNIVERSAL_DIR="target/universal/release"
mkdir -p "$UNIVERSAL_DIR" target/release mac-app/target/release mac-app/target/debug

X86_LIB="target/x86_64-apple-darwin/release/libfinder_core.dylib"
ARM_LIB="target/aarch64-apple-darwin/release/libfinder_core.dylib"
UNIVERSAL_LIB="$UNIVERSAL_DIR/libfinder_core.dylib"

if [ ! -f "$X86_LIB" ] || [ ! -f "$ARM_LIB" ]; then
  echo "Missing build artifacts for finder-core" >&2
  exit 1
fi

echo "Creating universal libfinder_core.dylib"
lipo -create -output "$UNIVERSAL_LIB" "$X86_LIB" "$ARM_LIB"

echo "Distributing libfinder_core.dylib"
for dest in target/release mac-app/target/release mac-app/target/debug; do
  cp "$UNIVERSAL_LIB" "$dest/libfinder_core.dylib"
done
