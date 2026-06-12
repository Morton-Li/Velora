//
//  ContentView.swift
//  Velora
//
//  Created by Morton Li on 2026/5/16.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var downloadStore: DownloadStore

    @State private var isSidebarVisible = true  // 侧边栏是否显示
    @State private var isDetailVisible = false  // 详情面板是否显示
    @State private var selectedFilter: DownloadFilter = .all  // 当前选中的下载筛选条件
    @State private var selectedDownloadID: DownloadItem.ID?  // 当前选中的下载项 ID
    @State private var searchText = ""  // 搜索框文本
    @State private var pendingRemoval: DownloadItem?
    @State private var shouldDeleteCompletedLocalFiles = false

    // 详情面板的最小宽度和最大宽度（避免过度展开或挤压）
    private let detailMinWidth: CGFloat = 300
    private let detailMaxWidth: CGFloat = 360

    @MainActor
    init(downloadStore: DownloadStore? = nil) {
        _downloadStore = StateObject(wrappedValue: downloadStore ?? DownloadStore())
    }

    // 计算属性：根据筛选条件和搜索文本返回要显示的下载列表
    private var filteredDownloads: [DownloadItem] {
        downloadStore.items(matching: selectedFilter, searchText: searchText)
    }
    
    // 根据当前选中的 ID，从过滤后的列表中找到对应下载项，如果没有找到，返回 nil。
    private var selectedDownload: DownloadItem? {
        downloadStore.item(id: selectedDownloadID, in: filteredDownloads)
    }

    private var filterCounts: [DownloadFilter: Int] {
        Dictionary(uniqueKeysWithValues: DownloadFilter.allCases.map { filter in
            (filter, filter.count(in: downloadStore.items))
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            // 是否渲染侧边栏
            if isSidebarVisible {
                SidebarView(
                    selectedFilter: $selectedFilter,
                    filterCounts: filterCounts,
                    endpointStatus: downloadStore.endpointStatus
                )
                .transition(.move(edge: .leading))  // 侧边栏出现或消失时，从左侧滑入或滑出
            }

            GeometryReader { proxy in
                // 详情面板宽度：取窗口宽度的 35%，但限制在 300 到 360 之间
                let detailWidth = min(max(proxy.size.width * 0.35, detailMinWidth), detailMaxWidth)
                HStack(spacing: 0) {
                    DownloadListView(
                        downloads: filteredDownloads,
                        selectedDownloadID: $selectedDownloadID,
                        searchText: $searchText,
                        onAddDownload: addDownload,
                        onPerformCommand: performDownloadCommand,
                        onSelectDownload: toggleDetail
                    )
                    .frame(width: isDetailVisible ? max(proxy.size.width - detailWidth, .zero) : proxy.size.width)

                    // 是否渲染详情面板
                    if isDetailVisible {
                        DownloadDetailView(
                            download: selectedDownload,
                            onPerformCommand: performDownloadCommand,
                            onClose: closeDetail
                        )
                        .frame(width: detailWidth)
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .navigationTitle("Velora")
        .frame(minWidth: 1080, minHeight: 680)  // 主界面的最小窗口尺寸
        .background(AppTheme.windowBackground)
        .animation(.smooth(duration: 0.25), value: isSidebarVisible)
        .animation(.smooth(duration: 0.35), value: isDetailVisible)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    isSidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
        }
        .onAppear(perform: normalizeSelection)
        .task {
            await downloadStore.startSyncing()
        }
        .onChange(of: downloadStore.items) { _, _ in
            normalizeSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            normalizeSelection()
        }
        .onChange(of: searchText) { _, _ in
            normalizeSelection()
        }
        .sheet(item: $pendingRemoval) { download in
            DeleteDownloadConfirmationSheet(
                download: download,
                shouldDeleteCompletedLocalFiles: $shouldDeleteCompletedLocalFiles,
                onCancel: cancelRemoveDownload,
                onConfirm: {
                    confirmRemoveDownload(download)
                }
            )
        }
    }

    // 校验选中状态的私有函数
    private func normalizeSelection() {
        // 如果当前选中的下载项仍然存在于过滤结果中，就什么也不做。
        if let selectedDownloadID, filteredDownloads.contains(where: { $0.id == selectedDownloadID }) {
            return
        }
        // 否则关闭详情面板，并清空选中项。
        closeDetail()
    }

    // 点击下载项时的处理函数
    private func toggleDetail(for download: DownloadItem) {
        // 如果点击的是当前已选中的下载项，并且详情面板已打开，则再次点击会关闭详情
        if selectedDownloadID == download.id, isDetailVisible {
            closeDetail()
            return
        }

        // 否则选中该下载项，并打开详情面板。
        selectedDownloadID = download.id
        isDetailVisible = true
    }

    private func addDownload(from urlString: String, to destinationDirectory: URL, fileName: String?) async throws -> DownloadItem.ID {
        let id = try await downloadStore.addDownload(from: urlString, destinationDirectory: destinationDirectory, fileName: fileName)
        selectedFilter = .all
        searchText = ""
        selectedDownloadID = id
        isDetailVisible = true
        return id
    }

    private func performDownloadCommand(_ command: DownloadCommand, on download: DownloadItem) {
        Task {
            do {
                switch command {
                case .pause:
                    try await downloadStore.pauseDownload(download)
                case .resume:
                    try await downloadStore.resumeDownload(download)
                case .remove:
                    pendingRemoval = download
                    shouldDeleteCompletedLocalFiles = false
                case .restart:
                    let id = try await downloadStore.restartDownload(download)
                    selectedFilter = .all
                    searchText = ""
                    selectedDownloadID = id
                    isDetailVisible = true
                }
            } catch {
                // The store already exposes operation failures through endpointStatus.
            }
        }
    }

    private func cancelRemoveDownload() {
        pendingRemoval = nil
        shouldDeleteCompletedLocalFiles = false
    }

    private func confirmRemoveDownload(_ download: DownloadItem) {
        let shouldDeleteLocalFiles = download.status == .completed ? shouldDeleteCompletedLocalFiles : true

        Task {
            do {
                try await downloadStore.removeDownload(download, deletingLocalFiles: shouldDeleteLocalFiles)
                closeDetail()
            } catch {
                // The store already exposes operation failures through endpointStatus.
            }

            pendingRemoval = nil
            shouldDeleteCompletedLocalFiles = false
        }
    }

    // 关闭详情面板，并清空选中项
    private func closeDetail() {
        selectedDownloadID = nil
        isDetailVisible = false
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif

private struct DeleteDownloadConfirmationSheet: View {
    let download: DownloadItem
    @Binding var shouldDeleteCompletedLocalFiles: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var isCompleted: Bool {
        download.status == .completed
    }

    private var hasLocalFiles: Bool {
        !download.localFilePaths.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove Download")
                        .font(.headline)
                    Text(download.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if isCompleted {
                Toggle("Also delete local file", isOn: $shouldDeleteCompletedLocalFiles)
                    .disabled(!hasLocalFiles)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Remove", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var message: String {
        if isCompleted {
            return "This will remove the task from Velora. The completed local file will be kept unless you choose to delete it."
        }

        return "This download is not complete. Removing it will also delete the local partial file."
    }
}
