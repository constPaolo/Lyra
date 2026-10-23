import Foundation

enum SearchHit: Hashable {
    case track(Track)
    case artist(ArtistGroup)
    case album(AlbumGroup)
    case playlist(Playlist)
}

struct SearchResults {
    var top: SearchHit?
    var songs: [Track] = []
    var artists: [ArtistGroup] = []
    var albums: [AlbumGroup] = []
    var playlists: [Playlist] = []

    var isEmpty: Bool {
        songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty
    }
}

enum SearchScore {
    /// Case- and diacritic-insensitive form used for matching.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 1 exact, 0.8 prefix, 0.6 word prefix, 0.3 substring, 0 no match.
    /// `query` must already be folded.
    static func score(_ text: String, _ query: String) -> Double {
        guard !query.isEmpty else { return 0 }
        let t = fold(text)
        if t == query { return 1 }
        if t.hasPrefix(query) { return 0.8 }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return 0.6 }
        if t.contains(query) { return 0.3 }
        return 0
    }
}
