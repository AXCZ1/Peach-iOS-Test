import SwiftUI

struct AccountSheet: View {
    @ObservedObject var session: PeachSession
    let libraryCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    HStack {
                        Text("服务")
                        Spacer()
                        Text(session.address)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("馆藏", value: "\(libraryCount) 个")
                    LabeledContent("模式", value: "只读测试版")
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        session.signOut()
                        dismiss()
                    }
                }
                Section {
                    Text("本测试版不写入播放历史、评分或收藏，也不提供管理、刮削、下载和文件操作。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PeachTheme.background)
            .navigationTitle("账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .preferredColorScheme(.dark)
        }
    }
}
