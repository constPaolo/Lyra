import Foundation
import AppKit
import ImageIO

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

    /// Full-size cover art, decoded on every call. For display use `thumbnail`.
    var artwork: NSImage? {
        artworkData.flatMap { NSImage(data: $0) }
    }

    /// Cover art downscaled for on-screen use, decoded once and cached.
    /// Embedded covers are often 1000px+ JPEGs; decoding them on every view
    /// update made scrolling the track list stutter.
    var thumbnail: NSImage? {
        guard let artworkData else { return nil }
        let key = id.uuidString as NSString
        if let cached = Self.thumbnails.object(forKey: key) { return cached }
        guard let image = Self.downscaled(artworkData, maxPixelSize: 320) else { return nil }
        Self.thumbnails.setObject(image, forKey: key)
        return image
    }

    // NSCache is thread-safe.
    nonisolated(unsafe) private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    private static func downscaled(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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
