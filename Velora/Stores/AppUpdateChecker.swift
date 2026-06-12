import Foundation
import Combine

struct AvailableAppUpdate: Equatable {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableAppUpdate?

    private let releaseService: GitHubReleaseService
    private let bundle: Bundle
    private var isChecking = false

    init(
        releaseService: GitHubReleaseService? = nil,
        bundle: Bundle = .main
    ) {
        self.releaseService = releaseService ?? GitHubReleaseService()
        self.bundle = bundle
    }

    func checkForUpdates() async {
        guard !isChecking else {
            print("Velora update check is already running.")
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let currentVersion = appVersion
            let latestRelease = try await releaseService.fetchLatestRelease()

            let hasNewerVersion = Self.isVersion(latestRelease.version, newerThan: currentVersion)
            let shouldShowUpdate = hasNewerVersion || Self.shouldForceShowUpdateBadge(currentVersion: currentVersion)

            if hasNewerVersion {
                print("Velora update available. Current version: \(currentVersion), latest version: \(latestRelease.version).")
            } else {
                print("Velora is already up to date. Current version: \(currentVersion), latest version: \(latestRelease.version).")
            }

            if !hasNewerVersion, shouldShowUpdate {
                print("Velora update badge is forced for preview.")
            }

            guard shouldShowUpdate else {
                availableUpdate = nil
                return
            }

            availableUpdate = AvailableAppUpdate(
                currentVersion: currentVersion,
                latestVersion: latestRelease.version,
                releaseURL: latestRelease.htmlURL
            )
        } catch {
            availableUpdate = nil
            print("Failed to check Velora updates: \(error.localizedDescription)")
        }
    }

    private var appVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let candidateVersion = SemanticVersion(candidate),
              let currentVersion = SemanticVersion(current) else {
            return false
        }

        return candidateVersion > currentVersion
    }

    private static func shouldForceShowUpdateBadge(currentVersion: String) -> Bool {
        if currentVersion == "dev" {
            return true
        }

        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let coreVersion = rawValue.split(separator: "-", maxSplits: 1).first ?? Substring(rawValue)
        let components = coreVersion.split(separator: ".")

        guard (1...3).contains(components.count) else {
            return nil
        }

        var numbers: [Int] = []

        for component in components {
            guard let number = Int(component) else {
                return nil
            }

            numbers.append(number)
        }

        while numbers.count < 3 {
            numbers.append(0)
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}
