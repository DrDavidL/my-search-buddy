# My Search Buddy 🐕

**Lightning-fast file search for macOS** - Your digital search companion that actually finds what you're looking for.

A production-ready macOS app combining SwiftUI elegance with Rust-powered search performance. Built with privacy-first principles, sandbox security, and zero data collection.

## What Makes It Special

🚀 **Blazing Fast** - Powered by Tantivy (Lucene-grade search engine)
🔒 **Privacy-First** - 100% local, zero tracking, no data collection
🎯 **Smart Indexing** - Processes recent files first, skips unchanged content
🎨 **Delightful UX** - Animated search dog, sortable columns, instant preview
📦 **Content Search** - Index file contents with intelligent sampling
☁️ **Cloud-Aware** - Detects iCloud/OneDrive placeholders automatically

---

## Repository Structure

- **`finder-core`** - Rust search engine (indexing, querying, file scanning)
- **`mac-app`** - SwiftUI macOS application with modern Mac design
- **`scripts`** - Build automation and universal binary creation

## Quick Start

### Prerequisites
- macOS 13.0+ (Ventura or later)
- Xcode 15+ with Command Line Tools
- Rust toolchain (stable)

### Build Instructions

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/my-search-buddy.git
cd my-search-buddy

# 2. Build universal Rust library (Intel + Apple Silicon)
bash scripts/build_finder_core_universal.sh

# 3. Build the Mac app
cd mac-app
xcodebuild -scheme MySearchBuddy -configuration Release build

# 4. Run the app
open ~/Library/Developer/Xcode/DerivedData/MySearchBuddy-*/Build/Products/Release/MySearchBuddy.app
```

### Running Tests
```bash
# Rust tests
cargo test -p finder-core

# Swift FFI tests
cd mac-app/Packages/FinderCoreFFI
swift test
```

## Pricing & Availability

- **30-day free trial.** Every Apple ID gets a month of full functionality to kick the tires.
- **$9.99/year thereafter.** Auto-renewing subscription that funds continuous extractor upgrades, incremental indexing improvements, and priority feature requests.
- Manage or cancel anytime via the App Store subscription settings; the app reverts to paywall mode when the subscription lapses.
- **Source stays MIT.** This repository remains MIT licensed, so you can inspect or fork the code, while the commercial App Store build is delivered under the subscription above. Contributions continue to be accepted under MIT-compatible terms.

## Indexing Model

- **Recent-aware results.** The index stores modified timestamps and the UI ships with a `Modified` sort toggle plus a last-indexed status, making it easy to surface the newest files right after a scan. On launch (and whenever you add/enable folders) the app automatically runs a lightweight incremental sweep using the previous index timestamp so fresh files appear without a manual rebuild.
- **No double work.** Each document is fingerprinted via device/inode + path, so unchanged files are skipped without reopening their contents on subsequent runs.
- **Full builds stay fast.** Tantivy commits happen in batches (count or time based), letting the index refresh quickly while still delivering Lucene-grade search speed.
- **Content sampling (beta).** Plaintext is sniffed with binary heuristics and, when enabled, sampled according to your preference (target default: 10% total with 8% from the beginning and 2% from the tail; small files index fully).
- **Format adapters roadmap.** Plain UTF-8 content is available today; PDF, DOCX, Markdown, and HTML adapters plug into the same pipeline so content searches keep pace as new extractors land.
- **Cloud-aware metadata.** Files that still live exclusively in iCloud/OneDrive/Dropbox placeholders are indexed by name and path, labelled with a cloud badge in results, and prompt the user to download before previewing. Once the file becomes available locally, the next incremental pass upgrades it with full content.

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

## Features

### Search & Discovery
- 🔍 **Multi-scope Search** - Search by name, content, or both
- 📊 **Sortable Results** - Click column headers (Name, Size, Modified, Relevance)
- 🏷️ **File Type Badges** - Color-coded extension tags (PDF, DOC, XLS, etc.)
- ⚡ **Quick Filters** - One-click filters for Office docs, PDFs, spreadsheets
- 👁️ **Quick Look** - Press Spacebar for instant preview
- 📂 **Smart Opening** - Enter to open, Double-click, or ⌘R to reveal in Finder

### Indexing Intelligence
- 🕐 **Recent-First** - Newest files indexed first (last 90 days → 6 months → year → older)
- 🔄 **Incremental Updates** - Only processes new/changed files
- ☁️ **Cloud Detection** - Identifies iCloud/OneDrive placeholders automatically
- 🚫 **Hidden File Protection** - Skips system files and secrets automatically
- 🎯 **Smart Sampling** - Configurable content coverage (2%-50%)

### User Experience
- 🐕 **Animated Mascot** - Cute digging dog during search, holds bone when done!
- 📍 **Location Management** - Multi-folder support with enable/disable toggles
- ⌨️ **Keyboard Shortcuts** - Spacebar (preview), Enter (open), ⌘R (reveal)
- 🎨 **File Icons** - Context-aware icons for documents, images, code, archives
- 🌙 **Native macOS** - SwiftUI design, follows system appearance

### Security & Privacy
- 🔐 **Sandboxed** - Full App Store sandbox compliance
- 🏠 **Local-Only** - Zero network access, no data transmission
- 🔒 **Security-Scoped Bookmarks** - User-controlled folder access only
- 🚫 **No Tracking** - Zero analytics, telemetry, or data collection
- 📜 **Privacy Manifest** - Complete transparency (PrivacyInfo.xcprivacy)

## Project Status

**Current Version:** 0.2 (Build 1)
**Status:** 🟢 Production-Ready - In TestFlight Beta
**Platform:** macOS 13.0+ (Ventura, Sonoma, Sequoia)
**Architecture:** Universal Binary (Intel + Apple Silicon)

### Recent Milestones
- ✅ Security audit complete (all vulnerabilities fixed)
- ✅ Memory leaks resolved
- ✅ Thread safety ensured
- ✅ Performance optimizations applied
- ✅ Sortable columns with visual indicators
- ✅ Animated search mascot
- ✅ TestFlight-ready build

### Roadmap
- 📄 PDF content extraction
- 📝 DOCX/DOC indexing
- 🌐 HTML/Markdown support
- 📊 Advanced search syntax (filters, operators)
- 🎨 Custom color themes
- ⚙️ Advanced indexing preferences

---

## Documentation

- **[TESTFLIGHT_DISTRIBUTION.md](TESTFLIGHT_DISTRIBUTION.md)** - Complete TestFlight setup guide
- **[SECURITY_AUDIT.md](SECURITY_AUDIT.md)** - Comprehensive security & privacy audit
- **[PRIVACY.md](PRIVACY.md)** - How permissions and storage work
- **[SECURITY.md](SECURITY.md)** - Responsible disclosure guidelines

---

## Contributing

We welcome contributions! This project uses:
- **Rust** (finder-core) - Search engine, indexing, FFI
- **Swift/SwiftUI** (mac-app) - macOS user interface
- **MIT License** - Permissive, commercial-friendly

### Accepted Licenses
✅ MIT, Apache-2.0, BSD, ISC, MPL-2.0, Unlicense, CC0, Zlib
❌ GPL, LGPL, AGPL (App Store compatibility)

### Guidelines
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes with clear messages
4. Push to your branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

All contributions are accepted under MIT-compatible terms.

---

## Support & Community

- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/yourusername/my-search-buddy/issues)
- 💡 **Feature Requests:** [GitHub Discussions](https://github.com/yourusername/my-search-buddy/discussions)
- 📧 **Contact:** [your-email@example.com]
- 🔒 **Security Issues:** See [SECURITY.md](SECURITY.md) for responsible disclosure

---

## Acknowledgments

### Core Technologies
- **[Tantivy](https://github.com/quickwit-oss/tantivy)** - Blazing fast search engine (MIT)
- **SwiftUI** - Modern macOS UI framework
- **Rust** - Memory-safe systems programming

### Key Dependencies
All dependencies use permissive open-source licenses:
- [tantivy](https://crates.io/crates/tantivy) - MIT
- [globset](https://crates.io/crates/globset) - MIT OR Unlicense
- [anyhow](https://crates.io/crates/anyhow) - MIT OR Apache-2.0
- [serde](https://crates.io/crates/serde) - MIT OR Apache-2.0

Full license attributions available in-app via LicensePlist.

---

## License

**MIT License** - See [LICENSE](LICENSE) file for details.

Copyright (c) 2025 My Search Buddy

Permission is hereby granted, free of charge, to use, modify, and distribute this software for any purpose, commercial or non-commercial, subject to the MIT license terms.

---

**Made with ❤️ for Mac users who deserve better search**

## FFI Header

- `finder-core/include/finder_core.h` is committed for the Swift bridge. Regenerate it with:
  ```bash
  cbindgen --config finder-core/cbindgen.toml --crate finder-core --output finder-core/include/finder_core.h
  ```
- Build the dynamic library for Swift with `cargo build -p finder-core` (debug) or `cargo build -p finder-core --release` and point `FINDER_CORE_DYLIB` at the resulting `.dylib` before running Swift tests.
