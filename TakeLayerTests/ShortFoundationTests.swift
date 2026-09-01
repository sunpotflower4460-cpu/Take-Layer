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
