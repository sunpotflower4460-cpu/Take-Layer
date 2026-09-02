import Foundation
import XCTest
@testable import TakeLayer

final class ElasticTonalAlignmentTests: XCTestCase {
    func testElasticAlignmentToleratesSectionStretchAndTransposition() throws {
        let stored = makeVector(
            signature: "stored",
            tonal: makeTonalEvidence(
                baseKey: 0,
                roots: [0, 0, 5, 5, 7, 7, 0, 0]
            )
        )
        let query = makeVector(
            duration: 205,
            signature: "query",
            tonal: makeTonalEvidence(
                baseKey: 2,
                roots: [0, 0, 0, 5, 5, 5, 7, 7, 0, 0]
            )
        )

        let evidence = SongResolver.compare(query, stored)

        XCTAssertEqual(evidence.transpositionSemitones, 2)
        XCTAssertGreaterThan(try XCTUnwrap(evidence.tonal), 0.90)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(evidence.tonalAlignmentCoverage), 0.80)
        XCTAssertGreaterThan(try XCTUnwrap(evidence.tonalWarpFraction), 0)
        XCTAssertLessThan(try XCTUnwrap(evidence.tonalWarpFraction), 0.50)
    }

    func testDifferentStructureScoresBelowElasticSameSong() throws {
        let stored = makeVector(
            signature: "stored",
            tonal: makeTonalEvidence(
                baseKey: 0,
                roots: [0, 0, 5, 5, 7, 7, 0, 0]
            )
        )
        let stretchedSameSong = makeVector(
            signature: "same",
            tonal: makeTonalEvidence(
                baseKey: 4,
                roots: [0, 0, 0, 5, 5, 5, 7, 7, 0, 0]
            )
        )
        let differentSong = makeVector(
            signature: "different",
            tonal: makeTonalEvidence(
                baseKey: 4,
                roots: [0, 3, 8, 10, 1, 6, 11, 4]
            )
        )

        let sameEvidence = SongResolver.compare(stretchedSameSong, stored)
        let differentEvidence = SongResolver.compare(differentSong, stored)

        XCTAssertGreaterThan(
            try XCTUnwrap(sameEvidence.tonal),
            try XCTUnwrap(differentEvidence.tonal) + 0.05
        )
    }

    func testEndpointDifferenceCanBeTrimmedButCannotHideLowCoverage() throws {
        let stored = makeVector(
            signature: "stored",
            tonal: makeTonalEvidence(
                baseKey: 0,
                roots: [0, 5, 7, 0, 5, 7, 0, 0]
            )
        )
        let longerIntroOutro = makeVector(
            signature: "live",
            tonal: makeTonalEvidence(
                baseKey: 0,
                roots: [2, 2, 0, 5, 7, 0, 5, 7, 0, 0, 9, 9]
            )
        )

        let evidence = SongResolver.compare(longerIntroOutro, stored)
        let coverage = try XCTUnwrap(evidence.tonalAlignmentCoverage)

        XCTAssertGreaterThan(try XCTUnwrap(evidence.tonal), 0.70)
        XCTAssertGreaterThanOrEqual(coverage, 0.75)
        XCTAssertLessThan(coverage, 1)
    }

    func testExactFingerprintReportsFullCoverageZeroWarpAndStillNeedsHumanConfirmation() throws {
        var songMemory = SongMemoryLibrary()
        let link = songMemory.upsertConfirmedSong(makeSongInput(title: "Exact"))
        let vector = makeVector(
            signature: "same-signature",
            tonal: makeTonalEvidence(baseKey: 0, roots: [0, 5, 7, 0])
        )

        var evidenceLibrary = SongResolverEvidenceLibrary()
        let fingerprint = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(link.arrangementID),
            evidence: vector,
            sourceFileName: "exact.wav"
        )
        songMemory.attachFingerprintID(fingerprint.id, to: try XCTUnwrap(link.arrangementID))

        let result = SongResolver.resolve(
            query: vector,
            songMemory: songMemory,
            evidenceLibrary: evidenceLibrary
        )
        let evidence = try XCTUnwrap(result.candidates.first?.evidence)

        XCTAssertEqual(evidence.tonalAlignmentCoverage, 1)
        XCTAssertEqual(evidence.tonalWarpFraction, 0)
        XCTAssertNil(result.resolvedSongID)
        XCTAssertNil(result.resolvedArrangementID)
        XCTAssertTrue(result.needsUserConfirmation)
    }

    func testLegacySongMatchEvidenceWithoutAlignmentFieldsStillDecodes() throws {
        let json = """
        {
          "duration": 0.9,
          "energyEnvelope": 0.8,
          "transientEnvelope": 0.7,
          "tonal": 0.95,
          "transpositionSemitones": 2
        }
        """

        let decoded = try JSONDecoder().decode(SongMatchEvidence.self, from: Data(json.utf8))

        XCTAssertNil(decoded.tonalAlignmentCoverage)
        XCTAssertNil(decoded.tonalWarpFraction)
        XCTAssertEqual(decoded.transpositionSemitones, 2)
    }

    private func makeSongInput(title: String) -> ConfirmedSongMemoryInput {
        ConfirmedSongMemoryInput(
            existingSongID: nil,
            existingArrangementID: nil,
            canonicalTitle: title,
            artistName: "flowertty",
            aliases: [],
            isOriginal: true,
            bpm: 90,
            keySignature: "C",
            tuningHz: 432,
            arrangementName: "Studio",
            arrangementType: .studio,
            arrangementTempoHint: 90,
            arrangementKeyHint: "C",
            formalLyricsText: "",
            lyricsLanguage: "ja"
        )
    }

    private func makeVector(
        duration: Double = 180,
        signature: String,
        tonal: TonalEvidenceVector
    ) -> AudioEvidenceVector {
        AudioEvidenceVector(
            durationSec: duration,
            sampleRate: 48_000,
            channelCount: 2,
            energyEnvelope: (0..<64).map { Double($0 + 1) / 64 },
            transientEnvelope: (0..<64).map { $0.isMultiple(of: 2) ? 0.2 : 0.8 },
            signature: signature,
            tonalEvidence: tonal
        )
    }

    private func makeTonalEvidence(baseKey: Int, roots: [Int]) -> TonalEvidenceVector {
        precondition(!roots.isEmpty)
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
}
