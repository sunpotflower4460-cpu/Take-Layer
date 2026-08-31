import Foundation

struct ExportSettings: Codable {
    var muteCameraAudio: Bool = true
    var outputResolution: OutputResolution = .hd1080p
    var outputFileType: OutputFileType = .mp4
}

enum OutputResolution: String, CaseIterable, Identifiable, Codable {
    case hd1080p = "1080p"

    var id: String { rawValue }
    var maxLongEdge: Double { 1920 }
    var maxShortEdge: Double { 1080 }
}

enum OutputFileType: String, CaseIterable, Identifiable, Codable {
    case mp4 = "MP4"

    var id: String { rawValue }
    var fileExtension: String { "mp4" }
}
