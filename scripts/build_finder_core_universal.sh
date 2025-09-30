#!/bin/sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"
export PATH="$CARGO_HOME/bin:$PATH"

# Source cargo environment for Xcode Cloud compatibility
if [ -f "$CARGO_HOME/env" ]; then
  # shellcheck disable=SC1090
  source "$CARGO_HOME/env"
fi

ensure_rust_toolchain() {
  if command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  echo "cargo not found. Attempting to install Rust toolchain." >&2

  install_script() {
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl not available; cannot install Rust automatically." >&2
      return 1
    fi
    # Install stable toolchain silently; rustup installer respects CARGO_HOME/RUSTUP_HOME.
    if ! curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable; then
      echo "Rust installer failed; see output above." >&2
      return 1
    fi
    return 0
  }

  if command -v rustup >/dev/null 2>&1; then
    if ! rustup update stable; then
      echo "rustup update failed." >&2
      return 1
    fi
  else
    install_script || return 1
  fi

  if [ -f "$CARGO_HOME/env" ]; then
    # shellcheck disable=SC1090
    source "$CARGO_HOME/env"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust installation completed but cargo still unavailable." >&2
    return 1
  fi
}

if ! ensure_rust_toolchain; then
  echo "Unable to locate or install Rust toolchain. See messages above." >&2
  exit 1
fi

if command -v rustup >/dev/null 2>&1; then
  ensure_target() {
    target="$1"
    if ! rustup target list --installed | grep -q "^${target}$"; then
      echo "Installing Rust standard library for ${target}"
      if ! rustup target add "$target"; then
        echo "Failed to install Rust target ${target}. Ensure network access and rerun." >&2
        exit 1
      fi
    fi
  }
  ensure_target x86_64-apple-darwin
  ensure_target aarch64-apple-darwin
else
  echo "rustup not found. Run ci_scripts/ci_post_clone.sh first to install toolchain." >&2
  exit 1
fi

echo "Building finder-core (x86_64)"
cargo build -p finder-core --release --target x86_64-apple-darwin --target-dir "$REPO_ROOT/target"

echo "Building finder-core (arm64)"
cargo build -p finder-core --release --target aarch64-apple-darwin --target-dir "$REPO_ROOT/target"

UNIVERSAL_DIR="$REPO_ROOT/target/universal/release"
mkdir -p "$UNIVERSAL_DIR" "$REPO_ROOT/target/release"

X86_LIB="$REPO_ROOT/target/x86_64-apple-darwin/release/libfinder_core.dylib"
ARM_LIB="$REPO_ROOT/target/aarch64-apple-darwin/release/libfinder_core.dylib"
UNIVERSAL_LIB="$UNIVERSAL_DIR/libfinder_core.dylib"

if [ ! -f "$X86_LIB" ] || [ ! -f "$ARM_LIB" ]; then
  echo "Missing finder-core build artifacts. Check cargo build output above." >&2
  exit 1
fi

echo "Creating universal libfinder_core.dylib"
lipo -create -output "$UNIVERSAL_LIB" "$X86_LIB" "$ARM_LIB"

echo "Distributing libfinder_core.dylib"
cp "$UNIVERSAL_LIB" "$REPO_ROOT/target/release/libfinder_core.dylib"

# Copies into additional convenience locations are best-effort only. Xcode's
# sandbox blocks writes to paths that are not declared as script outputs, so we
# skip them quietly when we do not have permission (local manual invocations
# can still populate them).
OPTIONAL_DESTINATIONS=(
  "$REPO_ROOT/target/debug"
  "$REPO_ROOT/mac-app/target/release"
  "$REPO_ROOT/mac-app/target/debug"
)

for dest in "${OPTIONAL_DESTINATIONS[@]}"; do
  if ! mkdir -p "$dest" >/dev/null 2>&1; then
    echo "warning: skipping optional copy to $dest (mkdir failed; likely sandbox restrictions)" >&2
    continue
  fi
  if ! cp "$UNIVERSAL_LIB" "$dest/libfinder_core.dylib" >/dev/null 2>&1; then
    echo "warning: skipping optional copy to $dest (copy failed; likely sandbox restrictions)" >&2
  fi
done
