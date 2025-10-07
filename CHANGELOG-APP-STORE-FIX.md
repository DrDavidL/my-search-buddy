# App Store Submission Fixes - October 6, 2025

## Issues Resolved

### 1. **App Crash on Launch** ❌ → ✅
**Problem**: App crashed immediately on App Store reviewers' machines with error:
```
Library not loaded: /Users/*/libfinder_core.dylib
Reason: tried: '/Users/*/libfinder_core.dylib' (no such file)
```

**Root Cause**:
- `libfinder_core.dylib` had hardcoded absolute path from development machine
- Library was not embedded in app bundle
- Only worked on developer's machine where library existed at that path

**Solution**:
1. **Fixed library install name** (`scripts/build_finder_core_universal.sh:103`)
   - Added `install_name_tool -id "@rpath/libfinder_core.dylib"`
   - Library now uses relative path instead of absolute path

2. **Embedded library in app bundle** (`project.pbxproj`)
   - Added "Embed Libraries" copy phase
   - Copies `libfinder_core.dylib` to `MySearchBuddy.app/Contents/Frameworks/`

3. **Code signed embedded library** (`scripts/build_finder_core_universal.sh:112-117`)
   - Library is signed during build (before embedding)
   - Avoids Xcode sandbox restrictions on signing after embedding

### 2. **Missing dSYM Files** ⚠️ → ✅
**Problem**: Apple warning during archive:
```
The archive did not include a dSYM for the libfinder_core.dylib with the UUIDs [...]
```

**Root Cause**:
- Rust release builds didn't include debug symbols by default
- No dSYM was being generated or included in archive

**Solution**:
1. **Enable debug symbols in Rust** (`Cargo.toml:7-8`)
   ```toml
   [profile.release]
   debug = true  # Include debug symbols for dSYM generation
   ```

2. **Generate dSYM during build** (`scripts/build_finder_core_universal.sh:106-109`)
   - Added `dsymutil` call to create dSYM bundle
   - Creates `libfinder_core.dylib.dSYM` (155MB with full debug info)

3. **Copy dSYM during Archive** (`project.pbxproj`)
   - Added "Copy dSYM" build phase
   - Runs only during archiving (`runOnlyForDeploymentPostprocessing = 1`)
   - Copies to `DWARF_DSYM_FOLDER_PATH` for App Store submission

## Version Update
- **Marketing Version**: 0.2 → **0.3.1**
- **Build Number**: 1 → **2**

This signals to Apple that it's a new build addressing the crash issues.

## Files Modified

### Core Changes
1. **`Cargo.toml`** - Added debug symbols to release builds
2. **`scripts/build_finder_core_universal.sh`**
   - Set library install name to @rpath
   - Generate dSYM bundle
   - Sign library during build
3. **`mac-app/MySearchBuddy.xcodeproj/project.pbxproj`**
   - Updated version to 0.3.1 (build 2)
   - Added "Embed Libraries" build phase
   - Added "Copy dSYM" build phase (archive only)

## Build Verification

### Check library is properly configured:
```bash
# Verify install name uses @rpath
otool -L target/release/libfinder_core.dylib
# Should show: @rpath/libfinder_core.dylib

# Verify library is embedded in app
ls build/Products/Release/MySearchBuddy.app/Contents/Frameworks/
# Should show: libfinder_core.dylib

# Verify code signing
codesign -vv build/Products/Release/MySearchBuddy.app
# Should show: valid on disk
```

### Build Commands
```bash
# Regular build (for testing)
xcodebuild -project MySearchBuddy.xcodeproj -scheme MySearchBuddy -configuration Release build

# Archive (for App Store submission)
xcodebuild -project MySearchBuddy.xcodeproj -scheme MySearchBuddy -configuration Release archive
```

## What Works Now

✅ App launches on any macOS system (no hardcoded paths)
✅ Library properly embedded and signed
✅ dSYM included for crash symbolication
✅ Ready for App Store resubmission

## Technical Details

### Library Loading Path Resolution
Before: `/Users/david/.../libfinder_core.dylib` (absolute, fails on other machines)
After: `@rpath/libfinder_core.dylib` → resolves to `@executable_path/../Frameworks/libfinder_core.dylib`

### Build Phase Order
1. **Build finder-core** - Compiles Rust library, generates dSYM, signs it
2. **Sources** - Compiles Swift code
3. **Frameworks** - Links dependencies
4. **Resources** - Copies resources
5. **Embed Libraries** - Copies signed dylib to app bundle
6. **Copy dSYM** - (Archive only) Copies dSYM for App Store

### Sandbox Workarounds
- Library signing: Done in build script (before embedding) to avoid sandbox restrictions
- dSYM copying: Uses `DWARF_DSYM_FOLDER_PATH` and `runOnlyForDeploymentPostprocessing` flag
- Output path declarations ensure sandbox permissions

## Next Steps

1. Clean build: `xcodebuild clean`
2. Archive: Product → Archive in Xcode
3. Validate archive (check for warnings)
4. Distribute to App Store
5. Resubmit version 0.3.1 (build 2)

---
*Summary: Fixed critical app launch crash by embedding Rust library with proper @rpath configuration and code signing. Added dSYM generation for crash reporting.*
