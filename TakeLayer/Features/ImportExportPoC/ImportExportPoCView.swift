import SwiftUI
import UniformTypeIdentifiers

/// Historical import-first proof of concept.
///
/// This feature is intentionally excluded from the active app target. Shared workflow UI lives in
/// `Features/Shared/WorkflowComponents.swift` so production screens never depend on this legacy folder.
struct ImportExportPoCView: View {
    @StateObject private var viewModel = ImportExportPoCViewModel()
    @State private var isVideoImporterPresented = false
    @State private var isAudioImporterPresented = false
    @State private var isRecordingPresented = false

    private let wavType = UTType(filenameExtension: "wav") ?? .audio

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
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
                    ExportProgressView(
                        canExport: viewModel.canExport,
                        isExporting: viewModel.isExporting,
                        exportResult: viewModel.exportResult,
                        errorMessage: viewModel.errorMessage,
                        onExport: viewModel.export
                    )
                }
                .padding()
            }
            .navigationTitle("Import-first Export PoC")
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
            Text("TakeLayer")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("既存動画 + 完成WAV + 手動基準点 + 1画面MP4書き出しを検証します。")
                .foregroundStyle(.secondary)
            Text("Project timeline 0:00 = 曲開始。songStartRawSec と songStartAudioSec を別々に保持します。")
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

struct ExportProgressView: View {
    let canExport: Bool
    let isExporting: Bool
    let exportResult: ExportResult?
    let errorMessage: String?
    let onExport: () -> Void

    var body: some View {
        SectionCard(title: "6. Export") {
            Button(isExporting ? "書き出し中..." : "1画面MP4を書き出し") {
                onExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canExport)

            Text("カメラ音声はcompositionへ挿入せず、完成WAVを本番音声として使用します。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let exportResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text("書き出し完了")
                        .font(.headline)
                    Text(exportResult.outputURL.lastPathComponent)
                    Text("duration: \(TimeFormatting.seconds(exportResult.durationSec))")
                    ShareLink(item: exportResult.outputURL) {
                        Label("共有", systemImage: "square.and.arrow.up")
                    }
                }
                .foregroundStyle(.green)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    ImportExportPoCView()
}
