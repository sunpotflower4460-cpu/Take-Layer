import AVFoundation
import CoreVideo
import Foundation

/// Generates tiny deterministic media so the full headless pipeline can be proven on a Mac
/// without any real footage: a silent H.264 video and a PCM16 mono "master" WAV.
enum SelfTestMedia {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func makeVideo(at url: URL, seconds: Double, width: Int, height: Int, fps: Int32) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw Failure(message: "video writer failed to start: \(writer.error?.localizedDescription ?? "?")") }
        writer.startSession(atSourceTime: .zero)
        let total = Int(seconds * Double(fps))
        for frame in 0..<total {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pixelBuffer = buffer else { throw Failure(message: "cannot allocate pixel buffer") }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, Int32((frame * 5) % 200 + 30), CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                throw Failure(message: "append failed: \(writer.error?.localizedDescription ?? "?")")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure(message: "video writer ended \(writer.status.rawValue): \(writer.error?.localizedDescription ?? "?")") }
    }

    static func makeWav(at url: URL, seconds: Double, sampleRate: Int = 48_000, frequency: Double = 440) throws {
        let frames = Int(seconds * Double(sampleRate))
        var pcm = Data(capacity: frames * 2)
        for n in 0..<frames {
            let sample = Int16((sin(2 * Double.pi * frequency * Double(n) / Double(sampleRate)) * 0.4 * 32767).rounded())
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8)); header.append(le32(UInt32(36 + pcm.count)))
        header.append(contentsOf: Array("WAVE".utf8)); header.append(contentsOf: Array("fmt ".utf8))
        header.append(le32(16)); header.append(le16(1)); header.append(le16(1))
        header.append(le32(UInt32(sampleRate))); header.append(le32(UInt32(sampleRate * 2)))
        header.append(le16(2)); header.append(le16(16))
        header.append(contentsOf: Array("data".utf8)); header.append(le32(UInt32(pcm.count)))
        try (header + pcm).write(to: url, options: .atomic)
    }
}
