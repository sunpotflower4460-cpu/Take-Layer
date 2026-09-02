import AVFoundation
import Foundation
import XCTest
@testable import TakeLayer

final class AudioEvidenceExtractorTests: XCTestCase {
    func testSyntheticWAVProducesStableFixedSizeEvidence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeLayer-AudioEvidence-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let sampleRate = 8_000.0
        let channelCount: AVAudioChannelCount = 1
        let frameCount = AVAudioFrameCount(sampleRate * 2)
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channelCount,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let envelope = frame < Int(frameCount / 2) ? 0.25 : 0.85
            let sample = sin(2 * .pi * 220 * time) * envelope
            samples[frame] = Float(sample)
        }

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
        }

        let first = try AudioEvidenceExtractor.extract(from: url)
        let second = try AudioEvidenceExtractor.extract(from: url)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.energyEnvelope.count, AudioEvidenceVector.bucketCount)
        XCTAssertEqual(first.transientEnvelope.count, AudioEvidenceVector.bucketCount)
        XCTAssertEqual(first.sampleRate, sampleRate, accuracy: 0.001)
        XCTAssertEqual(first.channelCount, 1)
        XCTAssertEqual(first.durationSec, 2, accuracy: 0.01)
        XCTAssertEqual(first.signature.count, 64)
        XCTAssertGreaterThan(first.energyEnvelope.max() ?? 0, 0.99)
        XCTAssertFalse(first.energyEnvelope.allSatisfy { $0 == 0 })
    }
}
