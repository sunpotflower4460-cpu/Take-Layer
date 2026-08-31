import Foundation

struct RecordedTake: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var createdAt: Date
    var durationSec: Double?
    var width: Int?
    var height: Int?
    var orientation: MediaOrientation
    var fileType: String?
    var hasAudio: Bool
    var fileSizeBytes: Int64?
    var songStartRawSec: Double?
    var selectedRawStartSec: Double?
    var selectedRawEndSec: Double?

    var importedVideo: ImportedVideo? {
        guard let durationSec else { return nil }
        return ImportedVideo(
            url: url,
            durationSec: durationSec,
            width: width,
            height: height,
            orientation: orientation,
            fileType: fileType,
            hasAudio: hasAudio,
            fileSizeBytes: fileSizeBytes
        )
    }
}
