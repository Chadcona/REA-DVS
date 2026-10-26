import AVFoundation
import Foundation

enum WaveformAnalyzer {
    static func analyze(url: URL, pointCount: Int = 320) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let totalFrames = max(1, Int(file.length))
        let framesPerPoint = max(1, totalFrames / pointCount)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192)!
        var points: [Float] = []
        var pointPeak: Float = 0
        var framesInPoint = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: buffer.frameCapacity)
            guard let channel = buffer.floatChannelData?[0] else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                pointPeak = max(pointPeak, abs(channel[frame]))
                framesInPoint += 1
                if framesInPoint >= framesPerPoint {
                    points.append(pointPeak)
                    pointPeak = 0
                    framesInPoint = 0
                }
            }
        }
        if framesInPoint > 0 { points.append(pointPeak) }
        guard let maximum = points.max(), maximum > 0 else { return Array(repeating: 0, count: pointCount) }
        return points.map { min(1, sqrt($0 / maximum)) }
    }
}
