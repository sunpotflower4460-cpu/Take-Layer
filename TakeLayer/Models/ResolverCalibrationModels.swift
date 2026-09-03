import Foundation

enum ResolverCalibrationRelationship: String, Codable, CaseIterable, Sendable {
    case sameArrangement
    case sameSongDifferentArrangement
    case differentSong

    var isSameSong: Bool {
        self != .differentSong
    }
}

struct ResolverCalibrationCase: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var relationship: ResolverCalibrationRelationship
    var queryEvidence: AudioEvidenceVector
    var referenceEvidence: AudioEvidenceVector
    var notes: String?
}

struct ResolverCalibrationDataset: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var name: String
    var cases: [ResolverCalibrationCase]
}

struct ResolverCalibrationObservation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { caseID }
    var caseID: UUID
    var caseName: String
    var relationship: ResolverCalibrationRelationship
    var confidence: Double
    var evidence: SongMatchEvidence
}

struct ResolverCalibrationDistribution: Codable, Equatable, Sendable {
    var count: Int
    var minimum: Double?
    var maximum: Double?
    var mean: Double?
    var median: Double?
}

struct ResolverCalibrationThresholdMetrics: Codable, Equatable, Sendable {
    var threshold: Double
    var truePositive: Int
    var falsePositive: Int
    var trueNegative: Int
    var falseNegative: Int
    var precision: Double
    var recall: Double
    var specificity: Double
    var f1: Double
    var balancedAccuracy: Double
}

struct ResolverCalibrationReport: Codable, Equatable, Sendable {
    var datasetName: String
    var totalCases: Int
    var observations: [ResolverCalibrationObservation]
    var sameArrangement: ResolverCalibrationDistribution
    var sameSongDifferentArrangement: ResolverCalibrationDistribution
    var differentSong: ResolverCalibrationDistribution
    /// Minimum confidence among all labeled same-song observations.
    var minimumPositiveConfidence: Double?
    /// Maximum confidence among all labeled different-song observations.
    var maximumNegativeConfidence: Double?
    /// Positive means the observed same-song and different-song confidence ranges do not overlap.
    var confidenceGap: Double?
    var thresholdMetrics: [ResolverCalibrationThresholdMetrics]
}
