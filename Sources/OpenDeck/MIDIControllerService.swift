import CoreMIDI
import SwiftUI

struct MIDISource: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
}

@Observable
@MainActor
final class MIDIControllerService {
    private(set) var sources: [MIDISource] = []

    init() { refresh() }

    func refresh() {
        sources = (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }
            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            var unmanagedName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
            let name = unmanagedName?.takeRetainedValue() as String? ?? "Unnamed MIDI source"
            return MIDISource(id: uniqueID, name: name)
        }
    }
}
