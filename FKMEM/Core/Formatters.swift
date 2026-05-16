import Foundation

enum MemoryFormatter {
    nonisolated private static let gb = 1024.0 * 1024.0 * 1024.0
    nonisolated private static let mb = 1024.0 * 1024.0
    nonisolated private static let kb = 1024.0

    nonisolated static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= gb {
            return String(format: "%.2f GB", value / gb)
        }
        if value >= mb {
            return String(format: "%.1f MB", value / mb)
        }
        return String(format: "%.0f KB", value / kb)
    }

    nonisolated static func formatCompact(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= gb {
            return String(format: "%.1fG", value / gb)
        }
        if value >= mb {
            return String(format: "%.0fM", value / mb)
        }
        return String(format: "%.0fK", value / kb)
    }
}
