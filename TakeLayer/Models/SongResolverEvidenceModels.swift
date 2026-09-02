import Foundation

struct AudioEvidenceVector: Codable, Equatable, Sendable {
    static let bucketCount = 64

    var durationSec: Double
    var sampleRate: Double
    var channelCount: Int
    var energyEnvelope: [Double]
    var transientEnvelope: [Double]
    var signature: String
}

struct ArrangementAudioFingerprint: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var arrangementID: UUID
    var evidence: AudioEvidenceVector
    var sourceFileName: String?
    var createdAt: Date
}

struct SongMatchEvidence: Codable, Equatable, Sendable {
    var duration: Double
    var energyEnvelope: Double
    var transientEnvelope: Double
}

struct SongMatchCandidate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { arrangementID }
    var songID: UUID
    var arrangementID: UUID
    var fingerprintID: UUID
    var confidence: Double
    var evidence: SongMatchEvidence
}

struct SongMatchResult: Codable, Equatable, Sendable {
    var candidates: [SongMatchCandidate]
    var resolvedSongID: UUID?
    var resolvedArrangementID: UUID?
    var needsUserConfirmation: Bool
}

struct SongResolverEvidenceLibrary: Codable, Equatable, Sendable {
    var fingerprints: [ArrangementAudioFingerprint] = []

    func fingerprints(for arrangementID: UUID) -> [ArrangementAudioFingerprint] {
        fingerprints.filter { $0.arrangementID == arrangementID }
    }

    func fingerprint(id: UUID) -> ArrangementAudioFingerprint? {
        fingerprints.first { $0.id == id }
    }

    @discardableResult
    mutating func register(
        arrangementID: UUID,
        evidence: AudioEvidenceVector,
        sourceFileName: String?,
        now: Date = Date()
    ) -> ArrangementAudioFingerprint {
        if let existing = fingerprints.first(where: {
            $0.arrangementID == arrangementID && $0.evidence.signature == evidence.signature
        }) {
            return existing
        }

        let fingerprint = ArrangementAudioFingerprint(
            id: UUID(),
            arrangementID: arrangementID,
            evidence: evidence,
            sourceFileName: sourceFileName,
            createdAt: now
        )
        fingerprints.append(fingerprint)
        return fingerprint
    }
}
