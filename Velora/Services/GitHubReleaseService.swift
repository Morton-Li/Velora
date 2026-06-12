import Foundation

struct GitHubRelease: Equatable {
    let tagName: String
    let htmlURL: URL

    var version: String {
        if tagName.lowercased().hasPrefix("v") {
            return String(tagName.dropFirst())
        }

        return tagName
    }
}

final class GitHubReleaseService {
    private let latestReleaseURL: URL
    private let urlSession: URLSession

    init(
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/Morton-Li/Velora/releases/latest")!,
        urlSession: URLSession = .shared
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.urlSession = urlSession
    }

    func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw GitHubReleaseError.httpStatus(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubLatestReleaseResponse.self, from: data)
        return GitHubRelease(tagName: release.tagName, htmlURL: release.htmlURL)
    }
}

private enum GitHubReleaseError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            "GitHub Releases API returned HTTP \(statusCode)."
        }
    }
}

private struct GitHubLatestReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
