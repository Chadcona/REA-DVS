import Combine
import CoreMIDI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var session: DJSession

    var body: some View {
        VStack(spacing: 10) {
            PerformanceHeader(session: session)
            HStack(alignment: .top, spacing: 10) {
                DeckView(deck: session.leftDeck, accent: .deckA, symbol: "A")
                MixerView(session: session)
                DeckView(deck: session.rightDeck, accent: .deckB, symbol: "B")
            }
            LibraryView(session: session)
            HStack(alignment: .top, spacing: 10) {
                SeratoImportView(session: session)
                VStack(spacing: 6) {
                    MIDIStatusView(midi: session.midi)
                    MIDILearnView(mappings: session.midiMappings)
                }
                .djPanel(cornerRadius: 12)
            }
        }
        .padding(14)
        .frame(minWidth: 1_050, minHeight: 700)
        .background(PerformanceBackground())
        .foregroundStyle(.white)
    }
}

private struct PerformanceHeader: View {
    @Bindable var session: DJSession
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.title3.weight(.bold)).foregroundStyle(Color.deckA)
                    .frame(width: 30, height: 30).background(Color.deckA.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 0) {
                    Text("OPENDECK").font(.headline.weight(.black)).tracking(1.5)
                    Text("PERFORMANCE MODE").font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusPill(title: "LOCAL LIBRARY", icon: "music.note", tint: .mint)
            StatusPill(title: session.midi.selectedSourceID == nil ? "MIDI STANDBY" : "MIDI CONNECTED", icon: "cable.connector", tint: session.midi.selectedSourceID == nil ? .secondary : .green)
            Button { session.sync() } label: {
                Label("SYNC", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.bold)).tracking(0.8)
            }
            .buttonStyle(.borderedProminent).tint(session.syncEnabled ? .green : .indigo).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).djPanel(cornerRadius: 12)
    }
}

private struct StatusPill: View {
    let title: String
    let icon: String
    let tint: Color
    var body: some View {
        Label(title, systemImage: icon).font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 6).background(tint.opacity(0.1), in: Capsule())
    }
}

private struct MIDILearnView: View {
    @Bindable var mappings: MIDIMapStore
    @State private var action: MIDIAction = .deckAPlayPause
    var body: some View {
        HStack(spacing: 8) {
            Label("MIDI LEARN", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Picker("Action", selection: $action) { ForEach(MIDIAction.allCases) { Text($0.rawValue).tag($0) } }
                .labelsHidden().controlSize(.small)
            Button(mappings.pendingAction == nil ? "Learn" : "Listening…") { mappings.pendingAction = mappings.pendingAction == nil ? action : nil }
                .buttonStyle(.bordered).controlSize(.small)
            Spacer()
            Text("\(mappings.mappings.count) MAPPED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
    }
}

private struct DeckView: View {
    @Bindable var deck: Deck
    let accent: Color
    let symbol: String
    @State private var isImporting = false
    private let playbackClock = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            deckHeader
            WaveformView(samples: deck.waveform, progress: deck.progress, accent: accent, cuePoints: deck.cuePoints, duration: deck.duration)
            trackDetails
            transport
            performancePads
            controls
        }
        .padding(12).frame(maxWidth: .infinity).djPanel(cornerRadius: 14, accent: accent)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            guard case let .success(url) = result else { return }
            do { try deck.load(url: url) } catch { deck.trackName = "Could not load this audio file"; deck.artist = error.localizedDescription }
        }
        .onReceive(playbackClock) { _ in deck.refreshPlaybackTime() }
    }

    private var deckHeader: some View {
        HStack {
            Text("DECK \(symbol)").font(.system(size: 11, weight: .black)).tracking(1.3).foregroundStyle(accent)
            Circle().fill(deck.isPlaying ? .green : .secondary.opacity(0.45)).frame(width: 6, height: 6)
            Spacer()
            Text(deck.pitchLabel).font(.system(.caption, design: .monospaced).weight(.bold)).foregroundStyle(deck.pitch == 0 ? .secondary : accent)
            Button("LOAD") { isImporting = true }.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var trackDetails: some View {
        HStack(spacing: 12) {
            DeckDisc(accent: accent, progress: deck.progress, isPlaying: deck.isPlaying)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.trackName.uppercased()).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(deck.artist.isEmpty ? "READY TO LOAD" : deck.artist.uppercased()).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Text(String(format: "%05.1f", deck.bpm)); Text("BPM").foregroundStyle(.secondary)
                    Text(timeLabel).foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 7) {
            DeckButton(title: "CUE", icon: "backward.end.fill", tint: .white, active: deck.isCueing) { deck.cue() }
            DeckButton(title: deck.isPlaying ? "PAUSE" : "PLAY", icon: deck.isPlaying ? "pause.fill" : "play.fill", tint: accent, active: deck.isPlaying) { deck.playPause() }
            ForEach([1, 2, 4, 8], id: \.self) { beats in
                Button("\(beats)") { deck.toggleLoop(beats) }.font(.caption.weight(.bold)).frame(maxWidth: .infinity, minHeight: 30)
                    .buttonStyle(.plain).foregroundStyle(deck.loopLength == beats ? .black : .secondary)
                    .background(deck.loopLength == beats ? accent : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var timeLabel: String {
        let seconds = max(0, Int(deck.elapsed))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder private var performancePads: some View {
        if !deck.cuePoints.isEmpty || !deck.savedLoops.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(deck.savedLoops.isEmpty ? "HOT CUES" : "SAVED CUES / LOOPS").font(.system(size: 8, weight: .black)).tracking(1).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                    ForEach(deck.cuePoints.prefix(4)) { cue in
                        PerformancePad(title: cue.name.isEmpty ? "CUE \(cue.index + 1)" : cue.name, tint: Color(hex: cue.colorHex) ?? accent) { deck.triggerCue(cue) }
                    }
                    ForEach(deck.savedLoops.prefix(max(0, 4 - deck.cuePoints.count))) { loop in
                        PerformancePad(title: loop.name.isEmpty ? "LOOP \(loop.index + 1)" : loop.name, tint: Color(hex: loop.colorHex) ?? .mint, active: deck.activeSavedLoop?.id == loop.id) { deck.toggleSavedLoop(loop) }
                    }
                }
            }
        } else {
            HStack(spacing: 5) {
                ForEach(1...4, id: \.self) { index in
                    Text("PAD \(index)").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 27).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                DeckKnob(title: "BPM", value: $deck.bpm, range: 60...200, tint: accent, valueLabel: String(format: "%.1f", deck.bpm))
                DeckKnob(title: "PITCH", value: $deck.pitch, range: -8...8, tint: accent, valueLabel: deck.pitchLabel)
                DeckKnob(title: "GAIN", value: $deck.gain, range: 0...1, tint: accent, valueLabel: String(format: "%d", Int(deck.gain * 100)))
                DeckKnob(title: "FILTER", value: $deck.filter, range: -1...1, tint: accent, valueLabel: deck.filter == 0 ? "0" : (deck.filter < 0 ? "LP" : "HP"))
            }
            HStack(spacing: 8) {
                EffectStrip(title: "ECHO", value: $deck.echo, tint: accent)
                EffectStrip(title: "REVERB", value: $deck.reverb, tint: accent)
            }
        }
    }
}

private struct DeckDisc: View {
    let accent: Color; let progress: Double; let isPlaying: Bool
    var body: some View {
        ZStack {
            Circle().fill(.black); Circle().stroke(accent.opacity(0.25), lineWidth: 2).padding(4)
            Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(11); Circle().fill(accent.opacity(0.7)).frame(width: 14, height: 14)
            Capsule().fill(.white.opacity(0.72)).frame(width: 2, height: 27).offset(y: -15).rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 54, height: 54).shadow(color: isPlaying ? accent.opacity(0.35) : .clear, radius: 8)
    }
}

private struct DeckButton: View {
    let title: String; let icon: String; let tint: Color; let active: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 10, weight: .black)).frame(maxWidth: .infinity, minHeight: 30) }
            .buttonStyle(.plain).foregroundStyle(active ? .black : tint).background(active ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.45)))
    }
}

private struct PerformancePad: View {
    let title: String; let tint: Color; var active = false; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title.uppercased()).font(.system(size: 8, weight: .black)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 27) }
            .buttonStyle(.plain).foregroundStyle(active ? .black : tint).background(active ? tint : tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.45)))
    }
}

private struct DeckKnob: View {
    let title: String; @Binding var value: Double; let range: ClosedRange<Double>; let tint: Color; let valueLabel: String
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 8, weight: .black)).tracking(0.6).foregroundStyle(.secondary)
            Text(valueLabel).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(tint)
            Slider(value: $value, in: range).controlSize(.mini).tint(tint)
        }.frame(maxWidth: .infinity)
    }
}

private struct EffectStrip: View {
    let title: String; @Binding var value: Double; let tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 8, weight: .black)).tracking(0.8).foregroundStyle(.secondary)
            Slider(value: $value, in: 0...1).tint(tint)
            Text("\(Int(value * 100))").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(tint).frame(width: 18, alignment: .trailing)
        }
    }
}

private extension Color {
    static let deckA = Color(red: 0.16, green: 0.84, blue: 0.95)
    static let deckB = Color(red: 1.0, green: 0.35, blue: 0.45)
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct MixerView: View {
    @Bindable var session: DJSession
    var body: some View {
        VStack(spacing: 14) {
            Text("MIXER").font(.system(size: 10, weight: .black)).tracking(1.4).foregroundStyle(.secondary)
            MixerMeter(leftTint: .deckA, rightTint: .deckB, master: session.masterGain)
            VStack(spacing: 5) {
                Text("MASTER").font(.system(size: 8, weight: .black)).tracking(0.8).foregroundStyle(.secondary)
                Slider(value: $session.masterGain, in: 0...1).tint(.white)
                Text("\(Int(session.masterGain * 100))%").font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            VStack(spacing: 6) {
                Text("CROSSFADER").font(.system(size: 8, weight: .black)).tracking(0.8).foregroundStyle(.secondary)
                HStack { Text("A").foregroundStyle(Color.deckA); Slider(value: $session.crossfader, in: -1...1).tint(.white); Text("B").foregroundStyle(Color.deckB) }
                    .font(.system(size: 10, weight: .black))
            }
        }.padding(12).frame(width: 170).djPanel(cornerRadius: 14)
    }
}

private struct MixerMeter: View {
    let leftTint: Color; let rightTint: Color; let master: Double
    var body: some View { HStack(spacing: 5) { Meter(tint: leftTint, amount: master * 0.82); Meter(tint: rightTint, amount: master * 0.68) }.frame(height: 88) }
}

private struct Meter: View {
    let tint: Color; let amount: Double
    var body: some View {
        VStack(spacing: 3) {
            ForEach((0..<10).reversed(), id: \.self) { index in
                let threshold = Double(index + 1) / 10
                RoundedRectangle(cornerRadius: 1).fill(threshold <= amount ? (index > 7 ? Color.red : tint) : Color.white.opacity(0.08)).frame(width: 17, height: 5)
            }
        }
    }
}

private struct WaveformView: View {
    let samples: [Float]; let progress: Double; let accent: Color; let cuePoints: [CuePoint]; let duration: TimeInterval
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let center = size.height / 2
                let waveform = samples.isEmpty ? Array(repeating: Float(0.08), count: 100) : samples
                var path = Path()
                for index in waveform.indices {
                    let x = size.width * CGFloat(index) / CGFloat(max(1, waveform.count - 1))
                    let height = max(1, CGFloat(waveform[index]) * center * 0.88)
                    path.move(to: CGPoint(x: x, y: center - height)); path.addLine(to: CGPoint(x: x, y: center + height))
                }
                context.stroke(path, with: .color(accent.opacity(0.78)), lineWidth: 1)
                context.stroke(Path(CGRect(x: 0, y: center, width: size.width, height: 1)), with: .color(.white.opacity(0.09)), lineWidth: 1)
                for cue in cuePoints where duration > 0 {
                    let x = size.width * CGFloat(cue.position / duration)
                    context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Color(hex: cue.colorHex) ?? accent))
                }
                let marker = size.width * progress
                context.fill(Path(CGRect(x: marker - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
            }
        }
        .frame(height: 104).background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) { Text("WAVEFORM").font(.system(size: 8, weight: .black)).tracking(0.8).foregroundStyle(.secondary).padding(7) }
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
                Label("LIBRARY", systemImage: "music.note.list").font(.system(size: 10, weight: .black)).tracking(1)
                Text("\(session.library.tracks.count) TRACKS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Spacer(); Button("IMPORT AUDIO") { isImporting = true }.buttonStyle(.bordered).controlSize(.small)
            }
            HStack(spacing: 8) {
                Picker("Crate", selection: $selectedCrateID) {
                    Text("ALL TRACKS").tag(UUID?.none)
                    ForEach(session.crates.crates) { crate in Text("\(crate.name.uppercased()) (\(crate.trackIDs.count))").tag(Optional(crate.id)) }
                }.labelsHidden().controlSize(.small)
                TextField("NEW CRATE", text: $newCrateName).textFieldStyle(.roundedBorder).frame(width: 135)
                Button("CREATE") { session.crates.create(name: newCrateName); newCrateName = "" }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(newCrateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let importError = session.library.importError { Text(importError).font(.caption).foregroundStyle(.red) }
            let visibleTracks = session.crates.tracks(in: selectedCrateID, from: session.library.tracks)
            if visibleTracks.isEmpty {
                ContentUnavailableView("Your local music lives here", systemImage: "music.note", description: Text("Import audio or choose a folder containing your owned music."))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            } else {
                HStack(spacing: 0) {
                    Text("TITLE").frame(maxWidth: .infinity, alignment: .leading); Text("BPM").frame(width: 62); Text("TIME").frame(width: 58); Text("LOAD").frame(width: 88)
                }.font(.system(size: 8, weight: .black)).tracking(0.8).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visibleTracks) { track in
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title).lineLimit(1)
                                    Text([track.cuePoints.isEmpty ? nil : "\(track.cuePoints.count) CUES", track.savedLoops.isEmpty ? nil : "\(track.savedLoops.count) LOOPS"].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(track.estimatedBPM.map { String(format: "%.1f", $0) } ?? "—").frame(width: 62).foregroundStyle(.secondary)
                                Text(track.durationLabel).frame(width: 58).foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Button("A") { try? session.leftDeck.load(track: track) }.tint(.deckA)
                                    Button("B") { try? session.rightDeck.load(track: track) }.tint(.deckB)
                                    Menu { ForEach(session.crates.crates) { crate in Button(crate.name) { session.crates.add(track, to: crate.id) } } } label: { Image(systemName: "folder.badge.plus") }.disabled(session.crates.crates.isEmpty)
                                    Button(role: .destructive) { session.library.remove(track) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                                }.buttonStyle(.bordered).controlSize(.mini).frame(width: 88)
                            }
                            .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 5).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }.frame(maxHeight: 132)
            }
        }
        .padding(12).djPanel(cornerRadius: 12)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }; session.library.importTracks(urls)
        }
    }
}

private struct MIDIStatusView: View {
    @Bindable var midi: MIDIControllerService
    var body: some View {
        HStack {
            Label("MIDI", systemImage: "slider.horizontal.3").font(.system(size: 10, weight: .black)).tracking(0.9).foregroundStyle(.secondary)
            if midi.sources.isEmpty {
                Text("NO INPUT DEVICES DETECTED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            } else {
                Picker("Input", selection: Binding(get: { midi.selectedSourceID }, set: { midi.connect(to: $0) })) {
                    Text("NO INPUT").tag(MIDIUniqueID?.none); ForEach(midi.sources) { source in Text(source.name).tag(Optional(source.id)) }
                }.labelsHidden().controlSize(.small)
                if let message = midi.lastMessage { Text(message.description).font(.caption.monospacedDigit()).foregroundStyle(Color.deckB) }
            }
            Spacer(); Button("REFRESH") { midi.refresh() }.buttonStyle(.borderless).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.deckA)
        }
    }
}

private struct SeratoImportView: View {
    @Bindable var session: DJSession
    @State private var isChoosingFolder = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("SERATO IMPORT", systemImage: "arrow.down.doc").font(.system(size: 10, weight: .black)).tracking(0.8)
                Spacer(); Button("CHOOSE FOLDER") { isChoosingFolder = true }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(session.seratoScanner.scanMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !session.seratoScanner.candidates.isEmpty {
                HStack {
                    Text("\(session.seratoScanner.candidates.count) LOCAL TRACKS FOUND").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.deckB)
                    Spacer()
                    Button("IMPORT DETECTED") { session.library.importTracks(session.seratoScanner.candidates.map(\.url)) }
                        .buttonStyle(.borderedProminent).controlSize(.small).disabled(session.seratoScanner.isScanning)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).djPanel(cornerRadius: 12)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }; session.seratoScanner.scan(folder: folder)
        }
    }
}

private struct PerformanceBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.055), Color(red: 0.055, green: 0.065, blue: 0.09)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .topLeading) { Circle().fill(Color.deckA.opacity(0.05)).frame(width: 500).blur(radius: 100).offset(x: -130, y: -180) }
            .overlay(alignment: .topTrailing) { Circle().fill(Color.deckB.opacity(0.04)).frame(width: 420).blur(radius: 100).offset(x: 150, y: -120) }.ignoresSafeArea()
    }
}

private extension View {
    func djPanel(cornerRadius: CGFloat, accent: Color? = nil) -> some View {
        background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke((accent ?? .white).opacity(accent == nil ? 0.09 : 0.28)))
    }
}
