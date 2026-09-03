import Foundation

enum ResolverCalibrationHarnessError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Resolver calibration dataset schema version \(version) is not supported."
        }
    }
}

enum ResolverCalibrationHarness {
    static let defaultThresholds: [Double] = (0...20).map { Double($0) / 20.0 }

    /// Creates one labeled benchmark case directly from two real completed-WAV files.
    /// The raw WAV files are not embedded in the returned dataset; only deterministic evidence is retained.
    static func makeCase(
        name: String,
        relationship: ResolverCalibrationRelationship,
        queryWAVURL: URL,
        referenceWAVURL: URL,
        notes: String? = nil
    ) throws -> ResolverCalibrationCase {
        ResolverCalibrationCase(
            id: UUID(),
            name: name,
            relationship: relationship,
            queryEvidence: try AudioEvidenceExtractor.extract(from: queryWAVURL),
            referenceEvidence: try AudioEvidenceExtractor.extract(from: referenceWAVURL),
            notes: notes
        )
    }

    static func evaluate(
        _ dataset: ResolverCalibrationDataset,
        thresholds: [Double] = defaultThresholds
    ) throws -> ResolverCalibrationReport {
        guard dataset.schemaVersion == ResolverCalibrationDataset.currentSchemaVersion else {
            throw ResolverCalibrationHarnessError.unsupportedSchemaVersion(dataset.schemaVersion)
        }

        let observations = dataset.cases.map { benchmarkCase -> ResolverCalibrationObservation in
            let evidence = SongResolver.compare(
                benchmarkCase.queryEvidence,
                benchmarkCase.referenceEvidence
            )
            return ResolverCalibrationObservation(
                caseID: benchmarkCase.id,
                caseName: benchmarkCase.name,
                relationship: benchmarkCase.relationship,
                confidence: SongResolver.combinedConfidence(evidence),
                evidence: evidence
            )
        }

        let positiveConfidences = observations
            .filter { $0.relationship.isSameSong }
            .map(\.confidence)
        let negativeConfidences = observations
            .filter { !$0.relationship.isSameSong }
            .map(\.confidence)
        let minimumPositive = positiveConfidences.min()
        let maximumNegative = negativeConfidences.max()
        let confidenceGap: Double?
        if let minimumPositive, let maximumNegative {
            confidenceGap = minimumPositive - maximumNegative
        } else {
            confidenceGap = nil
        }

        let normalizedThresholds = Array(
            Set(thresholds.map { min(1, max(0, $0)) })
        ).sorted()

        return ResolverCalibrationReport(
            datasetName: dataset.name,
            totalCases: observations.count,
            observations: observations,
            sameArrangement: distribution(
                observations.filter { $0.relationship == .sameArrangement }.map(\.confidence)
            ),
            sameSongDifferentArrangement: distribution(
                observations.filter { $0.relationship == .sameSongDifferentArrangement }.map(\.confidence)
            ),
            differentSong: distribution(
                observations.filter { $0.relationship == .differentSong }.map(\.confidence)
            ),
            minimumPositiveConfidence: minimumPositive,
            maximumNegativeConfidence: maximumNegative,
            confidenceGap: confidenceGap,
            thresholdMetrics: normalizedThresholds.map { thresholdMetrics($0, observations: observations) }
        )
    }

    static func loadDataset(from url: URL) throws -> ResolverCalibrationDataset {
        let data = try Data(contentsOf: url)
        let dataset = try JSONDecoder().decode(ResolverCalibrationDataset.self, from: data)
        guard dataset.schemaVersion == ResolverCalibrationDataset.currentSchemaVersion else {
            throw ResolverCalibrationHarnessError.unsupportedSchemaVersion(dataset.schemaVersion)
        }
        return dataset
    }

    static func save(_ dataset: ResolverCalibrationDataset, to url: URL) throws {
        try encoded(dataset).write(to: url, options: .atomic)
    }

    static func save(_ report: ResolverCalibrationReport, to url: URL) throws {
        try encoded(report).write(to: url, options: .atomic)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func distribution(_ values: [Double]) -> ResolverCalibrationDistribution {
        guard !values.isEmpty else {
            return ResolverCalibrationDistribution(
                count: 0,
                minimum: nil,
                maximum: nil,
                mean: nil,
                median: nil
            )
        }

        let sorted = values.sorted()
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            median = (sorted[upper - 1] + sorted[upper]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }

        return ResolverCalibrationDistribution(
            count: sorted.count,
            minimum: sorted.first,
            maximum: sorted.last,
            mean: sorted.reduce(0, +) / Double(sorted.count),
            median: median
        )
    }

    private static func thresholdMetrics(
        _ threshold: Double,
        observations: [ResolverCalibrationObservation]
    ) -> ResolverCalibrationThresholdMetrics {
        var truePositive = 0
        var falsePositive = 0
        var trueNegative = 0
        var falseNegative = 0

        for observation in observations {
            let expectedPositive = observation.relationship.isSameSong
            let predictedPositive = observation.confidence >= threshold

            switch (expectedPositive, predictedPositive) {
            case (true, true):
                truePositive += 1
            case (false, true):
                falsePositive += 1
            case (false, false):
                trueNegative += 1
            case (true, false):
                falseNegative += 1
            }
        }

        let precision = ratio(truePositive, truePositive + falsePositive)
        let recall = ratio(truePositive, truePositive + falseNegative)
        let specificity = ratio(trueNegative, trueNegative + falsePositive)
        let f1 = precision + recall > 0
            ? 2 * precision * recall / (precision + recall)
            : 0
        let balancedAccuracy = (recall + specificity) / 2

        return ResolverCalibrationThresholdMetrics(
            threshold: threshold,
            truePositive: truePositive,
            falsePositive: falsePositive,
            trueNegative: trueNegative,
            falseNegative: falseNegative,
            precision: precision,
            recall: recall,
            specificity: specificity,
            f1: f1,
            balancedAccuracy: balancedAccuracy
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}
