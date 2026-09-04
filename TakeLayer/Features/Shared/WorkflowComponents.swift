import AVKit
import SwiftUI

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
                    player.seek(
                        to: MediaTime.make(newValue),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
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
        player.seek(to: MediaTime.make(currentTimeSec))
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
                player.seek(
                    to: MediaTime.make(newValue),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
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
        player.seek(to: MediaTime.make(currentTimeSec))
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
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
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
