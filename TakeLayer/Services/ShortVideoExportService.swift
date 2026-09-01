import AVFoundation
import Foundation
import QuartzCore
import UIKit

enum ShortVideoExportError: LocalizedError {
    case invalidDraft
    case invalidLyrics
    case overlappingLyrics
    case missingVideo
    case missingMasterAudio
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateExportSession
    case unsupportedOutputType
    case cannotSaveOutput
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDraft:
            return "Shortの範囲または編集Planが不正です。"
        case .invalidLyrics:
            return "選択範囲内に未完成の歌詞字幕Cueがあります。テキストと開始・終了時刻を修正するか、不要なCueを削除してください。"
        case .overlappingLyrics:
            return "選択範囲内で歌詞字幕の時間が重なっています。各Cueの時間を重ならないように調整してください。"
        case .missingVideo:
            return "動画が読み込まれていません。"
        case .missingMasterAudio:
            return "完成WAVが読み込まれていません。"
        case .missingVideoTrack:
            return "動画trackを読み取れませんでした。"
        case .missingAudioTrack:
            return "WAV trackを読み取れませんでした。"
        case .cannotCreateExportSession:
            return "Short用export sessionを作成できませんでした。"
        case .unsupportedOutputType:
            return "この素材をMP4として書き出せません。"
        case .cannotSaveOutput:
            return "Shortの保存先を作成できませんでした。"
        case .exportFailed(let message):
            return "Short書き出しに失敗しました: \(message)"
        }
    }
}

enum ShortVideoExportService {
    // Microsecond ticks make millisecond user offsets exactly representable
    // while leaving ample headroom for normal project durations.
    static let mediaTimescale: CMTimeScale = 1_000_000

    static func export(project: ProjectDraft, draft: ShortEditDraft) async throws -> ExportResult {
        guard draft.durationSec > 0, draft.durationSec.isFinite else {
            throw ShortVideoExportError.invalidDraft
        }
        guard !draft.hasInvalidLyricCues else {
            throw ShortVideoExportError.invalidLyrics
        }
        guard !draft.hasOverlappingValidLyricCues else {
            throw ShortVideoExportError.overlappingLyrics
        }
        guard let video = project.activeVideo else { throw ShortVideoExportError.missingVideo }
        guard let audio = project.importedMasterAudio else { throw ShortVideoExportError.missingMasterAudio }

        let mapping: TimelineMapping
        do {
            mapping = try TimelineMapper.makeMapping(
                project: project,
                projectTimelineStartSec: draft.rangeStartProjectSec,
                durationSec: draft.durationSec
            )
        } catch {
            throw ShortVideoExportError.invalidDraft
        }

        let videoAsset = AVURLAsset(url: video.url)
        let audioAsset = AVURLAsset(url: audio.url)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ShortVideoExportError.missingVideoTrack
        }
        guard let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ShortVideoExportError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ShortVideoExportError.missingVideoTrack
        }
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ShortVideoExportError.missingAudioTrack
        }

        let outputDuration = mediaTime(mapping.outputDurationSec)
        try videoTrack.insertTimeRange(
            CMTimeRange(
                start: mediaTime(mapping.videoSourceStartSec),
                duration: outputDuration
            ),
            of: sourceVideoTrack,
            at: .zero
        )

        let audioDuration = mediaTime(mapping.audioInsertDurationSec)
        try audioTrack.insertTimeRange(
            CMTimeRange(
                start: mediaTime(mapping.audioSourceStartSec),
                duration: audioDuration
            ),
            of: sourceAudioTrack,
            at: mediaTime(mapping.audioInsertionTimeSec)
        )

        let videoComposition = try await makeVideoComposition(
            compositionVideoTrack: videoTrack,
            sourceVideoTrack: sourceVideoTrack,
            duration: outputDuration,
            projectRangeStartSec: draft.rangeStartProjectSec,
            draft: draft
        )

        let outputURL = try makeOutputURL()
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ShortVideoExportError.cannotCreateExportSession
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw ShortVideoExportError.unsupportedOutputType
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: .zero, duration: outputDuration)

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw ShortVideoExportError.exportFailed(error.localizedDescription)
        }

        return ExportResult(outputURL: outputURL, durationSec: mapping.outputDurationSec)
    }

    static func mediaTime(_ seconds: Double) -> CMTime {
        guard seconds.isFinite else { return .invalid }
        let ticks = (seconds * Double(mediaTimescale)).rounded()
        guard ticks >= Double(Int64.min), ticks <= Double(Int64.max) else { return .invalid }
        return CMTime(value: Int64(ticks), timescale: mediaTimescale)
    }

    private static func makeVideoComposition(
        compositionVideoTrack: AVCompositionTrack,
        sourceVideoTrack: AVAssetTrack,
        duration: CMTime,
        projectRangeStartSec: Double,
        draft: ShortEditDraft
    ) async throws -> AVMutableVideoComposition {
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let geometry = ShortRenderGeometryBuilder.make(displaySize: displaySize, crop: draft.crop)

        let normalize = CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        let scale = CGAffineTransform(scaleX: geometry.scale, y: geometry.scale)
        let cropTranslation = CGAffineTransform(
            translationX: -geometry.cropOffset.x,
            y: -geometry.cropOffset.y
        )
        let finalTransform = preferredTransform
            .concatenating(normalize)
            .concatenating(scale)
            .concatenating(cropTranslation)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = geometry.renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.animationTool = makeAnimationTool(
            renderSize: geometry.renderSize,
            durationSec: duration.seconds,
            projectRangeStartSec: projectRangeStartSec,
            draft: draft
        )
        return composition
    }

    private static func makeAnimationTool(
        renderSize: CGSize,
        durationSec: Double,
        projectRangeStartSec: Double,
        draft: ShortEditDraft
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let trimmedTitle = draft.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            let titleLayer = textLayer(
                text: trimmedTitle,
                frame: CGRect(x: 72, y: renderSize.height - 300, width: renderSize.width - 144, height: 180),
                fontSize: 60,
                alignment: .center
            )
            parentLayer.addSublayer(titleLayer)
        }

        let shortEnd = projectRangeStartSec + durationSec
        for cue in draft.validLyricCues {
            let overlapStart = max(cue.startProjectSec, projectRangeStartSec)
            let overlapEnd = min(cue.endProjectSec, shortEnd)
            guard overlapEnd > overlapStart else { continue }

            let layer = textLayer(
                text: cue.text,
                frame: CGRect(x: 72, y: 190, width: renderSize.width - 144, height: 260),
                fontSize: 52,
                alignment: .center
            )
            layer.opacity = 0
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, 1, 1, 0]
            animation.keyTimes = [0, 0.02, 0.98, 1]
            animation.duration = overlapEnd - overlapStart
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + (overlapStart - projectRangeStartSec)
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            layer.add(animation, forKey: "TakeLayerLyricVisibility")
            parentLayer.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func textLayer(
        text: String,
        frame: CGRect,
        fontSize: CGFloat,
        alignment: CATextLayerAlignmentMode
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.fontSize = fontSize
        layer.alignmentMode = alignment
        layer.foregroundColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.contentsScale = 2
        layer.isWrapped = true
        return layer
    }

    private static func makeOutputURL() throws -> URL {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ShortVideoExportError.cannotSaveOutput
        }
        return directory.appendingPathComponent("TakeLayer-Short-\(UUID().uuidString).mp4")
    }
}
