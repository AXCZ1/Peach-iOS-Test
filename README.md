# Peach iOS Test

Standalone SwiftUI test app for the Peach media server at `http://192.168.5.5:8900/`.

- Bundle ID: `com.axcz1.peachios.test`
- Display name: `Peach Test`
- Minimum iOS: 17.0
- Read-only catalog, search, filters, item details, native AVPlayer/HLS playback
- No write endpoints, management, scraping, downloads, or file operations

The app is intentionally separate from `NAS-ios`; it has its own Codemagic
application and produces `Peach-iOS-Test-unsigned.ipa`.
