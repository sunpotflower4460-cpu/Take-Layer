import Foundation

struct ImportedMasterAudio: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var durationSec: Double
    var sampleRate: Double?
    var channelCount: Int?
    var fileType: String?
    var fileSizeBytes: Int64?
}
