import AVFoundation
import CryptoKit
import Foundation

enum Hashing {
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct OutputFacts {
    var durationSec: Double
    var width: Int
    var height: Int
    var fps: Double
    var hasVideo: Bool
    var hasAudio: Bool
    var audioTrackCount: Int
    var sizeBytes: Int64
}

/// Render Quality Validation v1: exists, non-zero, readable container, duration range,
/// dimensions, fps, audio+video track, hash.
enum RenderValidator {
    static func probeDuration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    static func inspect(_ url: URL) async throws -> OutputFacts {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var width = 0, height = 0
        var fps = 0.0
        if let v = videoTracks.first {
            let natural = try await v.load(.naturalSize)
            let transform = try await v.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            width = Int(abs(rect.width).rounded())
            height = Int(abs(rect.height).rounded())
            fps = Double(try await v.load(.nominalFrameRate))
        }
        return OutputFacts(durationSec: duration, width: width, height: height, fps: fps,
                           hasVideo: !videoTracks.isEmpty, hasAudio: !audioTracks.isEmpty,
                           audioTrackCount: audioTracks.count, sizeBytes: size)
    }

    static func checks(facts: OutputFacts, expectedDurationSec: Double, expectedSize: CGSize) -> [RenderCheck] {
        let durationTolerance = 0.15
        return [
            RenderCheck(name: "file_non_empty", ok: facts.sizeBytes > 0, detail: "\(facts.sizeBytes) bytes"),
            RenderCheck(name: "container_readable", ok: facts.durationSec.isFinite && facts.durationSec > 0, detail: "duration \(facts.durationSec)s"),
            RenderCheck(name: "duration_in_range", ok: abs(facts.durationSec - expectedDurationSec) <= durationTolerance,
                        detail: "got \(facts.durationSec)s expected \(expectedDurationSec)s ±\(durationTolerance)"),
            RenderCheck(name: "dimensions", ok: facts.width == Int(expectedSize.width) && facts.height == Int(expectedSize.height),
                        detail: "got \(facts.width)x\(facts.height) expected \(Int(expectedSize.width))x\(Int(expectedSize.height))"),
            RenderCheck(name: "fps", ok: facts.fps >= 29 && facts.fps <= 31, detail: "nominal \(facts.fps)"),
            RenderCheck(name: "video_track", ok: facts.hasVideo, detail: "present=\(facts.hasVideo)"),
            RenderCheck(name: "audio_track", ok: facts.hasAudio && facts.audioTrackCount == 1, detail: "audio tracks=\(facts.audioTrackCount)"),
        ]
    }
}
