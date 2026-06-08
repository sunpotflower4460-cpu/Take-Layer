import Foundation

struct ExportValidationResult {
    var items: [ExportValidationItem]

    var isReady: Bool {
        items.allSatisfy(\.isValid)
    }
}

struct ExportValidationItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var isValid: Bool
}

enum ExportValidationService {
    static func validate(project: ProjectDraft) -> ExportValidationResult {
        let activeVideo = project.activeVideo
        let audio = project.importedMasterAudio
        let selectedRawStartSec = project.selectedRawStartSec
        let selectedRawEndSec = project.selectedRawEndSec
        let outputDurationSec = outputDuration(project: project)

        let items = [
            ExportValidationItem(
                title: "Project title",
                message: project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "タイトルを入力してください。" : "OK",
                isValid: !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            ExportValidationItem(
                title: "Video",
                message: activeVideo == nil ? "動画をインポートまたは録画してください。" : "OK",
                isValid: activeVideo != nil
            ),
            ExportValidationItem(
                title: "Master WAV",
                message: audio == nil ? "完成WAVをインポートしてください。" : "OK",
                isValid: audio != nil
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
                title: "Output duration",
                message: outputDurationSec > 0 ? TimeFormatting.seconds(outputDurationSec) : "書き出しdurationが0以下です。",
                isValid: outputDurationSec > 0
            )
        ]

        return ExportValidationResult(items: items)
    }

    static func outputDuration(project: ProjectDraft) -> Double {
        guard let selectedRawStartSec = project.selectedRawStartSec,
              let selectedRawEndSec = project.selectedRawEndSec,
              let audio = project.importedMasterAudio,
              let songStartAudioSec = project.songStartAudioSec,
              selectedRawEndSec > selectedRawStartSec,
              audio.durationSec > songStartAudioSec else {
            return 0
        }
        return min(selectedRawEndSec - selectedRawStartSec, audio.durationSec - songStartAudioSec)
    }

    private static func validateTime(_ value: Double?, duration: Double?) -> Bool {
        guard let value, let duration else { return false }
        return value >= 0 && value < duration
    }

    private static func validateTrim(start: Double?, end: Double?, videoDurationSec: Double?) -> Bool {
        guard let start, let end, let videoDurationSec else { return false }
        return start >= 0 && end <= videoDurationSec && start < end
    }
}
