import Foundation
import SwiftUI

struct Crate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: Set<UUID>
}

@Observable
@MainActor
final class CrateStore {
    private static let storageKey = "OpenDeck.crates.v1"
    private(set) var crates: [Crate] = []

    init() { load() }

    func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !crates.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        crates.append(Crate(id: UUID(), name: trimmed, trackIDs: []))
        save()
    }

    func add(_ track: LibraryTrack, to crateID: UUID) {
        guard let index = crates.firstIndex(where: { $0.id == crateID }) else { return }
        crates[index].trackIDs.insert(track.id)
        save()
    }

    func remove(_ track: LibraryTrack, from crateID: UUID) {
        guard let index = crates.firstIndex(where: { $0.id == crateID }) else { return }
        crates[index].trackIDs.remove(track.id)
        save()
    }

    func delete(_ crate: Crate) {
        crates.removeAll { $0.id == crate.id }
        save()
    }

    func tracks(in crateID: UUID?, from library: [LibraryTrack]) -> [LibraryTrack] {
        guard let crateID, let crate = crates.first(where: { $0.id == crateID }) else { return library }
        return library.filter { crate.trackIDs.contains($0.id) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        crates = (try? JSONDecoder().decode([Crate].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(crates) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
