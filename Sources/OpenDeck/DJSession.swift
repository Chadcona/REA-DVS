import AVFoundation
import SwiftUI

@MainActor
final class DeckAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let filterEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private var file: AVAudioFile?
    private var scheduledStartFrame: AVAudioFramePosition = 0

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(filterEQ)
        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: filterEQ, format: nil)
        engine.connect(filterEQ, to: delay, format: nil)
        engine.connect(delay, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        filterEQ.bands[0].filterType = .lowPass
        filterEQ.bands[0].bypass = true
        filterEQ.bands[1].filterType = .highPass
        filterEQ.bands[1].bypass = true
        delay.delayTime = 0.35
        delay.feedback = 32
        delay.wetDryMix = 0
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
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

    func jump(to seconds: TimeInterval, shouldPlay: Bool) throws {
        guard let file else { return }
        player.stop()
        let frame = AVAudioFramePosition((seconds * file.processingFormat.sampleRate).rounded())
        schedule(from: frame)
        if shouldPlay {
            try startEngineIfNeeded()
            player.play()
        }
    }

    func setGain(_ gain: Double) {
        player.volume = Float(gain)
    }

    func setPitchPercent(_ percent: Double) {
        timePitch.rate = Float(max(0.5, min(2.0, 1 + percent / 100)))
    }

    func setFilter(_ value: Double) {
        let amount = min(1, abs(value))
        if value < 0 {
            filterEQ.bands[0].bypass = false
            filterEQ.bands[0].frequency = Float(20_000 * pow(0.006, amount))
            filterEQ.bands[1].bypass = true
        } else if value > 0 {
            filterEQ.bands[0].bypass = true
            filterEQ.bands[1].bypass = false
            filterEQ.bands[1].frequency = Float(20 * pow(50, amount))
        } else {
            filterEQ.bands[0].bypass = true
            filterEQ.bands[1].bypass = true
        }
    }

    func setEcho(_ amount: Double) { delay.wetDryMix = Float(amount * 100) }
    func setReverb(_ amount: Double) { reverb.wetDryMix = Float(amount * 100) }

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
    struct ManualLoop: Equatable {
        let beats: Int
        let start: TimeInterval
        let end: TimeInterval
    }
    enum Side: String { case left = "A", right = "B" }

    let side: Side
    var trackName = "No track loaded"
    var artist = ""
    var duration: TimeInterval = 0
    var elapsed: TimeInterval = 0
    var bpm: Double = 120
    var pitch: Double = 0 { didSet { audio.setPitchPercent(pitch) } }
    var gain: Double = 0.8 { didSet { updateOutputGain() } }
    var filter: Double = 0 { didSet { audio.setFilter(filter) } }
    var echo: Double = 0 { didSet { audio.setEcho(echo) } }
    var reverb: Double = 0 { didSet { audio.setReverb(reverb) } }
    var isPlaying = false
    var isCueing = false
    var loopLength: Int? = nil
    var waveform: [Float] = []
    var cuePoints: [CuePoint] = []
    var savedLoops: [SavedLoop] = []
    var activeSavedLoop: SavedLoop?
    var activeManualLoop: ManualLoop?
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
        cuePoints = []
        savedLoops = []
        activeSavedLoop = nil
        activeManualLoop = nil
        trackName = url.deletingPathExtension().lastPathComponent
        artist = "Local audio file"
        elapsed = 0
        isPlaying = false
    }

    func load(track: LibraryTrack) throws {
        try load(url: track.url)
        waveform = track.waveform
        if let estimatedBPM = track.estimatedBPM { bpm = estimatedBPM }
        cuePoints = track.cuePoints
        savedLoops = track.savedLoops
    }

    func triggerCue(_ cue: CuePoint) {
        do {
            try audio.jump(to: cue.position, shouldPlay: isPlaying)
            elapsed = cue.position
        } catch {
            artist = error.localizedDescription
        }
    }

    func toggleSavedLoop(_ loop: SavedLoop) {
        if activeSavedLoop?.id == loop.id {
            activeSavedLoop = nil
            return
        }
        do {
            try audio.jump(to: TimeInterval(loop.startMilliseconds) / 1_000, shouldPlay: true)
            elapsed = TimeInterval(loop.startMilliseconds) / 1_000
            isPlaying = true
            activeSavedLoop = loop
            activeManualLoop = nil
            loopLength = nil
        } catch {
            artist = error.localizedDescription
        }
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
    func toggleLoop(_ beats: Int) {
        if activeManualLoop?.beats == beats {
            activeManualLoop = nil
            loopLength = nil
            return
        }
        let start = elapsed
        let loopSeconds = Double(beats) * 60 / bpm
        activeManualLoop = ManualLoop(beats: beats, start: start, end: min(duration, start + loopSeconds))
        activeSavedLoop = nil
        loopLength = beats
    }
    func setMixerGain(_ value: Double) {
        mixerGain = max(0, min(1, value))
        updateOutputGain()
    }
    func refreshPlaybackTime() {
        guard isPlaying else { return }
        elapsed = audio.currentTime
        let loopRange: (start: TimeInterval, end: TimeInterval)?
        if let loop = activeSavedLoop {
            loopRange = (TimeInterval(loop.startMilliseconds) / 1_000, TimeInterval(loop.endMilliseconds) / 1_000)
        } else if let loop = activeManualLoop {
            loopRange = (loop.start, loop.end)
        } else {
            loopRange = nil
        }
        if let loopRange, elapsed >= loopRange.end {
            do {
                try audio.jump(to: loopRange.start, shouldPlay: true)
                elapsed = loopRange.start
            } catch {
                activeSavedLoop = nil
                artist = error.localizedDescription
            }
        }
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
    let midiMappings = MIDIMapStore()

    init() {
        applyMixerLevels()
        midi.onMessage = { [weak self] message in self?.handleMIDI(message) }
    }

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

    private func handleMIDI(_ message: MIDIMessage) {
        if midiMappings.pendingAction != nil {
            midiMappings.learn(message)
            return
        }
        guard let action = midiMappings.action(for: message) else { return }
        let normalized = Double(message.data2) / 127
        switch action {
        case .deckAPlayPause: if message.data2 > 0 { leftDeck.playPause() }
        case .deckBPlayPause: if message.data2 > 0 { rightDeck.playPause() }
        case .crossfader: crossfader = normalized * 2 - 1
        case .deckAFilter: leftDeck.filter = normalized * 2 - 1
        case .deckBFilter: rightDeck.filter = normalized * 2 - 1
        case .deckAEcho: leftDeck.echo = normalized
        case .deckBEcho: rightDeck.echo = normalized
        case .deckAReverb: leftDeck.reverb = normalized
        case .deckBReverb: rightDeck.reverb = normalized
        case .deckACue1: triggerCue(leftDeck, index: 0, message: message)
        case .deckACue2: triggerCue(leftDeck, index: 1, message: message)
        case .deckACue3: triggerCue(leftDeck, index: 2, message: message)
        case .deckACue4: triggerCue(leftDeck, index: 3, message: message)
        case .deckBCue1: triggerCue(rightDeck, index: 0, message: message)
        case .deckBCue2: triggerCue(rightDeck, index: 1, message: message)
        case .deckBCue3: triggerCue(rightDeck, index: 2, message: message)
        case .deckBCue4: triggerCue(rightDeck, index: 3, message: message)
        case .deckALoop4: if message.data2 > 0 { leftDeck.toggleLoop(4) }
        case .deckBLoop4: if message.data2 > 0 { rightDeck.toggleLoop(4) }
        }
    }

    private func triggerCue(_ deck: Deck, index: Int, message: MIDIMessage) {
        guard message.data2 > 0, deck.cuePoints.indices.contains(index) else { return }
        deck.triggerCue(deck.cuePoints[index])
    }
}
