import Foundation

struct LyricsQueryCandidate: Hashable, Sendable {
    let trackName: String
    let artistName: String
}

enum LyricsMatcher {
    static func queryVariants(trackName: String, artistName: String) -> [LyricsQueryCandidate] {
        let baseTitle = trimmed(trackName)
        let baseArtist = cleanedArtistName(artistName)
        guard !baseTitle.isEmpty else { return [] }

        var candidates: [LyricsQueryCandidate] = []
        var seen: Set<String> = []

        func add(_ title: String, _ artist: String) {
            let t = trimmed(title)
            let a = trimmed(artist)
            guard !t.isEmpty else { return }
            let key = "\(normalized(t))|\(normalized(a))"
            guard seen.insert(key).inserted else { return }
            candidates.append(.init(trackName: t, artistName: a))
        }

        let titleVariants = titleVariants(for: baseTitle)

        add(baseTitle, baseArtist)
        add(baseTitle, "")

        for title in titleVariants {
            add(title, baseArtist)
            add(title, "")
        }

        if let split = splitTrackAndArtistFromTitle(baseTitle) {
            add(split.trackName, baseArtist.isEmpty ? split.artistName : baseArtist)
            add(split.trackName, split.artistName)
            add(split.trackName, "")
        }

        return Array(candidates.prefix(10))
    }

    static func score(
        result: LyricsSearchResult,
        candidate: LyricsQueryCandidate,
        expectedDuration: Double,
        expectedAlbum: String
    ) -> Int {
        let hasSynced = !(result.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPlain = !(result.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasSynced && !hasPlain { return Int.min }

        var score = hasSynced ? 12 : 5

        let candidateTitle = normalized(candidate.trackName)
        let resultTitle = normalized(result.trackName)
        score += stringMatchScore(candidateTitle, resultTitle, strong: 18, medium: 10, weak: 5)

        let candidateArtist = normalized(candidate.artistName)
        let resultArtist = normalized(result.artistName)
        if !candidateArtist.isEmpty {
            score += stringMatchScore(candidateArtist, resultArtist, strong: 12, medium: 7, weak: 3)
        }

        let album = normalized(expectedAlbum)
        if !album.isEmpty {
            let resultAlbum = normalized(result.albumName)
            if !resultAlbum.isEmpty {
                score += stringMatchScore(album, resultAlbum, strong: 3, medium: 2, weak: 1)
            }
        }

        if let resultDuration = result.duration, expectedDuration > 0 {
            let diff = abs(resultDuration - expectedDuration)
            switch diff {
            case ...1.5: score += 8
            case ...4.0: score += 5
            case ...8.0: score += 3
            case ...15.0: score += 1
            default: score -= 2
            }
        }

        return score
    }

    static func normalized(_ value: String) -> String {
        normalized(value, keepDash: false)
    }

    private static func titleVariants(for title: String) -> [String] {
        let cleaned = cleanedTrackName(title)
        var variants = [title, cleaned]
        if let split = splitTrackAndArtistFromTitle(title) {
            variants.append(split.trackName)
        }
        return variants.map(trimmed).filter { !$0.isEmpty }
    }

    private static func cleanedTrackName(_ value: String) -> String {
        var out = value
        out = replacing(out, pattern: #"\(.*?\)|\[.*?\]"#, with: " ")
        out = replacing(out, pattern: #"(?i)\b(feat\.?|ft\.?|featuring)\b.*$"#, with: " ")
        out = replacing(
            out,
            pattern: #"(?i)\b(remaster(?:ed)?|live|version|edit|radio edit|mono|stereo|deluxe)\b"#,
            with: " "
        )
        if let split = splitTrackAndArtistFromTitle(out) {
            out = split.trackName
        }
        return collapseWhitespace(out)
    }

    private static func cleanedArtistName(_ value: String) -> String {
        var out = value
        out = replacing(out, pattern: #"(?i)\b(feat\.?|ft\.?|featuring)\b.*$"#, with: " ")
        out = collapseWhitespace(out)
        return out
    }

    private static func splitTrackAndArtistFromTitle(_ value: String) -> (trackName: String, artistName: String)? {
        let parts = value
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { collapseWhitespace(String($0)) }
            .filter { !$0.isEmpty }
        guard parts.count == 2 else { return nil }
        guard parts[1].count <= 48 else { return nil }
        return (parts[0], parts[1])
    }

    private static func stringMatchScore(
        _ lhs: String,
        _ rhs: String,
        strong: Int,
        medium: Int,
        weak: Int
    ) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return strong }
        if lhs.contains(rhs) || rhs.contains(lhs) { return medium }
        let overlap = tokenOverlap(lhs, rhs)
        if overlap >= 0.75 { return weak }
        return 0
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let l = Set(lhs.split(separator: " ").map(String.init))
        let r = Set(rhs.split(separator: " ").map(String.init))
        guard !l.isEmpty, !r.isEmpty else { return 0 }
        let intersection = l.intersection(r).count
        let maxCount = max(l.count, r.count)
        guard maxCount > 0 else { return 0 }
        return Double(intersection) / Double(maxCount)
    }

    private static func normalized(_ value: String, keepDash: Bool) -> String {
        var text = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allowed = keepDash ? CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- ")) : CharacterSet.alphanumerics.union(.whitespaces)
        text = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return collapseWhitespace(text).lowercased()
    }

    private static func replacing(_ value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
