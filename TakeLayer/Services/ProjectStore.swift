import Foundation

enum ProjectStoreError: LocalizedError {
    case cannotCreateProjectsDirectory
    case cannotEncodeProject
    case cannotWriteProject
    case cannotReadProject

    var errorDescription: String? {
        switch self {
        case .cannotCreateProjectsDirectory:
            return "Project保存先を作成できませんでした。"
        case .cannotEncodeProject:
            return "Project情報を保存形式へ変換できませんでした。"
        case .cannotWriteProject:
            return "Project情報を保存できませんでした。"
        case .cannotReadProject:
            return "保存済みProjectを読み込めませんでした。"
        }
    }
}

enum ProjectStore {
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

    static func save(_ project: ProjectDraft) throws {
        let data: Data
        do {
            data = try encoder.encode(project)
        } catch {
            throw ProjectStoreError.cannotEncodeProject
        }

        let url = try projectURL(for: project.id)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ProjectStoreError.cannotWriteProject
        }
    }

    static func loadMostRecent() throws -> ProjectDraft? {
        let directory = try projectsDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let jsonURLs = urls.filter { $0.pathExtension.lowercased() == "json" }
        let sorted = jsonURLs.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        guard let url = sorted.first else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ProjectDraft.self, from: data)
        } catch {
            throw ProjectStoreError.cannotReadProject
        }
    }

    private static func projectURL(for id: UUID) throws -> URL {
        try projectsDirectory().appendingPathComponent("\(id.uuidString).json")
    }

    private static func projectsDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ProjectStoreError.cannotCreateProjectsDirectory
        }
        let directory = documentsDirectory.appendingPathComponent("Projects", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw ProjectStoreError.cannotCreateProjectsDirectory
            }
        }
        return directory
    }
}
