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

    init() {
        PeachRuntimeLogger.shared.log("App 启动", level: .info, category: "app", source: "PeachTestApp")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .environmentObject(offlinePreviews)
                .environmentObject(seekPreviews)
                .onChange(of: session.api?.baseURL, initial: true) { _, _ in
                    seekPreviews.setAPI(session.api)
                    if let api = session.api {
                        let origin = PeachAPI.originKey(for: api.baseURL)
                        PeachRuntimeLogger.shared.setUploader({ @Sendable batch in
                            try await api.uploadLogs(batch)
                        }, originKey: origin)
                    } else {
                        let fallbackOrigin = (try? PeachAPI.normalizedBaseURL(session.address)).map { PeachAPI.originKey(for: $0) }
                        PeachRuntimeLogger.shared.setUploader(nil, originKey: fallbackOrigin)
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    seekPreviews.setScene(phase)
                    offlinePreviews.setScene(phase)
                    PeachRuntimeLogger.shared.log(
                        "场景状态切换: \(String(describing: phase))",
                        level: .debug,
                        category: "lifecycle",
                        source: "PeachTestApp"
                    )
                    if phase == .active || phase == .background {
                        PeachRuntimeLogger.shared.triggerUpload()
                    }
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
