import SwiftUI
import AppKit

struct SidebarView: View {
    // 绑定父视图中的筛选状态
    @Binding var selectedFilter: DownloadFilter
    let filterCounts: [DownloadFilter: Int]
    let endpointStatus: EndpointStatus
    let availableUpdate: AvailableAppUpdate?

    var body: some View {
        SidebarContent(
            selectedFilter: $selectedFilter,
            filterCounts: filterCounts,
            endpointStatus: endpointStatus,
            availableUpdate: availableUpdate
        )
        .padding(.horizontal, 18)  // 水平内边距
        .padding(.vertical, 16)  // 垂直内边距
        .frame(width: 252)  // 侧边栏宽度
        .background(.thinMaterial)
    }
}

private struct SidebarContent: View {
    @Namespace private var selectionNamespace

    @Binding var selectedFilter: DownloadFilter
    let filterCounts: [DownloadFilter: Int]
    let endpointStatus: EndpointStatus
    let availableUpdate: AvailableAppUpdate?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {  // 垂直布局，内容左对齐，元素间距为 18
            // 侧边栏顶部标题区域
            SidebarHeader(availableUpdate: availableUpdate)

            VStack(spacing: 4) {  // 筛选列表容器，每一行之间间距为 4。
                ForEach(DownloadFilter.allCases) { filter in
                    SidebarRow(
                        filter: filter,
                        count: filterCounts[filter, default: 0],
                        isSelected: filter == selectedFilter,
                        selectionNamespace: selectionNamespace
                    ) {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 16)

            // 底部运行状态卡片，横向填满
            EndpointStatusView(status: endpointStatus)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)  // 让整个侧边栏内容横向填满
    }
}

// 侧边栏顶部标题组件
private struct SidebarHeader: View {
    let availableUpdate: AvailableAppUpdate?

    var body: some View {
        HStack(spacing: 10) {
            AppIconImage()
            .frame(width: 48, height: 48)
            .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text("Velora")
                    .font(.system(size: 16, weight: .semibold))
            }
            .lineLimit(1)  // 限制标题最多一行

            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            if let availableUpdate {
                NewVersionBadge(update: availableUpdate)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)  // 标题区域横向填满，最小高度 52
        .padding(.top, 4)  // 顶部留 4 点间距
        .animation(.smooth(duration: 0.2), value: availableUpdate)
    }
}

private struct NewVersionBadge: View {
    let update: AvailableAppUpdate
    @State private var isHovering = false

    var body: some View {
        Link(destination: update.releaseURL) {
            HStack(spacing: 4) {
                Text("New")
                    .font(.system(size: 10, weight: .bold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.2 : 0.13))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(isHovering ? 0.42 : 0.22), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(isHovering ? 0.18 : 0), radius: 5, x: 0, y: 2)
            .offset(y: isHovering ? -1 : 0)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            self.isHovering = isHovering
        }
        .animation(.smooth(duration: 0.16), value: isHovering)
        .help("Velora \(update.latestVersion) is available.")
        .accessibilityLabel("Velora \(update.latestVersion) is available")
    }
}

private struct AppIconImage: View {
    var body: some View {
        if let image = NSImage(named: "AppIcon") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// 定义单个筛选行
private struct SidebarRow: View {
    let filter: DownloadFilter
    let count: Int
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                    .scaleEffect(isSelected ? 1.06 : 1)

                Text(filter.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
            .background(alignment: .center) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.selectedFill)
                        .matchedGeometryEffect(id: "selected-filter-background", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isSelected)
    }
}

// 底部运行状态卡片
private struct EndpointStatusView: View {
    let status: EndpointStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Status")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(statusSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 86, alignment: .trailing)
            }
            .frame(height: 16)

            HStack(spacing: 14) {
                MetricLabel(title: "Down", value: DownloadFormatters.speed(status.downloadSpeedBytesPerSecond), width: 88)
                MetricLabel(title: "Conn", value: "\(status.connections)", width: 46)
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
        .help(statusTooltip)
    }

    private var statusTooltip: String {
        if let message = status.message, !message.isEmpty {
            return message
        }

        switch status.reachability {
        case .notChecked:
            return "Waiting to start the download service."
        case .checking:
            return "Checking the download service."
        case .reachable:
            if status.downloadSpeedBytesPerSecond > 0 || status.connections > 0 {
                return "Download service is running. Transfers are active."
            }

            return "Download service is running. No active transfers."
        case .unreachable:
            return "Download service is unavailable."
        }
    }

    private var statusSummary: String {
        switch status.reachability {
        case .notChecked:
            "Pending"
        case .checking:
            "Checking"
        case .reachable:
            "Running"
        case .unreachable:
            "Offline"
        }
    }

    private var statusColor: Color {
        switch status.reachability {
        case .notChecked:
            .secondary
        case .checking:
            .orange
        case .reachable:
            .green
        case .unreachable:
            .red
        }
    }

    private struct MetricLabel: View {
        let title: String
        let value: String
        let width: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}
