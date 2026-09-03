import Foundation

struct ResolverPrivateCorpusManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var name: String
    var cases: [ResolverPrivateCorpusManifestCase]
}

struct ResolverPrivateCorpusManifestCase: Codable, Equatable, Sendable {
    /// Optional stable identifier. If omitted, the runner derives a deterministic UUID from
    /// manifest name + case metadata + relative paths without storing raw audio bytes.
    var id: UUID? = nil
    var name: String
    var relationship: ResolverCalibrationRelationship
    var queryPath: String
    var referencePath: String
    var notes: String? = nil
}

struct ResolverPrivateCorpusRunResult: Equatable, Sendable {
    var dataset: ResolverCalibrationDataset
    var report: ResolverCalibrationReport
    var datasetURL: URL?
    var reportURL: URL?
}
