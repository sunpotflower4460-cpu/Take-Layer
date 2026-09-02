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

        var secondInput = makeSongInput(title: "CREATOR")
        let second = songMemory.upsertConfirmedSong(secondInput)
        secondInput.existingSongID = second.songID

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
        _ = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(first.arrangementID),
            evidence: close,
            sourceFileName: "aquarium.wav"
        )
        _ = evidenceLibrary.register(
            arrangementID: try XCTUnwrap(second.arrangementID),
            evidence: far,
            sourceFileName: "creator.wav"
        )

        let result = SongResolver.resolve(
            query: query,
            songMemory: songMemory,
            evidenceLibrary: evidenceLibrary
        )

        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertEqual(result.candidates.first?.songID, first.songID)
        XCTAssertGreaterThan(result.candidates[0].confidence, result.candidates[1].confidence)
    }

    func testRegisteringSameEvidenceTwiceDoesNotDuplicateFingerprint() throws {
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
        signature: String
    ) -> AudioEvidenceVector {
        AudioEvidenceVector(
            durationSec: duration,
            sampleRate: 48_000,
            channelCount: 2,
            energyEnvelope: energy ?? risingEnvelope(),
            transientEnvelope: transient ?? alternatingEnvelope(),
            signature: signature
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
