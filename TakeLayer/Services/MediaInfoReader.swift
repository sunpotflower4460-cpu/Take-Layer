import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum MediaInfoReaderError: LocalizedError {
    case unreadableVideo
    case unreadableAudio
    case missingVideoTrack
    case missingAudioTrack

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "動画を読み込めませんでした。"
        case .unreadableAudio:
            return "WAVを読み込めませんでした。"
        case .missingVideoTrack:
            return "動画にvideo trackがありません。"
        case .missingAudioTrack:
            return "WAVにaudio trackがありません。"
        }
    }
}

enum MediaInfoReader {
    static func readVideo(from url: URL) async throws -> ImportedVideo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw MediaInfoReaderError.missingVideoTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let displaySize = naturalSize.applying(preferredTransform)
        let width = Int(abs(displaySize.width).rounded())
        let height = Int(abs(displaySize.height).rounded())

        return ImportedVideo(
            url: url,
            durationSec: duration.seconds,
            width: width,
            height: height,
            orientation: orientation(width: width, height: height),
            fileType: fileType(for: url),
            hasAudio: !audioTracks.isEmpty,
            fileSizeBytes: fileSize(for: url)
        )
    }

    static func readRecordedTake(from url: URL, createdAt: Date = Date()) async throws -> RecordedTake {
        let video = try await readVideo(from: url)
        return RecordedTake(
            url: url,
            createdAt: createdAt,
            durationSec: video.durationSec,
            width: video.width,
            height: video.height,
            orientation: video.orientation,
            fileType: video.fileType,
            hasAudio: video.hasAudio,
            fileSizeBytes: video.fileSizeBytes
        )
    }

    static func readMasterAudio(from url: URL) async throws -> ImportedMasterAudio {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw MediaInfoReaderError.missingAudioTrack
        }

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let streamDescription = formatDescriptions
            .compactMap { formatDescription in
                CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
            }
            .first

        return ImportedMasterAudio(
            url: url,
            durationSec: duration.seconds,
            sampleRate: streamDescription?.mSampleRate,
            channelCount: streamDescription.map { Int($0.mChannelsPerFrame) },
            fileType: fileType(for: url),
            fileSizeBytes: fileSize(for: url)
        )
    }

    private static func orientation(width: Int, height: Int) -> MediaOrientation {
        if width == 0 || height == 0 { return .unknown }
        if width == height { return .square }
        return width > height ? .landscape : .portrait
    }

    private static func fileType(for url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType ?? type.identifier
        }
        return url.pathExtension.isEmpty ? nil : url.pathExtension.uppercased()
    }

    private static func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize.map { Int64($0) }
    }
}
