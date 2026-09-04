import Foundation

struct ExportSettings: Codable {
    var outputResolution: OutputResolution = .hd1080p
    var outputFileType: OutputFileType = .mp4

    /// Camera audio is not part of the deterministic program-audio export path.
    /// Kept as a read-only compatibility accessor for older UI/code while the
    /// persisted setting itself is intentionally removed.
    var muteCameraAudio: Bool { true }
}

enum OutputResolution: String, Codable, CaseIterable {
    case hd1080p = "1920x1080"
}

enum OutputFileType: String, Codable, CaseIterable {
    case mp4 = "MP4"

    var fileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        }
    }
}
