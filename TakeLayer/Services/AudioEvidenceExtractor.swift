import AVFoundation
import CryptoKit
import Foundation

enum AudioEvidenceExtractorError: LocalizedError {
    case unreadableAudio
    case unsupportedPCMFormat
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .unreadableAudio:
            return "Song Resolver用にWAVを読み込めませんでした。"
        case .unsupportedPCMFormat:
            return "Song Resolverが扱えるPCM形式へ変換できませんでした。"
        case .emptyAudio:
            return "Song Resolverで解析できる音声サンプルがありません。"
        }
    }
}

enum AudioEvidenceExtractor {
    static func extract(from url: URL) throws -> AudioEvidenceVector {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioEvidenceExtractorError.unreadableAudio
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let totalFrames = audioFile.length

        guard sampleRate > 0, channelCount > 0, totalFrames > 0 else {
            throw AudioEvidenceExtractorError.emptyAudio
        }

        let bucketCount = AudioEvidenceVector.bucketCount
        var energySums = Array(repeating: 0.0, count: bucketCount)
        var transientSums = Array(repeating: 0.0, count: bucketCount)
        var sampleCounts = Array(repeating: 0, count: bucketCount)

        let chunkFrames: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw AudioEvidenceExtractorError.unsupportedPCMFormat
        }

        var frameCursor: AVAudioFramePosition = 0
        var previousMono: Double?

        while frameCursor < totalFrames {
            buffer.frameLength = 0
            let remaining = totalFrames - frameCursor
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), remaining))

            do {
                try audioFile.read(into: buffer, frameCount: framesToRead)
            } catch {
                throw AudioEvidenceExtractorError.unreadableAudio
            }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channelData = buffer.floatChannelData else {
                throw AudioEvidenceExtractorError.unsupportedPCMFormat
            }

            for frameIndex in 0..<frameLength {
                var mono = 0.0
                var meanSquare = 0.0

                for channel in 0..<channelCount {
                    let sample = Double(channelData[channel][frameIndex])
                    mono += sample
                    meanSquare += sample * sample
                }

                mono /= Double(channelCount)
                meanSquare /= Double(channelCount)

                let absoluteFrame = frameCursor + AVAudioFramePosition(frameIndex)
                let progress = Double(absoluteFrame) / Double(totalFrames)
                let bucket = min(bucketCount - 1, max(0, Int(progress * Double(bucketCount))))

                energySums[bucket] += meanSquare
                if let previousMono {
                    transientSums[bucket] += abs(mono - previousMono)
                }
                sampleCounts[bucket] += 1
                previousMono = mono
            }

            frameCursor += AVAudioFramePosition(frameLength)
        }

        guard sampleCounts.reduce(0, +) > 0 else {
            throw AudioEvidenceExtractorError.emptyAudio
        }

        let rmsEnvelope = zip(energySums, sampleCounts).map { sum, count -> Double in
            guard count > 0 else { return 0 }
            return sqrt(sum / Double(count))
        }
        let transientEnvelope = zip(transientSums, sampleCounts).map { sum, count -> Double in
            guard count > 0 else { return 0 }
            return sum / Double(count)
        }

        let normalizedEnergy = normalized(rmsEnvelope)
        let normalizedTransient = normalized(transientEnvelope)
        let durationSec = Double(totalFrames) / sampleRate
        let signature = makeSignature(
            durationSec: durationSec,
            energyEnvelope: normalizedEnergy,
            transientEnvelope: normalizedTransient
        )

        return AudioEvidenceVector(
            durationSec: durationSec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            energyEnvelope: normalizedEnergy,
            transientEnvelope: normalizedTransient,
            signature: signature
        )
    }

    private static func normalized(_ values: [Double]) -> [Double] {
        guard let maximum = values.max(), maximum > 0 else {
            return Array(repeating: 0, count: values.count)
        }
        return values.map { value in
            let normalized = value / maximum
            return (normalized * 1_000_000).rounded() / 1_000_000
        }
    }

    private static func makeSignature(
        durationSec: Double,
        energyEnvelope: [Double],
        transientEnvelope: [Double]
    ) -> String {
        let durationMs = Int((durationSec * 1_000).rounded())
        let quantizedEnergy = energyEnvelope.map { Int(($0 * 1_000).rounded()) }
        let quantizedTransient = transientEnvelope.map { Int(($0 * 1_000).rounded()) }
        let payload = "\(durationMs)|E:\(quantizedEnergy.map(String.init).joined(separator: ","))|T:\(quantizedTransient.map(String.init).joined(separator: ","))"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
