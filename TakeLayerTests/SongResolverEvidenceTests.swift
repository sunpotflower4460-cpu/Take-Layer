import Foundation
import XCTest
@testable import TakeLayer

final class SongResolverEvidenceTests: XCTestCase {
    func testExactFingerprintProducesPerfectEvidenceButDoesNotAutoResolve() throws {
        var songMemory = SongMemoryLibrary()
        let link = songMemory.upsertConfirmedSong(makeSongInput(title: "Re:trip"))
        let vector = makeVector(signature: "exact")

        var evidenceLibrary = SongResolverEvidenceLibrary()
        let fingerprint = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(link.arrangementID),
            evidence: vector,
            sourceFileName: "retrip.wav"
        )
        songMemory.attachFingerprintID(fingerprint.id, to: try XCTUnwrap(link.arrangementID))

        let result = SongResolver.resolve(
            query: vector,
            songMemory: songMemory,
            evidenceLibrary: evidenceLibrary
        )

        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.songID, link.songID)
        XCTAssertEqual(candidate.arrangementID, link.arrangementID)
        XCTAssertEqual(candidate.confidence, 1, accuracy: 0.000_001)
        XCTAssertNil(result.resolvedSongID)
        XCTAssertNil(result.resolvedArrangementID)
        XCTAssertTrue(result.needsUserConfirmation)
    }

    func testResolverRanksCloserArrangementFirst() throws {
        var songMemory = SongMemoryLibrary()
        let first = songMemory.upsertConfirmedSong(makeSongInput(title: "Aquarium"))
        let second = songMemory.upsertConfirmedSong(makeSongInput(title: "CREATOR"))

        let query = makeVector(
            duration: 180,
            energy: risingEnvelope(),
            transient: alternatingEnvelope(),
            signature: "query"
        )
        let close = makeVector(
            duration: 181,
            energy: risingEnvelope(),
            transient: alternatingEnvelope(),
            signature: "close"
        )
        let far = makeVector(
            duration: 245,
            energy: fallingEnvelope(),
            transient: Array(repeating: 0.1, count: AudioEvidenceVector.bucketCount),
            signature: "far"
        )

        var evidenceLibrary = SongResolverEvidenceLibrary()
        let closeFingerprint = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(first.arrangementID),
            evidence: close,
            sourceFileName: "aquarium.wav"
        )
        let farFingerprint = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(second.arrangementID),
            evidence: far,
            sourceFileName: "creator.wav"
        )
        songMemory.attachFingerprintID(closeFingerprint.id, to: try XCTUnwrap(first.arrangementID))
        songMemory.attachFingerprintID(farFingerprint.id, to: try XCTUnwrap(second.arrangementID))

        let result = SongResolver.resolve(
            query: query,
            songMemory: songMemory,
            evidenceLibrary: evidenceLibrary
        )

        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertEqual(result.candidates.first?.songID, first.songID)
        XCTAssertGreaterThan(result.candidates[0].confidence, result.candidates[1].confidence)
    }

    func testTonalComparisonRecognizesSamePatternTwoSemitonesHigher() throws {
        let stored = makeVector(
            signature: "stored-c",
            tonal: makeTonalEvidence(baseKey: 0, progression: [0, 5, 7, 0])
        )
        let query = makeVector(
            signature: "query-d",
            tonal: makeTonalEvidence(baseKey: 2, progression: [0, 5, 7, 0])
        )

        let evidence = SongResolver.compare(query, stored)

        XCTAssertEqual(try XCTUnwrap(evidence.tonal), 1, accuracy: 0.000_01)
        XCTAssertEqual(evidence.transpositionSemitones, 2)
    }

    func testTonalComparisonRejectsDifferentProgressionMoreThanTransposedSameSong() throws {
        let stored = makeVector(
            signature: "stored",
            tonal: makeTonalEvidence(baseKey: 0, progression: [0, 5, 7, 0])
        )
        let transposedSameSong = makeVector(
            signature: "same-song",
            tonal: makeTonalEvidence(baseKey: 4, progression: [0, 5, 7, 0])
        )
        let differentSong = makeVector(
            signature: "different-song",
            tonal: makeTonalEvidence(baseKey: 4, progression: [0, 3, 8, 10])
        )

        let sameEvidence = SongResolver.compare(transposedSameSong, stored)
        let differentEvidence = SongResolver.compare(differentSong, stored)

        XCTAssertGreaterThan(
            try XCTUnwrap(sameEvidence.tonal),
            try XCTUnwrap(differentEvidence.tonal)
        )
    }

    func testExistingFingerprintUpgradesWithTonalEvidenceWithoutChangingID() throws {
        let arrangementID = UUID()
        let legacy = makeVector(signature: "same-signature")
        let enriched = makeVector(
            signature: "same-signature",
            tonal: makeTonalEvidence(baseKey: 0, progression: [0, 5, 7, 0])
        )
        var library = SongResolverEvidenceLibrary()

        let first = library.register(
            arrangementID: arrangementID,
            evidence: legacy,
            sourceFileName: "legacy.wav"
        )
        let second = library.register(
            arrangementID: arrangementID,
            evidence: enriched,
            sourceFileName: "enriched.wav"
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(library.fingerprints.count, 1)
        XCTAssertNotNil(library.fingerprints.first?.evidence.tonalEvidence)
        XCTAssertEqual(library.fingerprints.first?.sourceFileName, "enriched.wav")
    }

    func testLegacyAudioEvidenceJSONWithoutTonalFieldStillDecodes() throws {
        let json = """
        {
          "durationSec": 180,
          "sampleRate": 48000,
          "channelCount": 2,
          "energyEnvelope": [0.1, 0.2],
          "transientEnvelope": [0.2, 0.1],
          "signature": "legacy"
        }
        """

        let decoded = try JSONDecoder().decode(AudioEvidenceVector.self, from: Data(json.utf8))
        XCTAssertNil(decoded.tonalEvidence)
        XCTAssertEqual(decoded.signature, "legacy")
    }

    func testOrphanEvidenceNotReferencedByArrangementIsIgnored() throws {
        var songMemory = SongMemoryLibrary()
        let link = songMemory.upsertConfirmedSong(makeSongInput(title: "Orphan"))
        let vector = makeVector(signature: "orphan")
        var evidenceLibrary = SongResolverEvidenceLibrary()

        _ = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(link.arrangementID),
            evidence: vector,
            sourceFileName: "orphan.wav"
        )

        let result = SongResolver.resolve(
            query: vector,
            songMemory: songMemory,
            evidenceLibrary: evidenceLibrary
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.needsUserConfirmation)
        XCTAssertNil(result.resolvedSongID)
        XCTAssertNil(result.resolvedArrangementID)
    }

    func testRegisteringSameEvidenceTwiceDoesNotDuplicateFingerprint() {
        let arrangementID = UUID()
        let vector = makeVector(signature: "stable")
        var library = SongResolverEvidenceLibrary()

        let first = library.register(
            arrangementID: arrangementID,
            evidence: vector,
            sourceFileName: "one.wav"
        )
        let second = library.register(
            arrangementID: arrangementID,
            evidence: vector,
            sourceFileName: "two.wav"
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(library.fingerprints.count, 1)
    }

    func testAttachingFingerprintIDToArrangementIsIdempotent() throws {
        var songMemory = SongMemoryLibrary()
        let link = songMemory.upsertConfirmedSong(makeSongInput(title: "blue sky"))
        let arrangementID = try XCTUnwrap(link.arrangementID)
        let fingerprintID = UUID()

        songMemory.attachFingerprintID(fingerprintID, to: arrangementID)
        songMemory.attachFingerprintID(fingerprintID, to: arrangementID)

        let arrangement = try XCTUnwrap(songMemory.arrangement(for: arrangementID))
        XCTAssertEqual(arrangement.fingerprintIDs, [fingerprintID.uuidString])
    }

    func testResolverWithNoKnownEvidenceReturnsNoCandidateAndNoAutoResolution() {
        let result = SongResolver.resolve(
            query: makeVector(signature: "query"),
            songMemory: SongMemoryLibrary(),
            evidenceLibrary: SongResolverEvidenceLibrary()
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertNil(result.resolvedSongID)
        XCTAssertNil(result.resolvedArrangementID)
        XCTAssertFalse(result.needsUserConfirmation)
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
        energy: [Double]? = nil,
        transient: [Double]? = nil,
        signature: String,
        tonal: TonalEvidenceVector? = nil
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

    private func makeTonalEvidence(baseKey: Int, progression: [Int]) -> TonalEvidenceVector {
        var frames: [Double] = []
        var global = Array(repeating: 0.0, count: TonalEvidenceVector.pitchClassCount)

        for frameIndex in 0..<TonalEvidenceVector.frameCount {
            let degree = progression[frameIndex % progression.count]
            let root = (baseKey + degree + 12) % 12
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
