import Foundation

/// Result of a local export. Foundation-only so Core, Rendering and the iOS app share one type.
struct ExportResult {
    var outputURL: URL
    var durationSec: Double
}
