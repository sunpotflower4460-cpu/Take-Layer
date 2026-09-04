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
    private let minimumRangeDuration: Double

    init(project: ProjectDraft, onPersistDraft: @escaping (ShortEditDraft) -> Void) {
        self.project = project
        self.onPersistDraft = onPersistDraft

        let mapping = try? TimelineMapper.makeMapping(project: project)
        let start = mapping?.projectTimelineStartSec ?? 0
        let mappedDuration = max(0.001, mapping?.outputDurationSec ?? 15)
        let end = start + mappedDuration
        self.availableRange = start...end
        self.minimumRangeDuration = min(0.1, mappedDuration)

        var initial = project.shortEditDraft ?? ShortEditDraft(
            rangeStartProjectSec: start,
            rangeEndProjectSec: min(end, start + min(15, mappedDuration)),
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
            exportResult = nil
            errorMessage = nil

            let clampedPreview = min(
                max(previewProjectSec, newValue.rangeStartProjectSec),
                newValue.rangeEndProjectSec
            )
            if clampedPreview != previewProjectSec {
                previewProjectSec = clampedPreview
                seekPreview(to: clampedPreview)
            }
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
                ShortCropPreviewView(
                    player: player,
                    displaySize: CGSize(
                        width: project.activeVideo?.width ?? 1080,
                        height: project.activeVideo?.height ?? 1920
                    ),
                    crop: draft.crop
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
                in: draft.rangeStartProjectSec...max(draft.rangeEndProjectSec, draft.rangeStartProjectSec + 0.001)
            )
            Text("preview: \(TimeFormatting.signedSeconds(previewProjectSec)) on Project Timeline")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var rangeEditor: some View {
        GroupBox("1. Short Range") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(TimeFormatting.signedSeconds(draft.rangeStartProjectSec)) → \(TimeFormatting.signedSeconds(draft.rangeEndProjectSec))  (\(TimeFormatting.seconds(draft.durationSec)))")
                    .font(.headline.monospacedDigit())

                Text("Start")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { draft.rangeStartProjectSec },
                        set: { newValue in
                            draft.rangeStartProjectSec = min(
                                newValue,
                                draft.rangeEndProjectSec - minimumRangeDuration
                            )
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
                            draft.rangeEndProjectSec = max(
                                newValue,
                                draft.rangeStartProjectSec + minimumRangeDuration
                            )
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

                if draft.hasInvalidLyricCues {
                    Label("選択範囲内に未完成の字幕Cueがあります。テキストと開始・終了時刻を修正するか、不要なCueを削除すると書き出せます。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if draft.hasOverlappingValidLyricCues {
                    Label("選択範囲内で字幕Cueの時間が重なっています。Previewは先頭Cueだけを表示し、重なりを直すまで書き出しを停止します。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach($draft.lyricCues) { $cue in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("歌詞", text: $cue.text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("start", value: $cue.startProjectSec, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("end", value: $cue.endProjectSec, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
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
                .disabled(
                    isExporting ||
                    draft.durationSec <= 0 ||
                    draft.hasInvalidLyricCues ||
                    draft.hasOverlappingValidLyricCues
                )

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
        draft.validLyricCues.first {
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
        player.seek(
            to: MediaTime.make(max(0, rawSec)),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func exportShort() {
        let requestedDraft = draft
        isExporting = true
        exportResult = nil
        errorMessage = nil
        onPersistDraft(requestedDraft)

        Task {
            do {
                let result = try await ShortVideoExportService.export(project: project, draft: requestedDraft)
                if draft == requestedDraft {
                    exportResult = result
                }
            } catch {
                if draft == requestedDraft {
                    errorMessage = error.localizedDescription
                }
            }
            isExporting = false
        }
    }
}

private struct ShortCropPreviewView: View {
    let player: AVPlayer
    let displaySize: CGSize
    let crop: ShortCropPlan

    var body: some View {
        GeometryReader { proxy in
            let geometry = ShortRenderGeometryBuilder.make(displaySize: displaySize, crop: crop)
            let previewScale = proxy.size.width / geometry.renderSize.width

            ZStack(alignment: .topLeading) {
                Color.black
                ShortPlayerLayerView(player: player)
                    .frame(
                        width: geometry.scaledDisplaySize.width * previewScale,
                        height: geometry.scaledDisplaySize.height * previewScale
                    )
                    .offset(
                        x: -geometry.cropOffset.x * previewScale,
                        y: -geometry.cropOffset.y * previewScale
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
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
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }
}
