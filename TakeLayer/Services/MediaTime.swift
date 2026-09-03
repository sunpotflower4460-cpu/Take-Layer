import AVFoundation
import Foundation

/// Shared AVFoundation time conversion for all deterministic render paths.
///
/// A microsecond timescale makes millisecond user offsets exactly representable
/// and avoids renderer-specific rounding differences between normal and Short export.
enum MediaTime {
    static let timescale: CMTimeScale = 1_000_000

    static func make(_ seconds: Double) -> CMTime {
        guard seconds.isFinite else { return .invalid }
        let ticks = (seconds * Double(timescale)).rounded()
        guard ticks >= Double(Int64.min), ticks <= Double(Int64.max) else { return .invalid }
        return CMTime(value: Int64(ticks), timescale: timescale)
    }
}
