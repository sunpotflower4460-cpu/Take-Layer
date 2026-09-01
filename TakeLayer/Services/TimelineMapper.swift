import Foundation

enum TimelineMapperError: LocalizedError, Equatable {
    case missingVideo
    case missingMasterAudio
    case invalidVideoSongStart
    case invalidAudioSongStart
    case invalidTrimRange
    case invalidOffset
    case noAudioOverlap

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            return "動画が読み込まれていません。"
        case .missingMasterAudio:
            return "完成WAVが読み込まれていません。"
        case .invalidVideoSongStart:
            return "songStartRawSecが動画duration内にありません。"
        case .invalidAudioSongStart:
            return "songStartAudioSecがWAV duration内にありません。"
        case .invalidTrimRange:
            return "selectedRawStartSec / selectedRawEndSec が不正です。"
        case .invalidOffset:
            return "offsetMsが不正です。"
        case .noAudioOverlap:
            return "選択範囲と完成WAVに重なる音声区間がありません。"
        }
    }
}

/// A deterministic mapping from one selected raw-video window to the shared
/// TakeLayer project timeline and the completed-WAV source timeline.
///
/// `offsetMs > 0` means the completed WAV is delayed relative to video.
/// `offsetMs < 0` means the completed WAV is advanced relative to video.
struct TimelineMapping: Equatable {
    let videoSourceStartSec: Double
    let projectTimelineStartSec: Double
    let audioSourceStartSec: Double
    let audioInsertionTimeSec: Double
    let audioInsertDurationSec: Double
    let outputDurationSec: Double
}

enum TimelineMapper {
    static func projectTimelineSec(videoRawSec: Double, songStartRawSec: Double) -> Double {
        videoRawSec - songStartRawSec
    }

    static func videoRawSec(projectTimelineSec: Double, songStartRawSec: Double) -> Double {
        songStartRawSec + projectTimelineSec
    }

    static func remapProjectTimelineSec(
        _ projectTimelineSec: Double,
        fromSongStartRawSec oldSongStartRawSec: Double,
        toSongStartRawSec newSongStartRawSec: Double
    ) -> Double {
        let rawSec = videoRawSec(
            projectTimelineSec: projectTimelineSec,
            songStartRawSec: oldSongStartRawSec
        )
        return TimelineMapper.projectTimelineSec(
            videoRawSec: rawSec,
            songStartRawSec: newSongStartRawSec
        )
    }

    static func masterAudioSec(
        projectTimelineSec: Double,
        songStartAudioSec: Double,
        offsetMs: Double
    ) -> Double {
        // Positive offset delays program audio, therefore an earlier master
        // sample must be placed at the same output time.
        songStartAudioSec + projectTimelineSec - (offsetMs / 1_000.0)
    }

    /// Maps an arbitrary Project Timeline window through the same authoritative
    /// synchronization path used by the normal renderer. Short-form editors and
    /// future AI plans must call this instead of recreating sync math.
    static func makeMapping(
        project: ProjectDraft,
        projectTimelineStartSec: Double,
        durationSec: Double
    ) throws -> TimelineMapping {
        guard projectTimelineStartSec.isFinite,
              durationSec.isFinite,
              durationSec > 0,
              let songStartRawSec = project.songStartRawSec else {
            throw TimelineMapperError.invalidTrimRange
        }

        var scopedProject = project
        let rawStartSec = videoRawSec(
            projectTimelineSec: projectTimelineStartSec,
            songStartRawSec: songStartRawSec
        )
        scopedProject.selectedRawStartSec = rawStartSec
        scopedProject.selectedRawEndSec = rawStartSec + durationSec
        return try makeMapping(project: scopedProject)
    }

    static func makeMapping(project: ProjectDraft) throws -> TimelineMapping {
        guard let video = project.activeVideo else {
            throw TimelineMapperError.missingVideo
        }
        guard let audio = project.importedMasterAudio else {
            throw TimelineMapperError.missingMasterAudio
        }
        guard let songStartRawSec = project.songStartRawSec,
              songStartRawSec.isFinite,
              songStartRawSec >= 0,
              songStartRawSec < video.durationSec else {
            throw TimelineMapperError.invalidVideoSongStart
        }
        guard let songStartAudioSec = project.songStartAudioSec,
              songStartAudioSec.isFinite,
              songStartAudioSec >= 0,
              songStartAudioSec < audio.durationSec else {
            throw TimelineMapperError.invalidAudioSongStart
        }
        guard let selectedRawStartSec = project.selectedRawStartSec,
              let selectedRawEndSec = project.selectedRawEndSec,
              selectedRawStartSec.isFinite,
              selectedRawEndSec.isFinite,
              selectedRawStartSec >= 0,
              selectedRawEndSec <= video.durationSec,
              selectedRawEndSec > selectedRawStartSec else {
            throw TimelineMapperError.invalidTrimRange
        }
        guard project.offsetMs.isFinite else {
            throw TimelineMapperError.invalidOffset
        }

        let selectedVideoDurationSec = selectedRawEndSec - selectedRawStartSec
        let timelineStartSec = projectTimelineSec(
            videoRawSec: selectedRawStartSec,
            songStartRawSec: songStartRawSec
        )
        let desiredAudioStartSec = masterAudioSec(
            projectTimelineSec: timelineStartSec,
            songStartAudioSec: songStartAudioSec,
            offsetMs: project.offsetMs
        )

        // If the mathematically correct WAV position is before byte/sample zero,
        // preserve sync by inserting the WAV later rather than clamping time and
        // silently shifting the performance.
        let audioInsertionTimeSec = max(0, -desiredAudioStartSec)
        let audioSourceStartSec = max(0, desiredAudioStartSec)
        let availableAudioDurationSec = max(0, audio.durationSec - audioSourceStartSec)
        let maxCoveredOutputDurationSec = audioInsertionTimeSec + availableAudioDurationSec
        let outputDurationSec = min(selectedVideoDurationSec, maxCoveredOutputDurationSec)
        let audioInsertDurationSec = min(
            availableAudioDurationSec,
            max(0, outputDurationSec - audioInsertionTimeSec)
        )

        guard outputDurationSec > 0, audioInsertDurationSec > 0 else {
            throw TimelineMapperError.noAudioOverlap
        }

        return TimelineMapping(
            videoSourceStartSec: selectedRawStartSec,
            projectTimelineStartSec: timelineStartSec,
            audioSourceStartSec: audioSourceStartSec,
            audioInsertionTimeSec: audioInsertionTimeSec,
            audioInsertDurationSec: audioInsertDurationSec,
            outputDurationSec: outputDurationSec
        )
    }
}
