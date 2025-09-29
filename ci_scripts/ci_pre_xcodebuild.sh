#!/bin/sh
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

if [ ! -f "Cargo.toml" ]; then
  echo "ci_pre_xcodebuild.sh must run from repo root"
  exit 1
fi

echo "Building finder-core (release)"
cargo build -p finder-core --release
