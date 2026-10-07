import AVFoundation
import CoreGraphics
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


    /// Frame-level checks that burned-in text is really in the pixels. An export can "complete" with the text
    /// layers silently missing (valid duration, size and tracks, but no title or lyrics), so the self-test samples
    /// frames and measures the luminance spread inside the title / lyric bands. The self-test source video is flat
    /// in every frame, so a wide spread can only come from drawn text and a narrow one means "no text here".
    /// Limit: this proves that glyphs were drawn, not that they are the right glyphs (no OCR).
    enum OverlayBand {
        /// Title layer: 120...300 px below the top edge of the 1080x1920 frame (rows 30..<75 of the 1/4 bitmap).
        static let title = 30..<75
        /// Lyric layer: 190...450 px above the bottom edge (rows 367..<432 of the 1/4 bitmap).
        static let lyric = 367..<432
    }

    static func bandContrast(_ url: URL, atSec: Double, rows: Range<Int>) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: atSec, preferredTimescale: 600)).image
        let w = 270, h = 480                       // 1080x1920 scaled by 1/4
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lo = 255, hi = 0
        for row in rows { for col in 0..<w { let v = Int(pixels[row * w + col]); lo = min(lo, v); hi = max(hi, v) } }
        return hi - lo
    }

    /// EditingPlan semantics for the self-test edit: the title is visible for the whole Short, the lyric cue only
    /// inside [cueStart, cueEnd]. `margin` keeps the probes off the cue's 2% fade edges.
    static func overlaySemanticsChecks(_ url: URL, cueStart: Double, cueEnd: Double, margin: Double = 0.25, duration: Double) async throws -> [RenderCheck] {
        let visible = 60, absent = 15
        let during = (cueStart + cueEnd) / 2
        var checks: [RenderCheck] = []
        for (name, t) in [("title_visible_start", 0.1), ("title_visible_during_cue", during), ("title_visible_end", duration - 0.2)] {
            let spread = try await bandContrast(url, atSec: t, rows: OverlayBand.title)
            checks.append(RenderCheck(name: name, ok: spread >= visible, detail: "t=\(t)s title band spread \(spread) (need >= \(visible))"))
        }
        let inside = try await bandContrast(url, atSec: during, rows: OverlayBand.lyric)
        checks.append(RenderCheck(name: "lyric_visible_during_cue", ok: inside >= visible, detail: "t=\(during)s lyric band spread \(inside) (need >= \(visible))"))
        let before = try await bandContrast(url, atSec: cueStart - margin, rows: OverlayBand.lyric)
        checks.append(RenderCheck(name: "lyric_not_visible_before_cue", ok: before <= absent, detail: "t=\(cueStart - margin)s lyric band spread \(before) (need <= \(absent))"))
        let after = try await bandContrast(url, atSec: cueEnd + margin, rows: OverlayBand.lyric)
        checks.append(RenderCheck(name: "lyric_not_visible_after_cue", ok: after <= absent, detail: "t=\(cueEnd + margin)s lyric band spread \(after) (need <= \(absent))"))
        return checks
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
