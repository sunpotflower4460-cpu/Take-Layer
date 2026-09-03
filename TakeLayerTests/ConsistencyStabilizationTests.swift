import Foundation
import XCTest
@testable import TakeLayer

final class ConsistencyStabilizationTests: XCTestCase {
    func testRemovingConfirmedLyricsRestoresRetainedProviderReference() throws {
        var library = SongMemoryLibrary()
        let initial = library.upsertConfirmedSong(makeSongInput(title: "Lyrics Fallback"))
        let providerID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        library.formalLyrics.append(
            FormalLyrics(
                id: providerID,
                songID: initial.songID,
                text: "provider lyrics",
                source: .licensedProvider,
                userConfirmed: false,
                language: "ja",
                version: 1,
                createdAt: now,
                updatedAt: now
            )
        )
        let profileIndex = try XCTUnwrap(library.profiles.firstIndex { $0.songID == initial.songID })
        library.profiles[profileIndex].formalLyricsID = providerID

        var confirmed = makeSongInput(title: "Lyrics Fallback", lyrics: "confirmed lyrics")
        confirmed.existingSongID = initial.songID
        confirmed.existingArrangementID = initial.arrangementID
        _ = library.upsertConfirmedSong(confirmed, now: Date(timeIntervalSince1970: 1_100))
        XCTAssertEqual(library.lyrics(for: initial.songID)?.source, .userConfirmed)
        XCTAssertNotEqual(library.profile(for: initial.songID)?.formalLyricsID, providerID)

        var cleared = makeSongInput(title: "Lyrics Fallback", lyrics: "")
        cleared.existingSongID = initial.songID
        cleared.existingArrangementID = initial.arrangementID
        _ = library.upsertConfirmedSong(cleared, now: Date(timeIntervalSince1970: 1_200))

        XCTAssertEqual(library.lyrics(for: initial.songID)?.id, providerID)
        XCTAssertEqual(library.profile(for: initial.songID)?.formalLyricsID, providerID)
        XCTAssertEqual(library.formalLyrics.first(where: { $0.id == providerID })?.text, "provider lyrics")
    }

    func testRepairProjectLinkDropsOnlyMissingArrangementWhenSongStillExists() throws {
        var library = SongMemoryLibrary()
        let link = library.upsertConfirmedSong(makeSongInput(title: "Repair Link"))
        let stale = ProjectSongMemoryLink(
            songID: link.songID,
            arrangementID: UUID(),
            linkedAt: Date(timeIntervalSince1970: 2_000)
        )

        let repaired = try XCTUnwrap(library.repairedProjectLink(stale))

        XCTAssertEqual(repaired.songID, link.songID)
        XCTAssertNil(repaired.arrangementID)
        XCTAssertEqual(repaired.linkedAt, stale.linkedAt)
    }

    func testRepairProjectLinkDropsMissingSongEntirely() {
        let library = SongMemoryLibrary()
        let stale = ProjectSongMemoryLink(
            songID: UUID(),
            arrangementID: UUID(),
            linkedAt: Date()
        )

        XCTAssertNil(library.repairedProjectLink(stale))
    }

    func testExportValidationUsesStableIDsAndRejectsMissingPersistedFiles() {
        var project = ProjectDraft(title: "Missing Media")
        project.importedVideo = ImportedVideo(
            url: URL(fileURLWithPath: "/tmp/takelayer-definitely-missing-video.mov"),
            durationSec: 20,
            width: 1920,
            height: 1080,
            orientation: .landscape,
            fileType: "video/quicktime",
            hasAudio: true,
            fileSizeBytes: nil
        )
        project.importedMasterAudio = ImportedMasterAudio(
            url: URL(fileURLWithPath: "/tmp/takelayer-definitely-missing-master.wav"),
            durationSec: 20,
            sampleRate: 48_000,
            channelCount: 2,
            fileType: "audio/wav",
            fileSizeBytes: nil
        )
        project.songStartRawSec = 1
        project.songStartAudioSec = 1
        project.selectedRawStartSec = 1
        project.selectedRawEndSec = 10

        let first = ExportValidationService.validate(project: project)
        let second = ExportValidationService.validate(project: project)

        XCTAssertEqual(first.items.map(\.id), second.items.map(\.id))
        XCTAssertFalse(first.isReady)
        XCTAssertEqual(first.items.first(where: { $0.title == "Video" })?.isValid, false)
        XCTAssertEqual(first.items.first(where: { $0.title == "Master WAV" })?.isValid, false)
    }

    func testLegacyExportSettingsWithMuteCameraAudioFieldStillDecodes() throws {
        let json = """
        {
          "muteCameraAudio": false,
          "outputResolution": "1920x1080",
          "outputFileType": "MP4"
        }
        """

        let settings = try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.muteCameraAudio)
        XCTAssertEqual(settings.outputResolution, .hd1080p)
        XCTAssertEqual(settings.outputFileType, .mp4)
    }

    private func makeSongInput(title: String, lyrics: String = "") -> ConfirmedSongMemoryInput {
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
            formalLyricsText: lyrics,
            lyricsLanguage: "ja"
        )
    }
}
