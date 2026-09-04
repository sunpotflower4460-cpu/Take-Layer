import AVFoundation
import Foundation
import XCTest
@testable import TakeLayer

final class ResolverPrivateCorpusRunnerTests: XCTestCase {
    func testRunnerBuildsDeterministicDatasetAndReportFromLocalWAVManifest() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSyntheticWAV(to: root.appendingPathComponent("studio.wav"), frequency: 220)
        try writeSyntheticWAV(to: root.appendingPathComponent("acoustic.wav"), frequency: 246.94)

        let manifest = ResolverPrivateCorpusManifest(
            name: "private corpus",
            cases: [
                ResolverPrivateCorpusManifestCase(
                    name: "studio vs acoustic",
                    relationship: .sameSongDifferentArrangement,
                    queryPath: "acoustic.wav",
                    referencePath: "studio.wav"
                )
            ]
        )

        let first = try ResolverPrivateCorpusRunner.buildDataset(manifest: manifest, corpusRoot: root)
        let second = try ResolverPrivateCorpusRunner.buildDataset(manifest: manifest, corpusRoot: root)
        XCTAssertEqual(first.cases.count, 1)
        XCTAssertEqual(first.cases.first?.id, second.cases.first?.id)
        XCTAssertNotNil(first.cases.first?.queryEvidence.tonalEvidence)
        XCTAssertNotNil(first.cases.first?.referenceEvidence.tonalEvidence)

        let manifestURL = root.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let datasetURL = root.appendingPathComponent("derived/dataset.json")
        let reportURL = root.appendingPathComponent("derived/report.json")
        let result = try ResolverPrivateCorpusRunner.run(
            manifestURL: manifestURL,
            datasetOutputURL: datasetURL,
            reportOutputURL: reportURL,
            thresholds: [0.5, 0.8]
        )

        XCTAssertEqual(result.dataset.cases.count, 1)
        XCTAssertEqual(result.report.totalCases, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: datasetURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
    }

    func testAbsolutePathIsRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let absolute = root.appendingPathComponent("audio.wav")
        try writeSyntheticWAV(to: absolute, frequency: 220)

        let manifest = manifestWith(queryPath: absolute.path, referencePath: "missing.wav")
        XCTAssertThrowsError(try ResolverPrivateCorpusRunner.buildDataset(manifest: manifest, corpusRoot: root)) { error in
            guard case ResolverPrivateCorpusRunnerError.absolutePathNotAllowed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testParentTraversalOutsideRootIsRejected() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("Private", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeSyntheticWAV(to: parent.appendingPathComponent("outside.wav"), frequency: 220)
        try writeSyntheticWAV(to: root.appendingPathComponent("inside.wav"), frequency: 246.94)

        let manifest = manifestWith(queryPath: "../outside.wav", referencePath: "inside.wav")
        XCTAssertThrowsError(try ResolverPrivateCorpusRunner.buildDataset(manifest: manifest, corpusRoot: root)) { error in
            guard case ResolverPrivateCorpusRunnerError.pathEscapesCorpusRoot = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDuplicateExplicitCaseIDsAreRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSyntheticWAV(to: root.appendingPathComponent("a.wav"), frequency: 220)
        try writeSyntheticWAV(to: root.appendingPathComponent("b.wav"), frequency: 246.94)
        let duplicateID = UUID()
        let manifest = ResolverPrivateCorpusManifest(
            name: "duplicates",
            cases: [
                ResolverPrivateCorpusManifestCase(
                    id: duplicateID,
                    name: "one",
                    relationship: .sameArrangement,
                    queryPath: "a.wav",
                    referencePath: "b.wav"
                ),
                ResolverPrivateCorpusManifestCase(
                    id: duplicateID,
                    name: "two",
                    relationship: .differentSong,
                    queryPath: "b.wav",
                    referencePath: "a.wav"
                )
            ]
        )

        XCTAssertThrowsError(try ResolverPrivateCorpusRunner.buildDataset(manifest: manifest, corpusRoot: root)) { error in
            guard case ResolverPrivateCorpusRunnerError.duplicateCaseID(let id) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, duplicateID)
        }
    }

    func testAllCasePathsArePreflightedBeforeEvidenceExtractionStarts() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: root.appendingPathComponent("a.wav"))
        try Data([0]).write(to: root.appendingPathComponent("b.wav"))

        let manifest = ResolverPrivateCorpusManifest(
            name: "preflight",
            cases: [
                ResolverPrivateCorpusManifestCase(
                    name: "valid first case",
                    relationship: .sameArrangement,
                    queryPath: "a.wav",
                    referencePath: "b.wav"
                ),
                ResolverPrivateCorpusManifestCase(
                    name: "missing later case",
                    relationship: .differentSong,
                    queryPath: "a.wav",
                    referencePath: "missing.wav"
                )
            ]
        )

        var extractionCount = 0
        XCTAssertThrowsError(
            try ResolverPrivateCorpusRunner.buildDataset(
                manifest: manifest,
                corpusRoot: root,
                evidenceExtractor: { url in
                    extractionCount += 1
                    return stubEvidence(for: url)
                }
            )
        ) { error in
            guard case ResolverPrivateCorpusRunnerError.missingFile(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "missing.wav")
        }
        XCTAssertEqual(extractionCount, 0)
    }

    func testRepeatedWAVReferencesAreExtractedOnlyOncePerDatasetBuild() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.wav", "b.wav", "c.wav"] {
            try Data([0]).write(to: root.appendingPathComponent(name))
        }

        let manifest = ResolverPrivateCorpusManifest(
            name: "cache",
            cases: [
                ResolverPrivateCorpusManifestCase(
                    name: "a vs b",
                    relationship: .sameArrangement,
                    queryPath: "a.wav",
                    referencePath: "b.wav"
                ),
                ResolverPrivateCorpusManifestCase(
                    name: "a vs c",
                    relationship: .sameSongDifferentArrangement,
                    queryPath: "a.wav",
                    referencePath: "c.wav"
                ),
                ResolverPrivateCorpusManifestCase(
                    name: "b vs a",
                    relationship: .differentSong,
                    queryPath: "b.wav",
                    referencePath: "a.wav"
                )
            ]
        )

        var extractionCounts: [String: Int] = [:]
        let dataset = try ResolverPrivateCorpusRunner.buildDataset(
            manifest: manifest,
            corpusRoot: root,
            evidenceExtractor: { url in
                extractionCounts[url.lastPathComponent, default: 0] += 1
                return stubEvidence(for: url)
            }
        )

        XCTAssertEqual(dataset.cases.count, 3)
        XCTAssertEqual(extractionCounts["a.wav"], 1)
        XCTAssertEqual(extractionCounts["b.wav"], 1)
        XCTAssertEqual(extractionCounts["c.wav"], 1)
        XCTAssertEqual(extractionCounts.values.reduce(0, +), 3)
    }

    private func manifestWith(queryPath: String, referencePath: String) -> ResolverPrivateCorpusManifest {
        ResolverPrivateCorpusManifest(
            name: "paths",
            cases: [
                ResolverPrivateCorpusManifestCase(
                    name: "path case",
                    relationship: .differentSong,
                    queryPath: queryPath,
                    referencePath: referencePath
                )
            ]
        )
    }

    private func stubEvidence(for url: URL) -> AudioEvidenceVector {
        AudioEvidenceVector(
            durationSec: 1,
            sampleRate: 48_000,
            channelCount: 1,
            energyEnvelope: Array(repeating: 0.0, count: AudioEvidenceVector.bucketCount),
            transientEnvelope: Array(repeating: 0.0, count: AudioEvidenceVector.bucketCount),
            signature: url.lastPathComponent,
            tonalEvidence: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeLayer-PrivateCorpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSyntheticWAV(to url: URL, frequency: Double) throws {
        let sampleRate = 48_000.0
        let duration = 1.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            samples[frame] = Float(0.3 * sin(2 * .pi * frequency * time))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
