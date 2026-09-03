import Foundation

struct ExportValidationResult {
    var items: [ExportValidationItem]

    var isReady: Bool {
        items.allSatisfy(\.isValid)
    }
}

struct ExportValidationItem: Identifiable {
    var title: String
    var message: String
    var isValid: Bool

    var id: String { title }
}

enum ExportValidationService {
    static func validate(project: ProjectDraft) -> ExportValidationResult {
        let activeVideo = project.activeVideo
        let audio = project.importedMasterAudio
        let videoFileExists = activeVideo.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false
        let audioFileExists = audio.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false
        let selectedRawStartSec = project.selectedRawStartSec
        let selectedRawEndSec = project.selectedRawEndSec
        let mappingResult = Result<TimelineMapping, Error> {
            try TimelineMapper.makeMapping(project: project)
        }

        let mappingMessage: String
        let mappingIsValid: Bool
        let outputDurationSec: Double
        switch mappingResult {
        case .success(let mapping):
            mappingMessage = "OK"
            mappingIsValid = true
            outputDurationSec = mapping.outputDurationSec
        case .failure(let error):
            mappingMessage = error.localizedDescription
            mappingIsValid = false
            outputDurationSec = 0
        }

        let videoMessage: String
        if activeVideo == nil {
            videoMessage = "動画をインポートまたは録画してください。"
        } else if !videoFileExists {
            videoMessage = "保存済み動画ファイルが見つかりません。再インポートまたは再録画してください。"
        } else {
            videoMessage = "OK"
        }

        let audioMessage: String
        if audio == nil {
            audioMessage = "完成WAVをインポートしてください。"
        } else if !audioFileExists {
            audioMessage = "保存済み完成WAVファイルが見つかりません。再インポートしてください。"
        } else {
            audioMessage = "OK"
        }

        let items = [
            ExportValidationItem(
                title: "Project title",
                message: project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "タイトルを入力してください。" : "OK",
                isValid: !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            ExportValidationItem(
                title: "Video",
                message: videoMessage,
                isValid: activeVideo != nil && videoFileExists
            ),
            ExportValidationItem(
                title: "Master WAV",
                message: audioMessage,
                isValid: audio != nil && audioFileExists
            ),
            ExportValidationItem(
                title: "Video song start",
                message: validateTime(project.songStartRawSec, duration: activeVideo?.durationSec) ? "OK" : "songStartRawSecを動画duration内に設定してください。",
                isValid: validateTime(project.songStartRawSec, duration: activeVideo?.durationSec)
            ),
            ExportValidationItem(
                title: "WAV song start",
                message: validateTime(project.songStartAudioSec, duration: audio?.durationSec) ? "OK" : "songStartAudioSecをWAV duration内に設定してください。",
                isValid: validateTime(project.songStartAudioSec, duration: audio?.durationSec)
            ),
            ExportValidationItem(
                title: "Trim start",
                message: selectedRawStartSec == nil ? "selectedRawStartSecを設定してください。" : "OK",
                isValid: selectedRawStartSec != nil
            ),
            ExportValidationItem(
                title: "Trim end",
                message: selectedRawEndSec == nil ? "selectedRawEndSecを設定してください。" : "OK",
                isValid: selectedRawEndSec != nil
            ),
            ExportValidationItem(
                title: "Trim range",
                message: validateTrim(start: selectedRawStartSec, end: selectedRawEndSec, videoDurationSec: activeVideo?.durationSec) ? "OK" : "start < end かつ動画duration内にしてください。",
                isValid: validateTrim(start: selectedRawStartSec, end: selectedRawEndSec, videoDurationSec: activeVideo?.durationSec)
            ),
            ExportValidationItem(
                title: "Timeline mapping",
                message: mappingMessage,
                isValid: mappingIsValid
            ),
            ExportValidationItem(
                title: "Output duration",
                message: outputDurationSec > 0 ? TimeFormatting.seconds(outputDurationSec) : "書き出しdurationが0以下です。",
                isValid: outputDurationSec > 0
            )
        ]

        return ExportValidationResult(items: items)
    }

    static func outputDuration(project: ProjectDraft) -> Double {
        (try? TimelineMapper.makeMapping(project: project).outputDurationSec) ?? 0
    }

    private static func validateTime(_ value: Double?, duration: Double?) -> Bool {
        guard let value, let duration else { return false }
        return value.isFinite && value >= 0 && value < duration
    }

    private static func validateTrim(start: Double?, end: Double?, videoDurationSec: Double?) -> Bool {
        guard let start, let end, let videoDurationSec else { return false }
        return start.isFinite && end.isFinite && start >= 0 && end <= videoDurationSec && start < end
    }
}
