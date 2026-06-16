import Foundation

protocol DownloadService {
    var displayName: String { get }
    var endpointDescription: String { get }

    func fetchDownloads() async throws -> [DownloadItem]
    func addDownload(from url: URL, destinationDirectory: URL, fileName: String?) async throws -> DownloadItem.ID
    func addMagnetDownload(from magnetURI: String, destinationDirectory: URL) async throws -> DownloadItem.ID
    func addTorrentDownload(torrentData: Data, destinationDirectory: URL) async throws -> DownloadItem.ID
    func pauseDownload(id: DownloadItem.ID) async throws
    func resumeDownload(id: DownloadItem.ID) async throws
    func removeDownload(id: DownloadItem.ID) async throws
    func removeDownloadResult(id: DownloadItem.ID) async throws
}

extension DownloadService {
    var displayName: String {
        "Download Service"
    }

    var endpointDescription: String {
        ""
    }
}
