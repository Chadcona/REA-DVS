import Foundation
import SwiftUI

struct SeratoImportCandidate: Identifiable, Hashable {
    let url: URL
    let hasSeratoMarkers: Bool

    var id: String { url.path }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

@Observable
@MainActor
final class SeratoImportScanner {
    private(set) var candidates: [SeratoImportCandidate] = []
    private(set) var isScanning = false
    private(set) var selectedFolderName = ""
    private(set) var scanMessage = "Choose a music folder to preview local audio files."

    func scan(folder: URL) {
        isScanning = true
        selectedFolderName = folder.lastPathComponent
        scanMessage = "Scanning \(selectedFolderName)…"
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                Self.findCandidates(in: folder)
            }.value
            candidates = results
            isScanning = false
            let markerCount = results.filter(\.hasSeratoMarkers).count
            scanMessage = "Found \(results.count) audio files; \(markerCount) expose Serato marker metadata in their file header."
        }
    }

    private nonisolated static func findCandidates(in folder: URL) -> [SeratoImportCandidate] {
        let audioExtensions: Set<String> = ["aif", "aiff", "alac", "flac", "m4a", "mp3", "mp4", "ogg", "wav"]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [SeratoImportCandidate] = []
        for case let url as URL in enumerator {
            guard results.count < 5_000,
                  audioExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            results.append(SeratoImportCandidate(url: url, hasSeratoMarkers: headerContainsSeratoMarkers(url)))
        }
        return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private nonisolated static func headerContainsSeratoMarkers(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2 * 1_024 * 1_024) else { return false }
        return data.range(of: Data("Serato Markers".utf8)) != nil
    }
}
