import AVFoundation
import Combine
import Foundation

@MainActor
final class ImportExportPoCViewModel: ObservableObject {
    @Published var project = ProjectDraft()
    @Published var videoPreviewTimeSec: Double = 0
    @Published var audioPreviewTimeSec: Double = 0
    @Published var isImportingVideo = false
    @Published var isImportingAudio = false
    @Published var isExporting = false
    @Published var exportResult: ExportResult?
    @Published var errorMessage: String?

    var canExport: Bool {
        project.importedVideo != nil &&
        project.importedMasterAudio != nil &&
        project.songStartRawSec != nil &&
        project.songStartAudioSec != nil &&
        project.selectedRawStartSec != nil &&
        project.selectedRawEndSec != nil &&
        !isExporting
    }

    var masterAudioEffectiveDuration: Double? {
        guard let audio = project.importedMasterAudio,
              let songStartAudioSec = project.songStartAudioSec else {
            return nil
        }
        return max(0, audio.durationSec - songStartAudioSec)
    }

    var selectedDuration: Double? {
        guard let start = project.selectedRawStartSec,
              let end = project.selectedRawEndSec,
              end > start else {
            return nil
        }
        return end - start
    }

    var durationDifferenceFromProject: Double? {
        guard let selectedDuration,
              let masterAudioEffectiveDuration else {
            return nil
        }
        return selectedDuration - masterAudioEffectiveDuration
    }

    func importVideo(from pickedURL: URL) {
        isImportingVideo = true
        errorMessage = nil
        Task {
            do {
                let storedURL = try MediaImportStore.copyIntoImports(pickedURL)
                let video = try await MediaInfoReader.readVideo(from: storedURL)
                project.importedVideo = video
                videoPreviewTimeSec = 0
                project.songStartRawSec = nil
                project.selectedRawStartSec = nil
                project.selectedRawEndSec = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingVideo = false
        }
    }

    func useRecordedTake(_ take: RecordedTake) {
        errorMessage = nil
        guard let video = take.importedVideo else {
            errorMessage = "録画動画のdurationを読み取れませんでした。"
            return
        }
        project.importedVideo = video
        videoPreviewTimeSec = 0
        project.songStartRawSec = nil
        project.selectedRawStartSec = nil
        project.selectedRawEndSec = nil
    }

    func importMasterAudio(from pickedURL: URL) {
        isImportingAudio = true
        errorMessage = nil
        Task {
            do {
                let storedURL = try MediaImportStore.copyIntoImports(pickedURL)
                let audio = try await MediaInfoReader.readMasterAudio(from: storedURL)
                project.importedMasterAudio = audio
                audioPreviewTimeSec = 0
                project.songStartAudioSec = nil
                updateDefaultTrimIfPossible()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingAudio = false
        }
    }

    func setVideoSongStart() {
        guard let video = project.importedVideo else { return }
        let value = min(max(videoPreviewTimeSec, 0), max(0, video.durationSec - 0.01))
        project.songStartRawSec = value
        updateDefaultTrimIfPossible()
    }

    func setAudioSongStart() {
        guard let audio = project.importedMasterAudio else { return }
        let value = min(max(audioPreviewTimeSec, 0), max(0, audio.durationSec - 0.01))
        project.songStartAudioSec = value
        updateDefaultTrimIfPossible()
    }

    func updateSelectedRawStart(_ value: Double) {
        guard let video = project.importedVideo else { return }
        let clamped = min(max(value, 0), video.durationSec)
        project.selectedRawStartSec = clamped
        if let end = project.selectedRawEndSec, end <= clamped {
            project.selectedRawEndSec = min(video.durationSec, clamped + 0.1)
        }
    }

    func updateSelectedRawEnd(_ value: Double) {
        guard let video = project.importedVideo else { return }
        project.selectedRawEndSec = min(max(value, 0), video.durationSec)
    }

    func export() {
        guard canExport else { return }
        isExporting = true
        exportResult = nil
        errorMessage = nil
        Task {
            do {
                exportResult = try await VideoExportService.export(project: project)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func updateDefaultTrimIfPossible() {
        guard let video = project.importedVideo,
              let songStartRawSec = project.songStartRawSec else {
            return
        }
        let effectiveDuration = masterAudioEffectiveDuration ?? max(0, video.durationSec - songStartRawSec)
        project.selectedRawStartSec = songStartRawSec
        project.selectedRawEndSec = min(video.durationSec, songStartRawSec + effectiveDuration)
    }
}
