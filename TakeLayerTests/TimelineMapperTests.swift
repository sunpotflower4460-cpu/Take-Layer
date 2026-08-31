import XCTest
@testable import TakeLayer

final class TimelineMapperTests: XCTestCase {
    func testSongStartMapsDirectlyToMasterSongStart() throws {
        var project = makeProject()
        project.songStartRawSec = 20
        project.songStartAudioSec = 2
        project.selectedRawStartSec = 20
        project.selectedRawEndSec = 50

        let mapping = try TimelineMapper.makeMapping(project: project)

        XCTAssertEqual(mapping.projectTimelineStartSec, 0, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioSourceStartSec, 2, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioInsertionTimeSec, 0, accuracy: 0.000_001)
    }

    func testTrimAfterSongStartMovesMasterStartBySameAmount() throws {
        var project = makeProject()
        project.songStartRawSec = 20
        project.songStartAudioSec = 2
        project.selectedRawStartSec = 21
        project.selectedRawEndSec = 51

        let mapping = try TimelineMapper.makeMapping(project: project)

        XCTAssertEqual(mapping.projectTimelineStartSec, 1, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioSourceStartSec, 3, accuracy: 0.000_001)
    }

    func testPositiveOffsetDelaysMasterAudio() throws {
        var project = makeProject()
        project.songStartRawSec = 20
        project.songStartAudioSec = 2
        project.selectedRawStartSec = 20
        project.selectedRawEndSec = 50
        project.offsetMs = 100

        let mapping = try TimelineMapper.makeMapping(project: project)

        XCTAssertEqual(mapping.audioSourceStartSec, 1.9, accuracy: 0.000_001)
    }

    func testNegativeOffsetAdvancesMasterAudio() throws {
        var project = makeProject()
        project.songStartRawSec = 20
        project.songStartAudioSec = 2
        project.selectedRawStartSec = 20
        project.selectedRawEndSec = 50
        project.offsetMs = -100

        let mapping = try TimelineMapper.makeMapping(project: project)

        XCTAssertEqual(mapping.audioSourceStartSec, 2.1, accuracy: 0.000_001)
    }

    func testPreRollUsesAudioInsertionWhenMasterHasInsufficientLeadIn() throws {
        var project = makeProject(audioDuration: 120)
        project.songStartRawSec = 20
        project.songStartAudioSec = 0.5
        project.selectedRawStartSec = 19
        project.selectedRawEndSec = 49

        let mapping = try TimelineMapper.makeMapping(project: project)

        XCTAssertEqual(mapping.projectTimelineStartSec, -1, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioSourceStartSec, 0, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioInsertionTimeSec, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioInsertDurationSec, 29.5, accuracy: 0.000_001)
        XCTAssertEqual(mapping.outputDurationSec, 30, accuracy: 0.000_001)
    }

    private func makeProject(audioDuration: Double = 120) -> ProjectDraft {
        var project = ProjectDraft(title: "Timeline Test")
        project.importedVideo = ImportedVideo(
            url: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSec: 120,
            width: 1080,
            height: 1920,
            orientation: .portrait,
            fileType: "video/quicktime",
            hasAudio: true,
            fileSizeBytes: nil
        )
        project.importedMasterAudio = ImportedMasterAudio(
            url: URL(fileURLWithPath: "/tmp/master.wav"),
            durationSec: audioDuration,
            sampleRate: 48_000,
            channelCount: 2,
            fileType: "audio/wav",
            fileSizeBytes: nil
        )
        return project
    }
}
