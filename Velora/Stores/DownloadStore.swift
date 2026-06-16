import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var items: [DownloadItem]
    @Published private(set) var loadState: LoadState = .idle

    private let service: DownloadService
    private let processController: Aria2ProcessController?
    private let refreshInterval: Duration
    private var isSyncing = false
    private var securityScopedDestinationURLs: [URL] = []

    convenience init() {
        if let runtime = try? Aria2Runtime() {
            self.init(
                service: Aria2DownloadService(endpointURL: runtime.endpointURL, secret: runtime.secret),
                processController: Aria2ProcessController(runtime: runtime)
            )
        } else {
            self.init(service: Aria2DownloadService())
        }
    }

    init(
        service: DownloadService,
        processController: Aria2ProcessController? = nil,
        refreshInterval: Duration = .milliseconds(800)  // 状态刷新频率
    ) {
        self.service = service
        self.processController = processController
        self.refreshInterval = refreshInterval
        self.items = []
    }

    var endpointStatus: EndpointStatus {
        let reachability: EndpointStatus.Reachability
        let message: String?

        switch loadState {
        case .idle:
            reachability = .notChecked
            message = nil
        case .loading:
            reachability = items.isEmpty ? .checking : .reachable
            message = nil
        case .loaded:
            reachability = .reachable
            message = nil
        case .failed(let errorMessage):
            reachability = .unreachable
            message = errorMessage
        }

        return EndpointStatus(
            endpointName: service.displayName,
            endpointDescription: service.endpointDescription,
            reachability: reachability,
            message: message,
            downloadSpeedBytesPerSecond: items.reduce(0) { $0 + $1.speedBytesPerSecond },
            connections: items.reduce(0) { $0 + $1.connections }
        )
    }

    func startSyncing() async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await startRuntimeIfNeeded()
        } catch {
            loadState = .failed(error.localizedDescription)
            return
        }

        await refresh()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: refreshInterval)
                await refresh()
            } catch {
                break
            }
        }
    }

    func stopRuntime() {
        processController?.stop()
        stopAccessingSecurityScopedDestinationURLs()
    }

    func restartRuntime() async throws {
        guard processController != nil else {
            return
        }

        processController?.stop()
        try await startRuntimeIfNeeded()
        await refresh()
    }

    func refresh() async {
        if loadState == .idle {
            loadState = .loading
        }

        do {
            items = try await service.fetchDownloads()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func addDownload(from rawURL: String, destinationDirectory: URL, fileName rawFileName: String?) async throws -> DownloadItem.ID {
        let url = try Self.downloadURL(from: rawURL)
        let fileName = try Self.downloadFileName(from: rawFileName)

        do {
            try await startRuntimeIfNeeded()
            keepAccessToSecurityScopedDestination(destinationDirectory)
            try Self.ensureDirectoryExists(destinationDirectory)
            let id: DownloadItem.ID

            if let torrentFile = try await TorrentFileResolver.remoteTorrentPayloadIfDetected(from: url, suggestedFileName: fileName) {
                id = try await service.addTorrentDownload(torrentData: torrentFile.data, destinationDirectory: destinationDirectory)
            } else {
                id = try await service.addDownload(from: url, destinationDirectory: destinationDirectory, fileName: fileName)
            }

            await refresh()
            return id
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    func addTorrentDownload(fromFile fileURL: URL, destinationDirectory: URL) async throws -> DownloadItem.ID {
        let torrentFile = try TorrentFileResolver.localTorrentPayload(from: fileURL)
        return try await addTorrentDownload(torrentFile, destinationDirectory: destinationDirectory)
    }

    func addTorrentDownload(fromRemoteURL rawURL: String, destinationDirectory: URL) async throws -> DownloadItem.ID {
        let torrentFile = try await TorrentFileResolver.remoteTorrentPayload(from: rawURL)
        return try await addTorrentDownload(torrentFile, destinationDirectory: destinationDirectory)
    }

    func addMagnetDownload(from rawMagnetURI: String, destinationDirectory: URL) async throws -> DownloadItem.ID {
        let magnetURI = try Self.magnetURI(from: rawMagnetURI)

        do {
            try await startRuntimeIfNeeded()
            keepAccessToSecurityScopedDestination(destinationDirectory)
            try Self.ensureDirectoryExists(destinationDirectory)
            let id = try await service.addMagnetDownload(from: magnetURI, destinationDirectory: destinationDirectory)
            await refresh()
            return id
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    func pauseDownload(_ item: DownloadItem) async throws {
        try await performDownloadOperation {
            try await service.pauseDownload(id: item.id)
        }
    }

    func resumeDownload(_ item: DownloadItem) async throws {
        try await performDownloadOperation {
            try await service.resumeDownload(id: item.id)
        }
    }

    func removeDownload(_ item: DownloadItem, deletingLocalFiles: Bool) async throws {
        try await performDownloadOperation {
            try await removeDownloadWithoutRefresh(item)
            if deletingLocalFiles {
                removeLocalFiles(for: item)
            }
        }
    }

    func restartDownload(_ item: DownloadItem) async throws -> DownloadItem.ID {
        do {
            try await startRuntimeIfNeeded()
            try await removeDownloadWithoutRefresh(item)
            removeLocalFiles(for: item)
            let id: DownloadItem.ID

            if let magnetURI = try? Self.magnetURI(from: item.source) {
                id = try await service.addMagnetDownload(from: magnetURI, destinationDirectory: item.destinationDirectoryURL)
            } else {
                let url = try Self.downloadURL(from: item.source)
                id = try await service.addDownload(from: url, destinationDirectory: item.destinationDirectoryURL, fileName: item.fileName)
            }

            await refresh()
            return id
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    func items(matching filter: DownloadFilter, searchText: String) -> [DownloadItem] {
        let filtered = items.filter { filter.includes($0) }

        guard !searchText.isEmpty else {
            return filtered
        }

        return filtered.filter {
            $0.fileName.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText)
        }
    }

    func item(id: DownloadItem.ID?, in items: [DownloadItem]) -> DownloadItem? {
        guard let id else {
            return nil
        }

        return items.first { $0.id == id }
    }

    private func startRuntimeIfNeeded() async throws {
        try processController?.startIfNeeded()

        if processController != nil {
            try await Task.sleep(for: .milliseconds(300))
            try processController?.ensureRunning()
        }
    }

    private func performDownloadOperation(_ operation: () async throws -> Void) async throws {
        do {
            try await startRuntimeIfNeeded()
            try await operation()
            await refresh()
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    private func addTorrentDownload(_ torrentFile: TorrentFilePayload, destinationDirectory: URL) async throws -> DownloadItem.ID {
        do {
            try await startRuntimeIfNeeded()
            keepAccessToSecurityScopedDestination(destinationDirectory)
            try Self.ensureDirectoryExists(destinationDirectory)
            let id = try await service.addTorrentDownload(torrentData: torrentFile.data, destinationDirectory: destinationDirectory)
            await refresh()
            return id
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    private func removeDownloadWithoutRefresh(_ item: DownloadItem) async throws {
        switch item.status {
        case .active, .paused:
            try await service.removeDownload(id: item.id)
            await clearDownloadResult(id: item.id)
        case .completed, .stopped, .failed:
            try await service.removeDownloadResult(id: item.id)
        }
    }

    private func clearDownloadResult(id: DownloadItem.ID) async {
        do {
            try await service.removeDownloadResult(id: id)
        } catch {
            try? await Task.sleep(for: .milliseconds(150))
            try? await service.removeDownloadResult(id: id)
        }
    }

    private func removeLocalFiles(for item: DownloadItem) {
        let fileManager = FileManager.default

        item.localFilePaths
            .flatMap { [$0, "\($0).aria2"] }
            .map(URL.init(fileURLWithPath:))
            .forEach { url in
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    return
                }

                try? fileManager.removeItem(at: url)
            }
    }

    private static func downloadURL(from rawURL: String) throws -> URL {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty else {
            throw DownloadCreationError.emptyURL
        }

        guard let url = URL(string: trimmedURL), url.host != nil else {
            throw DownloadCreationError.invalidURL
        }

        guard let scheme = url.scheme?.lowercased(), ["http", "https", "ftp"].contains(scheme) else {
            throw DownloadCreationError.unsupportedScheme
        }

        return url
    }

    private static func magnetURI(from rawMagnetURI: String) throws -> String {
        try MagnetLink.parse(rawMagnetURI).normalizedURI
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return
        }

        guard isDirectory.boolValue else {
            throw DownloadCreationError.invalidDestination
        }
    }

    private static func downloadFileName(from rawFileName: String?) throws -> String? {
        guard let rawFileName else {
            return nil
        }

        guard let fileName = DownloadFileNameResolver.sanitizedFileName(rawFileName) else {
            throw DownloadCreationError.invalidFileName
        }

        return fileName
    }

    private func keepAccessToSecurityScopedDestination(_ url: URL) {
        guard !securityScopedDestinationURLs.contains(url), url.startAccessingSecurityScopedResource() else {
            return
        }

        securityScopedDestinationURLs.append(url)
    }

    private func stopAccessingSecurityScopedDestinationURLs() {
        securityScopedDestinationURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedDestinationURLs.removeAll()
    }
}

struct MagnetLink: Equatable {
    let normalizedURI: String
    let displayName: String?
    let exactTopic: String
    let infoHash: String?
    let trackers: [String]

    nonisolated static func parse(_ rawMagnetURI: String) throws -> MagnetLink {
        let normalizedURI = rawMagnetURI.components(separatedBy: .whitespacesAndNewlines).joined()

        guard !normalizedURI.isEmpty else {
            throw DownloadCreationError.emptyMagnetURI
        }

        let lowercasedURI = normalizedURI.lowercased()
        guard lowercasedURI.hasPrefix("magnet:?") else {
            throw DownloadCreationError.invalidMagnetURI
        }

        let queryStart = normalizedURI.index(normalizedURI.startIndex, offsetBy: "magnet:?".count)
        let parameters = parameters(from: normalizedURI[queryStart...])
        let exactTopics = parameters.values(named: "xt")

        guard let exactTopic = exactTopics.first(where: isSupportedExactTopic) else {
            throw DownloadCreationError.invalidMagnetURI
        }

        return MagnetLink(
            normalizedURI: normalizedURI,
            displayName: parameters.values(named: "dn").first?.nilIfEmpty,
            exactTopic: exactTopic,
            infoHash: infoHash(from: exactTopic),
            trackers: parameters.values(named: "tr").filter { !$0.isEmpty }
        )
    }

    private nonisolated static func parameters(from query: Substring) -> [MagnetLinkParameter] {
        query.split(separator: "&", omittingEmptySubsequences: true).compactMap { parameter in
            let parts = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return nil
            }

            return MagnetLinkParameter(
                name: decodedQueryValue(String(parts[0])),
                value: decodedQueryValue(String(parts[1]))
            )
        }
    }

    private nonisolated static func isSupportedExactTopic(_ exactTopic: String) -> Bool {
        let lowercasedTopic = exactTopic.lowercased()
        return lowercasedTopic.hasPrefix("urn:btih:") || lowercasedTopic.hasPrefix("urn:btmh:")
    }

    private nonisolated static func infoHash(from exactTopic: String) -> String? {
        let lowercasedTopic = exactTopic.lowercased()

        if lowercasedTopic.hasPrefix("urn:btih:") {
            return String(exactTopic.dropFirst("urn:btih:".count)).nilIfEmpty
        }

        if lowercasedTopic.hasPrefix("urn:btmh:") {
            return String(exactTopic.dropFirst("urn:btmh:".count)).nilIfEmpty
        }

        return nil
    }

    private nonisolated static func decodedQueryValue(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}

private struct MagnetLinkParameter: Equatable {
    let name: String
    let value: String
}

private extension [MagnetLinkParameter] {
    nonisolated func values(named name: String) -> [String] {
        filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum DownloadCreationError: LocalizedError {
    case emptyURL
    case emptyMagnetURI
    case invalidURL
    case invalidMagnetURI
    case unsupportedScheme
    case invalidDestination
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            "Enter a download URL."
        case .emptyMagnetURI:
            "Enter a magnet link."
        case .invalidURL:
            "Enter a valid URL."
        case .invalidMagnetURI:
            "Enter a valid magnet link."
        case .unsupportedScheme:
            "Only HTTP, HTTPS, and FTP links are supported."
        case .invalidDestination:
            "Choose a valid download folder."
        case .invalidFileName:
            "Enter a valid file name."
        }
    }
}
