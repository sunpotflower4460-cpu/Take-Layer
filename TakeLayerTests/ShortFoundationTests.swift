import AVFoundation
import CoreGraphics
import XCTest
@testable import TakeLayer

final class ShortFoundationTests: XCTestCase {
    func testProjectTimeShortRangeUsesAuthoritativeTimelineMapper() throws {
        var project = makeProject()
        project.songStartRawSec = 20
        project.songStartAudioSec = 2
        project.offsetMs = 100

        let mapping = try TimelineMapper.makeMapping(
            project: project,
            projectTimelineStartSec: 10,
            durationSec: 15
        )

        XCTAssertEqual(mapping.videoSourceStartSec, 30, accuracy: 0.000_001)
        XCTAssertEqual(mapping.projectTimelineStartSec, 10, accuracy: 0.000_001)
        XCTAssertEqual(mapping.audioSourceStartSec, 11.9, accuracy: 0.000_001)
        XCTAssertEqual(mapping.outputDurationSec, 15, accuracy: 0.000_001)
    }

    func testShortRangeOutsideVideoIsRejected() {
        var project = makeProject()
        project.songStartRawSec = 110
        project.songStartAudioSec = 2

        XCTAssertThrowsError(
            try TimelineMapper.makeMapping(
                project: project,
                projectTimelineStartSec: 5,
                durationSec: 10
            )
        ) { error in
            XCTAssertEqual(error as? TimelineMapperError, .invalidTrimRange)
        }
    }

    func testProjectTimelineRemapPreservesRawVideoPosition() {
        let oldProjectSec = 5.0
        let oldSongStartRawSec = 20.0
        let newSongStartRawSec = 21.0
        let remapped = TimelineMapper.remapProjectTimelineSec(
            oldProjectSec,
            fromSongStartRawSec: oldSongStartRawSec,
            toSongStartRawSec: newSongStartRawSec
        )

        XCTAssertEqual(remapped, 4, accuracy: 0.000_001)
        XCTAssertEqual(
            TimelineMapper.videoRawSec(projectTimelineSec: oldProjectSec, songStartRawSec: oldSongStartRawSec),
            TimelineMapper.videoRawSec(projectTimelineSec: remapped, songStartRawSec: newSongStartRawSec),
            accuracy: 0.000_001
        )
    }

    func testPortraitSourceAtDefaultCropNeedsNoOverflow() {
        let geometry = ShortRenderGeometryBuilder.make(
            displaySize: CGSize(width: 1080, height: 1920),
            crop: ShortCropPlan()
        )

        XCTAssertEqual(geometry.renderSize.width, 1080, accuracy: 0.001)
        XCTAssertEqual(geometry.renderSize.height, 1920, accuracy: 0.001)
        XCTAssertEqual(geometry.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(geometry.cropOffset.x, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.cropOffset.y, 0, accuracy: 0.001)
    }

    func testLandscapeSourceAspectFillsVerticalCanvas() {
        let geometry = ShortRenderGeometryBuilder.make(
            displaySize: CGSize(width: 1920, height: 1080),
            crop: ShortCropPlan()
        )

        XCTAssertEqual(geometry.scale, 1920.0 / 1080.0, accuracy: 0.000_001)
        XCTAssertEqual(geometry.scaledDisplaySize.height, 1920, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.scaledDisplaySize.width, 1080)
        XCTAssertEqual(
            geometry.cropOffset.x,
            (geometry.scaledDisplaySize.width - 1080) / 2,
            accuracy: 0.001
        )
    }

    func testCropPlanNormalizationKeepsAIAndUIInputsSafe() {
        var crop = ShortCropPlan(zoom: 8, focusX: -2, focusY: 3)
        crop.normalize()

        XCTAssertEqual(crop.zoom, 3)
        XCTAssertEqual(crop.focusX, 0)
        XCTAssertEqual(crop.focusY, 1)
    }

    func testDraftNormalizationPreservesNegativePreSongRange() {
        var draft = ShortEditDraft(
            rangeStartProjectSec: -10,
            rangeEndProjectSec: -5
        )
        draft.normalize(availableRange: -10 ... -5)

        XCTAssertEqual(draft.rangeStartProjectSec, -10, accuracy: 0.000_001)
        XCTAssertEqual(draft.rangeEndProjectSec, -5, accuracy: 0.000_001)
    }

    func testSignedProjectTimelineFormattingPreservesNegativeTime() {
        XCTAssertEqual(TimeFormatting.signedSeconds(-10), "-00:10.00")
        XCTAssertEqual(TimeFormatting.signedSeconds(0), "+00:00.00")
        XCTAssertEqual(TimeFormatting.signedSeconds(65.25), "+01:05.25")
    }

    func testDraftNormalizationDoesNotInventTimeForTinyMappedRange() {
        var draft = ShortEditDraft(
            rangeStartProjectSec: 4,
            rangeEndProjectSec: 4.05
        )
        draft.normalize(availableRange: 4 ... 4.05)

        XCTAssertEqual(draft.rangeStartProjectSec, 4, accuracy: 0.000_001)
        XCTAssertEqual(draft.rangeEndProjectSec, 4.05, accuracy: 0.000_001)
        XCTAssertEqual(draft.durationSec, 0.05, accuracy: 0.000_001)
    }

    func testDraftNormalizationPreservesIncompleteLyricForCorrection() {
        let cue = ShortLyricCue(startProjectSec: 3, endProjectSec: 3, text: "unfinished")
        var draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [cue]
        )
        draft.normalize(availableRange: 0 ... 10)

        XCTAssertEqual(draft.lyricCues, [cue])
        XCTAssertFalse(draft.lyricCues[0].isValid)
        XCTAssertTrue(draft.hasInvalidLyricCues)
    }

    func testInvalidLyricOutsideSelectedRangeDoesNotBlockExportValidation() {
        let cue = ShortLyricCue(startProjectSec: 20, endProjectSec: 20, text: "unfinished")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [cue]
        )

        XCTAssertFalse(draft.hasInvalidLyricCues)
    }

    func testExportRejectsIncompleteLyricsBeforeRendering() async {
        let cue = ShortLyricCue(startProjectSec: 3, endProjectSec: 3, text: "unfinished")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [cue]
        )

        do {
            _ = try await ShortVideoExportService.export(project: makeProject(), draft: draft)
            XCTFail("Expected invalidLyrics")
        } catch let error as ShortVideoExportError {
            guard case .invalidLyrics = error else {
                return XCTFail("Expected invalidLyrics, got \(error)")
            }
        } catch {
            XCTFail("Expected ShortVideoExportError, got \(error)")
        }
    }

    func testOverlappingValidLyricsAreDetected() {
        let first = ShortLyricCue(startProjectSec: 1, endProjectSec: 4, text: "first")
        let second = ShortLyricCue(startProjectSec: 3.5, endProjectSec: 5, text: "second")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [first, second]
        )

        XCTAssertTrue(draft.hasOverlappingValidLyricCues)
    }

    func testOverlappingLyricsOutsideSelectedRangeDoNotBlockExportValidation() {
        let first = ShortLyricCue(startProjectSec: 20, endProjectSec: 24, text: "first")
        let second = ShortLyricCue(startProjectSec: 22, endProjectSec: 25, text: "second")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [first, second]
        )

        XCTAssertFalse(draft.hasOverlappingValidLyricCues)
    }

    func testAdjacentLyricsDoNotCountAsOverlap() {
        let first = ShortLyricCue(startProjectSec: 1, endProjectSec: 4, text: "first")
        let second = ShortLyricCue(startProjectSec: 4, endProjectSec: 5, text: "second")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [first, second]
        )

        XCTAssertFalse(draft.hasOverlappingValidLyricCues)
    }

    func testAdjacentSubFiftyMillisecondLyricsDoNotCountAsOverlap() {
        let first = ShortLyricCue(startProjectSec: 1, endProjectSec: 1.01, text: "first")
        let second = ShortLyricCue(startProjectSec: 1.01, endProjectSec: 2, text: "second")
        let draft = ShortEditDraft(
            rangeStartProjectSec: 0,
            rangeEndProjectSec: 10,
            lyricCues: [first, second]
        )

        XCTAssertFalse(draft.hasOverlappingValidLyricCues)
    }

    func testShortExportMediaTimePreservesOneMillisecondSteps() {
        let first = ShortVideoExportService.mediaTime(1.001)
        let second = ShortVideoExportService.mediaTime(1.002)

        XCTAssertNotEqual(first.value, second.value)
        XCTAssertEqual(first.seconds, 1.001, accuracy: 0.000_001)
        XCTAssertEqual(second.seconds, 1.002, accuracy: 0.000_001)
    }

    private func makeProject() -> ProjectDraft {
        var project = ProjectDraft(title: "Short Test")
        project.importedVideo = ImportedVideo(
            url: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSec: 120,
            width: 1920,
            height: 1080,
            orientation: .landscape,
            fileType: "video/quicktime",
            hasAudio: true,
            fileSizeBytes: nil
        )
        project.importedMasterAudio = ImportedMasterAudio(
            url: URL(fileURLWithPath: "/tmp/master.wav"),
            durationSec: 120,
            sampleRate: 48_000,
            channelCount: 2,
            fileType: "audio/wav",
            fileSizeBytes: nil
        )
        return project
    }
}
