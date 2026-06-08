import Foundation

enum MediaImportStoreError: LocalizedError {
    case cannotCreateImportDirectory
    case cannotCopyImportedFile

    var errorDescription: String? {
        switch self {
        case .cannotCreateImportDirectory:
            return "インポート保存先を作成できませんでした。"
        case .cannotCopyImportedFile:
            return "インポートしたファイルを保存できませんでした。"
        }
    }
}

enum MediaImportStore {
    static func copyIntoImports(_ sourceURL: URL) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let importsDirectory = try importsDirectory()
        let fileExtension = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = importsDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(fileExtension)")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw MediaImportStoreError.cannotCopyImportedFile
        }
    }

    private static func importsDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw MediaImportStoreError.cannotCreateImportDirectory
        }
        let directory = documentsDirectory.appendingPathComponent("Imports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
