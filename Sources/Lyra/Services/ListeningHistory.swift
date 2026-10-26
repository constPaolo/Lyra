import Foundation
import Observation

/// One listening session of a song: what played, when, and for how long.
struct Listen: Codable, Hashable, Sendable {
    let path: String
    let title: String
    let artist: String
    let album: String
    let start: Date
    /// Seconds actually heard (seeks and pauses don't count).
    let seconds: Double
    let duration: Double

    /// A "play" in the counts: at least 30 seconds, or half of a short song.
    var countsAsPlay: Bool { seconds >= min(30, duration * 0.5) }

    /// First credited artist: "MadMan, Nitro" counts for MadMan.
    var primaryArtist: String {
        let first = artist.components(separatedBy: ",").first ?? artist
        let name = first.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unknown Artist" : name
    }
}

/// Every listen, kept in a JSON file in Application Support. Stays on this
/// Mac; nothing is sent anywhere.
@MainActor
@Observable
final class ListeningHistory {
    private(set) var listens: [Listen] = []

    /// Listens shorter than this are skips, not kept.
    static let minimumSeconds = 10.0

    @ObservationIgnored private let fileURL: URL?
    /// Writes run one after the other, so an older snapshot never lands last.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    init() {
        // Per process name, so a renamed debug copy keeps its own history.
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(ProcessInfo.processInfo.processName, isDirectory: true)
        fileURL = dir?.appendingPathComponent("listening-history.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            listens = (try? JSONDecoder.history.decode([Listen].self, from: data)) ?? []
        }
    }

    func record(_ track: Track, seconds: Double, duration: Double, start: Date) {
        guard seconds >= Self.minimumSeconds else { return }
        listens.append(Listen(
            path: track.url.standardizedFileURL.path,
            title: track.title,
            artist: track.artist,
            album: track.album,
            start: start,
            seconds: seconds,
            duration: duration
        ))
        save()
    }

    /// Writes right away instead of in the background, for app quit.
    func saveNow() {
        guard let fileURL, let data = try? JSONEncoder.history.encode(listens) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    #if DEBUG
    func replaceAll(with listens: [Listen]) {
        self.listens = listens
        save()
    }
    #endif

    private func save() {
        guard let fileURL else { return }
        let snapshot = listens
        let previous = lastSave
        lastSave = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder.history.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
