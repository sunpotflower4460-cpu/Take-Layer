import Foundation

enum RecordingFileStoreError: LocalizedError {
    case cannotCreateRecordingsDirectory
    case cannotRemoveRecording

    var errorDescription: String? {
        switch self {
        case .cannotCreateRecordingsDirectory:
            return "録画保存先を作成できませんでした。"
        case .cannotRemoveRecording:
            return "録画ファイルを削除できませんでした。"
        }
    }
}

enum RecordingFileStore {
    static func makeRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        return directory.appendingPathComponent("TakeLayer-Take-\(UUID().uuidString).mov")
    }

    static func removeRecording(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RecordingFileStoreError.cannotRemoveRecording
        }
    }

    static func availableCapacityBytes() -> Int64? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let values = try? documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
    }

    private static func recordingsDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecordingFileStoreError.cannotCreateRecordingsDirectory
        }
        let directory = documentsDirectory.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
