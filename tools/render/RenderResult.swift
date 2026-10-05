import Foundation

/// What the headless renderer reports back to the Mac Runner. Contains local paths
/// (the Runner resolves them to a runner-local asset id before anything leaves the Mac).
struct RenderCheck: Codable, Equatable {
    var name: String
    var ok: Bool
    var detail: String
}

struct RenderResult: Codable {
    var schemaVersion = 1
    var requestKey: String
    var status: String            // "completed" | "failed"
    var errorCode: String?
    var errorMessage: String?
    var renderer = "take-layer-render"
    var rendererVersion = renderToolVersion
    var outputPath: String?
    var contentHash: String?
    var sizeBytes: Int64?
    var durationSec: Double?
    var width: Int?
    var height: Int?
    var fps: Double?
    var hasVideoTrack: Bool?
    var hasAudioTrack: Bool?
    var audioSource: String?      // "master_wav" by construction (see ShortVideoExportService)
    var sourceHashes: [String: String]?
    var checks: [RenderCheck] = []
}

/// Written next to the output AFTER the atomic rename. The Runner's reconcile logic treats
/// "marker present and matching the file hash" as the only proof that a render completed.
struct RenderCommitMarker: Codable, Equatable {
    var schemaVersion = 1
    var requestKey: String
    var contentHash: String
    var sizeBytes: Int64
    var durationSec: Double
    var width: Int
    var height: Int
    var fps: Double
    var renderer: String
    var rendererVersion: String
    var audioSource: String
    var checks: [RenderCheck]
    var committedAt: String
}

let renderToolVersion = "1"

func markerURL(forOutput path: String) -> URL { URL(fileURLWithPath: path + ".commit.json") }
/// AVFoundation infers the container from the extension, so the partial file must also end in ".mp4".
func partialURL(forOutput path: String) -> URL {
    let base = path.hasSuffix(".mp4") ? String(path.dropLast(4)) : path
    return URL(fileURLWithPath: base + ".partial.mp4")
}
