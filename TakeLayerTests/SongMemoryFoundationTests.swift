import XCTest
@testable import TakeLayer

final class SongMemoryFoundationTests: XCTestCase {
    func testConfirmedSongCreatesIdentityProfileArrangementAndLyrics() {
        var library = SongMemoryLibrary()
        let now = Date(timeIntervalSince1970: 1_000)

        let link = library.upsertConfirmedSong(
            makeInput(
                canonicalTitle: "Re:trip",
                artistName: "しののめむすび",
                bpm: 92,
                keySignature: "C",
                tuningHz: 432,
                formalLyricsText: "旅の途中で"
            ),
            now: now
        )

        let identity = try XCTUnwrap(library.identity(for: link.songID))
        XCTAssertEqual(identity.canonicalTitle, "Re:trip")
        XCTAssertEqual(identity.artistName, "しののめむすび")
        XCTAssertTrue(identity.userConfirmed)
        XCTAssertEqual(identity.confidence, 1.0)

        let profile = try XCTUnwrap(library.profile(for: link.songID))
        XCTAssertEqual(profile.bpm, 92)
        XCTAssertEqual(profile.keySignature, "C")
        XCTAssertEqual(profile.tuningHz, 432)

        let arrangement = try XCTUnwrap(library.arrangement(for: link.arrangementID))
        XCTAssertEqual(arrangement.songID, link.songID)
        XCTAssertEqual(arrangement.type, .acousticSolo)

        let lyrics = try XCTUnwrap(library.lyrics(for: link.songID))
        XCTAssertEqual(lyrics.text, "旅の途中で")
        XCTAssertEqual(lyrics.source, .userConfirmed)
        XCTAssertTrue(lyrics.userConfirmed)
        XCTAssertEqual(lyrics.version, 1)
    }

    func testUpdatingConfirmedSongPreservesIdentityAndArrangementIDs() throws {
        var library = SongMemoryLibrary()
        let first = library.upsertConfirmedSong(makeInput(canonicalTitle: "Aquarium"))

        var updatedInput = makeInput(
            canonicalTitle: "Aquarium",
            artistName: "flowertty",
            bpm: 80,
            formalLyricsText: "first version"
        )
        updatedInput.existingSongID = first.songID
        updatedInput.existingArrangementID = first.arrangementID

        let second = library.upsertConfirmedSong(updatedInput)

        XCTAssertEqual(first.songID, second.songID)
        XCTAssertEqual(first.arrangementID, second.arrangementID)
        XCTAssertEqual(library.identities.count, 1)
        XCTAssertEqual(library.arrangements.count, 1)

        var thirdInput = updatedInput
        thirdInput.formalLyricsText = "second version"
        _ = library.upsertConfirmedSong(thirdInput)

        let lyrics = try XCTUnwrap(library.lyrics(for: first.songID))
        XCTAssertEqual(lyrics.version, 2)
        XCTAssertEqual(lyrics.text, "second version")
    }

    func testSavingEmptyFormalLyricsRemovesOnlyConfirmedLyrics() throws {
        var library = SongMemoryLibrary()
        let first = library.upsertConfirmedSong(
            makeInput(canonicalTitle: "CREATOR", formalLyricsText: "remember me")
        )
        XCTAssertNotNil(library.lyrics(for: first.songID))

        var update = makeInput(canonicalTitle: "CREATOR", formalLyricsText: "")
        update.existingSongID = first.songID
        update.existingArrangementID = first.arrangementID
        _ = library.upsertConfirmedSong(update)

        XCTAssertNil(library.lyrics(for: first.songID))
        XCTAssertNil(library.profile(for: first.songID)?.formalLyricsID)
    }

    func testAliasesAreTrimmedAndDeduplicatedCaseInsensitively() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(
            makeInput(
                canonicalTitle: "blue sky",
                aliases: [" Blue Sky ", "BLUE SKY", "青空", "青空"]
            )
        )

        let identity = try XCTUnwrap(library.identity(for: link.songID))
        XCTAssertEqual(identity.aliases, ["Blue Sky", "青空"])
    }

    func testInvalidNumericHintsAreStoredAsUnknown() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(
            makeInput(canonicalTitle: "Unknown", bpm: -1, tuningHz: .infinity)
        )

        let profile = try XCTUnwrap(library.profile(for: link.songID))
        XCTAssertNil(profile.bpm)
        XCTAssertNil(profile.tuningHz)
    }

    private func makeInput(
        canonicalTitle: String,
        artistName: String = "",
        aliases: [String] = [],
        bpm: Double? = nil,
        keySignature: String = "",
        tuningHz: Double? = nil,
        formalLyricsText: String = ""
    ) -> ConfirmedSongMemoryInput {
        ConfirmedSongMemoryInput(
            existingSongID: nil,
            existingArrangementID: nil,
            canonicalTitle: canonicalTitle,
            artistName: artistName,
            aliases: aliases,
            isOriginal: true,
            bpm: bpm,
            keySignature: keySignature,
            tuningHz: tuningHz,
            arrangementName: "Acoustic Solo",
            arrangementType: .acousticSolo,
            formalLyricsText: formalLyricsText,
            lyricsLanguage: "ja"
        )
    }
}
