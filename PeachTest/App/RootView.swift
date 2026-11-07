import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: PeachSession

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ZStack {
                    PeachTheme.background.ignoresSafeArea()
                    ProgressView("正在恢复登录…").tint(PeachTheme.coral).foregroundStyle(.white)
                }
            case .signedOut:
                LoginView()
            case .signedIn:
                if let api = session.api {
                    LibraryRootView(api: api, session: session)
                        .id(ObjectIdentifier(api))
                }
            }
        }
        .task { await session.restore() }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }
}
