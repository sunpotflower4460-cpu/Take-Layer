import AVFoundation
import Foundation

enum CameraRecordingServiceError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case cannotAddCameraInput
    case cannotAddMicrophoneInput
    case cannotAddMovieOutput
    case sessionNotConfigured
    case recordingAlreadyInProgress
    case recordingNotInProgress
    case recordingOutputMissing
    case recordingFailed(String)
    case savedFileMissing

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "カメラを利用できません。"
        case .microphoneUnavailable:
            return "マイクを利用できません。"
        case .cannotAddCameraInput:
            return "カメラ入力を追加できませんでした。"
        case .cannotAddMicrophoneInput:
            return "マイク入力を追加できませんでした。"
        case .cannotAddMovieOutput:
            return "動画出力を追加できませんでした。"
        case .sessionNotConfigured:
            return "録画セッションが準備できていません。"
        case .recordingAlreadyInProgress:
            return "すでに録画中です。"
        case .recordingNotInProgress:
            return "録画中ではありません。"
        case .recordingOutputMissing:
            return "録画出力が見つかりません。"
        case .recordingFailed(let message):
            return "録画に失敗しました: \(message)"
        case .savedFileMissing:
            return "録画ファイルが保存されませんでした。"
        }
    }
}

final class CameraRecordingService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "TakeLayer.CameraRecordingService.session")
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private var finishHandler: ((Result<URL, Error>) -> Void)?

    func configureSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraRecordingServiceError.sessionNotConfigured)
                    return
                }
                do {
                    try self.configureSessionOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startPreview() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stopPreview() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) throws {
        guard isConfigured else { throw CameraRecordingServiceError.sessionNotConfigured }
        guard !movieFileOutput.isRecording else { throw CameraRecordingServiceError.recordingAlreadyInProgress }
        guard movieFileOutput.connection(with: .video) != nil else { throw CameraRecordingServiceError.recordingOutputMissing }

        finishHandler = completion
        movieFileOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() throws {
        guard movieFileOutput.isRecording else { throw CameraRecordingServiceError.recordingNotInProgress }
        movieFileOutput.stopRecording()
    }

    private func configureSessionOnQueue() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            throw CameraRecordingServiceError.cameraUnavailable
        }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else {
            throw CameraRecordingServiceError.cannotAddCameraInput
        }
        session.addInput(cameraInput)

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw CameraRecordingServiceError.microphoneUnavailable
        }
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(microphoneInput) else {
            throw CameraRecordingServiceError.cannotAddMicrophoneInput
        }
        session.addInput(microphoneInput)

        guard session.canAddOutput(movieFileOutput) else {
            throw CameraRecordingServiceError.cannotAddMovieOutput
        }
        session.addOutput(movieFileOutput)
        if let connection = movieFileOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        isConfigured = true
    }
}

extension CameraRecordingService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let completion = finishHandler
        finishHandler = nil

        if let error {
            let nsError = error as NSError
            let finishedSuccessfully = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            if !finishedSuccessfully {
                completion?(.failure(CameraRecordingServiceError.recordingFailed(error.localizedDescription)))
                return
            }
        }

        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            completion?(.failure(CameraRecordingServiceError.savedFileMissing))
            return
        }

        completion?(.success(outputFileURL))
    }
}
