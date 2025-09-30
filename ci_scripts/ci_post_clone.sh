#!/bin/sh
set -euo pipefail

if ! command -v rustup >/dev/null 2>&1; then
  echo "Installing Rust toolchain"
  curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
  # Source the cargo environment immediately after installation
  source "$HOME/.cargo/env"
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "Updating Rust toolchain"
  rustup update
fi

rustup default stable

# Ensure cargo environment is properly set for subsequent scripts
if [ -f "$HOME/.cargo/env" ]; then
  source "$HOME/.cargo/env"
fi
