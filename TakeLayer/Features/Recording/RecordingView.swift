import SwiftUI

struct RecordingView: View {
    let onUseTake: (RecordedTake) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RecordingViewModel()
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraService.session)
                .ignoresSafeArea()

            if viewModel.isZenModeActive {
                zenOverlay
            } else {
                mainOverlay
            }
        }
        .task { await viewModel.prepare() }
        .onDisappear { viewModel.stopPreview() }
        .interactiveDismissDisabled(viewModel.isRecording || viewModel.isCountingDown)
        .confirmationDialog(
            "この録画ファイルを削除しますか？",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                viewModel.discardRecordedTake()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("元動画ファイルを削除します。この操作は取り消せません。")
        }
    }

    private var mainOverlay: some View {
        VStack(spacing: 16) {
            topBar
            Spacer()

            if viewModel.isPreparing {
                overlayCard {
                    ProgressView("カメラとマイクを準備中...")
                }
            } else if !viewModel.permissionState.isAuthorized {
                permissionCard
            } else if let recordedTake = viewModel.recordedTake {
                summaryCard(recordedTake)
            } else if viewModel.isReadingTake {
                overlayCard {
                    ProgressView("録画ファイルを確認中...")
                }
            } else if viewModel.isCountingDown {
                countdownView
            } else {
                recordingControls
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    private var topBar: some View {
        HStack {
            Button("閉じる") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(viewModel.isRecording || viewModel.isCountingDown)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Recording PoC")
                    .font(.headline)
                Text("録画開始 ≠ 曲開始")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var permissionCard: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("カメラとマイクの権限が必要です")
                    .font(.headline)
                Text("カメラは演奏動画の録画、マイクは後続Phaseで同期確認に使うカメラ音声の保持に使用します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                MediaInfoGrid(rows: [
                    ("camera", permissionText(viewModel.permissionState.camera)),
                    ("microphone", permissionText(viewModel.permissionState.microphone))
                ])
                Button("権限を再確認") {
                    Task { await viewModel.prepare() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var countdownView: some View {
        VStack(spacing: 12) {
            Text(viewModel.countdownValue.map(String.init) ?? "Recording")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("構えてください。カウントダウン開始時刻は曲開始として扱いません。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var recordingControls: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.isRecording {
                    recordingStatus
                    Button(role: .destructive) {
                        viewModel.stopRecording()
                    } label: {
                        Label("Stop Recording", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("3秒カウントダウン後に録画を開始します。録画ファイルにはカメラ音声も保持します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.startCountdownAndRecording()
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                capacityText
            }
        }
    }

    private var recordingStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
            Text("Recording")
                .font(.headline)
            Spacer()
            Text(TimeFormatting.seconds(viewModel.elapsedSec))
                .monospacedDigit()
        }
    }

    private var capacityText: some View {
        Text("available: \(TimeFormatting.fileSize(viewModel.availableCapacityBytes))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var zenOverlay: some View {
        VStack {
            HStack {
                Label("Recording", systemImage: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Spacer()
                Text(TimeFormatting.seconds(viewModel.elapsedSec))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()

            Button(role: .destructive) {
                viewModel.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.black.opacity(0.72))
    }

    private func summaryCard(_ recordedTake: RecordedTake) -> some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recorded Take")
                    .font(.headline)
                MediaInfoGrid(rows: [
                    ("duration", TimeFormatting.seconds(recordedTake.durationSec)),
                    ("width", recordedTake.width.map(String.init) ?? "Unknown"),
                    ("height", recordedTake.height.map(String.init) ?? "Unknown"),
                    ("orientation", recordedTake.orientation.rawValue),
                    ("has audio", recordedTake.hasAudio ? "Yes" : "No"),
                    ("file size", TimeFormatting.fileSize(recordedTake.fileSizeBytes))
                ])
                Text("Use This Take後も songStartRawSec と selectedRawStartSec / selectedRawEndSec は既存フローで手動指定します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    onUseTake(recordedTake)
                    dismiss()
                } label: {
                    Label("Use This Take", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                HStack {
                    Button("Record Again") {
                        viewModel.recordAgain()
                    }
                    .buttonStyle(.bordered)
                    Button("Discard", role: .destructive) {
                        isDiscardConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func overlayCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func permissionText(_ status: RecordingPermissionStatus) -> String {
        switch status {
        case .unknown:
            return "Not Determined"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        }
    }
}

#Preview {
    RecordingView { _ in }
}
