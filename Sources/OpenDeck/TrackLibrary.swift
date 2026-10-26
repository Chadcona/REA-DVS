import AVFoundation
import Foundation
import SwiftUI

struct LibraryTrack: Codable, Identifiable, Hashable {
    let id: UUID
    let path: String
    let title: String
    let duration: TimeInterval
    let cuePoints: [CuePoint]

    private enum CodingKeys: String, CodingKey { case id, path, title, duration, cuePoints }

    init(id: UUID, path: String, title: String, duration: TimeInterval, cuePoints: [CuePoint] = []) {
        self.id = id
        self.path = path
        self.title = title
        self.duration = duration
        self.cuePoints = cuePoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        title = try container.decode(String.self, forKey: .title)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        cuePoints = try container.decodeIfPresent([CuePoint].self, forKey: .cuePoints) ?? []
    }

    var url: URL { URL(fileURLWithPath: path) }
    var durationLabel: String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

@Observable
@MainActor
final class TrackLibrary {
    private static let storageKey = "OpenDeck.library.v1"
    private(set) var tracks: [LibraryTrack] = []
    var importError: String?

    init() { load() }

    func importTracks(_ urls: [URL]) {
        for url in urls where !tracks.contains(where: { $0.path == url.path }) {
            do {
                let file = try AVAudioFile(forReading: url)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                tracks.append(LibraryTrack(
                    id: UUID(),
                    path: url.path,
                    title: url.deletingPathExtension().lastPathComponent,
                    duration: duration,
                    cuePoints: SeratoMarkers.readCuePoints(from: url)
                ))
            } catch {
                importError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        save()
    }

    func remove(_ track: LibraryTrack) {
        tracks.removeAll { $0.id == track.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        tracks = (try? JSONDecoder().decode([LibraryTrack].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
