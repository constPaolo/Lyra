import Foundation

struct LibraryFolder: Identifiable, Hashable, Codable {
    let path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }
}

struct Playlist: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var trackPaths: [String]

    init(id: UUID = UUID(), name: String, trackPaths: [String] = []) {
        self.id = id
        self.name = name
        self.trackPaths = trackPaths
    }
}

enum LibrarySource: Hashable, Codable {
    case allTracks
    case liked
    case folder(path: String)
    case artist(name: String)
    case album(name: String)
    case playlist(id: UUID)
}

enum MainViewMode: Hashable {
    case browse
    case lyrics
    case visualizer
}

/// Top-level sidebar entries.
enum SidebarTab: Hashable {
    case home
    case allTracks
    case liked
    case artists
    case albums
    case folders
    case playlists
    case queue
    case recap
}

/// What the main browse area is currently showing — either an index list
/// (artists/folders/playlists) or a concrete track collection.
enum BrowsePage: Hashable {
    case home
    case allTracks
    case liked
    case artistsIndex
    case artist(name: String)
    case albumsIndex
    case album(name: String)
    case foldersIndex
    case folder(path: String)
    case playlistsIndex
    case playlist(id: UUID)
    case queue
    case recap
}

struct ArtistGroup: Identifiable, Hashable {
    let name: String
    let trackCount: Int

    var id: String { name }
}

struct AlbumGroup: Identifiable, Hashable {
    let name: String
    /// Single artist of the album, or "Various Artists" when tracks disagree.
    let artist: String
    let trackCount: Int

    var id: String { name }
}

struct FolderBrowseItem: Identifiable, Hashable {
    let path: String
    let displayName: String
    let depth: Int
    let isRoot: Bool

    var id: String { path }
}
