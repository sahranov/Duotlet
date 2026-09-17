import Foundation

struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    let description: String
    private let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) && ($0.count == 1 || $0.first != "0") }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        description = value
        components = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct AppRelease: Sendable {
    let version: ReleaseVersion
    let downloadURL: URL
}

enum UpdateCheckResult: Sendable {
    case available(AppRelease)
    case upToDate
    case noRelease
}

enum UpdateCheckError: Error {
    case invalidVersion, invalidResponse, rateLimited, server

    var messageKey: String {
        switch self {
        case .invalidVersion: "This build has no valid version number."
        case .invalidResponse: "The update information is incomplete. Try again later."
        case .rateLimited: "GitHub is receiving too many requests. Try again in an hour."
        case .server: "GitHub is unavailable. Try again later."
        }
    }
}

struct GitHubUpdateChecker {
    static let repository = "sahranov/Duotlet"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        guard let current = ReleaseVersion(currentVersion) else { throw UpdateCheckError.invalidVersion }
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Duotlet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        return try Self.evaluate(data: data, status: response.statusCode, current: current)
    }

    static func evaluate(data: Data, status: Int, current: ReleaseVersion) throws -> UpdateCheckResult {
        if status == 404 { return .noRelease }
        if status == 403 || status == 429 { throw UpdateCheckError.rateLimited }
        guard status == 200 else { throw UpdateCheckError.server }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease,
              release.tag_name.hasPrefix("v"),
              let version = ReleaseVersion(String(release.tag_name.dropFirst())) else {
            throw UpdateCheckError.invalidResponse
        }
        guard version > current else { return .upToDate }
        // Only offer complete, universal Duotlet archives from this exact release.
        for suffix in ["dmg", "zip"] {
            let name = "Duotlet-\(version).\(suffix)"
            let expected = "https://github.com/\(repository)/releases/download/v\(version)/\(name)"
            if let asset = release.assets.first(where: {
                $0.name == name && $0.state == "uploaded" && $0.size > 0 && $0.browser_download_url == expected
            }), let url = URL(string: asset.browser_download_url) {
                return .available(AppRelease(version: version, downloadURL: url))
            }
        }
        throw UpdateCheckError.invalidResponse
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
        let browser_download_url: String
    }
}
