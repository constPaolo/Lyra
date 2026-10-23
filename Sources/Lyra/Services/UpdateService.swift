import Foundation

struct UpdateCheckResult: Sendable {
    let latestVersion: String
    let releaseURL: URL
    let isNewerThanCurrent: Bool
}

actor UpdateService {
    private struct ReleasePayload: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func checkLatestRelease(repoSlug: String, currentVersion: String) async throws -> UpdateCheckResult {
        let slug = repoSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            throw NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repository slug is empty"])
        }

        guard let url = URL(string: "https://api.github.com/repos/\(slug)/releases/latest") else {
            throw NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid repository slug"])
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lyra", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "UpdateService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch latest release"])
        }

        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        guard let releaseURL = URL(string: payload.htmlURL) else {
            throw NSError(domain: "UpdateService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid release URL"])
        }

        let latestVersion = normalizedVersion(payload.tagName)
        let current = normalizedVersion(currentVersion)
        let newer = compare(latestVersion, current) == .orderedDescending

        return UpdateCheckResult(
            latestVersion: latestVersion,
            releaseURL: releaseURL,
            isNewerThanCurrent: newer
        )
    }

    private func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v"), trimmed.count > 1 {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let lv = i < a.count ? a[i] : 0
            let rv = i < b.count ? b[i] : 0
            if lv > rv { return .orderedDescending }
            if lv < rv { return .orderedAscending }
        }
        return .orderedSame
    }
}
