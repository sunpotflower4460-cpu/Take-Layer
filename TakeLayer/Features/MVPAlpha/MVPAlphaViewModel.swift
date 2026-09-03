import AVFoundation
import Combine
import Foundation

@MainActor
final class MVPAlphaViewModel: ObservableObject {
    @Published var project: ProjectDraft
    @Published var songMemoryLibrary: SongMemoryLibrary
    @Published var songResolverEvidenceLibrary: SongResolverEvidenceLibrary
    @Published var currentAudioEvidence: AudioEvidenceVector?
    @Published var songMatchResult: SongMatchResult?
    @Published var songResolverMessage: String?
    @Published var videoPreviewTimeSec: Double = 0
    @Published var audioPreviewTimeSec: Double = 0
    @Published var isImportingVideo = false
    @Published var isImportingAudio = false
    @Published var isAnalyzingSongEvidence = false
    @Published var isExporting = false
    @Published var exportResult: ExportResult?
    @Published var errorMessage: String?

    init() {
        let loadedProject: ProjectDraft
        var loadErrors: [String] = []
        do {
            loadedProject = try ProjectStore.loadMostRecent() ?? ProjectDraft(title: "New TakeLayer Project")
        } catch {
            loadedProject = ProjectDraft(title: "New TakeLayer Project")
            loadErrors.append(error.localizedDescription)
        }

        let loadedSongMemory: SongMemoryLibrary
        do {
            loadedSongMemory = try SongMemoryStore.load()
        } catch {
            loadedSongMemory = SongMemoryLibrary()
            loadErrors.append(error.localizedDescription)
        }

        let loadedResolverEvidence: SongResolverEvidenceLibrary
        do {
            loadedResolverEvidence = try SongResolverEvidenceStore.load()
        } catch {
            loadedResolverEvidence = SongResolverEvidenceLibrary()
            loadErrors.append(error.localizedDescription)
        }

        var normalizedProject = loadedProject
        let repairedLink = loadedSongMemory.repairedProjectLink(loadedProject.songMemoryLink)
        if repairedLink != loadedProject.songMemoryLink {
            normalizedProject.songMemoryLink = repairedLink
            normalizedProject.updatedAt = Date()
            do {
                try ProjectStore.save(normalizedProject)
            } catch {
                loadErrors.append(error.localizedDescription)
            }
        }

        self.project = normalizedProject
        self.songMemoryLibrary = loadedSongMemory
        self.songResolverEvidenceLibrary = loadedResolverEvidence
        self.currentAudioEvidence = nil
        self.songMatchResult = nil
        self.songResolverMessage = nil
        self.errorMessage = loadErrors.isEmpty ? nil : loadErrors.joined(separator: "\n")
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

    func saveConfirmedSongMemory(_ input: ConfirmedSongMemoryInput) {
        errorMessage = nil
        var updatedLibrary = songMemoryLibrary
        let link = updatedLibrary.upsertConfirmedSong(input)

        do {
            try SongMemoryStore.save(updatedLibrary)
            songMemoryLibrary = updatedLibrary
            project.songMemoryLink = link
            songMatchResult = nil
            songResolverMessage = nil
            touchAndPersist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func detachSongMemory() {
        project.songMemoryLink = nil
        songMatchResult = nil
        songResolverMessage = nil
        touchAndPersist()
    }

    func registerCurrentMasterAsArrangementEvidence() {
        guard !isAnalyzingSongEvidence else { return }
        guard let audio = project.importedMasterAudio else {
            errorMessage = "先に完成WAVを読み込んでください。"
            return
        }
        guard let arrangementID = project.songMemoryLink?.arrangementID,
              songMemoryLibrary.arrangement(for: arrangementID) != nil else {
            errorMessage = "Evidenceを登録する前にProjectをSong / Arrangementへ接続してください。"
            return
        }

        isAnalyzingSongEvidence = true
        errorMessage = nil
        songResolverMessage = "WAVからArrangement Evidenceを抽出しています…"
        let url = audio.url
        let audioID = audio.id

        Task {
            defer { isAnalyzingSongEvidence = false }
            do {
                let evidence = try await Task.detached(priority: .userInitiated) {
                    try AudioEvidenceExtractor.extract(from: url)
                }.value

                guard project.importedMasterAudio?.id == audioID,
                      project.songMemoryLink?.arrangementID == arrangementID,
                      songMemoryLibrary.arrangement(for: arrangementID) != nil else {
                    currentAudioEvidence = nil
                    songMatchResult = nil
                    songResolverMessage = "解析中にWAVまたはSong / Arrangement接続が変更されたため、古い解析結果を破棄しました。"
                    return
                }

                let originalSongMemory = songMemoryLibrary
                var updatedEvidenceLibrary = songResolverEvidenceLibrary
                let fingerprint = updatedEvidenceLibrary.register(
                    arrangementID: arrangementID,
                    evidence: evidence,
                    sourceFileName: url.lastPathComponent
                )

                var updatedSongMemory = songMemoryLibrary
                updatedSongMemory.attachFingerprintID(fingerprint.id, to: arrangementID)

                // Save the reference side first. If the evidence write fails, restore the
                // previous Song Memory snapshot so a half-registered fingerprint is not kept.
                try SongMemoryStore.save(updatedSongMemory)
                do {
                    try SongResolverEvidenceStore.save(updatedEvidenceLibrary)
                } catch {
                    try? SongMemoryStore.save(originalSongMemory)
                    throw error
                }

                currentAudioEvidence = evidence
                songResolverEvidenceLibrary = updatedEvidenceLibrary
                songMemoryLibrary = updatedSongMemory
                songMatchResult = nil
                songResolverMessage = "このWAVをArrangement Evidenceとして登録しました。"
            } catch {
                errorMessage = error.localizedDescription
                songResolverMessage = nil
            }
        }
    }

    func analyzeCurrentMasterAgainstSongMemory() {
        guard !isAnalyzingSongEvidence else { return }
        guard let audio = project.importedMasterAudio else {
            errorMessage = "先に完成WAVを読み込んでください。"
            return
        }

        isAnalyzingSongEvidence = true
        errorMessage = nil
        songResolverMessage = "既知Arrangementとの一致候補を解析しています…"
        let url = audio.url
        let audioID = audio.id

        Task {
            defer { isAnalyzingSongEvidence = false }
            do {
                let evidence = try await Task.detached(priority: .userInitiated) {
                    try AudioEvidenceExtractor.extract(from: url)
                }.value

                guard project.importedMasterAudio?.id == audioID else {
                    currentAudioEvidence = nil
                    songMatchResult = nil
                    songResolverMessage = "解析中にWAVが変更されたため、古い解析結果を破棄しました。"
                    return
                }

                let result = SongResolver.resolve(
                    query: evidence,
                    songMemory: songMemoryLibrary,
                    evidenceLibrary: songResolverEvidenceLibrary
                )
                currentAudioEvidence = evidence
                songMatchResult = result
                songResolverMessage = result.candidates.isEmpty
                    ? "比較できるArrangement Evidenceがまだありません。"
                    : "候補を\(result.candidates.count)件見つけました。接続は人間が確認した場合だけ行います。"
            } catch {
                errorMessage = error.localizedDescription
                songResolverMessage = nil
            }
        }
    }

    func confirmSongMatch(_ candidate: SongMatchCandidate) {
        guard songMatchResult?.candidates.contains(where: {
            $0.songID == candidate.songID && $0.arrangementID == candidate.arrangementID
        }) == true,
        songMemoryLibrary.identity(for: candidate.songID) != nil,
        let arrangement = songMemoryLibrary.arrangement(for: candidate.arrangementID),
        arrangement.songID == candidate.songID else {
            errorMessage = "選択したSong候補を現在のSong Memoryで確認できませんでした。"
            return
        }

        project.songMemoryLink = ProjectSongMemoryLink(
            songID: candidate.songID,
            arrangementID: candidate.arrangementID,
            linkedAt: Date()
        )
        songMatchResult = SongMatchResult(
            candidates: songMatchResult?.candidates ?? [],
            resolvedSongID: candidate.songID,
            resolvedArrangementID: candidate.arrangementID,
            needsUserConfirmation: false
        )
        songResolverMessage = "確認済み候補をProjectへ接続しました。"
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
                touchAndPersist(invalidateExport: true)
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
        touchAndPersist(invalidateExport: true)
    }

    func importMasterAudio(from pickedURL: URL) {
        isImportingAudio = true
        errorMessage = nil
        let isReplacingMasterAudio = project.importedMasterAudio != nil
        Task {
            do {
                let storedURL = try MediaImportStore.copyIntoImports(pickedURL)
                project.importedMasterAudio = try await MediaInfoReader.readMasterAudio(from: storedURL)
                audioPreviewTimeSec = 0
                project.songStartAudioSec = nil
                project.shortEditDraft = nil
                currentAudioEvidence = nil
                songMatchResult = nil
                songResolverMessage = nil
                if isReplacingMasterAudio {
                    // A replacement WAV may represent a different song or arrangement.
                    // Do not carry an old identity forward without explicit confirmation.
                    project.songMemoryLink = nil
                }
                updateDefaultTrimIfPossible()
                touchAndPersist(invalidateExport: true)
            } catch {
                errorMessage = error.localizedDescription
            }
            isImportingAudio = false
        }
    }

    func setVideoSongStart() {
        guard let video = project.activeVideo else { return }
        let newSongStartRawSec = min(max(videoPreviewTimeSec, 0), max(0, video.durationSec - 0.01))
        let shouldPreserveShortTrim = project.shortEditDraft != nil &&
            project.selectedRawStartSec != nil &&
            project.selectedRawEndSec != nil

        if let oldSongStartRawSec = project.songStartRawSec,
           oldSongStartRawSec != newSongStartRawSec {
            remapShortDraftForVideoSongStartChange(
                from: oldSongStartRawSec,
                to: newSongStartRawSec
            )
        }

        project.songStartRawSec = newSongStartRawSec
        if !shouldPreserveShortTrim {
            updateDefaultTrimIfPossible()
        }
        touchAndPersist(invalidateExport: true)
    }

    func setAudioSongStart() {
        guard let audio = project.importedMasterAudio else { return }
        let shouldPreserveShortTrim = project.shortEditDraft != nil &&
            project.selectedRawStartSec != nil &&
            project.selectedRawEndSec != nil
        project.songStartAudioSec = min(max(audioPreviewTimeSec, 0), max(0, audio.durationSec - 0.01))
        if !shouldPreserveShortTrim {
            updateDefaultTrimIfPossible()
        }
        touchAndPersist(invalidateExport: true)
    }

    func updateSelectedRawStart(_ value: Double) {
        guard let video = project.activeVideo else { return }
        let clamped = min(max(value, 0), video.durationSec)
        project.selectedRawStartSec = clamped
        if let end = project.selectedRawEndSec, end <= clamped {
            project.selectedRawEndSec = min(video.durationSec, clamped + 0.1)
        }
        touchAndPersist(invalidateExport: true)
    }

    func updateSelectedRawEnd(_ value: Double) {
        guard let video = project.activeVideo else { return }
        project.selectedRawEndSec = min(max(value, 0), video.durationSec)
        touchAndPersist(invalidateExport: true)
    }

    func adjustOffset(ms delta: Double) {
        project.offsetMs += delta
        touchAndPersist(invalidateExport: true)
    }

    func resetOffset() {
        project.offsetMs = 0
        touchAndPersist(invalidateExport: true)
    }

    func saveShortEditDraft(_ draft: ShortEditDraft) {
        project.shortEditDraft = draft
        touchAndPersist()
    }

    func export() {
        guard canExport else { return }
        let requestedProject = project
        let requestedRevision = project.updatedAt
        isExporting = true
        exportResult = nil
        errorMessage = nil

        Task {
            do {
                let result = try await VideoExportService.export(project: requestedProject)
                guard project.updatedAt == requestedRevision else {
                    errorMessage = "書き出し中にProjectが変更されたため、古い書き出し結果は表示しません。もう一度書き出してください。"
                    isExporting = false
                    return
                }
                exportResult = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func remapShortDraftForVideoSongStartChange(from oldSongStartRawSec: Double, to newSongStartRawSec: Double) {
        guard var draft = project.shortEditDraft else { return }

        draft.rangeStartProjectSec = TimelineMapper.remapProjectTimelineSec(
            draft.rangeStartProjectSec,
            fromSongStartRawSec: oldSongStartRawSec,
            toSongStartRawSec: newSongStartRawSec
        )
        draft.rangeEndProjectSec = TimelineMapper.remapProjectTimelineSec(
            draft.rangeEndProjectSec,
            fromSongStartRawSec: oldSongStartRawSec,
            toSongStartRawSec: newSongStartRawSec
        )

        for index in draft.lyricCues.indices {
            draft.lyricCues[index].startProjectSec = TimelineMapper.remapProjectTimelineSec(
                draft.lyricCues[index].startProjectSec,
                fromSongStartRawSec: oldSongStartRawSec,
                toSongStartRawSec: newSongStartRawSec
            )
            draft.lyricCues[index].endProjectSec = TimelineMapper.remapProjectTimelineSec(
                draft.lyricCues[index].endProjectSec,
                fromSongStartRawSec: oldSongStartRawSec,
                toSongStartRawSec: newSongStartRawSec
            )
        }

        project.shortEditDraft = draft
    }

    private func resetVideoDependentState() {
        videoPreviewTimeSec = 0
        project.songStartRawSec = nil
        project.selectedRawStartSec = nil
        project.selectedRawEndSec = nil
        project.shortEditDraft = nil
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

    private func touchAndPersist(invalidateExport: Bool = false) {
        if invalidateExport {
            exportResult = nil
        }
        project.updatedAt = Date()
        do {
            try ProjectStore.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
