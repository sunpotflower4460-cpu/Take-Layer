import Foundation
import XCTest
@testable import TakeLayer

final class SongMemoryConsistencyTests: XCTestCase {
    func testLicensedProviderLyricsOutrankNewerTranscriptionEstimate() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(makeInput(title: "Authority Test"))
        let now = Date(timeIntervalSince1970: 10_000)

        library.formalLyrics.append(
            FormalLyrics(
                id: UUID(),
                songID: link.songID,
                text: "licensed",
                source: .licensedProvider,
                userConfirmed: false,
                language: "ja",
                version: 1,
                createdAt: now,
                updatedAt: now
            )
        )
        library.formalLyrics.append(
            FormalLyrics(
                id: UUID(),
                songID: link.songID,
                text: "newer transcription",
                source: .transcriptionEstimate,
                userConfirmed: false,
                language: "ja",
                version: 99,
                createdAt: now.addingTimeInterval(10),
                updatedAt: now.addingTimeInterval(10)
            )
        )

        let selected = try XCTUnwrap(library.lyrics(for: link.songID))
        XCTAssertEqual(selected.source, .licensedProvider)
        XCTAssertEqual(selected.text, "licensed")
    }

    func testClearingConfirmedLyricsRestoresProviderBeforeTranscription() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(
            makeInput(title: "Fallback Test", lyrics: "confirmed")
        )
        let providerID = UUID()
        let now = Date(timeIntervalSince1970: 20_000)

        library.formalLyrics.append(
            FormalLyrics(
                id: providerID,
                songID: link.songID,
                text: "licensed",
                source: .licensedProvider,
                userConfirmed: false,
                language: "ja",
                version: 1,
                createdAt: now,
                updatedAt: now
            )
        )
        library.formalLyrics.append(
            FormalLyrics(
                id: UUID(),
                songID: link.songID,
                text: "transcription",
                source: .transcriptionEstimate,
                userConfirmed: false,
                language: "ja",
                version: 100,
                createdAt: now.addingTimeInterval(10),
                updatedAt: now.addingTimeInterval(10)
            )
        )

        var update = makeInput(title: "Fallback Test", lyrics: "")
        update.existingSongID = link.songID
        update.existingArrangementID = link.arrangementID
        _ = library.upsertConfirmedSong(update, now: now.addingTimeInterval(20))

        XCTAssertEqual(library.profile(for: link.songID)?.formalLyricsID, providerID)
        XCTAssertEqual(library.lyrics(for: link.songID)?.source, .licensedProvider)
        XCTAssertEqual(library.lyrics(for: link.songID)?.text, "licensed")
    }

    private func makeInput(title: String, lyrics: String = "") -> ConfirmedSongMemoryInput {
        ConfirmedSongMemoryInput(
            existingSongID: nil,
            existingArrangementID: nil,
            canonicalTitle: title,
            artistName: "",
            aliases: [],
            isOriginal: true,
            bpm: nil,
            keySignature: "",
            tuningHz: nil,
            arrangementName: "Acoustic Solo",
            arrangementType: .acousticSolo,
            arrangementTempoHint: nil,
            arrangementKeyHint: "",
            formalLyricsText: lyrics,
            lyricsLanguage: "ja"
        )
    }
}
