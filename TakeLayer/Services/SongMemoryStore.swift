import Foundation

enum SongMemoryStoreError: LocalizedError {
    case cannotCreateDirectory
    case cannotEncodeLibrary
    case cannotWriteLibrary
    case cannotReadLibrary

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory:
            return "Song Memory保存先を作成できませんでした。"
        case .cannotEncodeLibrary:
            return "Song Memoryを保存形式へ変換できませんでした。"
        case .cannotWriteLibrary:
            return "Song Memoryを保存できませんでした。"
        case .cannotReadLibrary:
            return "Song Memoryを読み込めませんでした。"
        }
    }
}

enum SongMemoryStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ library: SongMemoryLibrary) throws {
        let data: Data
        do {
            data = try encoder.encode(library)
        } catch {
            throw SongMemoryStoreError.cannotEncodeLibrary
        }

        do {
            try data.write(to: try libraryURL(), options: .atomic)
        } catch {
            throw SongMemoryStoreError.cannotWriteLibrary
        }
    }

    static func load() throws -> SongMemoryLibrary {
        let url = try libraryURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SongMemoryLibrary()
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SongMemoryLibrary.self, from: data)
        } catch {
            throw SongMemoryStoreError.cannotReadLibrary
        }
    }

    private static func libraryURL() throws -> URL {
        try songMemoryDirectory().appendingPathComponent("library.json")
    }

    private static func songMemoryDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SongMemoryStoreError.cannotCreateDirectory
        }

        let directory = documentsDirectory.appendingPathComponent("SongMemory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw SongMemoryStoreError.cannotCreateDirectory
            }
        }
        return directory
    }
}
