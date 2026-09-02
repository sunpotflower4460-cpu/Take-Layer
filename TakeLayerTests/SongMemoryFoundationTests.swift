import Foundation
import XCTest
@testable import TakeLayer

final class SongMemoryFoundationTests: XCTestCase {
    func testConfirmedSongCreatesIdentityProfileArrangementAndLyrics() throws {
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

    func testExistingSongCanCreateAdditionalArrangementWithoutDuplicatingIdentity() throws {
        var library = SongMemoryLibrary()
        let first = library.upsertConfirmedSong(makeInput(canonicalTitle: "Re:trip"))

        var duoInput = makeInput(canonicalTitle: "Re:trip")
        duoInput.existingSongID = first.songID
        duoInput.existingArrangementID = nil
        duoInput.arrangementName = "Duo"
        duoInput.arrangementType = .duo

        let second = library.upsertConfirmedSong(duoInput)

        XCTAssertEqual(first.songID, second.songID)
        XCTAssertNotEqual(first.arrangementID, second.arrangementID)
        XCTAssertEqual(library.identities.count, 1)
        XCTAssertEqual(library.arrangements(for: first.songID).count, 2)
        XCTAssertEqual(library.arrangement(for: second.arrangementID)?.type, .duo)
        XCTAssertEqual(library.arrangement(for: second.arrangementID)?.name, "Duo")
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

    func testSongMemoryLibraryCodableRoundTripPreservesConfirmedData() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(
            makeInput(
                canonicalTitle: "Aquarium",
                artistName: "flowertty",
                aliases: ["AQ"],
                bpm: 84,
                keySignature: "D",
                tuningHz: 432,
                formalLyricsText: "水の中で"
            ),
            now: Date(timeIntervalSince1970: 2_000)
        )

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(SongMemoryLibrary.self, from: data)

        XCTAssertEqual(decoded, library)
        XCTAssertEqual(decoded.identity(for: link.songID)?.canonicalTitle, "Aquarium")
        XCTAssertEqual(decoded.lyrics(for: link.songID)?.text, "水の中で")
    }

    func testLegacyProjectJSONWithoutSongMemoryLinkStillDecodes() throws {
        var project = ProjectDraft(title: "Legacy Project")
        project.offsetMs = 12

        let currentData = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        object.removeValue(forKey: "songMemoryLink")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ProjectDraft.self, from: legacyData)

        XCTAssertEqual(decoded.title, "Legacy Project")
        XCTAssertEqual(decoded.offsetMs, 12)
        XCTAssertNil(decoded.songMemoryLink)
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
