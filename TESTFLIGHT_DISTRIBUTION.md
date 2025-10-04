# TestFlight Distribution Guide for MySearchBuddy

## Overview
This guide outlines the steps to distribute MySearchBuddy via TestFlight for Mac apps.

## Code Hardening Completed

### Critical Fixes Applied:
1. **Memory Leak Fixed** (BookmarkStore.swift:62)
   - Added capture list to prevent resource leak in closure
   - Security-scoped resources now properly released

2. **Race Condition Fixed** (IndexCoordinator.swift:21, 238)
   - Added dedicated serial queue for schedule state management
   - All schedule modifications now properly synchronized
   - Fixed concurrent access to `scheduledWorkItem` and `nextScheduledRun`

3. **Thread Safety Improvements**
   - Replaced `DispatchQueue.main.async` with `Task { @MainActor }` for published properties
   - Ensures all UI updates happen on main thread via Swift concurrency

4. **Entitlements Configuration** (MySearchBuddy.entitlements)
   - Added `com.apple.security.app-sandbox` for App Store compliance
   - Added `com.apple.security.files.user-selected.read-write` for folder access
   - Added `com.apple.security.files.bookmarks` (app and document scope) for persistent access

5. **Error Handling Enhanced**
   - Added proper error logging throughout IndexCoordinator
   - Fixed silent failures in directory creation and file operations
   - Added error handling to SearchViewModel

6. **Rust FFI Safety** (ffi.rs:192-229)
   - Fixed potential double-free vulnerability in `fc_free_results`
   - Pointer nullification now happens before memory deallocation
   - Added defensive guards against invalid state

7. **Release Build Optimization** (project.pbxproj)
   - Enabled Link-Time Optimization (LTO)
   - Set optimization level to `-Os` (size)
   - Enabled dSYM generation for crash symbolication
   - Added `VALIDATE_PRODUCT = YES`

## Prerequisites

### 1. Apple Developer Account
- Active Apple Developer Program membership ($99/year)
- Admin or App Manager role in App Store Connect
- Valid Developer ID Application certificate

### 2. App Store Connect Setup
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to "My Apps"
3. Click "+" button and select "New App"
4. Fill in app information:
   - **Platform:** macOS
   - **Name:** My Search Buddy
   - **Primary Language:** English
   - **Bundle ID:** app.mysearchbuddy.mac (must match Xcode)
   - **SKU:** mysearchbuddy-mac-001 (unique identifier)

### 3. Code Signing Configuration

#### In Xcode:
1. Open `MySearchBuddy.xcodeproj`
2. Select MySearchBuddy target
3. Go to "Signing & Capabilities"
4. **Signing Team:** Select your Apple Developer team
5. **Bundle Identifier:** Verify it's `app.mysearchbuddy.mac`
6. **Signing Certificate:** "Apple Development" for TestFlight
7. Ensure "Automatically manage signing" is **UNCHECKED** for distribution builds

#### Create Distribution Certificate (if needed):
```bash
# In Xcode menu: Xcode > Settings > Accounts
# Select your team > Manage Certificates > + > Apple Distribution
```

### 4. Provisioning Profile
1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to Certificates, IDs & Profiles
3. Create new Provisioning Profile:
   - **Type:** Mac App Store
   - **App ID:** app.mysearchbuddy.mac
   - **Certificates:** Select your Distribution certificate
   - Download and double-click to install

## Build for Distribution

### Step 1: Archive the App
```bash
cd /Users/david/GitHub/my-search-buddy

# Build universal Rust library
bash scripts/build_finder_core_universal.sh

# Archive with Xcode
cd mac-app
xcodebuild -project MySearchBuddy.xcodeproj \
  -scheme MySearchBuddy \
  -configuration Release \
  -archivePath ./build/MySearchBuddy.xcarchive \
  clean archive \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="<YOUR_PROVISIONING_PROFILE_NAME>"
```

### Step 2: Export for App Store Distribution
```bash
# Create ExportOptions.plist
cat > ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string><YOUR_TEAM_ID></string>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
EOF

# Export archive
xcodebuild -exportArchive \
  -archivePath ./build/MySearchBuddy.xcarchive \
  -exportPath ./build/Export \
  -exportOptionsPlist ./ExportOptions.plist
```

### Step 3: Upload to App Store Connect

#### Option A: Using Transporter App (Recommended)
1. Download [Transporter](https://apps.apple.com/us/app/transporter/id1450874784) from Mac App Store
2. Open Transporter
3. Drag `MySearchBuddy.pkg` from `./build/Export/` into Transporter
4. Click "Deliver"
5. Wait for validation and upload to complete

#### Option B: Using altool (Command Line)
```bash
xcrun altool --upload-app \
  --type macos \
  --file ./build/Export/MySearchBuddy.pkg \
  --username "<YOUR_APPLE_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

**Note:** Generate app-specific password at [appleid.apple.com](https://appleid.apple.com) under Security > App-Specific Passwords

## TestFlight Configuration

### 1. Enable TestFlight
1. Go to App Store Connect
2. Select MySearchBuddy
3. Go to "TestFlight" tab
4. Wait for build to finish processing (10-30 minutes)

### 2. Configure Test Information
1. Under "Test Information":
   - **What to Test:** Describe key features to test
   - **Test Notes:** Include known issues or specific testing instructions
   - **Feedback Email:** Provide support email

### 3. Add Internal Testers
1. Click "Internal Testing" in left sidebar
2. Create a new group or use "App Store Connect Users"
3. Select testers from your team
4. Click "Add Build" and select your uploaded build
5. Testers will receive email invitation

### 4. Add External Testers (Optional)
1. Click "External Testing"
2. Create a new group
3. Add tester emails (up to 10,000)
4. **Note:** External testing requires App Review before sending invites

## Pre-Submission Checklist

- [ ] All critical crashes fixed (see fixes above)
- [ ] Entitlements properly configured
- [ ] Code signing certificate valid
- [ ] Provisioning profile includes correct App ID
- [ ] Version number incremented in Info.plist (CFBundleShortVersionString)
- [ ] Build number incremented (CFBundleVersion)
- [ ] App tested locally on clean machine
- [ ] Privacy manifest (PrivacyInfo.xcprivacy) reviewed
- [ ] No hardcoded credentials or API keys
- [ ] Subscription product ID configured: `com.mysearchbuddy.subscription.yearly`

## Troubleshooting

### Build Fails with Code Signing Error
- Verify certificate is valid: `security find-identity -v -p codesigning`
- Check provisioning profile matches bundle ID
- Ensure no expired certificates in Keychain Access

### Upload Rejected
- Check email from App Store Connect for specific issues
- Common issues:
  - Missing required icons (update Assets.xcassets)
  - Invalid entitlements
  - Missing privacy descriptions

### TestFlight Build Not Appearing
- Wait 10-30 minutes for processing
- Check for email from Apple about processing issues
- Verify build number is unique (increment if resubmitting)

## Version Management

Current version: **0.2 (Build 1)**

For each new TestFlight build:
1. Increment build number in Info.plist: `CFBundleVersion`
2. Update version for major releases: `CFBundleShortVersionString`
3. Document changes in "What to Test" section

## Security & Privacy

### Required Privacy Disclosures:
- **File Access:** App indexes user-selected folders for search
- **No Data Collection:** App does not collect analytics or user data
- **Local Processing:** All indexing happens locally on device
- **Subscription Data:** StoreKit handles payment info (not accessible to app)

### Indexing Behavior:
- **Hidden Files:** Automatically excluded (`.skipsHiddenFiles`) - prevents indexing system files
- **Indexing Order:** Processes recent files first (last 90 days → 6 months → 12 months → older)
- **Rebuild Index:** Completely resets and rebuilds the index from scratch
- **Update Index:** Only indexes new or modified files since last run

### Entitlements Explained:
- `app-sandbox`: Required for App Store distribution
- `files.user-selected.read-write`: Allows access to folders user explicitly selects
- `files.bookmarks`: Persists access to user-selected folders between launches

## Next Steps After TestFlight

1. **Gather Feedback:** Monitor TestFlight feedback and crash reports
2. **Fix Issues:** Address any crashes or critical bugs
3. **Prepare for Review:** Once stable, submit for App Store review
4. **App Store Listing:** Prepare screenshots, description, keywords
5. **Pricing:** Configure subscription pricing in App Store Connect

## Support

- Apple Developer Documentation: https://developer.apple.com/testflight/
- App Store Connect Help: https://help.apple.com/app-store-connect/
- Xcode Cloud (CI/CD): Consider for automated builds

---

**Build Hardening Status:** ✅ Complete
**Ready for TestFlight:** ✅ Yes
**Estimated Crash Risk:** Low (all critical vulnerabilities addressed)
