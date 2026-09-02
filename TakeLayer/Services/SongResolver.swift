import Foundation

enum SongResolver {
    static func resolve(
        query: AudioEvidenceVector,
        songMemory: SongMemoryLibrary,
        evidenceLibrary: SongResolverEvidenceLibrary,
        maximumCandidates: Int = 5
    ) -> SongMatchResult {
        var bestByArrangement: [UUID: SongMatchCandidate] = [:]

        for fingerprint in evidenceLibrary.fingerprints {
            guard let arrangement = songMemory.arrangement(for: fingerprint.arrangementID),
                  arrangement.fingerprintIDs.contains(fingerprint.id.uuidString) else {
                continue
            }

            let evidence = compare(query, fingerprint.evidence)
            let confidence = combinedConfidence(evidence)
            let candidate = SongMatchCandidate(
                songID: arrangement.songID,
                arrangementID: arrangement.id,
                fingerprintID: fingerprint.id,
                confidence: confidence,
                evidence: evidence
            )

            if let current = bestByArrangement[arrangement.id] {
                if candidate.confidence > current.confidence {
                    bestByArrangement[arrangement.id] = candidate
                }
            } else {
                bestByArrangement[arrangement.id] = candidate
            }
        }

        let candidates = bestByArrangement.values
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.arrangementID.uuidString < rhs.arrangementID.uuidString
            }
            .prefix(max(0, maximumCandidates))

        let resultCandidates = Array(candidates)
        return SongMatchResult(
            candidates: resultCandidates,
            resolvedSongID: nil,
            resolvedArrangementID: nil,
            needsUserConfirmation: !resultCandidates.isEmpty
        )
    }

    static func compare(_ lhs: AudioEvidenceVector, _ rhs: AudioEvidenceVector) -> SongMatchEvidence {
        if lhs.signature == rhs.signature {
            return SongMatchEvidence(duration: 1, energyEnvelope: 1, transientEnvelope: 1)
        }

        return SongMatchEvidence(
            duration: durationSimilarity(lhs.durationSec, rhs.durationSec),
            energyEnvelope: envelopeSimilarity(lhs.energyEnvelope, rhs.energyEnvelope),
            transientEnvelope: envelopeSimilarity(lhs.transientEnvelope, rhs.transientEnvelope)
        )
    }

    static func combinedConfidence(_ evidence: SongMatchEvidence) -> Double {
        let weighted = evidence.duration * 0.25
            + evidence.energyEnvelope * 0.45
            + evidence.transientEnvelope * 0.30
        return min(1, max(0, weighted))
    }

    private static func durationSimilarity(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs > 0, rhs > 0 else { return 0 }
        let relativeDifference = abs(lhs - rhs) / max(lhs, rhs)
        return min(1, max(0, 1 - (relativeDifference / 0.20)))
    }

    private static func envelopeSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        let lhsMean = lhs.reduce(0, +) / Double(lhs.count)
        let rhsMean = rhs.reduce(0, +) / Double(rhs.count)
        let lhsCentered = lhs.map { $0 - lhsMean }
        let rhsCentered = rhs.map { $0 - rhsMean }

        let numerator = zip(lhsCentered, rhsCentered).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
        let lhsNorm = sqrt(lhsCentered.reduce(0) { $0 + $1 * $1 })
        let rhsNorm = sqrt(rhsCentered.reduce(0) { $0 + $1 * $1 })

        if lhsNorm == 0 || rhsNorm == 0 {
            return lhs == rhs ? 1 : 0
        }

        let correlation = numerator / (lhsNorm * rhsNorm)
        return min(1, max(0, (correlation + 1) / 2))
    }
}

extension SongMemoryLibrary {
    mutating func attachFingerprintID(_ fingerprintID: UUID, to arrangementID: UUID, now: Date = Date()) {
        guard let index = arrangements.firstIndex(where: { $0.id == arrangementID }) else { return }
        let value = fingerprintID.uuidString
        if !arrangements[index].fingerprintIDs.contains(value) {
            arrangements[index].fingerprintIDs.append(value)
            arrangements[index].updatedAt = now
        }
    }
}
