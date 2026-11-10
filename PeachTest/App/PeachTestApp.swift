import SwiftUI

@main
struct PeachTestApp: App {
    @UIApplicationDelegateAdaptor(PeachAppDelegate.self) private var delegate
    @StateObject private var session = PeachSession()
    @StateObject private var preferences = Preferences()
    @StateObject private var playback = PlaybackSessions.shared
    @StateObject private var offlinePreviews = OfflinePreviewScan()
    @State private var seekPreviews = SeekPreviewSync()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .environmentObject(offlinePreviews)
                .environmentObject(seekPreviews)
                .onChange(of: session.api?.baseURL, initial: true) { _, _ in
                    seekPreviews.setAPI(session.api)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    seekPreviews.setScene(phase)
                    offlinePreviews.setScene(phase)
                }
                .onChange(of: session.phase) { _, phase in
                    if phase != .signedIn { offlinePreviews.stop() }
                }
                .preferredColorScheme(.dark)
                .fullScreenCover(item: $playback.restored) { session in
                    PlayerView(session: session)
                }
        }
    }
}
