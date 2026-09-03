import Foundation

struct ExportSettings: Codable {
    var outputResolution: OutputResolution = .hd1080p
    var outputFileType: OutputFileType = .mp4
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
