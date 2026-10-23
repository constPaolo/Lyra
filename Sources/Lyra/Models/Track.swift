import Foundation
import AppKit

struct Track: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Position within the album (1-based), from the file's metadata.
    var trackNumber: Int?
    /// Disc number for multi-disc albums, from the file's metadata.
    var discNumber: Int?
    var artworkData: Data?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        artworkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.artworkData = artworkData
    }

    var artwork: NSImage? {
        artworkData.flatMap { NSImage(data: $0) }
    }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Track {
    /// Ordering within a single album: disc, then track number, then title.
    /// Tracks without a number sort after numbered ones.
    static func albumOrder(_ a: Track, _ b: Track) -> Bool {
        let discA = a.discNumber ?? 1, discB = b.discNumber ?? 1
        if discA != discB { return discA < discB }
        let numA = a.trackNumber ?? Int.max, numB = b.trackNumber ?? Int.max
        if numA != numB { return numA < numB }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    /// Whole-library ordering: artist, album, then album order.
    static func libraryOrder(_ a: Track, _ b: Track) -> Bool {
        let artistCmp = a.artist.localizedCaseInsensitiveCompare(b.artist)
        if artistCmp != .orderedSame { return artistCmp == .orderedAscending }
        let albumCmp = a.album.localizedCaseInsensitiveCompare(b.album)
        if albumCmp != .orderedSame { return albumCmp == .orderedAscending }
        return albumOrder(a, b)
    }
}
