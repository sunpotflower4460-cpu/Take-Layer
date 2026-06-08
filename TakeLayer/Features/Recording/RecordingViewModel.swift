import Combine
import Foundation

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var permissionState = RecordingPermissionState.current
    @Published var isPreparing = false
    @Published var isCountingDown = false
    @Published var countdownValue: Int?
    @Published var isRecording = false
    @Published var elapsedSec: Double = 0
    @Published var isZenModeActive = false
    @Published var recordedTake: RecordedTake?
    @Published var errorMessage: String?
    @Published var availableCapacityBytes: Int64?
    @Published var isReadingTake = false

    let cameraService = CameraRecordingService()

    private var elapsedTimer: Timer?
    private var recordingStartedAt: Date?

    func prepare() async {
        isPreparing = true
        errorMessage = nil
        availableCapacityBytes = RecordingFileStore.availableCapacityBytes()
        permissionState = await RecordingPermissionService.requestPermissions()

        guard permissionState.isAuthorized else {
            isPreparing = false
            return
        }

        do {
            try cameraService.configureSession()
            cameraService.startPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    func startCountdownAndRecording() {
        guard !isCountingDown, !isRecording else { return }
        guard permissionState.isAuthorized else {
            errorMessage = "カメラとマイクの権限を許可してください。"
            return
        }

        recordedTake = nil
        errorMessage = nil
        isCountingDown = true
        countdownValue = 3

        Task {
            for value in stride(from: 3, through: 1, by: -1) {
                countdownValue = value
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdownValue = nil
            isCountingDown = false
            startRecordingNow()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        do {
            try cameraService.stopRecording()
        } catch {
            errorMessage = error.localizedDescription
            finishRecordingUI()
        }
    }

    func discardRecordedTake() {
        guard let recordedTake else { return }
        do {
            try RecordingFileStore.removeRecording(at: recordedTake.url)
            self.recordedTake = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordAgain() {
        recordedTake = nil
        errorMessage = nil
        elapsedSec = 0
        isZenModeActive = false
    }

    func stopPreview() {
        cameraService.stopPreview()
    }

    private func startRecordingNow() {
        do {
            let outputURL = try RecordingFileStore.makeRecordingURL()
            try cameraService.startRecording(to: outputURL) { [weak self] result in
                Task { @MainActor in
                    self?.handleRecordingResult(result)
                }
            }
            recordingStartedAt = Date()
            isRecording = true
            isZenModeActive = false
            startElapsedTimer()
            scheduleZenMode()
        } catch {
            errorMessage = error.localizedDescription
            finishRecordingUI()
        }
    }

    private func handleRecordingResult(_ result: Result<URL, Error>) {
        finishRecordingUI()
        switch result {
        case .success(let url):
            readRecordedTake(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func readRecordedTake(from url: URL) {
        isReadingTake = true
        Task {
            do {
                recordedTake = try await MediaInfoReader.readRecordedTake(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isReadingTake = false
            availableCapacityBytes = RecordingFileStore.availableCapacityBytes()
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recordingStartedAt = self.recordingStartedAt else { return }
                self.elapsedSec = Date().timeIntervalSince(recordingStartedAt)
            }
        }
    }

    private func scheduleZenMode() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if isRecording {
                isZenModeActive = true
            }
        }
    }

    private func finishRecordingUI() {
        isRecording = false
        isZenModeActive = false
        recordingStartedAt = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        availableCapacityBytes = RecordingFileStore.availableCapacityBytes()
    }
}
