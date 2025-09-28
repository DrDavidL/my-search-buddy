# My Search Buddy

Early-stage workspace for the macOS search companion app. The repo hosts:

- `finder-core`: Rust library that handles scanning, indexing, and searching.
- `mac-app`: SwiftUI macOS application that sits on top of the Rust core.
- `scripts`: Helper scripts for builds, tests, and automation.

## Getting Started

1. Install the Rust toolchain (nightly not required) and Xcode 15 or newer.
2. Build finder-core:
   ```bash
   cargo build -p finder-core
   cargo build -p finder-core --release
   ```
   Both debug and release dylibs will land in `target/` and are referenced by the app.
3. Open `mac-app/MySearchBuddy.xcodeproj`, select the **MySearchBuddy** scheme, and build/run. (You can also use `xcodebuild -scheme MySearchBuddy -configuration Debug`.)
4. Tests: `cargo test -p finder-core` (Rust) and `swift test` inside `mac-app/Packages/FinderCoreFFI` once the dylib is built.

## Indexing Model

- **Recent-aware results.** The index stores modified timestamps and the UI ships with a `Modified` sort toggle plus a last-indexed status, making it easy to surface the newest files right after a scan. Incremental refresh support is on the roadmap so frequent folders stay fresh without triggering a full rebuild.
- **No double work.** Each document is fingerprinted via device/inode + path, so unchanged files are skipped without reopening their contents on subsequent runs.
- **Full builds stay fast.** Tantivy commits happen in batches (count or time based), letting the index refresh quickly while still delivering Lucene-grade search speed.
- **Content sampling (beta).** Plaintext is sniffed with binary heuristics and, when enabled, sampled according to your preference (target default: 10% total with 8% from the beginning and 2% from the tail; small files index fully).
- **Format adapters roadmap.** Plain UTF-8 content is available today; PDF, DOCX, Markdown, and HTML adapters plug into the same pipeline so content searches keep pace as new extractors land.

### Content Coverage Preference (beta)

We are rolling out a user-facing knob for how much text to index per file:

- **Default target:** 10% coverage (8% head, 2% tail) so search stays representative without ballooning the index. This keeps snippets meaningful even for large reports.
- **Small files:** Anything under 128 KB is ingested in full regardless of the slider to preserve exact matches.
- **Upcoming controls:** The macOS preferences panel gains an `Indexing ▸ Content coverage` slider (2%–50%) and we will expose the same value as `MSB_CONTENT_PERCENT` for CLI/automation use.
- **Why it matters:** Lower percentages keep the index lean on huge datasets; higher percentages are ideal for research archives where the tail carries citations or appendices you routinely search.

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

## mac-app UI Highlights

- **Two-pane layout:** folders/filters on the left, results on the right.
- **Quick filters:** one-click buttons for DOC/DOCX, PPT/PPTX, PDF, and XLS/XLSX.
- **Location filters:** checkboxes per indexed folder with “All” and “None” shortcuts; only enabled locations are searched.
- **Search controls:** explicit Search & Clear buttons, scope toggle (Name/Content/Both), and sort toggle (Score/Modified).
- **Actions:** Open in Finder, Quick Look (sandbox-safe controller), and Reset Index.
- **Status:** shows last index time and status message beneath the indexing controls.

## Status

v0.2 is in flight. Expect rapid iteration and breaking changes while the MVP core loop is assembled.

## FFI Header

- `finder-core/include/finder_core.h` is committed for the Swift bridge. Regenerate it with:
  ```bash
  cbindgen --config finder-core/cbindgen.toml --crate finder-core --output finder-core/include/finder_core.h
  ```
- Build the dynamic library for Swift with `cargo build -p finder-core` (debug) or `cargo build -p finder-core --release` and point `FINDER_CORE_DYLIB` at the resulting `.dylib` before running Swift tests.
