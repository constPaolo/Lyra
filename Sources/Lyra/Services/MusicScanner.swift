import Foundation
import AVFoundation

actor MusicScanner {

    private let supportedExtensions: Set<String> = ["mp3", "flac", "aiff", "aif", "m4a", "wav"]
    private struct CachedTrackEntry {
        let modificationDate: Date?
        let fileSize: Int64
        let track: Track
    }
    private struct ScannedAudioFile {
        let url: URL
        let modificationDate: Date?
        let fileSize: Int64
    }
    private var cache: [URL: CachedTrackEntry] = [:]

    func scan(folders: [URL]) async throws -> [Track] {
        let fm = FileManager.default
        var audioFiles: [ScannedAudioFile] = []

        for folder in folders {
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            // for-in over NSEnumerator is unavailable in async contexts.
            while let obj = enumerator.nextObject() {
                guard let fileURL = obj as? URL,
                      supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                audioFiles.append(
                    .init(
                        url: fileURL,
                        modificationDate: values?.contentModificationDate,
                        fileSize: Int64(values?.fileSize ?? 0)
                    )
                )
            }
        }

        var tracks: [Track] = []
        var currentURLs: Set<URL> = []
        for audioFile in audioFiles {
            try Task.checkCancellation()
            currentURLs.insert(audioFile.url)

            if let cached = cache[audioFile.url],
               cached.fileSize == audioFile.fileSize,
               cached.modificationDate == audioFile.modificationDate {
                tracks.append(cached.track)
                continue
            }

            if let track = try? await loadTrack(from: audioFile.url) {
                cache[audioFile.url] = .init(
                    modificationDate: audioFile.modificationDate,
                    fileSize: audioFile.fileSize,
                    track: track
                )
                tracks.append(track)
            }
        }

        cache = cache.filter { currentURLs.contains($0.key) }

        return tracks.sorted(by: Track.libraryOrder)
    }

    /// Returns all raw metadata keys found across all formats — used by debug panel.
    static func rawMetadataKeys(for url: URL) async -> [String] {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var result: [String] = []
        for fmt in formats {
            let items = (try? await asset.loadMetadata(for: fmt)) ?? []
            for item in items {
                let key = item.key as? String ?? item.commonKey?.rawValue ?? "?"
                let data = try? await item.load(.dataValue)
                let str = try? await item.load(.stringValue)
                let valueDesc = str.map { "\"\($0)\"" } ?? (data.map { "\($0.count) bytes" } ?? "nil")
                result.append("[\(fmt.rawValue.components(separatedBy: ".").last ?? fmt.rawValue)] \(key) = \(valueDesc)")
            }
        }
        return result
    }

    private func loadTrack(from url: URL) async throws -> Track {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let duration = try await asset.load(.duration).seconds

        var title = url.deletingPathExtension().lastPathComponent
        // Artist tags can legitimately repeat (multiple ID3 TPE1 values, repeated
        // Vorbis ARTIST comments) — that's how featured artists are stored. Keep
        // every value and join them at the end instead of last-one-wins.
        var artistValues: [String] = []
        var album = "Unknown Album"
        var trackNumber: Int?
        var discNumber: Int?
        var artworkData: Data?

        // 1. Common metadata (ID3 / iTunes atoms)
        let commonMeta = try await asset.load(.commonMetadata)
        for item in commonMeta {
            switch item.commonKey {
            case .commonKeyTitle:
                if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
            case .commonKeyArtist:
                if let v = try? await item.load(.stringValue), !v.isEmpty { artistValues.append(v) }
            case .commonKeyAlbumName:
                if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
            case .commonKeyArtwork:
                artworkData = try? await item.load(.dataValue)
            default: break
            }
        }

        // 2. Vorbis Comment fallback (FLAC files use this format; AVFoundation doesn't
        //    map Vorbis keys to commonMetadata, so we read them directly.
        //    Artwork is stored as METADATA_BLOCK_PICTURE, not "artwork".)
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for fmt in formats where fmt.rawValue.contains("vorbis") {
            let items = (try? await asset.loadMetadata(for: fmt)) ?? []
            for item in items {
                guard let key = item.key as? String else { continue }
                switch key.uppercased() {
                case "TITLE":
                    if title == url.deletingPathExtension().lastPathComponent,
                       let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case "ARTIST":
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artistValues.append(v) }
                case "ALBUM", "ALBUMNAME":
                    if album == "Unknown Album",
                       let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case "METADATA_BLOCK_PICTURE":
                    if artworkData == nil {
                        artworkData = try? await item.load(.dataValue)
                    }
                default: break
                }
            }
        }

        // 3. Track / disc numbers. Not exposed via commonMetadata, so check the
        //    format-specific identifiers: ID3 TRCK/TPOS, iTunes trkn/disk atoms
        //    and Vorbis TRACKNUMBER/DISCNUMBER.
        for fmt in formats {
            let items = (try? await asset.loadMetadata(for: fmt)) ?? []
            for item in items {
                let key = (item.key as? String)?.uppercased()
                let id = item.identifier

                if trackNumber == nil,
                   id == .id3MetadataTrackNumber || id == .iTunesMetadataTrackNumber
                   || key == "TRCK" || key == "TRACKNUMBER" {
                    trackNumber = await numericValue(of: item)
                }
                if discNumber == nil,
                   id == .id3MetadataPartOfASet || id == .iTunesMetadataDiscNumber
                   || key == "TPOS" || key == "DISCNUMBER" {
                    discNumber = await numericValue(of: item)
                }
            }
            if trackNumber != nil && discNumber != nil { break }
        }

        // ID3v2.4 packs multiple values into one frame separated by NUL; split
        // those too, then dedupe (a FLAC can carry the same name in both common
        // and Vorbis metadata) preserving order: main artist first, feats after.
        let uniqueArtists = artistValues
            .flatMap { $0.components(separatedBy: "\0") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, name in
                if !acc.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    acc.append(name)
                }
            }
        let artist = uniqueArtists.isEmpty ? "Unknown Artist" : uniqueArtists.joined(separator: ", ")

        return Track(
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration.isFinite ? max(duration, 0) : 0,
            trackNumber: trackNumber,
            discNumber: discNumber,
            artworkData: artworkData
        )
    }

    /// Reads a numeric metadata value, accepting "3", "3/12" strings, plain
    /// numbers, or iTunes binary atoms (pairs of big-endian UInt16 where the
    /// second pair is the value).
    private func numericValue(of item: AVMetadataItem) async -> Int? {
        if let n = (try? await item.load(.numberValue)) ?? nil, n.intValue > 0 {
            return n.intValue
        }
        if let s = (try? await item.load(.stringValue)) ?? nil {
            let head = s.split(separator: "/").first.map(String.init) ?? s
            if let v = Int(head.trimmingCharacters(in: .whitespaces)), v > 0 { return v }
        }
        if let d = (try? await item.load(.dataValue)) ?? nil, d.count >= 4 {
            let v = Int(d[d.startIndex + 2]) << 8 | Int(d[d.startIndex + 3])
            if v > 0 { return v }
        }
        return nil
    }
}
