import AVFoundation
import Foundation

enum RecordingPermissionStatus {
    case unknown
    case authorized
    case denied
}

struct RecordingPermissionState {
    var camera: RecordingPermissionStatus
    var microphone: RecordingPermissionStatus

    var isAuthorized: Bool {
        camera == .authorized && microphone == .authorized
    }

    static var current: RecordingPermissionState {
        RecordingPermissionState(
            camera: status(for: AVCaptureDevice.authorizationStatus(for: .video)),
            microphone: status(for: AVCaptureDevice.authorizationStatus(for: .audio))
        )
    }

    private static func status(for avStatus: AVAuthorizationStatus) -> RecordingPermissionStatus {
        switch avStatus {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

enum RecordingPermissionService {
    static func requestPermissions() async -> RecordingPermissionState {
        async let cameraGranted = requestAccess(for: .video)
        async let microphoneGranted = requestAccess(for: .audio)
        _ = await (cameraGranted, microphoneGranted)
        return .current
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        guard status == .notDetermined else { return status == .authorized }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
