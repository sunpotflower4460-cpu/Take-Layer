import AVFoundation
import SwiftUI
import UIKit

struct ShortFoundationView: View {
    let project: ProjectDraft
    let onPersistDraft: (ShortEditDraft) -> Void

    @State private var draft: ShortEditDraft
    @State private var previewProjectSec: Double
    @State private var player: AVPlayer
    @State private var isExporting = false
    @State private var exportResult: ExportResult?
    @State private var errorMessage: String?

    private let availableRange: ClosedRange<Double>

    init(project: ProjectDraft, onPersistDraft: @escaping (ShortEditDraft) -> Void) {
        self.project = project
        self.onPersistDraft = onPersistDraft

        let mapping = try? TimelineMapper.makeMapping(project: project)
        let start = mapping?.projectTimelineStartSec ?? 0
        let end = start + max(0.1, mapping?.outputDurationSec ?? 15)
        self.availableRange = start...end

        var initial = project.shortEditDraft ?? ShortEditDraft(
            rangeStartProjectSec: max(0, start),
            rangeEndProjectSec: min(end, max(0, start) + min(15, max(0.1, end - max(0, start)))),
            titleText: project.title
        )
        initial.normalize(availableRange: start...end)
        _draft = State(initialValue: initial)
        _previewProjectSec = State(initialValue: initial.rangeStartProjectSec)
        _player = State(initialValue: AVPlayer(url: project.activeVideoURL ?? URL(fileURLWithPath: "/dev/null")))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro
                preview
                rangeEditor
                cropEditor
                titleEditor
                lyricEditor
                exportPanel
            }
            .padding()
        }
        .navigationTitle("Short Foundation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seekPreview(to: previewProjectSec)
        }
        .onChange(of: draft) { _, newValue in
            onPersistDraft(newValue)
            previewProjectSec = min(max(previewProjectSec, newValue.rangeStartProjectSec), newValue.rangeEndProjectSec)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phase 1.5 · Deterministic Short Editor")
                .font(.title2.bold())
            Text("AIなしで、1本の演奏動画を9:16ショートへ確実に変換する土台です。同期はTimelineMapperを通し、編集内容はShortEditDraftとして保存します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)

            ZStack {
                Color.black
                ShortPlayerLayerView(player: player)
                    .scaleEffect(draft.crop.zoom)
                    .offset(
                        x: CGFloat((0.5 - draft.crop.focusX) * 220 * draft.crop.zoom),
                        y: CGFloat((draft.crop.focusY - 0.5) * 220 * draft.crop.zoom)
                    )

                VStack {
                    if !draft.titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(draft.titleText)
                            .font(.headline.bold())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .padding(.top, 26)
                            .padding(.horizontal, 18)
                    }
                    Spacer()
                    if let lyric = activeLyricText {
                        Text(lyric)
                            .font(.headline.bold())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 42)
                    }
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Slider(
                value: Binding(
                    get: { previewProjectSec },
                    set: {
                        previewProjectSec = $0
                        seekPreview(to: $0)
                    }
                ),
                in: draft.rangeStartProjectSec...max(draft.rangeEndProjectSec, draft.rangeStartProjectSec + 0.1)
            )
            Text("preview: \(TimeFormatting.seconds(previewProjectSec)) on Project Timeline")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var rangeEditor: some View {
        GroupBox("1. Short Range") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(TimeFormatting.seconds(draft.rangeStartProjectSec)) → \(TimeFormatting.seconds(draft.rangeEndProjectSec))  (\(TimeFormatting.seconds(draft.durationSec)))")
                    .font(.headline.monospacedDigit())

                Text("Start")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { draft.rangeStartProjectSec },
                        set: { newValue in
                            draft.rangeStartProjectSec = min(newValue, draft.rangeEndProjectSec - 0.1)
                        }
                    ),
                    in: availableRange
                )

                Text("End")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { draft.rangeEndProjectSec },
                        set: { newValue in
                            draft.rangeEndProjectSec = max(newValue, draft.rangeStartProjectSec + 0.1)
                        }
                    ),
                    in: availableRange
                )
            }
        }
    }

    private var cropEditor: some View {
        GroupBox("2. 9:16 Crop / Zoom / Pan") {
            VStack(alignment: .leading, spacing: 12) {
                valueSlider("Zoom", value: $draft.crop.zoom, range: 1...3)
                valueSlider("Focus X", value: $draft.crop.focusX, range: 0...1)
                valueSlider("Focus Y", value: $draft.crop.focusY, range: 0...1)
                Button("Reset Crop") {
                    draft.crop = ShortCropPlan()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var titleEditor: some View {
        GroupBox("3. Title Layer") {
            TextField("曲名 / タイトル", text: $draft.titleText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Text("同じ入力から毎回同じ位置・同じ描画になる決定論的タイトルです。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lyricEditor: some View {
        GroupBox("4. User-supplied Lyrics") {
            VStack(alignment: .leading, spacing: 12) {
                Text("歌詞は生成せず、ユーザーが入力した正式テキストだけを字幕として使います。時刻はProject Timeline基準です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($draft.lyricCues) { $cue in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("歌詞", text: $cue.text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("start", value: $cue.startProjectSec, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            TextField("end", value: $cue.endProjectSec, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Button(role: .destructive) {
                                draft.lyricCues.removeAll { $0.id == cue.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    let start = previewProjectSec
                    draft.lyricCues.append(
                        ShortLyricCue(
                            startProjectSec: start,
                            endProjectSec: min(draft.rangeEndProjectSec, start + 3),
                            text: ""
                        )
                    )
                } label: {
                    Label("字幕Cueを追加", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var exportPanel: some View {
        GroupBox("5. Preview → Micro-adjustment → Export") {
            VStack(alignment: .leading, spacing: 12) {
                Text("1080 × 1920 / 30fps / 完成WAV / camera audio muted")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isExporting ? "Shortを書き出し中…" : "9:16 Shortを書き出す") {
                    exportShort()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || draft.durationSec <= 0)

                if isExporting {
                    ProgressView()
                }
                if let exportResult {
                    ShareLink(item: exportResult.outputURL) {
                        Label("書き出し完了 · 共有", systemImage: "square.and.arrow.up")
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }

    private var activeLyricText: String? {
        draft.lyricCues.first {
            $0.startProjectSec <= previewProjectSec && previewProjectSec < $0.endProjectSec
        }?.text
    }

    private func valueSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func seekPreview(to projectSec: Double) {
        guard let songStartRawSec = project.songStartRawSec else { return }
        let rawSec = TimelineMapper.videoRawSec(
            projectTimelineSec: projectSec,
            songStartRawSec: songStartRawSec
        )
        player.seek(to: CMTime(seconds: max(0, rawSec), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func exportShort() {
        isExporting = true
        exportResult = nil
        errorMessage = nil
        onPersistDraft(draft)
        Task {
            do {
                exportResult = try await ShortVideoExportService.export(project: project, draft: draft)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
}

private struct ShortPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerLayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspectFill
    }
}
