import Foundation

/// Display formatting helpers for local and soft-router log file sizes.
enum PeachLogFormatting {
    static let unavailableText = "暂未获取"

    /// Formats an actual byte count into KB or MB without estimation or zero masking.
    /// When `bytes` is `nil` (never obtained from the soft router), returns `"暂未获取"`.
    static func formatFileSize(bytes: Int64?) -> String {
        guard let bytes else { return unavailableText }
        let safeBytes = max(Int64(0), bytes)
        let megabyte: Double = 1024 * 1024
        if Double(safeBytes) >= megabyte {
            return String(format: "%.2f MB", Double(safeBytes) / megabyte)
        }
        let kb = Double(safeBytes) / 1024.0
        if safeBytes > 0 && safeBytes < 103 {
            return String(format: "%.2f KB", kb)
        }
        return String(format: "%.1f KB", kb)
    }

    static func formatTimestamp(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return unavailableText }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
