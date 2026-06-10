import SwiftUI
import AppKit
import Darwin

struct DownloadListView: View {
    let downloads: [DownloadItem]
    @Binding var selectedDownloadID: DownloadItem.ID?
    @Binding var searchText: String
    let onAddDownload: (String, URL) async throws -> DownloadItem.ID
    let onPerformCommand: (DownloadCommand, DownloadItem) -> Void
    let onSelectDownload: (DownloadItem) -> Void

    private var selectedDownload: DownloadItem? {
        guard let selectedDownloadID else {
            return nil
        }

        return downloads.first { $0.id == selectedDownloadID }
    }

    var body: some View {
        VStack(spacing: 0) {
            DownloadToolbar(
                searchText: $searchText,
                selectedDownload: selectedDownload,
                onAddDownload: onAddDownload,
                onPerformCommand: onPerformCommand
            )

            Divider()
                .opacity(0.45)

            if downloads.isEmpty {
                EmptyDownloadsView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(downloads) { download in
                            DownloadRowView(
                                download: download,
                                isSelected: download.id == selectedDownloadID
                            ) {
                                onSelectDownload(download)
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 0)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.28))
    }
}

private struct DownloadToolbar: View {
    @Binding var searchText: String
    let selectedDownload: DownloadItem?
    let onAddDownload: (String, URL) async throws -> DownloadItem.ID
    let onPerformCommand: (DownloadCommand, DownloadItem) -> Void
    @State private var isAddingDownload = false

    private var canPauseSelectedDownload: Bool {
        selectedDownload?.status == .active
    }

    private var canResumeSelectedDownload: Bool {
        selectedDownload?.status == .paused
    }

    private var canRestartSelectedDownload: Bool {
        guard let selectedDownload else {
            return false
        }

        return [.paused, .completed, .stopped, .failed].contains(selectedDownload.status)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isAddingDownload = true
            } label: {
                Label("Add", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            IconButton(
                systemName: "pause.fill",
                help: "Pause selected download",
                isDisabled: !canPauseSelectedDownload
            ) {
                perform(.pause)
            }
            IconButton(
                systemName: "play.fill",
                help: "Resume selected download",
                isDisabled: !canResumeSelectedDownload
            ) {
                perform(.resume)
            }
            IconButton(
                systemName: "arrow.clockwise",
                help: "Restart selected download",
                isDisabled: !canRestartSelectedDownload
            ) {
                perform(.restart)
            }
            IconButton(
                systemName: "trash",
                help: "Remove selected download",
                role: .destructive,
                isDisabled: selectedDownload == nil
            ) {
                perform(.remove)
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search downloads", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 220, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .sheet(isPresented: $isAddingDownload) {
            AddDownloadSheet(onAddDownload: onAddDownload)
        }
    }

    private func perform(_ command: DownloadCommand) {
        guard let selectedDownload else {
            return
        }

        onPerformCommand(command, selectedDownload)
    }
}

private struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool

    let onAddDownload: (String, URL) async throws -> DownloadItem.ID

    @State private var urlString = ""
    @State private var destinationDirectoryURL = Self.defaultDestinationDirectoryURL
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var destinationDisplayName: String {
        let displayName = FileManager.default.displayName(atPath: destinationDirectoryURL.path)
        return displayName.isEmpty ? destinationDirectoryURL.lastPathComponent : displayName
    }

    private var destinationPathDisplay: String {
        let path = destinationDirectoryURL.path(percentEncoded: false)
        let homePath = Self.userHomeDirectoryURL.path(percentEncoded: false)

        guard path == homePath || path.hasPrefix("\(homePath)/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    private var isUsingDefaultDestination: Bool {
        destinationDirectoryURL.standardizedFileURL == Self.defaultDestinationDirectoryURL.standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text("New Download")
                    .font(.headline)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://example.com/file.zip", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .focused($isURLFieldFocused)
                    .disabled(isSubmitting)
                    .onSubmit {
                        submit()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(destinationDisplayName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            Text(destinationPathDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Button {
                            resetDestinationDirectory()
                        } label: {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }
                        .disabled(isSubmitting || isUsingDefaultDestination)

                        Spacer()

                        Button {
                            chooseDestinationDirectory()
                        } label: {
                            Label("Choose...", systemImage: "folder.badge.plus")
                        }
                        .disabled(isSubmitting)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSubmitting)

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Add", systemImage: "plus")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedURL.isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            destinationDirectoryURL = Self.defaultDestinationDirectoryURL
            isURLFieldFocused = true
        }
    }

    private func chooseDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationDirectoryURL
        panel.message = "Choose a folder for this download."
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            destinationDirectoryURL = url
        }
    }

    private func resetDestinationDirectory() {
        destinationDirectoryURL = Self.defaultDestinationDirectoryURL
    }

    private func submit() {
        guard !trimmedURL.isEmpty, !isSubmitting else {
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await onAddDownload(trimmedURL, destinationDirectoryURL)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }

    private static var defaultDestinationDirectoryURL: URL {
        userHomeDirectoryURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
    }

    private static var userHomeDirectoryURL: URL {
        guard let userRecord = getpwuid(getuid()), let homeDirectory = userRecord.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }

        return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
            .standardizedFileURL
    }
}

private struct DownloadRowView: View {
    let download: DownloadItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StatusIcon(status: download.status)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(download.fileName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(DownloadFormatters.percent(download.progress))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    LinearProgressBar(value: download.progress, tint: download.status.tint, height: 4)

                    HStack(spacing: 12) {
                        InfoChip(systemName: "arrow.down", value: DownloadFormatters.speed(download.speedBytesPerSecond))
                        InfoChip(systemName: "externaldrive", value: "\(DownloadFormatters.bytes(download.downloadedBytes))/\(DownloadFormatters.bytes(download.totalBytes))")
                        InfoChip(systemName: "timer", value: DownloadFormatters.duration(download.remainingSeconds))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.selectedFill : AppTheme.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : AppTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StatusIcon: View {
    let status: DownloadStatus

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(status.tint)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(status.tint.opacity(0.12))
            )
    }
}

private struct InfoChip: View {
    let systemName: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.caption2.weight(.medium))
            Text(value)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct EmptyDownloadsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No downloads")
                .font(.headline)
            Text("Add an HTTP or HTTPS link to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
