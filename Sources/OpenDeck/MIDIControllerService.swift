import CoreMIDI
import SwiftUI

struct MIDISource: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
}

struct MIDIMessage: Hashable {
    let status: UInt8
    let data1: UInt8
    let data2: UInt8

    var description: String {
        String(format: "Status %02X · Data %d · Value %d", status, data1, data2)
    }
}

@Observable
@MainActor
final class MIDIControllerService {
    private(set) var sources: [MIDISource] = []
    private(set) var selectedSourceID: MIDIUniqueID?
    private(set) var lastMessage: MIDIMessage?
    var onMessage: ((MIDIMessage) -> Void)?
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    init() {
        MIDIClientCreateWithBlock("OpenDeck MIDI" as CFString, &client) { _ in }
        MIDIInputPortCreateWithBlock(client, "OpenDeck Input" as CFString, &inputPort) { [weak self] packets, _ in
            let packet = packets.pointee.packet
            guard packet.length >= 3 else { return }
            let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
            guard bytes.count >= 3 else { return }
            let message = MIDIMessage(status: bytes[0], data1: bytes[1], data2: bytes[2])
            DispatchQueue.main.async {
                self?.lastMessage = message
                self?.onMessage?(message)
            }
        }
        refresh()
    }

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

    func connect(to uniqueID: MIDIUniqueID?) {
        if let selectedSourceID {
            var object = MIDIObjectRef()
            var type = MIDIObjectType(rawValue: 0)!
            if MIDIObjectFindByUniqueID(selectedSourceID, &object, &type) == noErr {
                MIDIPortDisconnectSource(inputPort, MIDIEndpointRef(object))
            }
        }
        selectedSourceID = uniqueID
        lastMessage = nil
        guard let uniqueID else { return }
        var object = MIDIObjectRef()
        var type = MIDIObjectType(rawValue: 0)!
        guard MIDIObjectFindByUniqueID(uniqueID, &object, &type) == noErr else { return }
        MIDIPortConnectSource(inputPort, MIDIEndpointRef(object), nil)
    }
}
