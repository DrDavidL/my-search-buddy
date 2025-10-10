# My Search Buddy - iOS

> **Status:** 🚧 Coming Soon

## Overview

The iOS version of My Search Buddy will bring powerful file search capabilities to iPhone and iPad, with a focus on:

- **Cross-cloud search** - Unified search across iCloud Drive, Dropbox, Google Drive, OneDrive
- **Smart file organization** - Quick access to files from multiple cloud services
- **Enhanced metadata search** - Search by file type, size, date, content
- **Native iOS integration** - Files app integration, Siri shortcuts, widgets

## Architecture

The iOS app will share the core Rust search engine (`core/finder-core`) with the macOS app, ensuring consistent performance and behavior across platforms.

```
ios/
├── MySearchBuddyiOS.xcodeproj    (Coming soon)
├── MySearchBuddyiOS/              (SwiftUI app)
├── Packages/
│   └── FinderCoreFFI-iOS/         (iOS-specific FFI wrapper)
└── scripts/
    └── build_finder_core_ios.sh   (iOS build script)
```

## Planned Features

### Phase 1 - MVP
- [ ] iCloud Drive indexing and search
- [ ] Files app integration
- [ ] Basic metadata filtering
- [ ] SwiftUI interface optimized for iOS

### Phase 2
- [ ] Dropbox integration
- [ ] Google Drive integration
- [ ] OneDrive integration
- [ ] Offline search
- [ ] Smart suggestions

### Phase 3
- [ ] Siri shortcuts
- [ ] Home screen widgets
- [ ] Share extension for quick save/tag
- [ ] iPad multitasking support

## Development Timeline

iOS development will begin after the macOS version is successfully launched on the App Store.

## Building (When Ready)

```bash
cd ios
./scripts/build_finder_core_ios.sh
open MySearchBuddyiOS.xcodeproj
```

## Contributing

Interested in helping with the iOS version? Check out the main README and open an issue to discuss!
