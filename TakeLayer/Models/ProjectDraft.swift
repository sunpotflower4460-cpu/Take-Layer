import Foundation

struct ProjectDraft: Identifiable {
    var id = UUID()
    var title: String
    var importedVideo: ImportedVideo?
    var importedMasterAudio: ImportedMasterAudio?
    var songStartRawSec: Double?
    var songStartAudioSec: Double?
    var selectedRawStartSec: Double?
    var selectedRawEndSec: Double?
    var exportSettings: ExportSettings

    init(title: String = "Untitled TakeLayer PoC") {
        self.title = title
        self.exportSettings = ExportSettings()
    }
}
