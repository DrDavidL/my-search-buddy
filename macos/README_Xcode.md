# Building MySearchBuddy (SwiftUI app)

## Prerequisites

- Xcode 15.3 or newer (for Swift 5.9+ and macOS 13 deployment target)
- Rust toolchain (stable 1.7x) with `cargo`

## Steps

1. Build the Rust core so the Swift wrapper can link against `libfinder_core.dylib`:

   ```bash
   cargo build -p finder-core --release
   ```

   This produces the dylib in `target/release` (and `target/debug` if you build without `--release`).

2. Open the Xcode project:

   ```bash
   open mac-app/MySearchBuddy.xcodeproj
   ```

3. Select the **MySearchBuddy** scheme and build/run.

   If Xcode reports “library 'finder_core' not found”, ensure step 1 completed and that Xcode has permission to read the repo’s `target` directory.

## Troubleshooting

- **Missing dylib**: Re-run `cargo build -p finder-core --release`.
- **Linker errors / missing modules**: Clean build folder (`Shift`+`Cmd`+`K`), then build again.
- **SwiftPM sandbox warnings**: Xcode may emit diagnostics about cached manifests or simulator logs while resolving the FinderCoreFFI package; these do not affect macOS builds.

