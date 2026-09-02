import AVFoundation
import Foundation

enum TonalEvidenceExtractor {
    private static let windowSize = 4_096
    private static let lowestMIDINote = 36   // C2
    private static let highestMIDINote = 95  // B6
    private static let referenceAHz = 440.0
    private static let centOffsets = [-35.0, 0.0, 35.0]

    static func extract(from url: URL) throws -> TonalEvidenceVector {
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

        var flattenedFrames: [Double] = []
        flattenedFrames.reserveCapacity(TonalEvidenceVector.frameCount * TonalEvidenceVector.pitchClassCount)
        var global = Array(repeating: 0.0, count: TonalEvidenceVector.pitchClassCount)

        for analysisIndex in 0..<TonalEvidenceVector.frameCount {
            let samples = try readWindow(
                from: audioFile,
                format: format,
                totalFrames: totalFrames,
                analysisIndex: analysisIndex
            )
            let chroma = chromaVector(samples: samples, sampleRate: sampleRate)
            flattenedFrames.append(contentsOf: chroma)
            for pitchClass in 0..<TonalEvidenceVector.pitchClassCount {
                global[pitchClass] += chroma[pitchClass]
            }
        }

        let normalizedGlobal = normalizeAndQuantize(global)
        return TonalEvidenceVector(
            pitchClassFrames: flattenedFrames,
            globalPitchClass: normalizedGlobal,
            referenceAHz: referenceAHz
        )
    }

    private static func readWindow(
        from audioFile: AVAudioFile,
        format: AVAudioFormat,
        totalFrames: AVAudioFramePosition,
        analysisIndex: Int
    ) throws -> [Double] {
        let relativeCenter = (Double(analysisIndex) + 0.5) / Double(TonalEvidenceVector.frameCount)
        let centerFrame = AVAudioFramePosition(relativeCenter * Double(totalFrames))
        let halfWindow = AVAudioFramePosition(windowSize / 2)
        let maximumStart = max(0, totalFrames - AVAudioFramePosition(windowSize))
        let startFrame = min(max(0, centerFrame - halfWindow), maximumStart)
        let available = max(0, totalFrames - startFrame)
        let frameCount = AVAudioFrameCount(min(AVAudioFramePosition(windowSize), available))

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(windowSize)
              ) else {
            throw AudioEvidenceExtractorError.unsupportedPCMFormat
        }

        audioFile.framePosition = startFrame
        do {
            try audioFile.read(into: buffer, frameCount: frameCount)
        } catch {
            throw AudioEvidenceExtractorError.unreadableAudio
        }

        guard let channelData = buffer.floatChannelData else {
            throw AudioEvidenceExtractorError.unsupportedPCMFormat
        }

        let actualFrames = Int(buffer.frameLength)
        guard actualFrames > 0 else {
            throw AudioEvidenceExtractorError.emptyAudio
        }

        var mono = Array(repeating: 0.0, count: windowSize)
        var mean = 0.0
        for frame in 0..<actualFrames {
            var value = 0.0
            for channel in 0..<Int(format.channelCount) {
                value += Double(channelData[channel][frame])
            }
            value /= Double(format.channelCount)
            mono[frame] = value
            mean += value
        }
        mean /= Double(actualFrames)

        if actualFrames == 1 {
            mono[0] -= mean
            return mono
        }

        for frame in 0..<actualFrames {
            let hann = 0.5 - 0.5 * cos((2 * .pi * Double(frame)) / Double(actualFrames - 1))
            mono[frame] = (mono[frame] - mean) * hann
        }
        return mono
    }

    private static func chromaVector(samples: [Double], sampleRate: Double) -> [Double] {
        var pitchClasses = Array(repeating: 0.0, count: TonalEvidenceVector.pitchClassCount)
        let nyquist = sampleRate / 2

        for midiNote in lowestMIDINote...highestMIDINote {
            let baseFrequency = referenceAHz * pow(2, Double(midiNote - 69) / 12)
            guard baseFrequency < nyquist * 0.95 else { continue }

            var strongestPower = 0.0
            for cents in centOffsets {
                let frequency = baseFrequency * pow(2, cents / 1_200)
                guard frequency < nyquist * 0.98 else { continue }
                strongestPower = max(
                    strongestPower,
                    goertzelPower(samples: samples, sampleRate: sampleRate, frequency: frequency)
                )
            }

            // Fold octave information into one of the twelve pitch classes.
            pitchClasses[midiNote % TonalEvidenceVector.pitchClassCount] += sqrt(max(0, strongestPower))
        }

        return normalizeAndQuantize(pitchClasses)
    }

    private static func goertzelPower(
        samples: [Double],
        sampleRate: Double,
        frequency: Double
    ) -> Double {
        guard !samples.isEmpty, sampleRate > 0, frequency > 0 else { return 0 }

        let omega = 2 * .pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var previous = 0.0
        var previous2 = 0.0

        for sample in samples {
            let current = sample + coefficient * previous - previous2
            previous2 = previous
            previous = current
        }

        return max(0, previous * previous + previous2 * previous2 - coefficient * previous * previous2)
    }

    private static func normalizeAndQuantize(_ values: [Double]) -> [Double] {
        let total = values.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 0, count: values.count)
        }
        return values.map { value in
            let normalized = value / total
            return (normalized * 1_000_000).rounded() / 1_000_000
        }
    }
}
