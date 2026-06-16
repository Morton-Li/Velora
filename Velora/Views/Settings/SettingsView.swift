import SwiftUI

struct SettingsView: View {
    let onRestartRuntime: () async throws -> Void

    @StateObject private var configurationStore = AppConfigurationStore()
    @State private var selectedSection: SettingsSection = .magnetLinks
    @State private var presentationToken = UUID()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedSection) {
                Label(SettingsSection.magnetLinks.title, systemImage: SettingsSection.magnetLinks.symbolName)
                    .tag(SettingsSection.magnetLinks)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            MagnetLinkSettingsPane(configurationStore: configurationStore)
                .environment(\.restartDownloadRuntime, onRestartRuntime)
                .id(presentationToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 380)
        .onAppear {
            configurationStore.reload()
            presentationToken = UUID()
        }
        .onDisappear {
            configurationStore.discardChanges()
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case magnetLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magnetLinks:
            "Magnet Links"
        }
    }

    var symbolName: String {
        switch self {
        case .magnetLinks:
            "link.circle"
        }
    }
}

private struct MagnetLinkSettingsPane: View {
    @Environment(\.restartDownloadRuntime) private var restartDownloadRuntime
    @ObservedObject var configurationStore: AppConfigurationStore
    @State private var isApplying = false
    @State private var applyMessage: SettingsMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Magnet Links")
                    .font(.title2.weight(.semibold))

                Spacer()
            }

            DHTEntryPointBlock(configurationStore: configurationStore)

            Spacer()

            Divider()

            HStack(spacing: 10) {
                if let applyMessage {
                    Label(applyMessage.text, systemImage: applyMessage.symbolName)
                        .font(.caption)
                        .foregroundStyle(applyMessage.tint)
                }

                Spacer()

                Button("Apply") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!configurationStore.hasPendingChanges || !configurationStore.dhtEntryPoint.isValid || isApplying)
            }
        }
        .padding(22)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func apply() {
        guard !isApplying else {
            return
        }

        isApplying = true
        applyMessage = nil

        Task {
            let changes = configurationStore.apply()

            do {
                if changes.dhtEntryPointChanged {
                    try await restartDownloadRuntime()
                }

                applyMessage = .success(changes.dhtEntryPointChanged ? "Settings applied. Download engine restarted." : "Settings applied.")
            } catch {
                applyMessage = .failure(error.localizedDescription)
            }

            isApplying = false
        }
    }
}

private struct DHTEntryPointBlock: View {
    @ObservedObject var configurationStore: AppConfigurationStore
    @State private var isTesting = false
    @State private var testMessage: SettingsMessage?

    private var isEntryPointValid: Bool {
        configurationStore.dhtEntryPoint.isValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DHT Entry Point", systemImage: "network")
                    .font(.headline)

                Spacer()

                Button {
                    testEntryPoint()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                .controlSize(.small)
                .disabled(!isEntryPointValid || isTesting)
                .help("Test the current DHT entry point")

                Button {
                    configurationStore.resetDHTEntryPoint()
                } label: {
                    Label("Use Default", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .help("Restore the default DHT entry point")
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Host")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(AppConfigurationPersistence.defaultDHTEntryPoint.host, text: $configurationStore.dhtEntryPoint.host)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Port")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("6881", value: $configurationStore.dhtEntryPoint.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: isEntryPointValid ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isEntryPointValid ? Color.secondary : Color.orange)

                    Text(isEntryPointValid ? "\(configurationStore.dhtEntryPoint.endpoint) will be saved when you click Apply." : "Enter a host and a port from 1 to 65535.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let testMessage {
                    Label(testMessage.text, systemImage: testMessage.symbolName)
                        .font(.caption)
                        .foregroundStyle(testMessage.tint)
                        .labelStyle(.titleAndIcon)
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

    private func testEntryPoint() {
        guard !isTesting else {
            return
        }

        isTesting = true
        testMessage = nil

        Task {
            do {
                let result = try await DHTEntryPointTester.test(configurationStore.dhtEntryPoint)
                let milliseconds = Int((result.responseTime * 1_000).rounded())
                testMessage = .success("DHT response received from \(result.endpoint) in \(milliseconds) ms.")
            } catch {
                testMessage = .failure(error.localizedDescription)
            }

            isTesting = false
        }
    }
}

private struct SettingsMessage {
    let text: String
    let symbolName: String
    let tint: Color

    static func success(_ text: String) -> SettingsMessage {
        SettingsMessage(text: text, symbolName: "checkmark.circle.fill", tint: .green)
    }

    static func failure(_ text: String) -> SettingsMessage {
        SettingsMessage(text: text, symbolName: "exclamationmark.triangle.fill", tint: .red)
    }
}

private struct RestartDownloadRuntimeKey: EnvironmentKey {
    static let defaultValue: () async throws -> Void = {}
}

private extension EnvironmentValues {
    var restartDownloadRuntime: () async throws -> Void {
        get { self[RestartDownloadRuntimeKey.self] }
        set { self[RestartDownloadRuntimeKey.self] = newValue }
    }
}

#if DEBUG
#Preview {
    SettingsView {}
}
#endif
