# Privacy Policy

_Last updated: 2024-05-23_

My Search Buddy is built for people who care about privacy. The app performs every indexing and search operation locally on your Mac. No filenames, file contents, metadata, or usage analytics ever leave your device.

## What data we collect

We do **not** collect personal data. The app does not transmit any data to external servers, does not use third-party analytics or advertising SDKs, and does not perform telemetry of any kind.

## How the app accesses your files

- You explicitly choose the folders to index via `NSOpenPanel`.
- The app stores Apple security-scoped bookmarks so it can re-open those folders inside the App Sandbox without requesting broader permissions.
- No hidden permissions are requested; you can revoke access at any time from the in-app settings.

## Local storage

- Indexed data (Tantivy indexes and metadata caches) are stored locally on disk within the app’s sandbox container.
- You can delete the index at any time from the settings screen; the app will remove the on-disk files.

## Networking

- The app does not perform network requests. You can verify this by inspecting the code in this public repository or monitoring network activity; it should be zero while the app is running.

## Third-party services

- We do not embed third-party SDKs that collect data.
- Open-source dependencies are limited to permissive licenses (MIT, Apache-2.0, BSD, ISC, MPL-2.0, Unlicense, CC0, Zlib). Copyleft licenses are intentionally excluded to avoid distribution conflicts.

## Contact

Questions about privacy? Email david at codeaccelerate.com.

Please do not send personal or sensitive data when contacting us.
