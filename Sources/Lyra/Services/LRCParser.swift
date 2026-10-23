import Foundation

struct LRCParser {

    /// Parses standard LRC content (`[mm:ss.xx]` / `[mm:ss.xxx]`) into time-sorted lyric lines.
    /// Supports multiple timestamps on a single line: `[00:12.34][01:03.20]text`
    static func parse(_ content: String) -> [LyricLine] {
        // Matches a single [mm:ss.xx] or [mm:ss.xxx] tag at the START of a string segment
        let tsPattern = #"\[(\d{1,2}):(\d{2})\.(\d{2,3})\]"#
        guard let tsRegex = try? NSRegularExpression(pattern: tsPattern) else { return [] }

        var lines: [LyricLine] = []

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = tsRegex.matches(in: line, range: fullRange)
            guard !matches.isEmpty else { continue }

            // The lyric text follows the last timestamp tag
            let lastMatch = matches[matches.count - 1]
            let textStart = lastMatch.range.location + lastMatch.range.length
            let text: String
            if textStart < nsLine.length {
                text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            } else {
                text = ""
            }
            guard !text.isEmpty else { continue }

            for match in matches {
                let mins  = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let secs  = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let fracS = nsLine.substring(with: match.range(at: 3))
                let frac  = fracS.count == 2
                    ? (Double(fracS) ?? 0) / 100.0
                    : (Double(fracS) ?? 0) / 1000.0
                lines.append(LyricLine(timestamp: mins * 60 + secs + frac, text: text))
            }
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
