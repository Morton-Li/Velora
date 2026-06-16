import SwiftUI
import AppKit
import Darwin
import UniformTypeIdentifiers

struct DownloadListView: View {
    let downloads: [DownloadItem]
    @Binding var selectedDownloadID: DownloadItem.ID?
    @Binding var searchText: String
    let onAddDownload: (String, URL, String?) async throws -> DownloadItem.ID
    let onAddMagnetDownload: (String, URL) async throws -> DownloadItem.ID
    let onAddTorrentFileDownload: (URL, URL) async throws -> DownloadItem.ID
    let onAddTorrentURLDownload: (String, URL) async throws -> DownloadItem.ID
    let onPerformCommand: (DownloadCommand, DownloadItem) -> Void
    let onSelectDownload: (DownloadItem) -> Void
    let pendingPauseDownloadIDs: Set<DownloadItem.ID>

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
                onAddMagnetDownload: onAddMagnetDownload,
                onAddTorrentFileDownload: onAddTorrentFileDownload,
                onAddTorrentURLDownload: onAddTorrentURLDownload,
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
                                isSelected: download.id == selectedDownloadID,
                                isPausePending: pendingPauseDownloadIDs.contains(download.id)
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
    let onAddDownload: (String, URL, String?) async throws -> DownloadItem.ID
    let onAddMagnetDownload: (String, URL) async throws -> DownloadItem.ID
    let onAddTorrentFileDownload: (URL, URL) async throws -> DownloadItem.ID
    let onAddTorrentURLDownload: (String, URL) async throws -> DownloadItem.ID
    let onPerformCommand: (DownloadCommand, DownloadItem) -> Void
    @State private var isAddingDownload = false
    @State private var isAddingMagnetDownload = false
    @State private var isAddingTorrentDownload = false

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

        return selectedDownload.isRestartable && [.paused, .completed, .stopped, .failed].contains(selectedDownload.status)
    }

    var body: some View {
        HStack(spacing: 10) {
            AddDownloadSplitButton(
                onAddFileDownload: {
                    isAddingDownload = true
                },
                onAddMagnetDownload: {
                    isAddingMagnetDownload = true
                },
                onAddTorrentDownload: {
                    isAddingTorrentDownload = true
                }
            )

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
        .sheet(isPresented: $isAddingMagnetDownload) {
            AddMagnetDownloadSheet(onAddMagnetDownload: onAddMagnetDownload)
        }
        .sheet(isPresented: $isAddingTorrentDownload) {
            AddBitTorrentDownloadSheet(
                onAddTorrentFileDownload: onAddTorrentFileDownload,
                onAddTorrentURLDownload: onAddTorrentURLDownload
            )
        }
    }

    private func perform(_ command: DownloadCommand) {
        guard let selectedDownload else {
            return
        }

        onPerformCommand(command, selectedDownload)
    }
}

private struct AddDownloadSplitButton: View {
    let onAddFileDownload: () -> Void
    let onAddMagnetDownload: () -> Void
    let onAddTorrentDownload: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAddFileDownload) {
                Label("Add", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a file download")

            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(width: 1, height: 16)

            Menu {
                Button(action: onAddMagnetDownload) {
                    Label("Magnet Link", systemImage: "link.circle")
                }

                Button(action: onAddTorrentDownload) {
                    Label("BitTorrent", systemImage: "doc.badge.plus")
                }
            } label: {
                Text("")
                    .frame(width: 18, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Choose another download channel")
        }
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool

    let onAddDownload: (String, URL, String?) async throws -> DownloadItem.ID

    @State private var urlString = ""
    @State private var fileName = ""
    @State private var destinationDirectoryURL = DefaultDownloadDestination.url
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isResolvingFileName = false
    @State private var isFileNameEdited = false

    private var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFileName: String {
        fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var destinationDisplayName: String {
        let displayName = FileManager.default.displayName(atPath: destinationDirectoryURL.path)
        return displayName.isEmpty ? destinationDirectoryURL.lastPathComponent : displayName
    }

    private var destinationPathDisplay: String {
        let path = destinationDirectoryURL.path(percentEncoded: false)
        let homePath = DefaultDownloadDestination.userHomeDirectoryURL.path(percentEncoded: false)

        guard path == homePath || path.hasPrefix("\(homePath)/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    private var isUsingDefaultDestination: Bool {
        destinationDirectoryURL.standardizedFileURL == DefaultDownloadDestination.url.standardizedFileURL
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

                Text("New File Download")
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
                HStack {
                    Text("File Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isResolvingFileName {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                TextField(
                    "File.zip",
                    text: Binding(
                        get: { fileName },
                        set: { newValue in
                            fileName = newValue
                            isFileNameEdited = true
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .disabled(isSubmitting)
            }

            DestinationPickerCard(
                isSubmitting: isSubmitting,
                destinationDisplayName: destinationDisplayName,
                destinationPathDisplay: destinationPathDisplay,
                isUsingDefaultDestination: isUsingDefaultDestination,
                resetDestinationDirectory: resetDestinationDirectory,
                chooseDestinationDirectory: chooseDestinationDirectory
            )

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
                .disabled(trimmedURL.isEmpty || trimmedFileName.isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            destinationDirectoryURL = DefaultDownloadDestination.url
            isURLFieldFocused = true
        }
        .task(id: trimmedURL) {
            await resolveFileName(for: trimmedURL)
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
        destinationDirectoryURL = DefaultDownloadDestination.url
    }

    private func submit() {
        guard !trimmedURL.isEmpty, !trimmedFileName.isEmpty, !isSubmitting else {
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await onAddDownload(trimmedURL, destinationDirectoryURL, trimmedFileName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }

    private func resolveFileName(for rawURL: String) async {
        let urlForResolution = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlForResolution.isEmpty else {
            isResolvingFileName = false
            isFileNameEdited = false
            fileName = ""
            return
        }

        isFileNameEdited = false
        isResolvingFileName = true

        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            isResolvingFileName = false
            return
        }

        let suggestedFileName = await DownloadFileNameResolver.suggestedFileName(from: urlForResolution)

        guard !Task.isCancelled, urlForResolution == trimmedURL else {
            return
        }

        if !isFileNameEdited {
            fileName = suggestedFileName ?? ""
        }

        isResolvingFileName = false
    }

}

private struct AddMagnetDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isMagnetFieldFocused: Bool

    let onAddMagnetDownload: (String, URL) async throws -> DownloadItem.ID

    @State private var magnetURI = ""
    @State private var destinationDirectoryURL = DefaultDownloadDestination.url
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var normalizedMagnetURI: String {
        magnetURI.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private var parsedMagnetLink: MagnetLink? {
        try? MagnetLink.parse(magnetURI)
    }

    private var shouldShowInvalidMagnetMessage: Bool {
        !normalizedMagnetURI.isEmpty && parsedMagnetLink == nil
    }

    private var destinationDisplayName: String {
        let displayName = FileManager.default.displayName(atPath: destinationDirectoryURL.path)
        return displayName.isEmpty ? destinationDirectoryURL.lastPathComponent : displayName
    }

    private var destinationPathDisplay: String {
        let path = destinationDirectoryURL.path(percentEncoded: false)
        let homePath = DefaultDownloadDestination.userHomeDirectoryURL.path(percentEncoded: false)

        guard path == homePath || path.hasPrefix("\(homePath)/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    private var isUsingDefaultDestination: Bool {
        destinationDirectoryURL.standardizedFileURL == DefaultDownloadDestination.url.standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text("New Magnet Download")
                    .font(.headline)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Magnet Link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("magnet:?xt=urn:btih:...", text: $magnetURI)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .focused($isMagnetFieldFocused)
                    .disabled(isSubmitting)
                    .onSubmit {
                        submit()
                    }
            }

            if let parsedMagnetLink {
                MagnetLinkSummaryCard(magnetLink: parsedMagnetLink)
            } else if shouldShowInvalidMagnetMessage {
                Label("Enter a valid magnet link.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }

            DestinationPickerCard(
                isSubmitting: isSubmitting,
                destinationDisplayName: destinationDisplayName,
                destinationPathDisplay: destinationPathDisplay,
                isUsingDefaultDestination: isUsingDefaultDestination,
                resetDestinationDirectory: resetDestinationDirectory,
                chooseDestinationDirectory: chooseDestinationDirectory
            )

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
                .disabled(parsedMagnetLink == nil || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            destinationDirectoryURL = DefaultDownloadDestination.url
            isMagnetFieldFocused = true
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
        destinationDirectoryURL = DefaultDownloadDestination.url
    }

    private func submit() {
        guard let parsedMagnetLink, !isSubmitting else {
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await onAddMagnetDownload(parsedMagnetLink.normalizedURI, destinationDirectoryURL)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }
}

private enum BitTorrentInputMode: String, CaseIterable, Identifiable {
    case file
    case url

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file:
            "File"
        case .url:
            "URL"
        }
    }
}

private struct AddBitTorrentDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool

    let onAddTorrentFileDownload: (URL, URL) async throws -> DownloadItem.ID
    let onAddTorrentURLDownload: (String, URL) async throws -> DownloadItem.ID

    @State private var inputMode: BitTorrentInputMode = .file
    @State private var torrentFileURL: URL?
    @State private var localCandidate: TorrentFileCandidate?
    @State private var torrentURLString = ""
    @State private var remoteCandidate: TorrentFileCandidate?
    @State private var destinationDirectoryURL = DefaultDownloadDestination.url
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isResolvingRemoteTorrent = false

    private var trimmedTorrentURL: String {
        torrentURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeCandidate: TorrentFileCandidate? {
        switch inputMode {
        case .file:
            localCandidate
        case .url:
            remoteCandidate
        }
    }

    private var canSubmit: Bool {
        guard !isSubmitting else {
            return false
        }

        switch inputMode {
        case .file:
            return torrentFileURL != nil && localCandidate?.isLikelyTorrent == true
        case .url:
            return !trimmedTorrentURL.isEmpty && remoteCandidate?.isLikelyTorrent == true && !isResolvingRemoteTorrent
        }
    }

    private var destinationDisplayName: String {
        let displayName = FileManager.default.displayName(atPath: destinationDirectoryURL.path)
        return displayName.isEmpty ? destinationDirectoryURL.lastPathComponent : displayName
    }

    private var destinationPathDisplay: String {
        let path = destinationDirectoryURL.path(percentEncoded: false)
        let homePath = DefaultDownloadDestination.userHomeDirectoryURL.path(percentEncoded: false)

        guard path == homePath || path.hasPrefix("\(homePath)/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    private var isUsingDefaultDestination: Bool {
        destinationDirectoryURL.standardizedFileURL == DefaultDownloadDestination.url.standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text("New BitTorrent Download")
                    .font(.headline)

                Spacer()
            }

            Picker("Source", selection: $inputMode) {
                ForEach(BitTorrentInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isSubmitting)
            .onChange(of: inputMode) { _, newMode in
                errorMessage = nil
                if newMode == .url {
                    isURLFieldFocused = true
                }
            }

            switch inputMode {
            case .file:
                torrentFilePicker
            case .url:
                torrentURLPicker
            }

            if let activeCandidate {
                TorrentFileSummaryCard(candidate: activeCandidate)
            }

            DestinationPickerCard(
                isSubmitting: isSubmitting,
                destinationDisplayName: destinationDisplayName,
                destinationPathDisplay: destinationPathDisplay,
                isUsingDefaultDestination: isUsingDefaultDestination,
                resetDestinationDirectory: resetDestinationDirectory,
                chooseDestinationDirectory: chooseDestinationDirectory
            )

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
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            destinationDirectoryURL = DefaultDownloadDestination.url
        }
        .task(id: trimmedTorrentURL) {
            await resolveRemoteTorrent(for: trimmedTorrentURL)
        }
    }

    private var torrentFilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Torrent File")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    chooseTorrentFile()
                } label: {
                    Label(localCandidate == nil ? "Choose..." : "Change...", systemImage: "doc.badge.plus")
                }
                .disabled(isSubmitting)

                if localCandidate == nil {
                    Text("Choose a .torrent file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var torrentURLPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Torrent URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isResolvingRemoteTorrent {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("https://example.com/file.torrent", text: $torrentURLString)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .focused($isURLFieldFocused)
                .disabled(isSubmitting)
                .onSubmit {
                    submit()
                }

            if !trimmedTorrentURL.isEmpty, !isResolvingRemoteTorrent, remoteCandidate == nil {
                Label("Enter a torrent file URL.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func chooseTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose a BitTorrent file."
        panel.prompt = "Choose"

        if let torrentType = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [torrentType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            torrentFileURL = url
            localCandidate = TorrentFileResolver.localCandidate(from: url)
            errorMessage = localCandidate == nil ? "Choose a valid torrent file." : nil
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
        destinationDirectoryURL = DefaultDownloadDestination.url
    }

    private func resolveRemoteTorrent(for rawURL: String) async {
        guard inputMode == .url else {
            return
        }

        guard !rawURL.isEmpty else {
            isResolvingRemoteTorrent = false
            remoteCandidate = nil
            return
        }

        isResolvingRemoteTorrent = true
        remoteCandidate = nil

        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            isResolvingRemoteTorrent = false
            return
        }

        let candidate = await TorrentFileResolver.remoteCandidate(from: rawURL)

        guard !Task.isCancelled, rawURL == trimmedTorrentURL else {
            return
        }

        remoteCandidate = candidate
        isResolvingRemoteTorrent = false
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                switch inputMode {
                case .file:
                    guard let torrentFileURL else {
                        throw TorrentSheetError.missingTorrentFile
                    }

                    _ = try await onAddTorrentFileDownload(torrentFileURL, destinationDirectoryURL)
                case .url:
                    _ = try await onAddTorrentURLDownload(trimmedTorrentURL, destinationDirectoryURL)
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }
}

private struct TorrentFileSummaryCard: View {
    let candidate: TorrentFileCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TorrentFileSummaryRow(title: "Name", value: candidate.displayName)

            if let byteCount = candidate.byteCount {
                TorrentFileSummaryRow(title: "Size", value: DownloadFormatters.bytes(byteCount))
            }

            if let contentType = candidate.contentType {
                TorrentFileSummaryRow(title: "Type", value: contentType)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

private struct TorrentFileSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private enum TorrentSheetError: LocalizedError {
    case missingTorrentFile

    var errorDescription: String? {
        switch self {
        case .missingTorrentFile:
            "Choose a torrent file."
        }
    }
}

private struct MagnetLinkSummaryCard: View {
    let magnetLink: MagnetLink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let displayName = magnetLink.displayName {
                MagnetLinkSummaryRow(title: "Name", value: displayName)
            }

            if let infoHash = magnetLink.infoHash {
                MagnetLinkSummaryRow(title: "Hash", value: infoHash)
            }

            MagnetLinkSummaryRow(title: "Trackers", value: "\(magnetLink.trackers.count)")
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

private struct MagnetLinkSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct DestinationPickerCard: View {
    let isSubmitting: Bool
    let destinationDisplayName: String
    let destinationPathDisplay: String
    let isUsingDefaultDestination: Bool
    let resetDestinationDirectory: () -> Void
    let chooseDestinationDirectory: () -> Void

    var body: some View {
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
    }
}

private enum DefaultDownloadDestination {
    static var url: URL {
        userHomeDirectoryURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
    }

    static var userHomeDirectoryURL: URL {
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
    let isPausePending: Bool
    let action: () -> Void

    private var showsProcessingIcon: Bool {
        isPausePending || download.isMetadataPlaceholder
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StatusIcon(status: download.status, isProcessing: showsProcessingIcon)

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
                        if download.isMetadataPlaceholder {
                            InfoChip(systemName: "link.circle", value: "Magnet metadata")
                        } else {
                            InfoChip(systemName: "arrow.down", value: DownloadFormatters.speed(download.speedBytesPerSecond))
                            InfoChip(systemName: "externaldrive", value: "\(DownloadFormatters.bytes(download.downloadedBytes))/\(DownloadFormatters.bytes(download.totalBytes))")
                            InfoChip(systemName: "timer", value: DownloadFormatters.duration(download.remainingSeconds))
                        }
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
    var isProcessing = false

    var body: some View {
        Group {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .tint(status.tint)
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(status.tint)
            }
        }
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
            Text("Add an HTTP, HTTPS, FTP, or magnet link to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
