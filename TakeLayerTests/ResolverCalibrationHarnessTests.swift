import Foundation
import XCTest
@testable import TakeLayer

final class ResolverCalibrationHarnessTests: XCTestCase {
    func testCalibrationReportSeparatesLabeledPositiveAndNegativeFixtures() throws {
        let exact = makeVector(
            signature: "exact",
            tonal: makeTonalEvidence(baseKey: 0, roots: [0, 5, 7, 0])
        )
        let stored = makeVector(
            signature: "stored",
            tonal: makeTonalEvidence(baseKey: 0, roots: [0, 0, 5, 5, 7, 7, 0, 0])
        )
        let live = makeVector(
            duration: 205,
            signature: "live",
            tonal: makeTonalEvidence(baseKey: 2, roots: [0, 0, 0, 5, 5, 5, 7, 7, 0, 0])
        )
        let unrelated = makeVector(
            duration: 260,
            energy: fallingEnvelope(),
            transient: Array(repeating: 0.1, count: AudioEvidenceVector.bucketCount),
            signature: "unrelated",
            tonal: makeTonalEvidence(baseKey: 4, roots: [0, 3, 8, 10, 1, 6, 11, 4])
        )

        let dataset = ResolverCalibrationDataset(
            name: "synthetic separation",
            cases: [
                ResolverCalibrationCase(
                    id: UUID(),
                    name: "exact arrangement",
                    relationship: .sameArrangement,
                    queryEvidence: exact,
                    referenceEvidence: exact,
                    notes: nil
                ),
                ResolverCalibrationCase(
                    id: UUID(),
                    name: "live transposed",
                    relationship: .sameSongDifferentArrangement,
                    queryEvidence: live,
                    referenceEvidence: stored,
                    notes: nil
                ),
                ResolverCalibrationCase(
                    id: UUID(),
                    name: "different song",
                    relationship: .differentSong,
                    queryEvidence: unrelated,
                    referenceEvidence: stored,
                    notes: nil
                )
            ]
        )

        let report = try ResolverCalibrationHarness.evaluate(dataset, thresholds: [0.5, 0.8, 0.9])

        XCTAssertEqual(report.totalCases, 3)
        XCTAssertEqual(report.sameArrangement.count, 1)
        XCTAssertEqual(report.sameSongDifferentArrangement.count, 1)
        XCTAssertEqual(report.differentSong.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(report.confidenceGap), 0)
        XCTAssertGreaterThan(
            try XCTUnwrap(report.minimumPositiveConfidence),
            try XCTUnwrap(report.maximumNegativeConfidence)
        )

        let threshold = try XCTUnwrap(report.thresholdMetrics.first(where: { abs($0.threshold - 0.8) < 0.000_001 }))
        XCTAssertEqual(threshold.truePositive, 2)
        XCTAssertEqual(threshold.falsePositive, 0)
        XCTAssertEqual(threshold.trueNegative, 1)
        XCTAssertEqual(threshold.falseNegative, 0)
        XCTAssertEqual(threshold.precision, 1, accuracy: 0.000_001)
        XCTAssertEqual(threshold.recall, 1, accuracy: 0.000_001)
        XCTAssertEqual(threshold.specificity, 1, accuracy: 0.000_001)
        XCTAssertEqual(threshold.f1, 1, accuracy: 0.000_001)
        XCTAssertEqual(threshold.balancedAccuracy, 1, accuracy: 0.000_001)
    }

    func testDatasetAndReportJSONRoundTrip() throws {
        let evidence = makeVector(
            signature: "roundtrip",
            tonal: makeTonalEvidence(baseKey: 0, roots: [0, 5, 7, 0])
        )
        let dataset = ResolverCalibrationDataset(
            name: "roundtrip",
            cases: [
                ResolverCalibrationCase(
                    id: UUID(),
                    name: "case",
                    relationship: .sameArrangement,
                    queryEvidence: evidence,
                    referenceEvidence: evidence,
                    notes: "derived evidence only"
                )
            ]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeLayer-Calibration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let datasetURL = directory.appendingPathComponent("dataset.json")
        let reportURL = directory.appendingPathComponent("report.json")
        try ResolverCalibrationHarness.save(dataset, to: datasetURL)
        let loaded = try ResolverCalibrationHarness.loadDataset(from: datasetURL)
        XCTAssertEqual(loaded, dataset)

        let report = try ResolverCalibrationHarness.evaluate(loaded, thresholds: [0, 0.5, 1])
        try ResolverCalibrationHarness.save(report, to: reportURL)
        let reportData = try Data(contentsOf: reportURL)
        let decodedReport = try JSONDecoder().decode(ResolverCalibrationReport.self, from: reportData)
        XCTAssertEqual(decodedReport, report)
    }

    func testUnsupportedDatasetSchemaIsRejected() {
        let dataset = ResolverCalibrationDataset(
            schemaVersion: ResolverCalibrationDataset.currentSchemaVersion + 1,
            name: "future",
            cases: []
        )

        XCTAssertThrowsError(try ResolverCalibrationHarness.evaluate(dataset)) { error in
            guard case ResolverCalibrationHarnessError.unsupportedSchemaVersion(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, ResolverCalibrationDataset.currentSchemaVersion + 1)
        }
    }

    func testEmptyDatasetProducesInspectableEmptyReport() throws {
        let report = try ResolverCalibrationHarness.evaluate(
            ResolverCalibrationDataset(name: "empty", cases: []),
            thresholds: [-1, 0.5, 2, 0.5]
        )

        XCTAssertEqual(report.totalCases, 0)
        XCTAssertEqual(report.sameArrangement.count, 0)
        XCTAssertNil(report.sameArrangement.mean)
        XCTAssertNil(report.minimumPositiveConfidence)
        XCTAssertNil(report.maximumNegativeConfidence)
        XCTAssertNil(report.confidenceGap)
        XCTAssertEqual(report.thresholdMetrics.map(\.threshold), [0, 0.5, 1])
    }

    private func makeVector(
        duration: Double = 180,
        energy: [Double]? = nil,
        transient: [Double]? = nil,
        signature: String,
        tonal: TonalEvidenceVector
    ) -> AudioEvidenceVector {
        AudioEvidenceVector(
            durationSec: duration,
            sampleRate: 48_000,
            channelCount: 2,
            energyEnvelope: energy ?? risingEnvelope(),
            transientEnvelope: transient ?? alternatingEnvelope(),
            signature: signature,
            tonalEvidence: tonal
        )
    }

    private func makeTonalEvidence(baseKey: Int, roots: [Int]) -> TonalEvidenceVector {
        var frames: [Double] = []
        var global = Array(repeating: 0.0, count: TonalEvidenceVector.pitchClassCount)

        for frameIndex in 0..<TonalEvidenceVector.frameCount {
            let sourceIndex = min(
                roots.count - 1,
                Int(Double(frameIndex) / Double(TonalEvidenceVector.frameCount) * Double(roots.count))
            )
            let root = (baseKey + roots[sourceIndex] + 12) % 12
            var frame = Array(repeating: 0.0, count: TonalEvidenceVector.pitchClassCount)
            frame[root] = 0.55
            frame[(root + 4) % 12] = 0.25
            frame[(root + 7) % 12] = 0.20
            frames.append(contentsOf: frame)
            for pitchClass in 0..<12 {
                global[pitchClass] += frame[pitchClass]
            }
        }

        let total = global.reduce(0, +)
        global = global.map { $0 / total }
        return TonalEvidenceVector(
            pitchClassFrames: frames,
            globalPitchClass: global,
            referenceAHz: 440
        )
    }

    private func risingEnvelope() -> [Double] {
        (0..<AudioEvidenceVector.bucketCount).map { Double($0 + 1) / Double(AudioEvidenceVector.bucketCount) }
    }

    private func fallingEnvelope() -> [Double] {
        Array(risingEnvelope().reversed())
    }

    private func alternatingEnvelope() -> [Double] {
        (0..<AudioEvidenceVector.bucketCount).map { $0.isMultiple(of: 2) ? 0.2 : 0.9 }
    }
}
