import Foundation

struct TorrentFileCandidate: Equatable {
    let displayName: String
    let byteCount: Int64?
    let contentType: String?

    var isLikelyTorrent: Bool {
        TorrentFileResolver.isTorrentFileName(displayName) ||
            TorrentFileResolver.isTorrentContentType(contentType)
    }
}

struct TorrentFilePayload {
    let data: Data
}

enum TorrentFileResolver {
    private static let infoMarker = Data("4:info".utf8)

    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func localCandidate(from fileURL: URL) -> TorrentFileCandidate? {
        let displayName = fileURL.lastPathComponent
        guard isTorrentFileName(displayName) else {
            return nil
        }

        let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return TorrentFileCandidate(
            displayName: displayName,
            byteCount: fileSize.map(Int64.init),
            contentType: nil
        )
    }

    static func localTorrentPayload(from fileURL: URL) throws -> TorrentFilePayload {
        guard localCandidate(from: fileURL) != nil else {
            throw TorrentFileError.invalidTorrentFile
        }

        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        try validateTorrentData(data)

        return TorrentFilePayload(
            data: data
        )
    }

    static func remoteCandidate(from rawURL: String) async -> TorrentFileCandidate? {
        guard let url = remoteURL(from: rawURL) else {
            return nil
        }

        return await remoteCandidate(from: url)
    }

    static func remoteCandidate(from url: URL) async -> TorrentFileCandidate? {
        let fallbackCandidate = fallbackRemoteCandidate(from: url)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let candidate = candidate(from: response, originalURL: url) else {
                return fallbackCandidate?.isLikelyTorrent == true ? fallbackCandidate : nil
            }

            if candidate.isLikelyTorrent {
                return candidate
            }

            return fallbackCandidate?.isLikelyTorrent == true ? fallbackCandidate : nil
        } catch {
            return fallbackCandidate?.isLikelyTorrent == true ? fallbackCandidate : nil
        }
    }

    static func remoteTorrentPayload(from rawURL: String) async throws -> TorrentFilePayload {
        guard let url = remoteURL(from: rawURL) else {
            throw TorrentFileError.invalidTorrentURL
        }

        let candidate = await remoteCandidate(from: url)
        return try await remoteTorrentPayload(
            from: url,
            candidate: candidate,
            suggestedFileName: nil,
            requiresTorrentSignal: true
        )
    }

    static func remoteTorrentPayloadIfDetected(from url: URL, suggestedFileName: String?) async throws -> TorrentFilePayload? {
        let candidate = fallbackRemoteCandidate(from: url)
        let isDetected = candidate?.isLikelyTorrent == true || isTorrentFileName(suggestedFileName)

        guard isDetected else {
            return nil
        }

        return try await remoteTorrentPayload(
            from: url,
            candidate: candidate,
            suggestedFileName: suggestedFileName,
            requiresTorrentSignal: false
        )
    }

    static func isTorrentFileName(_ fileName: String?) -> Bool {
        guard let fileName else {
            return false
        }

        return fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasSuffix(".torrent")
    }

    static func isTorrentContentType(_ contentType: String?) -> Bool {
        guard let contentType else {
            return false
        }

        guard let normalizedContentType = contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }

        return [
            "application/x-bittorrent",
            "application/x-torrent",
            "application/torrent",
            "application/vnd.bittorrent"
        ].contains(normalizedContentType)
    }

    private static func remoteTorrentPayload(
        from url: URL,
        candidate knownCandidate: TorrentFileCandidate?,
        suggestedFileName: String?,
        requiresTorrentSignal: Bool
    ) async throws -> TorrentFilePayload {
        let (data, response) = try await urlSession.data(from: url)
        let responseCandidate = Self.candidate(from: response, originalURL: url)
        let hasTorrentSignal = responseCandidate?.isLikelyTorrent == true
            || knownCandidate?.isLikelyTorrent == true
            || isTorrentFileName(suggestedFileName)

        if requiresTorrentSignal, !hasTorrentSignal {
            throw TorrentFileError.remoteFileIsNotTorrent
        }

        try validateTorrentData(data)

        return TorrentFilePayload(
            data: data
        )
    }

    private static func validateTorrentData(_ data: Data) throws {
        guard !data.isEmpty,
              data.first == 100,
              data.range(of: infoMarker) != nil else {
            throw TorrentFileError.invalidTorrentFile
        }
    }

    private static func candidate(from response: URLResponse, originalURL: URL) -> TorrentFileCandidate? {
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<400).contains(httpResponse.statusCode) else {
                return nil
            }

            let contentDispositionFileName = httpResponse
                .value(forHTTPHeaderField: "Content-Disposition")
                .flatMap(DownloadFileNameResolver.fileName(fromContentDisposition:))
            let responseURL = httpResponse.url ?? originalURL
            let displayName = contentDispositionFileName
                ?? DownloadFileNameResolver.localFileName(from: responseURL)
                ?? DownloadFileNameResolver.localFileName(from: originalURL)
                ?? "BitTorrent File.torrent"
            let byteCount = httpResponse
                .value(forHTTPHeaderField: "Content-Length")
                .flatMap(Int64.init)

            return TorrentFileCandidate(
                displayName: displayName,
                byteCount: byteCount,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
            )
        }

        return fallbackRemoteCandidate(from: response.url ?? originalURL)
    }

    private static func fallbackRemoteCandidate(from url: URL) -> TorrentFileCandidate? {
        guard let displayName = DownloadFileNameResolver.localFileName(from: url) else {
            return nil
        }

        return TorrentFileCandidate(
            displayName: displayName,
            byteCount: nil,
            contentType: nil
        )
    }

    private static func remoteURL(from rawURL: String) -> URL? {
        DownloadFileNameResolver.downloadURL(from: rawURL)
    }
}

private enum TorrentFileError: LocalizedError {
    case invalidTorrentFile
    case invalidTorrentURL
    case remoteFileIsNotTorrent

    var errorDescription: String? {
        switch self {
        case .invalidTorrentFile:
            "Choose a valid torrent file."
        case .invalidTorrentURL:
            "Enter a valid torrent file URL."
        case .remoteFileIsNotTorrent:
            "The remote file is not a torrent file."
        }
    }
}
