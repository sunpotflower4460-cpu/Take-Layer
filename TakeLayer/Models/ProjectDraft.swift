import Foundation

struct ProjectDraft: Identifiable, Codable {
    var id = UUID()
    var title: String
    var importedVideo: ImportedVideo?
    var recordedTake: RecordedTake?
    var importedMasterAudio: ImportedMasterAudio?
    var songStartRawSec: Double?
    var songStartAudioSec: Double?
    var selectedRawStartSec: Double?
    var selectedRawEndSec: Double?
    var offsetMs: Double
    var exportSettings: ExportSettings
    var shortEditDraft: ShortEditDraft?
    var songMemoryLink: ProjectSongMemoryLink?
    var createdAt: Date
    var updatedAt: Date

    var activeVideo: ImportedVideo? {
        recordedTake?.importedVideo ?? importedVideo
    }

    var activeVideoURL: URL? {
        activeVideo?.url
    }

    init(title: String = "Untitled TakeLayer Project") {
        let now = Date()
        self.title = title
        self.offsetMs = 0
        self.exportSettings = ExportSettings()
        self.shortEditDraft = nil
        self.songMemoryLink = nil
        self.createdAt = now
        self.updatedAt = now
    }
}
