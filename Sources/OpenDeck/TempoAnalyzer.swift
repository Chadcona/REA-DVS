import AVFoundation
import Foundation

enum TempoAnalyzer {
    /// Estimates tempo from a local audio file using an onset envelope and autocorrelation.
    /// The result is a starting point for DJ preparation, not a replacement for beat-grid review.
    static func estimateBPM(url: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: url)
        let windowSize = 1_024
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(windowSize))!
        var energy: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: buffer.frameCapacity)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { continue }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            energy.append(sqrt(sum / Float(count)))
        }
        guard energy.count > 32 else { return nil }
        var onsets = Array(repeating: Float(0), count: energy.count)
        for index in 1..<energy.count { onsets[index] = max(0, energy[index] - energy[index - 1]) }
        let peak = onsets.max() ?? 0
        guard peak > 0 else { return nil }
        onsets = onsets.map { $0 / peak }

        let envelopeRate = file.processingFormat.sampleRate / Double(windowSize)
        var bestBPM: Double?
        var bestScore: Float = 0
        for halfBPM in 120...400 { // 60.0 ... 200.0 BPM in 0.5 increments
            let bpm = Double(halfBPM) / 2
            let lag = Int((60 / bpm * envelopeRate).rounded())
            guard lag > 0, lag < onsets.count else { continue }
            var score: Float = 0
            for index in lag..<onsets.count { score += onsets[index] * onsets[index - lag] }
            if score > bestScore {
                bestScore = score
                bestBPM = bpm
            }
        }
        return bestBPM
    }
}
