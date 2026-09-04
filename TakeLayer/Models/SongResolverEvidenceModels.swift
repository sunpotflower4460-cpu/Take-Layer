import Foundation

struct TonalEvidenceVector: Codable, Equatable, Sendable {
    static let pitchClassCount = 12
    static let frameCount = 32

    var pitchClassFrames: [Double]
    var globalPitchClass: [Double]
    var referenceAHz: Double

    func frame(at index: Int) -> ArraySlice<Double>? {
        guard index >= 0, index < Self.frameCount else { return nil }
        let start = index * Self.pitchClassCount
        let end = start + Self.pitchClassCount
        guard pitchClassFrames.count >= end else { return nil }
        return pitchClassFrames[start..<end]
    }
}

struct AudioEvidenceVector: Codable, Equatable, Sendable {
    static let bucketCount = 64

    var durationSec: Double
    var sampleRate: Double
    var channelCount: Int
    var energyEnvelope: [Double]
    var transientEnvelope: [Double]
    var signature: String
    var tonalEvidence: TonalEvidenceVector? = nil
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
    var tonal: Double? = nil
    /// Semitone shift that best maps the stored Arrangement fingerprint to the query WAV.
    /// Example: +2 means the query is best explained as two semitones above the stored tonal pattern.
    var transpositionSemitones: Int? = nil
    /// Fraction of the shorter 32-frame tonal sequence included in the best elastic alignment.
    /// 1.0 means the alignment used the full normalized structure; lower values indicate endpoint trimming.
    var tonalAlignmentCoverage: Double? = nil
    /// Fraction of non-diagonal DTW-style path steps in the best tonal alignment.
    /// Higher values mean more structural stretching / compression was required.
    var tonalWarpFraction: Double? = nil
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
        if let index = fingerprints.firstIndex(where: { existing in
            guard existing.arrangementID == arrangementID,
                  existing.evidence.signature == evidence.signature else {
                return false
            }

            // The legacy signature intentionally excludes tonal evidence. It is
            // therefore only safe as a deduplication key when at least one side
            // is legacy (no tonal data) or both tonal vectors are actually equal.
            switch (existing.evidence.tonalEvidence, evidence.tonalEvidence) {
            case (nil, _), (_, nil):
                return true
            case (let existingTonal?, let newTonal?):
                return existingTonal == newTonal
            }
        }) {
            // Tonal Evidence upgrades a legacy local fingerprint in place.
            if fingerprints[index].evidence.tonalEvidence == nil,
               evidence.tonalEvidence != nil {
                fingerprints[index].evidence.tonalEvidence = evidence.tonalEvidence
                if let sourceFileName {
                    fingerprints[index].sourceFileName = sourceFileName
                }
            }
            return fingerprints[index]
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
