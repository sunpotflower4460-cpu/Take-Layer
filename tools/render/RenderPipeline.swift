import AVFoundation
import Foundation

/// Headless RENDER_EDIT_PLAN pipeline. Uses the SAME `TimelineMapper` and
/// `ShortVideoExportService` as the iOS app: no sync or crop maths lives here.
enum RenderPipeline {
    static func failure(_ request: RenderEditPlanRequest?, key: String, code: String, _ message: String) -> RenderResult {
        RenderResult(requestKey: key, status: "failed", errorCode: code, errorMessage: message)
    }

    static func run(_ request: RenderEditPlanRequest) async -> RenderResult {
        let key = request.requestKey
        do { try request.validate() } catch { return failure(request, key: key, code: "INVALID_REQUEST", error.localizedDescription) }

        let fm = FileManager.default
        guard fm.fileExists(atPath: request.video.localPath) else { return failure(request, key: key, code: "SOURCE_MISSING", "video source not found") }
        guard fm.fileExists(atPath: request.masterAudio.localPath) else { return failure(request, key: key, code: "SOURCE_MISSING", "master audio source not found") }
        if fm.fileExists(atPath: request.outputPath) { return failure(request, key: key, code: "OUTPUT_EXISTS", "refusing to overwrite an existing output") }

        var hashes: [String: String] = [:]
        do {
            for (name, source) in [("video", request.video), ("masterAudio", request.masterAudio)] {
                let actual = try Hashing.sha256Hex(of: URL(fileURLWithPath: source.localPath))
                if let expected = source.sha256, expected != actual {
                    return failure(request, key: key, code: "SOURCE_HASH_MISMATCH", "\(name) hash does not match the request")
                }
                hashes[name] = actual
            }
        } catch { return failure(request, key: key, code: "SOURCE_MISSING", "cannot read source: \(error.localizedDescription)") }

        // The declared durations feed TimelineMapper; refuse if the real files disagree.
        do {
            for (name, source) in [("video", request.video), ("masterAudio", request.masterAudio)] {
                let actual = try await RenderValidator.probeDuration(URL(fileURLWithPath: source.localPath))
                if abs(actual - source.durationSec) > 0.1 {
                    return failure(request, key: key, code: "SOURCE_FACTS_MISMATCH", "\(name) duration \(actual)s differs from the declared \(source.durationSec)s")
                }
            }
        } catch { return failure(request, key: key, code: "SOURCE_UNREADABLE", "cannot read source media: \(error.localizedDescription)") }

        let project = request.makeProject()
        let draft = request.edit.shortEditDraft
        let mapping: TimelineMapping
        do {
            mapping = try TimelineMapper.makeMapping(project: project, projectTimelineStartSec: draft.rangeStartProjectSec, durationSec: draft.durationSec)
        } catch { return failure(request, key: key, code: "INVALID_REQUEST", "timeline mapping rejected: \(error.localizedDescription)") }

        let partial = partialURL(forOutput: request.outputPath)
        try? fm.removeItem(at: partial)
        do {
            _ = try await ShortVideoExportService.export(project: project, draft: draft, destination: partial)
        } catch {
            try? fm.removeItem(at: partial)
            return failure(request, key: key, code: "RENDER_FAILED", error.localizedDescription)
        }

        var result = RenderResult(requestKey: key, status: "completed")
        do {
            let facts = try await RenderValidator.inspect(partial)
            let checks = RenderValidator.checks(facts: facts, expectedDurationSec: mapping.outputDurationSec, expectedSize: ShortRenderGeometryBuilder.renderSize)
            result.checks = checks
            result.durationSec = facts.durationSec
            result.width = facts.width
            result.height = facts.height
            result.fps = facts.fps
            result.hasVideoTrack = facts.hasVideo
            result.hasAudioTrack = facts.hasAudio
            result.sizeBytes = facts.sizeBytes
            result.sourceHashes = hashes
            // Provenance by construction: ShortVideoExportService inserts only the master-WAV audio track.
            result.audioSource = "master_wav"
            if let bad = checks.first(where: { !$0.ok }) {
                try? fm.removeItem(at: partial)
                result.status = "failed"
                result.errorCode = "RENDER_QUALITY_FAILED"
                result.errorMessage = "\(bad.name): \(bad.detail)"
                return result
            }
            let hash = try Hashing.sha256Hex(of: partial)
            let final = URL(fileURLWithPath: request.outputPath)
            try fm.moveItem(at: partial, to: final)
            let marker = RenderCommitMarker(
                requestKey: key, contentHash: hash, sizeBytes: facts.sizeBytes, durationSec: facts.durationSec,
                width: facts.width, height: facts.height, fps: facts.fps, renderer: result.renderer,
                rendererVersion: result.rendererVersion, audioSource: "master_wav", checks: checks,
                committedAt: ISO8601DateFormatter().string(from: Date())
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(marker).write(to: markerURL(forOutput: request.outputPath), options: .atomic)
            result.outputPath = request.outputPath
            result.contentHash = hash
            return result
        } catch {
            try? fm.removeItem(at: partial)
            result.status = "failed"
            result.errorCode = "RENDER_QUALITY_FAILED"
            result.errorMessage = "post-render validation error: \(error.localizedDescription)"
            return result
        }
    }

    /// Generates synthetic media and renders it. Proves AVFoundation export works in this process.
    static func selfTest(workDir: URL) async -> RenderResult {
        let key = "self-test-\(UUID().uuidString.prefix(8))"
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let videoURL = workDir.appendingPathComponent("selftest-video.mp4")
            let wavURL = workDir.appendingPathComponent("selftest-master.wav")
            try await SelfTestMedia.makeVideo(at: videoURL, seconds: 8, width: 640, height: 360, fps: 30)
            try SelfTestMedia.makeWav(at: wavURL, seconds: 10)
            let request = RenderEditPlanRequest(
                schemaVersion: 1, requestKey: key,
                plan: .init(planId: "self-test-plan", planVersion: 1, planHash: "self-test"),
                edit: .init(draft: ShortEditDraft(
                    rangeStartProjectSec: 0, rangeEndProjectSec: 4, titleText: "Self Test",
                    crop: ShortCropPlan(zoom: 1.5, focusX: 0.5, focusY: 0.5),
                    lyricCues: [ShortLyricCue(startProjectSec: 0.5, endProjectSec: 2.5, text: "テスト")]
                )),
                video: .init(runnerAssetId: "self-test-video", localPath: videoURL.path, sha256: try Hashing.sha256Hex(of: videoURL),
                             durationSec: 8, width: 640, height: 360, hasAudio: false, sampleRate: nil, channelCount: nil),
                masterAudio: .init(runnerAssetId: "self-test-wav", localPath: wavURL.path, sha256: try Hashing.sha256Hex(of: wavURL),
                                   durationSec: 10, width: nil, height: nil, hasAudio: true, sampleRate: 48_000, channelCount: 1),
                timeline: .init(songStartRawSec: 1, songStartAudioSec: 0, offsetMs: 0),
                outputPath: workDir.appendingPathComponent("selftest-output-\(key).mp4").path
            )
            var result = await run(request)
            // The self-test edit has a title, so text that is missing from the pixels is a render failure.
            if result.status == "completed", let output = result.outputPath {
                let spread = try await RenderValidator.titleBandContrast(URL(fileURLWithPath: output), atSec: 1.0)
                let ok = spread >= 60
                result.checks.append(RenderCheck(name: "title_text_rendered", ok: ok, detail: "title band luminance spread \(spread) (>= 60 when text is burned in)"))
                if !ok {
                    result.status = "failed"
                    result.errorCode = "RENDER_QUALITY_FAILED"
                    result.errorMessage = "title_text_rendered: the title text is not present in the rendered frames"
                }
            }
            return result
        } catch {
            return failure(nil, key: key, code: "SELF_TEST_SETUP_FAILED", error.localizedDescription)
        }
    }
}
