import AVFoundation
import Combine
import Foundation

@MainActor
final class MVPAlphaViewModel: ObservableObject {
    @Published var project: ProjectDraft
    @Published var videoPreviewTimeSec: Double = 0
    @Published var audioPreviewTimeSec: Double = 0
    @Published var isImportingVideo = false
    @Published var isImportingAudio = false
    @Published var isExporting = false
    @Published var exportResult: ExportResult?
    @Published var errorMessage: String?

    init() {
        do {
            self.project = try ProjectStore.loadMostRecent() ?? ProjectDraft(title: "New TakeLayer Project")
            self.errorMessage = nil
        } catch {
            self.project = ProjectDraft(title: "New TakeLayer Project")
            self.errorMessage = error.localizedDescription
        }
    }

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
        touchAndPersist()
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
                touchAndPersist()
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
        touchAndPersist()
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
                updateDefaultTrimIfPossible()
                touchAndPersist()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingAudio = false
        }
    }

    func setVideoSongStart() {
        guard let video = project.activeVideo else { return }
        project.songStartRawSec = min(max(videoPreviewTimeSec, 0), max(0, video.durationSec - 0.01))
        updateDefaultTrimIfPossible()
        touchAndPersist()
    }

    func setAudioSongStart() {
        guard let audio = project.importedMasterAudio else { return }
        project.songStartAudioSec = min(max(audioPreviewTimeSec, 0), max(0, audio.durationSec - 0.01))
        updateDefaultTrimIfPossible()
        touchAndPersist()
    }

    func updateSelectedRawStart(_ value: Double) {
        guard let video = project.activeVideo else { return }
        let clamped = min(max(value, 0), video.durationSec)
        project.selectedRawStartSec = clamped
        if let end = project.selectedRawEndSec, end <= clamped {
            project.selectedRawEndSec = min(video.durationSec, clamped + 0.1)
        }
        touchAndPersist()
    }

    func updateSelectedRawEnd(_ value: Double) {
        guard let video = project.activeVideo else { return }
        project.selectedRawEndSec = min(max(value, 0), video.durationSec)
        touchAndPersist()
    }

    func adjustOffset(ms delta: Double) {
        project.offsetMs += delta
        touchAndPersist()
    }

    func resetOffset() {
        project.offsetMs = 0
        touchAndPersist()
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
    }

    private func updateDefaultTrimIfPossible() {
        guard let video = project.activeVideo,
              let songStartRawSec = project.songStartRawSec else {
            return
        }
        let effectiveDuration = masterAudioEffectiveDuration ?? max(0, video.durationSec - songStartRawSec)
        project.selectedRawStartSec = songStartRawSec
        project.selectedRawEndSec = min(video.durationSec, songStartRawSec + effectiveDuration)
    }

    private func touchAndPersist() {
        project.updatedAt = Date()
        do {
            try ProjectStore.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
