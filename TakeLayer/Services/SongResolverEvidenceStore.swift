import Foundation

enum SongResolverEvidenceStoreError: LocalizedError {
    case cannotCreateDirectory
    case cannotEncodeLibrary
    case cannotWriteLibrary
    case cannotReadLibrary

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory:
            return "Song Resolver Evidence保存先を作成できませんでした。"
        case .cannotEncodeLibrary:
            return "Song Resolver Evidenceを保存形式へ変換できませんでした。"
        case .cannotWriteLibrary:
            return "Song Resolver Evidenceを保存できませんでした。"
        case .cannotReadLibrary:
            return "Song Resolver Evidenceを読み込めませんでした。"
        }
    }
}

enum SongResolverEvidenceStore {
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

    static func save(_ library: SongResolverEvidenceLibrary) throws {
        let data: Data
        do {
            data = try encoder.encode(library)
        } catch {
            throw SongResolverEvidenceStoreError.cannotEncodeLibrary
        }

        do {
            try data.write(to: try libraryURL(), options: .atomic)
        } catch {
            throw SongResolverEvidenceStoreError.cannotWriteLibrary
        }
    }

    static func load() throws -> SongResolverEvidenceLibrary {
        let url = try libraryURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SongResolverEvidenceLibrary()
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SongResolverEvidenceLibrary.self, from: data)
        } catch {
            throw SongResolverEvidenceStoreError.cannotReadLibrary
        }
    }

    private static func libraryURL() throws -> URL {
        try resolverDirectory().appendingPathComponent("evidence.json")
    }

    private static func resolverDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SongResolverEvidenceStoreError.cannotCreateDirectory
        }

        let directory = documentsDirectory
            .appendingPathComponent("SongMemory", isDirectory: true)
            .appendingPathComponent("ResolverEvidence", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw SongResolverEvidenceStoreError.cannotCreateDirectory
            }
        }
        return directory
    }
}
