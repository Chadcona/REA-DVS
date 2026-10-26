import Combine
import CoreMIDI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var session: DJSession

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 14) {
                DeckView(deck: session.leftDeck, accent: .cyan)
                MixerView(session: session)
                DeckView(deck: session.rightDeck, accent: .orange)
            }
            LibraryView(session: session)
            SeratoImportView(session: session)
            MIDIStatusView(midi: session.midi)
            MIDILearnView(mappings: session.midiMappings)
        }
        .padding(18)
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Label("OPENDECK", systemImage: "waveform.path.ecg")
                .font(.headline.weight(.bold))
            Spacer()
            Text("Clean-room DJ prototype")
                .foregroundStyle(.secondary)
            Button("Sync") { session.sync() }
                .buttonStyle(.borderedProminent)
                .tint(session.syncEnabled ? .green : .indigo)
        }
    }
}

private struct MIDILearnView: View {
    @Bindable var mappings: MIDIMapStore
    @State private var action: MIDIAction = .deckAPlayPause

    var body: some View {
        HStack {
            Text("MIDI learn").font(.caption.weight(.semibold))
            Picker("Action", selection: $action) {
                ForEach(MIDIAction.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            Button(mappings.pendingAction == nil ? "Learn next input" : "Listening…") {
                mappings.pendingAction = mappings.pendingAction == nil ? action : nil
            }
            .buttonStyle(.bordered)
            Spacer()
            Text("\(mappings.mappings.count) mappings")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
    }
}

private struct DeckView: View {
    @Bindable var deck: Deck
    let accent: Color
    @State private var isImporting = false
    private let playbackClock = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DECK \(deck.side.rawValue)").font(.headline)
                Spacer()
                Button("Load") { isImporting = true }
                    .buttonStyle(.bordered)
                Text(deck.pitchLabel).monospacedDigit().foregroundStyle(accent)
            }
            .padding(.horizontal, 4)

            WaveformView(samples: deck.waveform, progress: deck.progress, accent: accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.trackName).font(.title3.weight(.semibold))
                Text(deck.artist.isEmpty ? "Drag a local audio file here (next milestone)" : deck.artist)
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f BPM", deck.bpm)).font(.caption.monospacedDigit()).foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("CUE") { deck.cue() }.buttonStyle(.bordered)
                Button(deck.isPlaying ? "PAUSE" : "PLAY") { deck.playPause() }
                    .buttonStyle(.borderedProminent).tint(accent)
                ForEach([1, 2, 4, 8], id: \.self) { beats in
                    Button("\(beats)") { deck.toggleLoop(beats) }
                        .buttonStyle(.bordered)
                        .tint(deck.loopLength == beats ? accent : .gray)
                }
            }
            if !deck.cuePoints.isEmpty {
                HStack(spacing: 6) {
                    ForEach(deck.cuePoints.prefix(8)) { cue in
                        Button(cue.name.isEmpty ? "C\(cue.index + 1)" : cue.name) {
                            deck.triggerCue(cue)
                        }
                        .lineLimit(1)
                        .buttonStyle(.bordered)
                        .tint(Color(hex: cue.colorHex) ?? accent)
                    }
                }
            }
            if !deck.savedLoops.isEmpty {
                HStack(spacing: 6) {
                    ForEach(deck.savedLoops.prefix(8)) { loop in
                        Button(loop.name.isEmpty ? "L\(loop.index + 1)" : loop.name) {
                            deck.toggleSavedLoop(loop)
                        }
                        .lineLimit(1)
                        .buttonStyle(.bordered)
                        .tint(deck.activeSavedLoop?.id == loop.id ? .mint : (Color(hex: loop.colorHex) ?? accent))
                    }
                }
            }
            HStack {
                ControlSlider(title: "Pitch", value: $deck.pitch, range: -8...8, tint: accent)
                ControlSlider(title: "Gain", value: $deck.gain, range: 0...1, tint: accent)
                ControlSlider(title: "Filter", value: $deck.filter, range: -1...1, tint: accent)
            }
            HStack {
                ControlSlider(title: "Echo", value: $deck.echo, range: 0...1, tint: accent)
                ControlSlider(title: "Reverb", value: $deck.reverb, range: 0...1, tint: accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.45)))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            guard case let .success(url) = result else { return }
            do { try deck.load(url: url) }
            catch {
                deck.trackName = "Could not load this audio file"
                deck.artist = error.localizedDescription
            }
        }
        .onReceive(playbackClock) { _ in deck.refreshPlaybackTime() }
    }
}

private extension Color {
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}


private struct MixerView: View {
    @Bindable var session: DJSession

    var body: some View {
        VStack(spacing: 18) {
            Text("MIXER").font(.headline)
            ControlSlider(title: "Master", value: $session.masterGain, range: 0...1, tint: .white)
                .frame(width: 64)
            Text("Crossfader").font(.caption).foregroundStyle(.secondary)
            Slider(value: $session.crossfader, in: -1...1)
                .frame(width: 160)
                .rotationEffect(.degrees(-90))
                .frame(height: 170)
            HStack { Text("A"); Spacer(); Text("B") }
                .font(.caption.weight(.bold)).frame(width: 165)
        }
        .padding(16)
        .frame(width: 210)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: $value, in: range).tint(tint)
        }
    }
}

private struct WaveformView: View {
    let samples: [Float]
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let center = size.height / 2
                let visibleSamples = samples.isEmpty ? Array(repeating: Float(0.18), count: 80) : samples
                var path = Path()
                for index in visibleSamples.indices {
                    let x = size.width * CGFloat(index) / CGFloat(max(1, visibleSamples.count - 1))
                    let height = CGFloat(visibleSamples[index]) * center
                    path.move(to: CGPoint(x: x, y: center - height))
                    path.addLine(to: CGPoint(x: x, y: center + height))
                }
                context.stroke(path, with: .color(accent.opacity(0.75)), lineWidth: 1)
                let marker = size.width * progress
                context.stroke(Path(CGRect(x: marker, y: 0, width: 1, height: size.height)), with: .color(.white), lineWidth: 2)
            }
        }
        .frame(height: 120)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LibraryView: View {
    @Bindable var session: DJSession
    @State private var isImporting = false
    @State private var newCrateName = ""
    @State private var selectedCrateID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Library", systemImage: "music.note.list")
                    .font(.headline)
                Text("\(session.library.tracks.count) local tracks")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import audio") { isImporting = true }
                    .buttonStyle(.bordered)
            }
            HStack {
                Picker("Crate", selection: $selectedCrateID) {
                    Text("All tracks").tag(UUID?.none)
                    ForEach(session.crates.crates) { crate in
                        Text("\(crate.name) (\(crate.trackIDs.count))").tag(Optional(crate.id))
                    }
                }
                .labelsHidden()
                TextField("New crate", text: $newCrateName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button("Create") {
                    session.crates.create(name: newCrateName)
                    newCrateName = ""
                }
                .buttonStyle(.bordered)
                .disabled(newCrateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let importError = session.library.importError {
                Text(importError).font(.caption).foregroundStyle(.red)
            }
            let visibleTracks = session.crates.tracks(in: selectedCrateID, from: session.library.tracks)
            if visibleTracks.isEmpty {
                Text("Import locally owned music to build your OpenDeck library.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visibleTracks) { track in
                            HStack {
                                Text(track.title).lineLimit(1)
                                if !track.cuePoints.isEmpty {
                                    Text("\(track.cuePoints.count) cues").foregroundStyle(.orange)
                                }
                                if !track.savedLoops.isEmpty {
                                    Text("\(track.savedLoops.count) loops").foregroundStyle(.mint)
                                }
                                Spacer()
                                Text(track.durationLabel).monospacedDigit().foregroundStyle(.secondary)
                                if let bpm = track.estimatedBPM {
                                    Text(String(format: "%.1f BPM", bpm)).monospacedDigit().foregroundStyle(.secondary)
                                }
                                Button("A") { try? session.leftDeck.load(track: track) }
                                    .buttonStyle(.bordered)
                                Button("B") { try? session.rightDeck.load(track: track) }
                                    .buttonStyle(.bordered)
                                Menu {
                                    ForEach(session.crates.crates) { crate in
                                        Button(crate.name) { session.crates.add(track, to: crate.id) }
                                    }
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                }
                                .disabled(session.crates.crates.isEmpty)
                                Button(role: .destructive) { session.library.remove(track) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
        .padding(12)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            session.library.importTracks(urls)
        }
    }
}

private struct MIDIStatusView: View {
    @Bindable var midi: MIDIControllerService

    var body: some View {
        HStack {
            Label("MIDI", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
            if midi.sources.isEmpty {
                Text("No MIDI input devices detected")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Input", selection: Binding(
                    get: { midi.selectedSourceID },
                    set: { midi.connect(to: $0) }
                )) {
                    Text("No input").tag(MIDIUniqueID?.none)
                    ForEach(midi.sources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .labelsHidden()
                if let message = midi.lastMessage {
                    Text(message.description).monospacedDigit().foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Refresh devices") { midi.refresh() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .font(.caption)
        .padding(.horizontal, 12)
    }
}

private struct SeratoImportView: View {
    @Bindable var session: DJSession
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Serato import", systemImage: "arrow.down.doc")
                    .font(.headline)
                Spacer()
                Button("Choose music folder") { isChoosingFolder = true }
                    .buttonStyle(.bordered)
            }
            Text(session.seratoScanner.scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !session.seratoScanner.candidates.isEmpty {
                HStack {
                    Text("Marker-tag detection is read-only. Files without a detected tag can still be imported as audio.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Import detected tracks") {
                        session.library.importTracks(session.seratoScanner.candidates.map(\.url))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.seratoScanner.isScanning)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(session.seratoScanner.candidates.prefix(12)) { track in
                            HStack {
                                Image(systemName: track.hasSeratoMarkers ? "bookmark.fill" : "music.note")
                                    .foregroundStyle(track.hasSeratoMarkers ? .orange : .secondary)
                                Text(track.title).lineLimit(1)
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
        }
        .padding(12)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            session.seratoScanner.scan(folder: folder)
        }
    }
}
