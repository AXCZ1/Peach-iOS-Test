import SwiftUI

@main
struct PeachTestApp: App {
    @StateObject private var session = PeachSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
