import AVFoundation
import SwiftUI

@MainActor
final class DeckAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var file: AVAudioFile?
    private var scheduledStartFrame: AVAudioFramePosition = 0

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    func load(url: URL) throws -> TimeInterval {
        let newFile = try AVAudioFile(forReading: url)
        file = newFile
        scheduledStartFrame = 0
        player.stop()
        schedule(from: 0)
        return Double(newFile.length) / newFile.processingFormat.sampleRate
    }

    func play() throws {
        try startEngineIfNeeded()
        if !player.isPlaying { player.play() }
    }

    func pause() {
        scheduledStartFrame = currentFrame
        player.pause()
    }

    func cue() {
        player.stop()
        scheduledStartFrame = 0
        schedule(from: 0)
    }

    func setGain(_ gain: Double) {
        player.volume = Float(gain)
    }

    func setPitchPercent(_ percent: Double) {
        timePitch.rate = Float(max(0.5, min(2.0, 1 + percent / 100)))
    }

    var currentTime: TimeInterval {
        guard let file else { return 0 }
        return Double(currentFrame) / file.processingFormat.sampleRate
    }

    private var currentFrame: AVAudioFramePosition {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return scheduledStartFrame }
        return min(scheduledStartFrame + AVAudioFramePosition(playerTime.sampleTime), file?.length ?? 0)
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file else { return }
        let start = max(0, min(frame, file.length))
        let remaining = AVAudioFrameCount(max(0, file.length - start))
        guard remaining > 0 else { return }
        scheduledStartFrame = start
        player.scheduleSegment(file, startingFrame: start, frameCount: remaining, at: nil)
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }
}

@Observable
@MainActor
final class Deck {
    enum Side: String { case left = "A", right = "B" }

    let side: Side
    var trackName = "No track loaded"
    var artist = ""
    var duration: TimeInterval = 0
    var elapsed: TimeInterval = 0
    var bpm: Double = 120
    var pitch: Double = 0 { didSet { audio.setPitchPercent(pitch) } }
    var gain: Double = 0.8 { didSet { updateOutputGain() } }
    var filter: Double = 0
    var isPlaying = false
    var isCueing = false
    var loopLength: Int? = nil
    var waveform: [Float] = []
    private let audio = DeckAudioEngine()
    private var mixerGain: Double = 1

    init(side: Side) {
        self.side = side
        updateOutputGain()
    }

    var progress: Double { duration > 0 ? elapsed / duration : 0 }
    var pitchLabel: String { String(format: "%+.1f%%", pitch) }

    func load(url: URL) throws {
        duration = try audio.load(url: url)
        waveform = try WaveformAnalyzer.analyze(url: url)
        if let estimatedBPM = try TempoAnalyzer.estimateBPM(url: url) { bpm = estimatedBPM }
        trackName = url.deletingPathExtension().lastPathComponent
        artist = "Local audio file"
        elapsed = 0
        isPlaying = false
    }

    func load(track: LibraryTrack) throws {
        try load(url: track.url)
        waveform = track.waveform
        if let estimatedBPM = track.estimatedBPM { bpm = estimatedBPM }
    }

    func playPause() {
        guard duration > 0 else { return }
        do {
            if isPlaying {
                audio.pause()
                elapsed = audio.currentTime
                isPlaying = false
            } else {
                try audio.play()
                isPlaying = true
            }
        } catch {
            trackName = "Could not play this audio file"
            artist = error.localizedDescription
            isPlaying = false
        }
    }
    func cue() {
        audio.cue()
        elapsed = 0
        isCueing = true
    }
    func toggleLoop(_ beats: Int) { loopLength = loopLength == beats ? nil : beats }
    func setMixerGain(_ value: Double) {
        mixerGain = max(0, min(1, value))
        updateOutputGain()
    }
    func refreshPlaybackTime() {
        guard isPlaying else { return }
        elapsed = audio.currentTime
        if elapsed >= duration { isPlaying = false }
    }

    private func updateOutputGain() {
        audio.setGain(gain * mixerGain)
    }
}

@Observable
@MainActor
final class DJSession {
    let leftDeck = Deck(side: .left)
    let rightDeck = Deck(side: .right)
    var crossfader: Double = 0 { didSet { applyMixerLevels() } }
    var masterGain: Double = 0.8 { didSet { applyMixerLevels() } }
    var syncEnabled = false
    let midi = MIDIControllerService()
    let library = TrackLibrary()
    let crates = CrateStore()
    let seratoScanner = SeratoImportScanner()

    init() { applyMixerLevels() }

    func sync() {
        rightDeck.bpm = leftDeck.bpm
        syncEnabled = true
    }

    private func applyMixerLevels() {
        let leftLevel = masterGain * (crossfader > 0 ? 1 - crossfader : 1)
        let rightLevel = masterGain * (crossfader < 0 ? 1 + crossfader : 1)
        leftDeck.setMixerGain(leftLevel)
        rightDeck.setMixerGain(rightLevel)
    }
}
