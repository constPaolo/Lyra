import Foundation

enum LyricsState: Sendable {
    case idle
    case loading
    case loaded([LyricLine])
    case plain(String)
    case notFound
    case error(String)
}

struct LyricsSearchResult: Identifiable, Sendable, Hashable {
    let id: String
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
}

actor LyricsService {

    private let apiGetBase = "https://lrclib.net/api/get"
    private let apiSearchBase = "https://lrclib.net/api/search"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        config.httpAdditionalHeaders = ["User-Agent": "Lyra/\(version) (macOS lyrics player)"]
        self.session = URLSession(configuration: config)
    }

    /// Local `.lrc` first, then lrclib.net, then a fuzzy search fallback.
    /// Also returns the HTTP status and a raw response excerpt for the debug panel.
    func fetchLyrics(for track: Track, enableSmartMatching: Bool = true) async -> (LyricsState, Int?, String?) {
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let cached = loadLocalLRC(at: lrcURL) { return (cached, nil, "Local .lrc file") }

        guard let apiURL = buildURL(for: track) else {
            return (.error("Could not build request URL"), nil, nil)
        }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse else {
                return (.error("Invalid response"), nil, nil)
            }
            let rawJSON = String(data: data.prefix(500), encoding: .utf8)
            switch http.statusCode {
            case 200:
                let state = (try? decode(data: data, cacheTo: lrcURL)) ?? .notFound
                if isUsable(state) || !enableSmartMatching {
                    return (state, http.statusCode, rawJSON)
                }
            case 404:
                if !enableSmartMatching {
                    return (.notFound, http.statusCode, rawJSON)
                }
            default:
                if !enableSmartMatching {
                    return (.notFound, http.statusCode, rawJSON)
                }
            }

            if let fallback = try? await resolveWithSearchFallback(for: track, cacheTo: lrcURL) {
                let fallbackInfo = "Fallback matched via search (\(fallback.query.trackName) / \(fallback.query.artistName))"
                let combined = [rawJSON, fallbackInfo]
                    .compactMap { $0 }
                    .joined(separator: " | ")
                return (fallback.state, http.statusCode, combined)
            }
            return (.notFound, http.statusCode, rawJSON)
        } catch is CancellationError {
            return (.idle, nil, nil)
        } catch {
            DiagnosticsLogger.log("Lyrics fetch error: \(error.localizedDescription)", category: "lyrics")
            return (.error(error.localizedDescription), nil, nil)
        }
    }

    // MARK: - Helpers

    private func loadLocalLRC(at url: URL) -> LyricsState? {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = LRCParser.parse(content)
        if !lines.isEmpty { return .loaded(lines) }
        if let plain = normalizedPlainLyrics(content) { return .plain(plain) }
        return nil
    }

    private func buildURL(for track: Track) -> URL? {
        var components = URLComponents(string: apiGetBase)
        var items: [URLQueryItem] = []
        if !track.title.isEmpty      { items.append(.init(name: "track_name",  value: track.title))  }
        if track.artist != "Unknown Artist" { items.append(.init(name: "artist_name", value: track.artist)) }
        if track.album  != "Unknown Album"  { items.append(.init(name: "album_name",  value: track.album))  }
        if track.duration > 0        { items.append(.init(name: "duration",    value: "\(Int(track.duration))")) }
        components?.queryItems = items
        return components?.url
    }

    private struct APIResponse: Codable {
        let id: Int?
        let name: String?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private func decode(data: Data, cacheTo lrcURL: URL) throws -> LyricsState {
        let response = try JSONDecoder().decode(APIResponse.self, from: data)

        if let synced = response.syncedLyrics, !synced.isEmpty {
            // Cache
            try? synced.write(to: lrcURL, atomically: true, encoding: .utf8)
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .loaded(lines) }
        }

        if let plain = normalizedPlainLyrics(response.plainLyrics) {
            return .plain(plain)
        }

        return .notFound
    }

    private func isUsable(_ state: LyricsState) -> Bool {
        switch state {
        case .loaded, .plain:
            return true
        default:
            return false
        }
    }

    private func resolveWithSearchFallback(
        for track: Track,
        cacheTo lrcURL: URL
    ) async throws -> (state: LyricsState, query: LyricsQueryCandidate) {
        let queries = LyricsMatcher.queryVariants(trackName: track.title, artistName: track.artist)
        guard !queries.isEmpty else { throw NSError(domain: "LyricsService", code: 1) }

        var best: (result: LyricsSearchResult, query: LyricsQueryCandidate, score: Int)?

        for query in queries {
            let results = try await searchLyrics(trackName: query.trackName, artistName: query.artistName)
            for result in results {
                let score = LyricsMatcher.score(
                    result: result,
                    candidate: query,
                    expectedDuration: track.duration,
                    expectedAlbum: track.album == "Unknown Album" ? "" : track.album
                )
                guard score > (best?.score ?? Int.min) else { continue }
                best = (result, query, score)
            }
            if let best, best.score >= 32 { break }
        }

        guard let best else {
            throw NSError(domain: "LyricsService", code: 2)
        }

        let state = state(from: best.result, cacheTo: lrcURL)
        guard isUsable(state) else {
            throw NSError(domain: "LyricsService", code: 3)
        }
        return (state, best.query)
    }

    private func state(from result: LyricsSearchResult, cacheTo lrcURL: URL) -> LyricsState {
        if let synced = result.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                try? synced.write(to: lrcURL, atomically: true, encoding: .utf8)
                return .loaded(lines)
            }
        }
        if let plain = normalizedPlainLyrics(result.plainLyrics) {
            return .plain(plain)
        }
        return .notFound
    }

    func searchLyrics(trackName: String, artistName: String) async throws -> [LyricsSearchResult] {
        let trimmedTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrack.isEmpty else { return [] }

        var components = URLComponents(string: apiSearchBase)
        var items: [URLQueryItem] = [
            .init(name: "track_name", value: trimmedTrack)
        ]
        if !trimmedArtist.isEmpty {
            items.append(.init(name: "artist_name", value: trimmedArtist))
        }
        components?.queryItems = items

        guard let url = components?.url else { return [] }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return [] }
        guard http.statusCode == 200 else { return [] }

        let payloads: [APIResponse]
        if let decoded = try? JSONDecoder().decode([APIResponse].self, from: data) {
            payloads = decoded
        } else if let single = try? JSONDecoder().decode(APIResponse.self, from: data) {
            payloads = [single]
        } else {
            return []
        }

        return payloads.enumerated().map { index, p in
            let title = (p.trackName ?? p.name ?? trimmedTrack).trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (p.artistName ?? trimmedArtist).trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (p.albumName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rid = p.id.map(String.init) ?? "result-\(index)"
            return LyricsSearchResult(
                id: rid,
                trackName: title.isEmpty ? trimmedTrack : title,
                artistName: artist,
                albumName: album,
                duration: p.duration,
                syncedLyrics: p.syncedLyrics,
                plainLyrics: normalizedPlainLyrics(p.plainLyrics)
            )
        }
    }

    private func normalizedPlainLyrics(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
