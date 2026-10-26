import Foundation
import SwiftUI

enum MIDIAction: String, Codable, CaseIterable, Identifiable {
    case deckAPlayPause = "Deck A Play/Pause"
    case deckBPlayPause = "Deck B Play/Pause"
    case crossfader = "Crossfader"
    case deckAFilter = "Deck A Filter"
    case deckBFilter = "Deck B Filter"
    case deckAEcho = "Deck A Echo"
    case deckBEcho = "Deck B Echo"
    var id: String { rawValue }
}

struct MIDIMapping: Codable, Identifiable, Hashable {
    let id: UUID
    let status: UInt8
    let data1: UInt8
    let action: MIDIAction
}

@Observable
@MainActor
final class MIDIMapStore {
    private static let storageKey = "OpenDeck.midiMappings.v1"
    private(set) var mappings: [MIDIMapping] = []
    var pendingAction: MIDIAction?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            mappings = (try? JSONDecoder().decode([MIDIMapping].self, from: data)) ?? []
        }
    }

    func learn(_ message: MIDIMessage) {
        guard let action = pendingAction else { return }
        mappings.removeAll { $0.action == action || ($0.status == message.status && $0.data1 == message.data1) }
        mappings.append(MIDIMapping(id: UUID(), status: message.status, data1: message.data1, action: action))
        pendingAction = nil
        save()
    }

    func action(for message: MIDIMessage) -> MIDIAction? {
        mappings.first { $0.status == message.status && $0.data1 == message.data1 }?.action
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
