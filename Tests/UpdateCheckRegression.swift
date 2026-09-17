import Foundation

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var payload = Data()
    static var failure: Error?
    static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        precondition(request.url?.absoluteString == "https://api.github.com/repos/sahranov/Duotlet/releases/latest")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Duotlet/") == true)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.payload)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main
enum UpdateCheckRegression {
    static func fixture(_ version: String = "0.3.0", draft: Bool = false, prerelease: Bool = false,
                        suffix: String = "dmg", url: String? = nil, size: Int = 42) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": "v\(version)", "draft": draft, "prerelease": prerelease,
            "assets": [["name": "Duotlet-\(version).\(suffix)", "size": size, "state": "uploaded",
                        "browser_download_url": url ?? "https://github.com/sahranov/Duotlet/releases/download/v\(version)/Duotlet-\(version).\(suffix)"]],
        ])
    }

    static func main() async throws {
        precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
        precondition(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        precondition(ReleaseVersion("0.2.0")! == ReleaseVersion("0.2.0")!)
        for value in ["", "v0.2.0", "0.2", "01.2.0", "1.0.0-beta", "1.0.0+abc", "1.-1.0", "١.٢.٣"] {
            precondition(ReleaseVersion(value) == nil, value)
        }
        let current = ReleaseVersion("0.2.0")!
        for suffix in ["dmg", "zip"] {
            let result = try GitHubUpdateChecker.evaluate(data: fixture(suffix: suffix), status: 200, current: current)
            guard case .available(let release) = result else { fatalError("New release not offered") }
            precondition(release.version.description == "0.3.0")
            precondition(release.downloadURL.pathExtension == suffix)
        }
        for version in ["0.2.0", "0.1.0"] {
            guard case .upToDate = try GitHubUpdateChecker.evaluate(data: fixture(version), status: 200, current: current)
            else { fatalError("Equal or older version offered as an update") }
        }
        guard case .noRelease = try GitHubUpdateChecker.evaluate(data: Data(), status: 404, current: current)
        else { fatalError("Empty repository not handled") }
        for data in [try fixture(draft: true), try fixture(prerelease: true),
                     try fixture("0.3.0-beta"), try fixture(size: 0), try fixture(suffix: "exe"),
                     try fixture(url: "https://example.com/app.dmg"), Data("bad json".utf8)] {
            do {
                _ = try GitHubUpdateChecker.evaluate(data: data, status: 200, current: current)
                fatalError("Incomplete or invalid release accepted")
            } catch UpdateCheckError.invalidResponse {}
        }
        for status in [403, 429, 500, 301] {
            do {
                _ = try GitHubUpdateChecker.evaluate(data: fixture(), status: status, current: current)
                fatalError("HTTP failure reported as success")
            } catch is UpdateCheckError {}
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let checker = GitHubUpdateChecker(session: session)
        StubProtocol.payload = try fixture()
        guard case .available = try await checker.check(currentVersion: "0.2.0") else { fatalError("Transport failed") }
        precondition(StubProtocol.requests == 1)
        do {
            _ = try await checker.check(currentVersion: "invalid")
            fatalError("Invalid local version accepted")
        } catch UpdateCheckError.invalidVersion {}
        precondition(StubProtocol.requests == 1)
        StubProtocol.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await checker.check(currentVersion: "0.2.0")
            fatalError("Offline reported as up-to-date")
        } catch is URLError {}
        print("Update checks passed: versions, release validation, HTTP failures, offline and URLSession transport")

        if CommandLine.arguments.contains("--live") {
            switch try await GitHubUpdateChecker().check(currentVersion: "0.2.0") {
            case .available(let release): print("Live GitHub check: \(release.version)")
            case .upToDate: print("Live GitHub check: up to date")
            case .noRelease: print("Live GitHub check: no published releases")
            }
        }
    }
}
