import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: PeachSession
    @State private var password = ""
    @State private var working = false
    @FocusState private var focus: Field?

    private enum Field { case address, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PeachMark(size: 54)
                        .padding(.bottom, 28)

                    Text("Peach")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("馆藏测试版")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 2)

                    Text("使用同一 Wi-Fi 连接你的 Peach 媒体库。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 18)
                        .padding(.bottom, 34)

                    fieldLabel("服务地址")
                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .foregroundStyle(.white.opacity(0.45))
                        TextField("http://192.168.5.5:8900/", text: $session.address)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .focused($focus, equals: .address)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("login.address")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(PeachTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)))

                    fieldLabel("访问密码").padding(.top, 22)
                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .foregroundStyle(.white.opacity(0.45))
                        SecureField("Peach 访问密码", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .foregroundStyle(.white)
                            .submitLabel(.go)
                            .onSubmit { signIn() }
                            .accessibilityIdentifier("login.password")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(PeachTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)))

                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(PeachTheme.coral)
                            .padding(.top, 14)
                            .accessibilityIdentifier("login.error")
                    }

                    Button(action: signIn) {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(.black) }
                            Text(working ? "正在登录…" : "进入馆藏")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.black)
                        .background(PeachTheme.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(working || password.isEmpty)
                    .opacity(password.isEmpty ? 0.45 : 1)
                    .padding(.top, 28)
                    .accessibilityIdentifier("login.submit")

                    Text("密码仅用于本次登录，并保存在系统 Cookie 存储中；不会写入构建产物。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                        .lineSpacing(3)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 26)
                .padding(.top, 70)
            }
            .background(PeachTheme.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.bottom, 8)
    }

    private func signIn() {
        guard !working, !password.isEmpty else { return }
        working = true
        focus = nil
        Task {
            let entered = password
            await session.signIn(password: entered)
            working = false
            if session.phase == .signedIn { password = "" }
        }
    }
}

struct PeachMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [PeachTheme.coral, PeachTheme.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.black.opacity(0.78))
                .rotationEffect(.degrees(-16))
        }
        .frame(width: size, height: size)
        .shadow(color: PeachTheme.coral.opacity(0.3), radius: 22, y: 10)
    }
}

enum PeachTheme {
    static let background = Color(red: 0.055, green: 0.052, blue: 0.05)
    static let surface = Color(red: 0.095, green: 0.09, blue: 0.085)
    static let field = Color(red: 0.12, green: 0.115, blue: 0.11)
    static let coral = Color(red: 0.965, green: 0.478, blue: 0.42)
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.42)
    static let line = Color.white.opacity(0.08)
}
