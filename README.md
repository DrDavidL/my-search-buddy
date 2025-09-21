# My Search Buddy

Early-stage workspace for the macOS search companion app. The repo hosts:

- `finder-core`: Rust library that handles scanning, indexing, and searching.
- `mac-app`: SwiftUI macOS application that will embed the Rust core.
- `scripts`: Helper scripts for builds, tests, and automation.

## Getting Started

1. Install the Rust toolchain (nightly not required) and Xcode 15 or newer.
2. Run `cargo test -p finder-core` to exercise the Rust unit suite once it exists.
3. Use `xcodebuild -scheme MacApp -configuration Debug` to build the SwiftUI app once the project scaffolding lands.

## Privacy at a glance

> **Local-only.** Indexing and search happen entirely on your device.  
> **No uploads.** The app never sends file names or contents anywhere.  
> **Transparent permissions.** You choose folders; access is sandboxed via security-scoped bookmarks.  
> **No telemetry.** We don’t collect analytics.  
> **App Store privacy label:** *Data Not Collected* (see [`Resources/PrivacyInfo.xcprivacy`](mac-app/Resources/PrivacyInfo.xcprivacy)).

## Trust & documentation

- [PRIVACY.md](PRIVACY.md) – how permissions, storage, and networking work (spoiler: they don’t phone home).
- [SECURITY.md](SECURITY.md) – responsible disclosure guidelines and expectations for contributors.
- CI guardrails: secret scanning (GitHub + Gitleaks + TruffleHog) and license checks run on every pull request.
- License: [MIT](LICENSE). We only accept permissive third-party licenses (MIT/Apache/BSD/ISC/MPL-2.0/Unlicense/CC0/Zlib); copyleft (GPL/LGPL/AGPL) is denied for App Store compatibility.
- Third-party acknowledgements are generated in-app via LicensePlist so users can review every dependency.

### Key open-source dependencies (permissive licenses)

- [tantivy](https://crates.io/crates/tantivy) – MIT
- [globset](https://crates.io/crates/globset) – MIT OR Unlicense
- [rayon](https://crates.io/crates/rayon) – MIT OR Apache-2.0
- [aho-corasick](https://crates.io/crates/aho-corasick) – MIT OR Unlicense
- [walkdir](https://crates.io/crates/walkdir) – MIT OR Unlicense
- [ignore](https://crates.io/crates/ignore) – MIT OR Unlicense
- [serde](https://crates.io/crates/serde) – MIT OR Apache-2.0
- [anyhow](https://crates.io/crates/anyhow) – MIT OR Apache-2.0

## Status

v0.1 planning is underway. Expect rapid iteration and breaking changes while the MVP core loop is assembled.

## FFI Header

- `finder-core/include/finder_core.h` is committed for the Swift bridge. Regenerate it with `cbindgen --config finder-core/cbindgen.toml --crate finder-core --output finder-core/include/finder_core.h` when FFI structs or functions change.
- Build the dynamic library for Swift with `cargo build -p finder-core` (debug) or `cargo build -p finder-core --release` and point `FINDER_CORE_DYLIB` at the resulting `.dylib` before running Swift tests.
