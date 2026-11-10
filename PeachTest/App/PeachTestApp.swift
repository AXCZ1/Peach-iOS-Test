import SwiftUI

@main
struct PeachTestApp: App {
    @UIApplicationDelegateAdaptor(PeachAppDelegate.self) private var delegate
    @StateObject private var session = PeachSession()
    @StateObject private var preferences = Preferences()
    @StateObject private var playback = PlaybackSessions.shared
    @StateObject private var offlinePreviews = OfflinePreviewScan()
    @StateObject private var seekPreviews = SeekPreviewSync()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .environmentObject(offlinePreviews)
                .environmentObject(seekPreviews)
                .task(id: SeekPreviewSync.Trigger(
                    active: scenePhase == .active && seekPreviews.onWiFi,
                    peach: session.api?.baseURL,
                    configuration: seekPreviews.configurationRevision
                )) {
                    guard scenePhase == .active else { return }
                    await seekPreviews.sync(session.api)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in offlinePreviews.setScene(phase) }
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
