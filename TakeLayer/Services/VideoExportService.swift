import AVFoundation
import Foundation
import UIKit

enum VideoExportServiceError: LocalizedError {
    case missingVideo
    case missingMasterAudio
    case missingVideoTrack
    case missingAudioTrack
    case invalidSongStartRawSec
    case invalidSongStartAudioSec
    case invalidTrimRange
    case cannotCreateExportSession
    case unsupportedOutputType
    case exportFailed(String)
    case cannotSaveOutput

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            return "動画が読み込まれていません。"
        case .missingMasterAudio:
            return "WAVが読み込まれていません。"
        case .missingVideoTrack:
            return "動画にvideo trackがありません。"
        case .missingAudioTrack:
            return "WAVにaudio trackがありません。"
        case .invalidSongStartRawSec:
            return "songStartRawSecが動画duration外です。"
        case .invalidSongStartAudioSec:
            return "songStartAudioSecがWAV duration外です。"
        case .invalidTrimRange:
            return "selectedRawEndSecはselectedRawStartSecより大きくしてください。"
        case .cannotCreateExportSession:
            return "AVAssetExportSessionを作成できませんでした。"
        case .unsupportedOutputType:
            return "この素材ではMP4として書き出せません。"
        case .exportFailed(let message):
            return "書き出しに失敗しました: \(message)"
        case .cannotSaveOutput:
            return "出力先に保存できませんでした。"
        }
    }
}

struct ExportResult {
    var outputURL: URL
    var durationSec: Double
}

enum VideoExportService {
    static func export(project: ProjectDraft) async throws -> ExportResult {
        guard let importedVideo = project.activeVideo else { throw VideoExportServiceError.missingVideo }
        guard let importedMasterAudio = project.importedMasterAudio else { throw VideoExportServiceError.missingMasterAudio }

        let mapping: TimelineMapping
        do {
            mapping = try TimelineMapper.makeMapping(project: project)
        } catch TimelineMapperError.invalidVideoSongStart {
            throw VideoExportServiceError.invalidSongStartRawSec
        } catch TimelineMapperError.invalidAudioSongStart {
            throw VideoExportServiceError.invalidSongStartAudioSec
        } catch TimelineMapperError.invalidTrimRange {
            throw VideoExportServiceError.invalidTrimRange
        } catch {
            throw VideoExportServiceError.exportFailed(error.localizedDescription)
        }

        let videoAsset = AVURLAsset(url: importedVideo.url)
        let audioAsset = AVURLAsset(url: importedMasterAudio.url)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideoTrack = videoTracks.first else { throw VideoExportServiceError.missingVideoTrack }
        guard let sourceAudioTrack = audioTracks.first else { throw VideoExportServiceError.missingAudioTrack }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoExportServiceError.missingVideoTrack
        }
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoExportServiceError.missingAudioTrack
        }

        let outputDuration = CMTime(seconds: mapping.outputDurationSec, preferredTimescale: 600)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: mapping.videoSourceStartSec, preferredTimescale: 600),
                duration: outputDuration
            ),
            of: sourceVideoTrack,
            at: .zero
        )

        let audioInsertDuration = CMTime(seconds: mapping.audioInsertDurationSec, preferredTimescale: 600)
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: mapping.audioSourceStartSec, preferredTimescale: 600),
                duration: audioInsertDuration
            ),
            of: sourceAudioTrack,
            at: CMTime(seconds: mapping.audioInsertionTimeSec, preferredTimescale: 600)
        )

        let videoComposition = try await makeVideoComposition(
            for: compositionVideoTrack,
            sourceVideoTrack: sourceVideoTrack,
            duration: outputDuration
        )
        let outputURL = try makeOutputURL(fileExtension: project.exportSettings.outputFileType.fileExtension)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw VideoExportServiceError.cannotCreateExportSession
        }
        guard exportSession.supportedFileTypes.contains(.mp4) else {
            throw VideoExportServiceError.unsupportedOutputType
        }

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(start: .zero, duration: outputDuration)

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch {
            throw VideoExportServiceError.exportFailed(error.localizedDescription)
        }

        return ExportResult(outputURL: outputURL, durationSec: mapping.outputDurationSec)
    }

    private static func makeVideoComposition(
        for compositionVideoTrack: AVCompositionTrack,
        sourceVideoTrack: AVAssetTrack,
        duration: CMTime
    ) async throws -> AVMutableVideoComposition {
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let renderSize = scaledRenderSize(for: displaySize)
        let scale = min(renderSize.width / displaySize.width, renderSize.height / displaySize.height)
        let scaledSize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let normalizeTransform = CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let centerTransform = CGAffineTransform(
            translationX: (renderSize.width - scaledSize.width) / 2,
            y: (renderSize.height - scaledSize.height) / 2
        )
        let finalTransform = preferredTransform
            .concatenating(normalizeTransform)
            .concatenating(scaleTransform)
            .concatenating(centerTransform)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        return videoComposition
    }

    private static func scaledRenderSize(for displaySize: CGSize) -> CGSize {
        guard displaySize.width > 0, displaySize.height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }
        if displaySize.width >= displaySize.height {
            return CGSize(width: 1920, height: 1080)
        } else {
            return CGSize(width: 1080, height: 1920)
        }
    }

    private static func makeOutputURL(fileExtension: String) throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let directory else { throw VideoExportServiceError.cannotSaveOutput }
        let fileName = "TakeLayer-MVPAlpha-\(UUID().uuidString).\(fileExtension)"
        let outputURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        return outputURL
    }
}
