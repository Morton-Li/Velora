import SwiftUI

struct DownloadDetailView: View {
    let download: DownloadItem?
    var onPerformCommand: (DownloadCommand, DownloadItem) -> Void = { _, _ in }
    var onClose: () -> Void = {}
    var isPausePending = false

    var body: some View {
        VStack(spacing: 0) {
            if let download {
                DetailHeader(
                    download: download,
                    onPerformCommand: onPerformCommand,
                    onClose: onClose,
                    isPausePending: isPausePending
                )

                Divider()
                    .opacity(0.45)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DetailProgressCard(download: download)
                        DetailSection(title: "Source") {
                            DetailValueRow(title: "URL", value: download.source, symbolName: "link")
                            DetailValueRow(title: "Destination", value: download.destination, symbolName: "folder")
                        }
                        DetailSection(title: "Transfer") {
                            DetailValueRow(title: "Downloaded", value: DownloadFormatters.bytes(download.downloadedBytes), symbolName: "externaldrive")
                            DetailValueRow(title: "Remaining", value: DownloadFormatters.bytes(download.remainingBytes), symbolName: "tray.and.arrow.down")
                            DetailValueRow(title: "Connections", value: "\(download.connections)", symbolName: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptySelectionView()
            }
        }
        .frame(minWidth: 300)
        .background(.thinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .vertical)
                .allowsHitTesting(false)
        }
    }
}

private struct DetailHeader: View {
    let download: DownloadItem
    let onPerformCommand: (DownloadCommand, DownloadItem) -> Void
    let onClose: () -> Void
    let isPausePending: Bool

    private var showsProcessingIcon: Bool {
        isPausePending || download.isMetadataPlaceholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if showsProcessingIcon {
                        ProgressView()
                            .controlSize(.small)
                            .tint(download.status.tint)
                    } else {
                        Image(systemName: download.status.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(download.status.tint)
                    }
                }
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(download.status.tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(download.fileName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    Text(showsProcessingIcon ? processingTitle : download.status.title)
                        .font(.caption)
                        .foregroundStyle(download.status.tint)
                }

                Spacer()

                IconButton(systemName: "sidebar.right", help: "Hide details", action: onClose)
            }

            HStack(spacing: 8) {
                ForEach(DetailControl.controls(for: download)) { control in
                    IconButton(
                        systemName: control.systemName,
                        help: control.help,
                        role: control.role
                    ) {
                        onPerformCommand(control.command, download)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var processingTitle: String {
        if download.isMetadataPlaceholder {
            return "Fetching metadata"
        }

        return "Pausing"
    }
}

private struct DetailControl: Identifiable {
    let id: String
    let command: DownloadCommand
    let systemName: String
    let help: String
    var role: ButtonRole?

    static func controls(for download: DownloadItem) -> [DetailControl] {
        switch download.status {
        case .completed:
            download.isRestartable ? [restart, delete] : [delete]
        case .stopped, .failed:
            download.isRestartable ? [restart, delete] : [delete]
        case .active:
            [pause, delete]
        case .paused:
            download.isRestartable ? [resume, restart, delete] : [resume, delete]
        }
    }

    private static let pause = DetailControl(
        id: "pause",
        command: .pause,
        systemName: "pause.fill",
        help: "Pause selected download"
    )

    private static let resume = DetailControl(
        id: "resume",
        command: .resume,
        systemName: "play.fill",
        help: "Resume selected download"
    )

    private static let restart = DetailControl(
        id: "restart",
        command: .restart,
        systemName: "arrow.clockwise",
        help: "Restart selected download"
    )

    private static let delete = DetailControl(
        id: "delete",
        command: .remove,
        systemName: "trash",
        help: "Delete selected download",
        role: .destructive
    )
}

private struct DetailProgressCard: View {
    let download: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(DownloadFormatters.percent(download.progress))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(DownloadFormatters.speed(download.speedBytesPerSecond))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LinearProgressBar(value: download.progress, tint: download.status.tint, height: 6)

            HStack {
                DetailMetric(title: "Size", value: DownloadFormatters.bytes(download.totalBytes))
                Spacer()
                DetailMetric(title: "ETA", value: DownloadFormatters.duration(download.remainingSeconds))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
}

private struct DetailValueRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select a download")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
