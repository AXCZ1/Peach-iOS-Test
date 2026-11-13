import SwiftUI

struct AppLogsView: View {
    @State private var snapshot: PeachLogSnapshot?
    @State private var syncing = false

    @MainActor
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        List {
            Section("文件占用") {
                LabeledContent(
                    "本机日志占用",
                    value: PeachLogFormatting.formatFileSize(bytes: snapshot?.localFileBytes)
                )
                LabeledContent(
                    "软路由日志占用",
                    value: PeachLogFormatting.formatFileSize(bytes: snapshot?.serverFileBytes)
                )
                LabeledContent(
                    "软路由更新时间",
                    value: PeachLogFormatting.formatTimestamp(snapshot?.serverUpdatedAt)
                )
                LabeledContent(
                    "本机有效记录",
                    value: snapshot.map { "\($0.totalCount) 条（待上传 \($0.pendingCount) 条）" } ?? PeachLogFormatting.unavailableText
                )
                if let lastError = snapshot?.lastError, !lastError.isEmpty {
                    Text("最近上传异常：\(lastError)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    Task {
                        syncing = true
                        defer { syncing = false }
                        snapshot = await PeachRuntimeLogger.shared.refreshSnapshot(syncPending: true)
                    }
                } label: {
                    HStack {
                        Label("立即上传待同步日志", systemImage: "arrow.up.circle")
                        Spacer()
                        if syncing || snapshot?.isUploading == true {
                            ProgressView().tint(PeachTheme.coral)
                        }
                    }
                }
                .disabled(syncing || (snapshot?.pendingCount ?? 0) == 0)
            } header: {
                Text("同步")
            } footer: {
                Text("手机与软路由均只保留最近 1 小时日志；记录在写盘和上传前均会自动脱敏。软路由占用仅在日志上传响应中更新，不单独探测。")
            }

            Section("最近本机日志（已脱敏）") {
                if let entries = snapshot?.recentEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(entry.level.uppercased())
                                    .font(.caption2.weight(.bold).monospaced())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(levelColor(entry.level).opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(levelColor(entry.level))
                                Text(entry.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text(Self.shortTimeFormatter.string(from: Date(timeIntervalSince1970: entry.ts)))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                            if !entry.fields.isEmpty {
                                Text(entry.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } else {
                    Text(snapshot == nil ? "正在读取本机日志…" : "最近一小时内暂无日志记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachTheme.background)
        .foregroundStyle(.white)
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PeachTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        snapshot = await PeachRuntimeLogger.shared.refreshSnapshot(syncPending: false)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                snapshot = await PeachRuntimeLogger.shared.refreshSnapshot(syncPending: false)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func levelColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "error", "fault": return .red
        case "warning": return .orange
        case "info", "notice": return PeachTheme.coral
        default: return .gray
        }
    }
}
