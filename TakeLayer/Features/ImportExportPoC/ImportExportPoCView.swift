import AVKit
import SwiftUI
import UniformTypeIdentifiers

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
                        video: viewModel.project.importedVideo,
                        isImporting: viewModel.isImportingVideo,
                        onImport: { isVideoImporterPresented = true },
                        onRecord: { isRecordingPresented = true }
                    )
                    AudioImportView(
                        audio: viewModel.project.importedMasterAudio,
                        isImporting: viewModel.isImportingAudio,
                        onImport: { isAudioImporterPresented = true }
                    )
                    if let video = viewModel.project.importedVideo {
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
                    if let video = viewModel.project.importedVideo {
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

struct VideoImportView: View {
    let video: ImportedVideo?
    let isImporting: Bool
    let onImport: () -> Void
    let onRecord: () -> Void

    var body: some View {
        SectionCard(title: "1. Video Source") {
            HStack {
                Button(isImporting ? "Importing..." : "Import Video") {
                    onImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)

                Button("Record New Take") {
                    onRecord()
                }
                .buttonStyle(.bordered)
            }

            Text("カメラロールから選ぶか、TakeLayer内で新規録画します。どちらも後から songStartRawSec を手動指定します。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let video {
                MediaInfoGrid(rows: [
                    ("duration", TimeFormatting.seconds(video.durationSec)),
                    ("width", video.width.map(String.init) ?? "Unknown"),
                    ("height", video.height.map(String.init) ?? "Unknown"),
                    ("orientation", video.orientation.rawValue),
                    ("file type", video.fileType ?? "Unknown"),
                    ("has audio", video.hasAudio ? "Yes" : "No"),
                    ("file size", TimeFormatting.fileSize(video.fileSizeBytes))
                ])
            } else {
                Text("未インポート")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AudioImportView: View {
    let audio: ImportedMasterAudio?
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        SectionCard(title: "2. Import Master WAV") {
            Button(isImporting ? "Importing..." : "WAVをインポート") {
                onImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)

            if let audio {
                MediaInfoGrid(rows: [
                    ("duration", TimeFormatting.seconds(audio.durationSec)),
                    ("sample rate", audio.sampleRate.map { String(format: "%.0f Hz", $0) } ?? "Unknown"),
                    ("channels", audio.channelCount.map(String.init) ?? "Unknown"),
                    ("file type", audio.fileType ?? "Unknown"),
                    ("file size", TimeFormatting.fileSize(audio.fileSizeBytes))
                ])
            } else {
                Text("未インポート")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct VideoSongStartEditorView: View {
    let video: ImportedVideo
    @Binding var currentTimeSec: Double
    let songStartRawSec: Double?
    let onSetSongStart: () -> Void
    @State private var player = AVPlayer()

    var body: some View {
        SectionCard(title: "3. Set Video Song Start") {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear { configurePlayer() }
                .onChange(of: currentTimeSec) { newValue in
                    player.seek(to: CMTime(seconds: newValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }

            MarkerSlider(
                currentTimeSec: $currentTimeSec,
                durationSec: video.durationSec,
                label: "動画内の現在位置"
            )
            Button("この位置を曲開始に設定") {
                onSetSongStart()
            }
            .buttonStyle(.bordered)
            Text("songStartRawSec: \(TimeFormatting.seconds(songStartRawSec))")
                .font(.headline)
        }
    }

    private func configurePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: video.url))
        player.seek(to: CMTime(seconds: currentTimeSec, preferredTimescale: 600))
    }
}

struct AudioSongStartEditorView: View {
    let audio: ImportedMasterAudio
    @Binding var currentTimeSec: Double
    let songStartAudioSec: Double?
    let onSetSongStart: () -> Void
    @State private var player = AVPlayer()

    var body: some View {
        SectionCard(title: "4. Set WAV Song Start") {
            HStack(spacing: 12) {
                Button("再生") { player.play() }
                    .buttonStyle(.bordered)
                Button("停止") { player.pause() }
                    .buttonStyle(.bordered)
            }
            .onAppear { configurePlayer() }
            .onChange(of: currentTimeSec) { newValue in
                player.seek(to: CMTime(seconds: newValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }

            MarkerSlider(
                currentTimeSec: $currentTimeSec,
                durationSec: audio.durationSec,
                label: "WAV内の現在位置"
            )
            Button("この位置を曲開始に設定") {
                onSetSongStart()
            }
            .buttonStyle(.bordered)
            Text("songStartAudioSec: \(TimeFormatting.seconds(songStartAudioSec))")
                .font(.headline)
        }
    }

    private func configurePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: audio.url))
        player.seek(to: CMTime(seconds: currentTimeSec, preferredTimescale: 600))
    }
}

struct TrimRangeEditorView: View {
    let videoDurationSec: Double
    @Binding var selectedRawStartSec: Double
    @Binding var selectedRawEndSec: Double
    let selectedDurationSec: Double?
    let masterAudioEffectiveDurationSec: Double?
    let durationDifferenceSec: Double?

    var body: some View {
        SectionCard(title: "5. Set Trim Range") {
            MarkerSlider(
                currentTimeSec: $selectedRawStartSec,
                durationSec: videoDurationSec,
                label: "selectedRawStartSec"
            )
            MarkerSlider(
                currentTimeSec: $selectedRawEndSec,
                durationSec: videoDurationSec,
                label: "selectedRawEndSec"
            )
            MediaInfoGrid(rows: [
                ("selected duration", TimeFormatting.seconds(selectedDurationSec)),
                ("master effective duration", TimeFormatting.seconds(masterAudioEffectiveDurationSec)),
                ("difference", durationDifferenceSec.map { String(format: "%+.2f sec", $0) } ?? "Unknown")
            ])
            Text("元動画は切断せず、使用範囲をメタデータとして保持します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

struct MarkerSlider: View {
    @Binding var currentTimeSec: Double
    let durationSec: Double
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(TimeFormatting.seconds(currentTimeSec))
                    .monospacedDigit()
            }
            Slider(value: $currentTimeSec, in: 0...max(durationSec, 0.01))
        }
    }
}

struct MediaInfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ImportExportPoCView()
}
