#!/bin/sh
set -euo pipefail

if ! command -v rustup >/dev/null 2>&1; then
  echo "Installing Rust toolchain"
  curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "Updating Rust toolchain"
  rustup update
fi
