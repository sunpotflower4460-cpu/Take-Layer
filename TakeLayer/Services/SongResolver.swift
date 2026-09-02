import Foundation

enum SongResolver {
    private struct TonalComparison {
        var score: Double
        var semitones: Int
        var coverage: Double
        var warpFraction: Double
    }

    private struct AlignmentState {
        var cost: Double
        var similaritySum: Double
        var pathLength: Int
        var warpSteps: Int
    }

    private struct ElasticAlignment {
        var score: Double
        var coverage: Double
        var warpFraction: Double
    }

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
            let hasTonalEvidence = lhs.tonalEvidence != nil && rhs.tonalEvidence != nil
            return SongMatchEvidence(
                duration: 1,
                energyEnvelope: 1,
                transientEnvelope: 1,
                tonal: hasTonalEvidence ? 1 : nil,
                transpositionSemitones: hasTonalEvidence ? 0 : nil,
                tonalAlignmentCoverage: hasTonalEvidence ? 1 : nil,
                tonalWarpFraction: hasTonalEvidence ? 0 : nil
            )
        }

        let tonalComparison: TonalComparison?
        if let lhsTonal = lhs.tonalEvidence,
           let rhsTonal = rhs.tonalEvidence {
            tonalComparison = compareTonal(lhsTonal, rhsTonal)
        } else {
            tonalComparison = nil
        }

        return SongMatchEvidence(
            duration: durationSimilarity(lhs.durationSec, rhs.durationSec),
            energyEnvelope: envelopeSimilarity(lhs.energyEnvelope, rhs.energyEnvelope),
            transientEnvelope: envelopeSimilarity(lhs.transientEnvelope, rhs.transientEnvelope),
            tonal: tonalComparison?.score,
            transpositionSemitones: tonalComparison?.semitones,
            tonalAlignmentCoverage: tonalComparison?.coverage,
            tonalWarpFraction: tonalComparison?.warpFraction
        )
    }

    static func combinedConfidence(_ evidence: SongMatchEvidence) -> Double {
        let weighted: Double
        if let tonal = evidence.tonal {
            weighted = evidence.duration * 0.15
                + evidence.energyEnvelope * 0.20
                + evidence.transientEnvelope * 0.15
                + tonal * 0.50
        } else {
            // Preserve the merged Resolver Evidence behavior for legacy fingerprints.
            weighted = evidence.duration * 0.25
                + evidence.energyEnvelope * 0.45
                + evidence.transientEnvelope * 0.30
        }
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

    /// Compares query tonal evidence (`lhs`) against a stored Arrangement (`rhs`).
    /// The returned semitone value is the rotation that best maps the stored pattern to the query.
    private static func compareTonal(
        _ lhs: TonalEvidenceVector,
        _ rhs: TonalEvidenceVector
    ) -> TonalComparison {
        guard lhs.globalPitchClass.count == TonalEvidenceVector.pitchClassCount,
              rhs.globalPitchClass.count == TonalEvidenceVector.pitchClassCount else {
            return TonalComparison(score: 0, semitones: 0, coverage: 0, warpFraction: 1)
        }

        var best = TonalComparison(score: -Double.infinity, semitones: 0, coverage: 0, warpFraction: 1)

        for rawShift in 0..<TonalEvidenceVector.pitchClassCount {
            let shiftedGlobal = shiftedPitchClasses(rhs.globalPitchClass, by: rawShift)
            let globalScore = cosineSimilarity(lhs.globalPitchClass, shiftedGlobal)
            let alignment = elasticSequenceAlignment(lhs, rhs, pitchShift: rawShift)
            let score = globalScore * 0.25 + alignment.score * 0.75
            let normalizedShift = rawShift <= 6 ? rawShift : rawShift - 12

            if score > best.score + 0.000_000_1 ||
                (abs(score - best.score) <= 0.000_000_1 && alignment.coverage > best.coverage + 0.000_000_1) ||
                (abs(score - best.score) <= 0.000_000_1 &&
                    abs(alignment.coverage - best.coverage) <= 0.000_000_1 &&
                    alignment.warpFraction < best.warpFraction - 0.000_000_1) ||
                (abs(score - best.score) <= 0.000_000_1 &&
                    abs(alignment.coverage - best.coverage) <= 0.000_000_1 &&
                    abs(alignment.warpFraction - best.warpFraction) <= 0.000_000_1 &&
                    abs(normalizedShift) < abs(best.semitones)) {
                best = TonalComparison(
                    score: score,
                    semitones: normalizedShift,
                    coverage: alignment.coverage,
                    warpFraction: alignment.warpFraction
                )
            }
        }

        best.score = min(1, max(0, best.score))
        return best
    }

    /// Small deterministic semi-global DTW-style alignment over the fixed 32-frame tonal evidence.
    /// It allows limited endpoint trimming plus horizontal / vertical steps for section stretching,
    /// but exposes both coverage and warp fraction so a high score cannot hide an aggressive path.
    private static func elasticSequenceAlignment(
        _ lhs: TonalEvidenceVector,
        _ rhs: TonalEvidenceVector,
        pitchShift: Int
    ) -> ElasticAlignment {
        let frameCount = TonalEvidenceVector.frameCount
        let endpointAllowance = 4
        let endpointRange = 0...endpointAllowance
        let endingRange = (frameCount - 1 - endpointAllowance)..<(frameCount)
        let warpTransitionPenalty = 0.08

        var similarities = Array(
            repeating: Array(repeating: 0.0, count: frameCount),
            count: frameCount
        )

        for queryFrame in 0..<frameCount {
            guard let lhsSlice = lhs.frame(at: queryFrame) else { continue }
            let lhsFrame = Array(lhsSlice)
            for storedFrame in 0..<frameCount {
                guard let rhsSlice = rhs.frame(at: storedFrame) else { continue }
                let shiftedRHS = shiftedPitchClasses(Array(rhsSlice), by: pitchShift)
                similarities[queryFrame][storedFrame] = cosineSimilarity(lhsFrame, shiftedRHS)
            }
        }

        var best = ElasticAlignment(score: 0, coverage: 0, warpFraction: 1)

        for queryStart in endpointRange {
            for storedStart in endpointRange {
                var states = Array(
                    repeating: Array<AlignmentState?>(repeating: nil, count: frameCount),
                    count: frameCount
                )

                states[queryStart][storedStart] = AlignmentState(
                    cost: 1 - similarities[queryStart][storedStart],
                    similaritySum: similarities[queryStart][storedStart],
                    pathLength: 1,
                    warpSteps: 0
                )

                for queryFrame in queryStart..<frameCount {
                    for storedFrame in storedStart..<frameCount {
                        if queryFrame == queryStart && storedFrame == storedStart { continue }

                        let localSimilarity = similarities[queryFrame][storedFrame]
                        let localCost = 1 - localSimilarity
                        var candidates: [AlignmentState] = []

                        if queryFrame > queryStart,
                           storedFrame > storedStart,
                           let previous = states[queryFrame - 1][storedFrame - 1] {
                            candidates.append(
                                advanced(
                                    previous,
                                    similarity: localSimilarity,
                                    localCost: localCost,
                                    warpStep: false,
                                    warpTransitionPenalty: warpTransitionPenalty
                                )
                            )
                        }

                        if queryFrame > queryStart,
                           let previous = states[queryFrame - 1][storedFrame] {
                            candidates.append(
                                advanced(
                                    previous,
                                    similarity: localSimilarity,
                                    localCost: localCost,
                                    warpStep: true,
                                    warpTransitionPenalty: warpTransitionPenalty
                                )
                            )
                        }

                        if storedFrame > storedStart,
                           let previous = states[queryFrame][storedFrame - 1] {
                            candidates.append(
                                advanced(
                                    previous,
                                    similarity: localSimilarity,
                                    localCost: localCost,
                                    warpStep: true,
                                    warpTransitionPenalty: warpTransitionPenalty
                                )
                            )
                        }

                        states[queryFrame][storedFrame] = candidates.min(by: betterAlignmentState)
                    }
                }

                for queryEnd in endingRange {
                    for storedEnd in endingRange {
                        guard queryEnd >= queryStart,
                              storedEnd >= storedStart,
                              let state = states[queryEnd][storedEnd] else {
                            continue
                        }

                        let averageSimilarity = state.similaritySum / Double(max(1, state.pathLength))
                        let warpFraction = Double(state.warpSteps) / Double(max(1, state.pathLength - 1))
                        let queryCoverage = Double(queryEnd - queryStart + 1) / Double(frameCount)
                        let storedCoverage = Double(storedEnd - storedStart + 1) / Double(frameCount)
                        let coverage = min(queryCoverage, storedCoverage)

                        // Coverage and warp penalties are deliberately modest. Their main role is
                        // to prevent a tiny or heavily stretched subsequence from looking perfect.
                        let score = min(
                            1,
                            max(
                                0,
                                averageSimilarity
                                    - warpFraction * 0.10
                                    - (1 - coverage) * 0.20
                            )
                        )

                        if score > best.score + 0.000_000_1 ||
                            (abs(score - best.score) <= 0.000_000_1 && coverage > best.coverage + 0.000_000_1) ||
                            (abs(score - best.score) <= 0.000_000_1 &&
                                abs(coverage - best.coverage) <= 0.000_000_1 &&
                                warpFraction < best.warpFraction) {
                            best = ElasticAlignment(
                                score: score,
                                coverage: coverage,
                                warpFraction: warpFraction
                            )
                        }
                    }
                }
            }
        }

        return best
    }

    private static func advanced(
        _ state: AlignmentState,
        similarity: Double,
        localCost: Double,
        warpStep: Bool,
        warpTransitionPenalty: Double
    ) -> AlignmentState {
        AlignmentState(
            cost: state.cost + localCost + (warpStep ? warpTransitionPenalty : 0),
            similaritySum: state.similaritySum + similarity,
            pathLength: state.pathLength + 1,
            warpSteps: state.warpSteps + (warpStep ? 1 : 0)
        )
    }

    private static func betterAlignmentState(_ lhs: AlignmentState, _ rhs: AlignmentState) -> Bool {
        if abs(lhs.cost - rhs.cost) > 0.000_000_1 {
            return lhs.cost < rhs.cost
        }
        if lhs.warpSteps != rhs.warpSteps {
            return lhs.warpSteps < rhs.warpSteps
        }
        return lhs.pathLength < rhs.pathLength
    }

    private static func shiftedPitchClasses(_ values: [Double], by semitones: Int) -> [Double] {
        guard values.count == TonalEvidenceVector.pitchClassCount else { return values }
        let shift = ((semitones % 12) + 12) % 12
        return (0..<TonalEvidenceVector.pitchClassCount).map { outputIndex in
            let sourceIndex = (outputIndex - shift + 12) % 12
            return values[sourceIndex]
        }
    }

    private static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot = zip(lhs, rhs).reduce(0.0) { $0 + $1.0 * $1.1 }
        let lhsNorm = sqrt(lhs.reduce(0.0) { $0 + $1 * $1 })
        let rhsNorm = sqrt(rhs.reduce(0.0) { $0 + $1 * $1 })
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return min(1, max(0, dot / (lhsNorm * rhsNorm)))
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
