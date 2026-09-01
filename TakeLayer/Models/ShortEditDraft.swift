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

    var validLyricCues: [ShortLyricCue] {
        lyricCues.filter(\.isValid).sorted(by: lyricSort)
    }

    var lyricCuesIntersectingSelectedRange: [ShortLyricCue] {
        lyricCues.filter { cueIntersectsSelectedRange($0) }
    }

    var hasInvalidLyricCues: Bool {
        lyricCuesIntersectingSelectedRange.contains { !$0.isValid }
    }

    var hasOverlappingValidLyricCues: Bool {
        let cues = lyricCuesIntersectingSelectedRange.filter(\.isValid).sorted(by: lyricSort)
        guard cues.count > 1 else { return false }
        for index in 1..<cues.count where cues[index].startProjectSec < cues[index - 1].endProjectSec {
            return true
        }
        return false
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

        let availableDuration = max(0, availableRange.upperBound - availableRange.lowerBound)
        let minimumDuration = min(0.1, availableDuration)
        let latestStart = max(availableRange.lowerBound, availableRange.upperBound - minimumDuration)

        rangeStartProjectSec = min(max(rangeStartProjectSec, availableRange.lowerBound), latestStart)
        rangeEndProjectSec = min(
            max(rangeEndProjectSec, rangeStartProjectSec + minimumDuration),
            availableRange.upperBound
        )

        // Keep incomplete/temporarily invalid lyric cues so the editor never
        // destroys user-entered lyrics while normalizing unrelated fields.
    }

    private func cueIntersectsSelectedRange(_ cue: ShortLyricCue) -> Bool {
        guard cue.startProjectSec.isFinite, cue.endProjectSec.isFinite else {
            // An unlocatable cue cannot safely be proven outside the selected
            // range, so keep it visible to validation until the user repairs it.
            return true
        }

        let selectionStart = min(rangeStartProjectSec, rangeEndProjectSec)
        let selectionEnd = max(rangeStartProjectSec, rangeEndProjectSec)
        let cueStart = min(cue.startProjectSec, cue.endProjectSec)
        let cueEnd = max(cue.startProjectSec, cue.endProjectSec)

        if cueStart == cueEnd {
            return cueStart >= selectionStart && cueStart < selectionEnd
        }
        return cueEnd > selectionStart && cueStart < selectionEnd
    }

    private func lyricSort(_ lhs: ShortLyricCue, _ rhs: ShortLyricCue) -> Bool {
        if lhs.startProjectSec == rhs.startProjectSec {
            return lhs.endProjectSec < rhs.endProjectSec
        }
        return lhs.startProjectSec < rhs.startProjectSec
    }
}
