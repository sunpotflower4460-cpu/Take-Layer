import Foundation

enum TimeFormatting {
    static func seconds(_ value: Double?) -> String {
        guard let value else { return "--:--.--" }
        return seconds(value)
    }

    static func seconds(_ value: Double) -> String {
        guard value.isFinite else { return "--:--.--" }
        let clampedValue = max(0, value)
        let minutes = Int(clampedValue / 60)
        let seconds = clampedValue - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    static func fileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
