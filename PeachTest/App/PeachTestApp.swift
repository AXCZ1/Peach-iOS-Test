import SwiftUI

@main
struct PeachTestApp: App {
    @StateObject private var session = PeachSession()
    @StateObject private var preferences = Preferences()
    @StateObject private var playback = PlaybackSessions.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .preferredColorScheme(.dark)
                .fullScreenCover(item: $playback.restored) { session in
                    PlayerView(session: session)
                }
        }
    }
}
