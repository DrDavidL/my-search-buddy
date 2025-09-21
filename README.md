# My Search Buddy

Early-stage workspace for the macOS search companion app. The repo hosts:

- `finder-core`: Rust library that handles scanning, indexing, and searching.
- `mac-app`: SwiftUI macOS application that will embed the Rust core.
- `scripts`: Helper scripts for builds, tests, and automation.

## Getting Started

1. Install the Rust toolchain (nightly not required) and Xcode 15 or newer.
2. Run `cargo test -p finder-core` to exercise the Rust unit suite once it exists.
3. Use `xcodebuild -scheme MacApp -configuration Debug` to build the SwiftUI app once the project scaffolding lands.

## Status

v0.1 planning is underway. Expect rapid iteration and breaking changes while the MVP core loop is assembled.
