# Peach iOS Test

Standalone SwiftUI app for the Peach media server at http://192.168.5.5:8900/.

- Bundle ID: com.axcz1.peachios.test
- Display name: Peach Test
- Minimum iOS: 17.0
- Catalog, search, filters, entity index/profiles, item details
- Native AVPlayer/HLS playback with resume position and watch telemetry
- Immersive random queue, video wall, large/dense density toggle
- Personal records: rating, climax count with undo, watch later, like, seen/dislike
- Read-only management view (tasks, configuration, scan/follow/download status)
- No delete, scrape, download-submit, authentication or deployment writes

Feature-by-feature parity with Peach 0.52.0, including what is intentionally
absent, is in [FEATURE-MATRIX.md](FEATURE-MATRIX.md).

The app is intentionally separate from NAS-ios; it has its own Codemagic
application and produces Peach-iOS-Test-unsigned.ipa.

Device acceptance steps are in [ACCEPTANCE.md](ACCEPTANCE.md). The app is not
connected to NAS iOS and does not modify NAS build 82.

