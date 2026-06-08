import AVFoundation
import Combine
import Foundation

@MainActor
final class MVPAlphaViewModel: ObservableObject {
    @Published var project = ProjectDraft(title: "New TakeLayer Project")
    @Published var videoPreviewTimeSec: Double = 0
    @Published var audioPreviewTimeSec: Double = 0
    @Published var isImportingVideo = false
    @Published var isImportingAudio = false
    @Published var isExporting = false
    @Published var exportResult: ExportResult?
    @Published var errorMessage: String?

    var validationResult: ExportValidationResult {
        ExportValidationService.validate(project: project)
    }

    var canExport: Bool {
        validationResult.isReady && !isExporting
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

    var outputDuration: Double {
        ExportValidationService.outputDuration(project: project)
    }

    var durationDifferenceFromProject: Double? {
        guard let selectedDuration,
              let masterAudioEffectiveDuration else {
            return nil
        }
        return selectedDuration - masterAudioEffectiveDuration
    }

    func updateTitle(_ title: String) {
        project.title = title
        project.updatedAt = Date()
    }

    func importVideo(from pickedURL: URL) {
        isImportingVideo = true
        errorMessage = nil
        Task {
            do {
                let storedURL = try MediaImportStore.copyIntoImports(pickedURL)
                project.importedVideo = try await MediaInfoReader.readVideo(from: storedURL)
                project.recordedTake = nil
                resetVideoDependentState()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingVideo = false
        }
    }

    func useRecordedTake(_ take: RecordedTake) {
        errorMessage = nil
        guard take.importedVideo != nil else {
            errorMessage = "録画動画のdurationを読み取れませんでした。"
            return
        }
        project.recordedTake = take
        project.importedVideo = nil
        resetVideoDependentState()
    }

    func importMasterAudio(from pickedURL: URL) {
        isImportingAudio = true
        errorMessage = nil
        Task {
            do {
                let storedURL = try MediaImportStore.copyIntoImports(pickedURL)
                project.importedMasterAudio = try await MediaInfoReader.readMasterAudio(from: storedURL)
                audioPreviewTimeSec = 0
                project.songStartAudioSec = nil
                project.updatedAt = Date()
                updateDefaultTrimIfPossible()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingAudio = false
        }
    }

    func setVideoSongStart() {
        guard let video = project.activeVideo else { return }
        project.songStartRawSec = min(max(videoPreviewTimeSec, 0), max(0, video.durationSec - 0.01))
        project.updatedAt = Date()
        updateDefaultTrimIfPossible()
    }

    func setAudioSongStart() {
        guard let audio = project.importedMasterAudio else { return }
        project.songStartAudioSec = min(max(audioPreviewTimeSec, 0), max(0, audio.durationSec - 0.01))
        project.updatedAt = Date()
        updateDefaultTrimIfPossible()
    }

    func updateSelectedRawStart(_ value: Double) {
        guard let video = project.activeVideo else { return }
        let clamped = min(max(value, 0), video.durationSec)
        project.selectedRawStartSec = clamped
        if let end = project.selectedRawEndSec, end <= clamped {
            project.selectedRawEndSec = min(video.durationSec, clamped + 0.1)
        }
        project.updatedAt = Date()
    }

    func updateSelectedRawEnd(_ value: Double) {
        guard let video = project.activeVideo else { return }
        project.selectedRawEndSec = min(max(value, 0), video.durationSec)
        project.updatedAt = Date()
    }

    func adjustOffset(ms delta: Double) {
        project.offsetMs += delta
        project.updatedAt = Date()
    }

    func resetOffset() {
        project.offsetMs = 0
        project.updatedAt = Date()
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

    private func resetVideoDependentState() {
        videoPreviewTimeSec = 0
        project.songStartRawSec = nil
        project.selectedRawStartSec = nil
        project.selectedRawEndSec = nil
        project.updatedAt = Date()
    }

    private func updateDefaultTrimIfPossible() {
        guard let video = project.activeVideo,
              let songStartRawSec = project.songStartRawSec else {
            return
        }
        let effectiveDuration = masterAudioEffectiveDuration ?? max(0, video.durationSec - songStartRawSec)
        project.selectedRawStartSec = songStartRawSec
        project.selectedRawEndSec = min(video.durationSec, songStartRawSec + effectiveDuration)
        project.updatedAt = Date()
    }
}
