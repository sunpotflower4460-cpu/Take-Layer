import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct MVPAlphaFlowView: View {
    @StateObject private var viewModel = MVPAlphaViewModel()
    @State private var isVideoImporterPresented = false
    @State private var isAudioImporterPresented = false
    @State private var isRecordingPresented = false

    private let wavType = UTType(filenameExtension: "wav") ?? .audio

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ProjectSetupView(project: viewModel.project, onTitleChange: viewModel.updateTitle)
                    MediaStatusView(project: viewModel.project, validationResult: viewModel.validationResult)
                    VideoImportView(
                        video: viewModel.project.activeVideo,
                        isImporting: viewModel.isImportingVideo,
                        onImport: { isVideoImporterPresented = true },
                        onRecord: { isRecordingPresented = true }
                    )
                    AudioImportView(
                        audio: viewModel.project.importedMasterAudio,
                        isImporting: viewModel.isImportingAudio,
                        onImport: { isAudioImporterPresented = true }
                    )
                    if let video = viewModel.project.activeVideo {
                        VideoSongStartEditorView(
                            video: video,
                            currentTimeSec: $viewModel.videoPreviewTimeSec,
                            songStartRawSec: viewModel.project.songStartRawSec,
                            onSetSongStart: viewModel.setVideoSongStart
                        )
                    }
                    if let audio = viewModel.project.importedMasterAudio {
                        AudioSongStartEditorView(
                            audio: audio,
                            currentTimeSec: $viewModel.audioPreviewTimeSec,
                            songStartAudioSec: viewModel.project.songStartAudioSec,
                            onSetSongStart: viewModel.setAudioSongStart
                        )
                    }
                    if let video = viewModel.project.activeVideo {
                        TrimRangeEditorView(
                            videoDurationSec: video.durationSec,
                            selectedRawStartSec: Binding(
                                get: { viewModel.project.selectedRawStartSec ?? 0 },
                                set: viewModel.updateSelectedRawStart
                            ),
                            selectedRawEndSec: Binding(
                                get: { viewModel.project.selectedRawEndSec ?? video.durationSec },
                                set: viewModel.updateSelectedRawEnd
                            ),
                            selectedDurationSec: viewModel.selectedDuration,
                            masterAudioEffectiveDurationSec: viewModel.masterAudioEffectiveDuration,
                            durationDifferenceSec: viewModel.durationDifferenceFromProject
                        )
                    }
                    OffsetAdjustmentView(
                        offsetMs: viewModel.project.offsetMs,
                        onAdjust: viewModel.adjustOffset,
                        onReset: viewModel.resetOffset
                    )
                    ExportReviewView(
                        project: viewModel.project,
                        selectedVideoDurationSec: viewModel.selectedDuration,
                        masterAudioEffectiveDurationSec: viewModel.masterAudioEffectiveDuration,
                        outputDurationSec: viewModel.outputDuration,
                        validationResult: viewModel.validationResult,
                        canExport: viewModel.canExport,
                        isExporting: viewModel.isExporting,
                        exportResult: viewModel.exportResult,
                        errorMessage: viewModel.errorMessage,
                        onExport: viewModel.export
                    )
                }
                .padding()
            }
            .navigationTitle("MVP-α Flow")
            .fileImporter(
                isPresented: $isVideoImporterPresented,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result, importAction: viewModel.importVideo)
            }
            .fileImporter(
                isPresented: $isAudioImporterPresented,
                allowedContentTypes: [wavType],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result, importAction: viewModel.importMasterAudio)
            }
            .sheet(isPresented: $isRecordingPresented) {
                RecordingView(onUseTake: viewModel.useRecordedTake)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TakeLayer Phase 1")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("1本動画を、DAW完成WAVつきの演奏動画として書き出すMVP-α統合フローです。")
                .foregroundStyle(.secondary)
            Text("Project timeline 0:00 = 曲開始。songStartRawSec / songStartAudioSec / trim range / offsetMs は手動で保持します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>, importAction: (URL) -> Void) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importAction(url)
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct ProjectSetupView: View {
    let project: ProjectDraft
    let onTitleChange: (String) -> Void

    var body: some View {
        SectionCard(title: "Project") {
            TextField(
                "Project title",
                text: Binding(
                    get: { project.title },
                    set: onTitleChange
                )
            )
            .textFieldStyle(.roundedBorder)

            MediaInfoGrid(rows: [
                ("createdAt", project.createdAt.formatted(date: .abbreviated, time: .shortened)),
                ("updatedAt", project.updatedAt.formatted(date: .abbreviated, time: .shortened))
            ])
        }
    }
}

struct MediaStatusView: View {
    let project: ProjectDraft
    let validationResult: ExportValidationResult

    var body: some View {
        SectionCard(title: "Flow Status") {
            MediaInfoGrid(rows: [
                ("Project", status(!project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)),
                ("Video", project.activeVideo == nil ? "Missing" : videoSourceText),
                ("Master WAV", status(project.importedMasterAudio != nil)),
                ("Video Song Start", status(project.songStartRawSec != nil)),
                ("WAV Song Start", status(project.songStartAudioSec != nil)),
                ("Trim Range", status(project.selectedRawStartSec != nil && project.selectedRawEndSec != nil)),
                ("Export", validationResult.isReady ? "Ready" : "Not Ready")
            ])
        }
    }

    private var videoSourceText: String {
        project.recordedTake == nil ? "Imported" : "Recorded"
    }

    private func status(_ isComplete: Bool) -> String {
        isComplete ? "OK" : "Missing"
    }
}

struct OffsetAdjustmentView: View {
    let offsetMs: Double
    let onAdjust: (Double) -> Void
    let onReset: () -> Void

    var body: some View {
        SectionCard(title: "6. Manual Offset") {
            Text("offsetMs: \(formattedOffset)")
                .font(.headline)
                .monospacedDigit()
            HStack {
                ForEach([-100.0, -10.0, -1.0], id: \.self) { delta in
                    Button(String(format: "%.0fms", delta)) { onAdjust(delta) }
                        .buttonStyle(.bordered)
                }
                Button("reset") { onReset() }
                    .buttonStyle(.bordered)
                ForEach([1.0, 10.0, 100.0], id: \.self) { delta in
                    Button(String(format: "+%.0fms", delta)) { onAdjust(delta) }
                        .buttonStyle(.bordered)
                }
            }
            .font(.caption)
            Text("MVP-αでは手動補正値をProjectDraftに保持します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedOffset: String {
        String(format: "%+.0f ms", offsetMs)
    }
}

struct ExportReviewView: View {
    let project: ProjectDraft
    let selectedVideoDurationSec: Double?
    let masterAudioEffectiveDurationSec: Double?
    let outputDurationSec: Double
    let validationResult: ExportValidationResult
    let canExport: Bool
    let isExporting: Bool
    let exportResult: ExportResult?
    let errorMessage: String?
    let onExport: () -> Void

    var body: some View {
        SectionCard(title: "7. Export Review") {
            MediaInfoGrid(rows: [
                ("selected video duration", TimeFormatting.seconds(selectedVideoDurationSec)),
                ("master audio effective duration", TimeFormatting.seconds(masterAudioEffectiveDurationSec)),
                ("output duration", TimeFormatting.seconds(outputDurationSec)),
                ("mute camera audio", project.exportSettings.muteCameraAudio ? "true" : "false"),
                ("output file type", project.exportSettings.outputFileType.rawValue),
                ("offsetMs", String(format: "%+.0f ms", project.offsetMs))
            ])

            validationList

            Button(isExporting ? "書き出し中..." : "1画面MP4を書き出し") {
                onExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canExport)

            Text("カメラ音声はcompositionへ挿入せず、完成WAVを本番音声として使用します。元動画と元WAVは非破壊で保持します。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isExporting {
                ProgressView("Exporting...")
            }

            if let exportResult {
                exportSuccess(exportResult)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var validationList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Validation")
                .font(.headline)
            ForEach(validationResult.items) { item in
                Label {
                    Text("\(item.title): \(item.message)")
                } icon: {
                    Image(systemName: item.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.isValid ? .green : .orange)
                }
                .font(.footnote)
            }
        }
    }

    private func exportSuccess(_ exportResult: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("書き出し完了")
                .font(.headline)
            Text(exportResult.outputURL.lastPathComponent)
            Text("duration: \(TimeFormatting.seconds(exportResult.durationSec))")
            VideoPlayer(player: AVPlayer(url: exportResult.outputURL))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            ShareLink(item: exportResult.outputURL) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
        }
        .foregroundStyle(.green)
    }
}

#Preview {
    MVPAlphaFlowView()
}
