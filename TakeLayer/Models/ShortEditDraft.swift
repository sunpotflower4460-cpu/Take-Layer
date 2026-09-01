import Foundation

struct ShortCropPlan: Codable, Equatable {
    var zoom: Double = 1.0
    var focusX: Double = 0.5
    var focusY: Double = 0.5

    mutating func normalize() {
        zoom = min(max(zoom, 1.0), 3.0)
        focusX = min(max(focusX, 0.0), 1.0)
        focusY = min(max(focusY, 0.0), 1.0)
    }
}

struct ShortLyricCue: Identifiable, Codable, Equatable {
    var id = UUID()
    var startProjectSec: Double
    var endProjectSec: Double
    var text: String

    var isValid: Bool {
        startProjectSec.isFinite &&
        endProjectSec.isFinite &&
        endProjectSec > startProjectSec &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ShortEditDraft: Codable, Equatable {
    var rangeStartProjectSec: Double
    var rangeEndProjectSec: Double
    var titleText: String
    var crop: ShortCropPlan
    var lyricCues: [ShortLyricCue]

    var durationSec: Double {
        max(0, rangeEndProjectSec - rangeStartProjectSec)
    }

    init(
        rangeStartProjectSec: Double = 0,
        rangeEndProjectSec: Double = 15,
        titleText: String = "",
        crop: ShortCropPlan = ShortCropPlan(),
        lyricCues: [ShortLyricCue] = []
    ) {
        self.rangeStartProjectSec = rangeStartProjectSec
        self.rangeEndProjectSec = rangeEndProjectSec
        self.titleText = titleText
        self.crop = crop
        self.lyricCues = lyricCues
    }

    mutating func normalize(availableRange: ClosedRange<Double>) {
        crop.normalize()
        rangeStartProjectSec = min(max(rangeStartProjectSec, availableRange.lowerBound), availableRange.upperBound)
        rangeEndProjectSec = min(max(rangeEndProjectSec, rangeStartProjectSec + 0.1), availableRange.upperBound)
        lyricCues = lyricCues.filter(\.isValid)
    }
}
