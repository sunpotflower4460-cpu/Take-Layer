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
    private var countdownTask: Task<Void, Never>?
    private var zenModeTask: Task<Void, Never>?
    private var isStoppingRecording = false

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
            try await cameraService.configureSession()
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

        countdownTask?.cancel()
        recordedTake = nil
        errorMessage = nil
        isCountingDown = true
        countdownValue = 3

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for value in stride(from: 3, through: 1, by: -1) {
                self.countdownValue = value
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    self.countdownValue = nil
                    self.isCountingDown = false
                    self.countdownTask = nil
                    return
                }
                guard !Task.isCancelled else {
                    self.countdownValue = nil
                    self.isCountingDown = false
                    self.countdownTask = nil
                    return
                }
            }

            self.countdownValue = nil
            self.isCountingDown = false
            self.countdownTask = nil
            await self.startRecordingNow()
        }
    }

    func stopRecording() {
        guard isRecording, !isStoppingRecording else { return }
        isStoppingRecording = true
        Task { @MainActor in
            do {
                try await cameraService.stopRecording()
            } catch {
                errorMessage = error.localizedDescription
                finishRecordingUI()
            }
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
        countdownTask?.cancel()
        countdownTask = nil
        isCountingDown = false
        countdownValue = nil
        zenModeTask?.cancel()
        zenModeTask = nil
        cameraService.stopPreview()
    }

    private func startRecordingNow() async {
        do {
            let outputURL = try RecordingFileStore.makeRecordingURL()
            try await cameraService.startRecording(to: outputURL) { [weak self] result in
                Task { @MainActor in
                    self?.handleRecordingResult(result)
                }
            }
            recordingStartedAt = Date()
            isRecording = true
            isStoppingRecording = false
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
        Task { @MainActor in
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
        zenModeTask?.cancel()
        zenModeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.isRecording else { return }
            self.isZenModeActive = true
            self.zenModeTask = nil
        }
    }

    private func finishRecordingUI() {
        isRecording = false
        isStoppingRecording = false
        isZenModeActive = false
        recordingStartedAt = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        zenModeTask?.cancel()
        zenModeTask = nil
        availableCapacityBytes = RecordingFileStore.availableCapacityBytes()
    }
}
