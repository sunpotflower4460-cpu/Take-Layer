import Foundation

/// Headless render request. A thin, serialisable projection of the existing
/// `ShortEditDraft` + the minimum project facts `TimelineMapper` needs.
///
/// It deliberately carries NO new editing semantics: range / zoom / focus /
/// title / lyric cues are exactly the `ShortEditDraft` fields, and all sync
/// maths still happens in `TimelineMapper.makeMapping` (called by the renderer).
///
/// `localPath` values are produced on the Mac by the Runner after it resolved a
/// `runnerAssetId`; they never travel to Artist OS servers.
struct RenderEditPlanRequest: Codable, Equatable {
    static let supportedSchemaVersion = 1

    struct PlanSnapshot: Codable, Equatable {
        var planId: String
        var planVersion: Int
        var planHash: String
    }

    struct Cue: Codable, Equatable {
        var startProjectSec: Double
        var endProjectSec: Double
        var text: String
    }

    struct Crop: Codable, Equatable {
        var zoom: Double
        var focusX: Double
        var focusY: Double
    }

    struct Edit: Codable, Equatable {
        var rangeStartProjectSec: Double
        var rangeEndProjectSec: Double
        var titleText: String
        var crop: Crop
        var lyricCues: [Cue]
        var cuePlacement: String? = nil   // "bottom" (default) | "upper-middle"
    }

    struct Source: Codable, Equatable {
        var runnerAssetId: String
        var localPath: String
        /// Lower-case hex SHA-256 of the file. When present the renderer refuses on mismatch.
        var sha256: String?
        var durationSec: Double
        var width: Int?
        var height: Int?
        var hasAudio: Bool?
        var sampleRate: Double?
        var channelCount: Int?
    }

    struct Timeline: Codable, Equatable {
        var songStartRawSec: Double
        var songStartAudioSec: Double
        var offsetMs: Double
    }

    var schemaVersion: Int
    var requestKey: String
    var plan: PlanSnapshot
    var edit: Edit
    var video: Source
    var masterAudio: Source
    var timeline: Timeline
    var outputPath: String
}

extension RenderEditPlanRequest.Edit {
    init(draft: ShortEditDraft) {
        self.init(
            rangeStartProjectSec: draft.rangeStartProjectSec,
            rangeEndProjectSec: draft.rangeEndProjectSec,
            titleText: draft.titleText,
            crop: .init(zoom: draft.crop.zoom, focusX: draft.crop.focusX, focusY: draft.crop.focusY),
            lyricCues: draft.lyricCues.map { .init(startProjectSec: $0.startProjectSec, endProjectSec: $0.endProjectSec, text: $0.text) },
            cuePlacement: draft.cuePlacement?.rawValue
        )
    }

    var shortEditDraft: ShortEditDraft {
        ShortEditDraft(
            rangeStartProjectSec: rangeStartProjectSec,
            rangeEndProjectSec: rangeEndProjectSec,
            titleText: titleText,
            crop: ShortCropPlan(zoom: crop.zoom, focusX: crop.focusX, focusY: crop.focusY),
            lyricCues: lyricCues.map { ShortLyricCue(startProjectSec: $0.startProjectSec, endProjectSec: $0.endProjectSec, text: $0.text) },
            cuePlacement: cuePlacement.flatMap(CuePlacement.init(rawValue:))
        )
    }
}

enum RenderEditPlanRequestError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case missingField(String)
    case notFinite(String)
    case relativePath(String)
    case invalidHash(String)
    case unknownCuePlacement(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let v): return "unsupported request schemaVersion \(v)"
        case .missingField(let f): return "missing or empty field: \(f)"
        case .notFinite(let f): return "non-finite number: \(f)"
        case .relativePath(let f): return "path must be absolute: \(f)"
        case .invalidHash(let f): return "sha256 must be 64 lower-case hex chars: \(f)"
        case .unknownCuePlacement(let v): return "unknown edit.cuePlacement '\(v)' (expected bottom or upper-middle)"
        }
    }
}

extension RenderEditPlanRequest {
    /// Structural validation only (no file access). Edit semantics are validated by
    /// the existing `ShortVideoExportService` / `TimelineMapper` guards at render time.
    func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else { throw RenderEditPlanRequestError.unsupportedSchema(schemaVersion) }
        for (name, value) in [("requestKey", requestKey), ("plan.planId", plan.planId), ("plan.planHash", plan.planHash),
                              ("video.runnerAssetId", video.runnerAssetId), ("masterAudio.runnerAssetId", masterAudio.runnerAssetId)] where value.isEmpty {
            throw RenderEditPlanRequestError.missingField(name)
        }
        let numbers: [(String, Double)] = [
            ("edit.rangeStartProjectSec", edit.rangeStartProjectSec), ("edit.rangeEndProjectSec", edit.rangeEndProjectSec),
            ("edit.crop.zoom", edit.crop.zoom), ("edit.crop.focusX", edit.crop.focusX), ("edit.crop.focusY", edit.crop.focusY),
            ("video.durationSec", video.durationSec), ("masterAudio.durationSec", masterAudio.durationSec),
            ("timeline.songStartRawSec", timeline.songStartRawSec), ("timeline.songStartAudioSec", timeline.songStartAudioSec),
            ("timeline.offsetMs", timeline.offsetMs),
        ]
        for (name, value) in numbers where !value.isFinite { throw RenderEditPlanRequestError.notFinite(name) }
        // Fail closed: an unknown placement must not silently fall back to the bottom position.
        if let placement = edit.cuePlacement, CuePlacement(rawValue: placement) == nil { throw RenderEditPlanRequestError.unknownCuePlacement(placement) }
        for (name, path) in [("video.localPath", video.localPath), ("masterAudio.localPath", masterAudio.localPath), ("outputPath", outputPath)] {
            guard !path.isEmpty else { throw RenderEditPlanRequestError.missingField(name) }
            guard path.hasPrefix("/") else { throw RenderEditPlanRequestError.relativePath(name) }
        }
        for (name, hash) in [("video.sha256", video.sha256), ("masterAudio.sha256", masterAudio.sha256)] {
            guard let hash else { continue }
            let ok = hash.count == 64 && hash.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
            guard ok else { throw RenderEditPlanRequestError.invalidHash(name) }
        }
    }

    /// Builds the `ProjectDraft` the existing renderer/mapper already understand.
    func makeProject() -> ProjectDraft {
        var project = ProjectDraft(title: "headless-\(requestKey)")
        let videoWidth = video.width
        let videoHeight = video.height
        let orientation: MediaOrientation
        if let w = videoWidth, let h = videoHeight { orientation = w > h ? .landscape : (w < h ? .portrait : .square) } else { orientation = .unknown }
        project.importedVideo = ImportedVideo(
            url: URL(fileURLWithPath: video.localPath), durationSec: video.durationSec, width: videoWidth, height: videoHeight,
            orientation: orientation, fileType: nil, hasAudio: video.hasAudio ?? false, fileSizeBytes: nil
        )
        project.importedMasterAudio = ImportedMasterAudio(
            url: URL(fileURLWithPath: masterAudio.localPath), durationSec: masterAudio.durationSec,
            sampleRate: masterAudio.sampleRate, channelCount: masterAudio.channelCount, fileType: nil, fileSizeBytes: nil
        )
        project.songStartRawSec = timeline.songStartRawSec
        project.songStartAudioSec = timeline.songStartAudioSec
        project.offsetMs = timeline.offsetMs
        project.shortEditDraft = edit.shortEditDraft
        return project
    }
}
