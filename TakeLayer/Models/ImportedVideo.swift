import Foundation

struct ImportedVideo: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var durationSec: Double
    var width: Int?
    var height: Int?
    var orientation: MediaOrientation
    var fileType: String?
    var hasAudio: Bool
    var fileSizeBytes: Int64?
}

enum MediaOrientation: String, Codable {
    case portrait = "Portrait"
    case landscape = "Landscape"
    case square = "Square"
    case unknown = "Unknown"
}
