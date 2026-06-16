import Foundation

final class Aria2DownloadService: DownloadService {
    private static let taskKeys = [
        "gid",
        "status",
        "totalLength",
        "completedLength",
        "downloadSpeed",
        "connections",
        "infoHash",
        "followedBy",
        "following",
        "belongsTo",
        "dir",
        "files"
    ]

    private let endpointURL: URL
    private let secret: String?
    private let urlSession: URLSession

    init(
        endpointURL: URL = URL(string: "http://127.0.0.1:6800/jsonrpc")!,
        secret: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.endpointURL = endpointURL
        self.secret = secret
        self.urlSession = urlSession
    }

    var displayName: String {
        "aria2 RPC"
    }

    var endpointDescription: String {
        if let host = endpointURL.host, let port = endpointURL.port {
            return "\(host):\(port)"
        }

        return endpointURL.host ?? endpointURL.absoluteString
    }

    func fetchDownloads() async throws -> [DownloadItem] {
        async let active: [Aria2Status] = call(method: "aria2.tellActive", params: [Self.taskKeys])
        async let waiting: [Aria2Status] = call(method: "aria2.tellWaiting", params: [0, 100, Self.taskKeys])
        async let stopped: [Aria2Status] = call(method: "aria2.tellStopped", params: [0, 100, Self.taskKeys])

        let statuses = try await (active + waiting + stopped)
        let realDownloadInfoHashes = Set(
            statuses.compactMap { status in
                status.isMetadataDownload ? nil : status.normalizedInfoHash
            }
        )
        let realDownloadParentIDs = Set(
            statuses
                .filter { !$0.isMetadataDownload }
                .flatMap { [$0.following, $0.belongsTo].compactMap { $0 } }
        )

        return statuses
            .filter {
                !$0.shouldHideMetadataDownload(
                    realDownloadInfoHashes: realDownloadInfoHashes,
                    realDownloadParentIDs: realDownloadParentIDs
                )
            }
            .map(\.downloadItem)
    }

    func addDownload(from url: URL, destinationDirectory: URL, fileName: String?) async throws -> DownloadItem.ID {
        var options = ["dir": destinationDirectory.path]

        if let fileName, !fileName.isEmpty {
            options["out"] = fileName
        }

        return try await call(
            method: "aria2.addUri",
            params: [
                [url.absoluteString],
                options
            ]
        )
    }

    func addMagnetDownload(from magnetURI: String, destinationDirectory: URL) async throws -> DownloadItem.ID {
        var options = ["dir": destinationDirectory.path]

        if let magnetLink = try? MagnetLink.parse(magnetURI), !magnetLink.trackers.isEmpty {
            options["bt-tracker"] = magnetLink.trackers.joined(separator: ",")
        }

        return try await call(
            method: "aria2.addUri",
            params: [
                [magnetURI],
                options
            ]
        )
    }

    func pauseDownload(id: DownloadItem.ID) async throws {
        do {
            let _: String = try await call(method: "aria2.pause", params: [id])
        } catch {
            let _: String = try await call(method: "aria2.forcePause", params: [id])
        }
    }

    func resumeDownload(id: DownloadItem.ID) async throws {
        let _: String = try await call(method: "aria2.unpause", params: [id])
    }

    func removeDownload(id: DownloadItem.ID) async throws {
        let _: String = try await call(method: "aria2.forceRemove", params: [id])
    }

    func removeDownloadResult(id: DownloadItem.ID) async throws {
        let _: String = try await call(method: "aria2.removeDownloadResult", params: [id])
    }

    private func call<Result: Decodable>(method: String, params: [Any]) async throws -> Result {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(method: method, params: params))

        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw Aria2Error.httpStatus(httpResponse.statusCode)
        }

        let rpcResponse = try JSONDecoder().decode(Aria2Response<Result>.self, from: data)

        if let error = rpcResponse.error {
            throw Aria2Error.rpc(code: error.code, message: error.message)
        }

        guard let result = rpcResponse.result else {
            throw Aria2Error.missingResult(method)
        }

        return result
    }

    private func requestBody(method: String, params: [Any]) -> [String: Any] {
        var rpcParams = params

        if let secret, !secret.isEmpty {
            rpcParams.insert("token:\(secret)", at: 0)
        }

        return [
            "jsonrpc": "2.0",
            "id": method,
            "method": method,
            "params": rpcParams
        ]
    }
}

private enum Aria2Error: LocalizedError {
    case httpStatus(Int)
    case rpc(code: Int, message: String)
    case missingResult(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            "aria2 RPC returned HTTP \(statusCode)."
        case .rpc(_, let message):
            message
        case .missingResult(let method):
            "aria2 RPC returned no result for \(method)."
        }
    }
}

private struct Aria2Response<Result: Decodable>: Decodable {
    let result: Result?
    let error: Aria2RPCError?
}

private struct Aria2RPCError: Decodable {
    let code: Int
    let message: String
}

private struct Aria2Status: Decodable {
    let gid: String
    let status: String
    let totalLength: String
    let completedLength: String
    let downloadSpeed: String
    let connections: String?
    let infoHash: String?
    let followedBy: [String]?
    let following: String?
    let belongsTo: String?
    let dir: String?
    let files: [Aria2File]?

    var downloadItem: DownloadItem {
        let totalBytes = totalLength.int64Value
        let downloadedBytes = completedLength.int64Value
        let speedBytesPerSecond = downloadSpeed.int64Value
        let remainingBytes = max(totalBytes - downloadedBytes, 0)
        let remainingSeconds = speedBytesPerSecond > 0 ? TimeInterval(remainingBytes) / TimeInterval(speedBytesPerSecond) : nil

        return DownloadItem(
            id: gid,
            fileName: fileName,
            source: source,
            destination: destination,
            status: downloadStatus,
            progress: progress(downloadedBytes: downloadedBytes, totalBytes: totalBytes),
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: speedBytesPerSecond,
            remainingSeconds: remainingSeconds,
            connections: connections?.intValue ?? 0,
            localFilePaths: localFilePaths,
            isMetadataPlaceholder: isMetadataDownload
        )
    }

    private var fileName: String {
        if isMetadataDownload, let displayName = metadataDisplayName {
            return displayName
        }

        if let path = primaryFile?.path, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        if let uri = primaryFile?.uris?.first?.uri, let url = URL(string: uri), let lastPathComponent = url.pathComponents.last, !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        return gid
    }

    private var source: String {
        primaryFile?.uris?.first?.uri ?? ""
    }

    private var destination: String {
        dir ?? primaryFile?.path ?? ""
    }

    private var localFilePaths: [String] {
        files?
            .compactMap(\.path)
            .filter { !$0.isEmpty } ?? []
    }

    private var primaryFile: Aria2File? {
        files?.first
    }

    var normalizedInfoHash: String? {
        infoHash?.lowercased()
            ?? metadataInfoHash?.lowercased()
    }

    var isMetadataDownload: Bool {
        guard let path = primaryFile?.path else {
            return false
        }

        return path.contains("[METADATA]")
    }

    func shouldHideMetadataDownload(realDownloadInfoHashes: Set<String>, realDownloadParentIDs: Set<String>) -> Bool {
        guard isMetadataDownload else {
            return false
        }

        if let followedBy, !followedBy.isEmpty {
            return true
        }

        if realDownloadParentIDs.contains(gid) {
            return true
        }

        if let normalizedInfoHash, realDownloadInfoHashes.contains(normalizedInfoHash) {
            return true
        }

        return false
    }

    private var metadataDisplayName: String? {
        guard metadataInfoHash != nil else {
            return nil
        }

        return "Fetching metadata ..."
    }

    private var metadataInfoHash: String? {
        guard let path = primaryFile?.path,
              let metadataRange = path.range(of: "[METADATA]") else {
            return nil
        }

        let infoHash = path[metadataRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return infoHash.isEmpty ? nil : infoHash
    }

    private var downloadStatus: DownloadStatus {
        switch status {
        case "active":
            .active
        case "paused":
            .paused
        case "complete":
            .completed
        case "error":
            .failed
        default:
            .stopped
        }
    }

    private func progress(downloadedBytes: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }
}

private struct Aria2File: Decodable {
    let path: String?
    let uris: [Aria2URI]?
}

private struct Aria2URI: Decodable {
    let uri: String
}

private extension String {
    var int64Value: Int64 {
        Int64(self) ?? 0
    }

    var intValue: Int {
        Int(self) ?? 0
    }
}
