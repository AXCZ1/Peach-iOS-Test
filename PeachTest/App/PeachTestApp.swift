import SwiftUI

@main
struct PeachTestApp: App {
    @StateObject private var session = PeachSession()
    @StateObject private var preferences = Preferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .preferredColorScheme(.dark)
        }
    }
}
