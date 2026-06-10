import Foundation
import SwiftUI

struct DownloadItem: Identifiable, Hashable {
    let id: String
    let fileName: String
    let source: String
    let destination: String
    let status: DownloadStatus
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Int64
    let remainingSeconds: TimeInterval?
    let connections: Int
    let localFilePaths: [String]

    var remainingBytes: Int64 {
        max(totalBytes - downloadedBytes, 0)
    }

    var destinationDirectoryURL: URL {
        if let firstLocalFilePath = localFilePaths.first {
            return URL(fileURLWithPath: firstLocalFilePath).deletingLastPathComponent()
        }

        return URL(fileURLWithPath: destination)
    }
}

enum DownloadStatus: String, CaseIterable {
    case active
    case paused
    case completed
    case stopped
    case failed

    var title: String {
        switch self {
        case .active: "Downloading"
        case .paused: "Paused"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .failed: "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .active: "arrow.down.circle.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: .accentColor
        case .paused: .orange
        case .completed: .green
        case .stopped: .secondary
        case .failed: .red
        }
    }
}

enum DownloadFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case active
    case paused
    case completed
    case stopped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .stopped: "Stopped"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        }
    }

    func includes(_ item: DownloadItem) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            item.status == .active
        case .paused:
            item.status == .paused
        case .completed:
            item.status == .completed
        case .stopped:
            item.status == .stopped
        }
    }

    func count(in downloads: [DownloadItem]) -> Int {
        downloads.filter { includes($0) }.count
    }
}

enum DownloadCommand {
    case pause
    case resume
    case remove
    case restart
}
