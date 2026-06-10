import SwiftUI
import AppKit

struct SidebarView: View {
    // 绑定父视图中的筛选状态
    @Binding var selectedFilter: DownloadFilter
    let filterCounts: [DownloadFilter: Int]
    let endpointStatus: EndpointStatus

    var body: some View {
        SidebarContent(
            selectedFilter: $selectedFilter,
            filterCounts: filterCounts,
            endpointStatus: endpointStatus
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {  // 垂直布局，内容左对齐，元素间距为 18
            // 侧边栏顶部标题区域
            SidebarHeader()

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

            // aria2 RPC 状态卡片，横向填满
            EndpointStatusView(status: endpointStatus)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)  // 让整个侧边栏内容横向填满
    }
}

// 侧边栏顶部标题组件
private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            AppIconImage()
            .frame(width: 32, height: 32)
            .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text("Velora")
                    .font(.system(size: 16, weight: .semibold))
            }
            .lineLimit(1)  // 限制标题最多一行

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)  // 标题区域横向填满，最小高度 36
        .padding(.top, 4)  // 顶部留 4 点间距
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

// 底部端点状态卡片
private struct EndpointStatusView: View {
    let status: EndpointStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(status.endpointName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(status.endpointDescription)
                    .font(.caption2.monospacedDigit())
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
            return "Waiting to start aria2 RPC."
        case .checking:
            return "Starting aria2 and checking RPC."
        case .reachable:
            if status.downloadSpeedBytesPerSecond > 0 || status.connections > 0 {
                return "RPC is reachable. Transfers are active."
            }

            return "RPC is reachable. No active transfers."
        case .unreachable:
            return "Unable to reach aria2 RPC."
        }
    }

    private var statusColor: Color {
        switch status.reachability {
        case .notChecked, .checking:
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
