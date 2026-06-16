import Foundation
import Combine

struct DHTEntryPoint: Codable, Hashable, Sendable {
    var host: String
    var port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    nonisolated var endpoint: String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines)):\(port)"
    }

    nonisolated var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }
}

struct AppConfigurationChangeSet: Equatable, Sendable {
    let dhtEntryPointChanged: Bool
}

enum AppConfigurationPersistence {
    private static let dhtEntryPointKey = "magnet.dhtEntryPoint"
    private static let legacyDHTBootstrapNodesKey = "magnet.dhtBootstrapNodes"

    static let defaultDHTEntryPoint = DHTEntryPoint(host: "router.bittorrent.com", port: 6881)

    static func dhtEntryPoint() -> DHTEntryPoint {
        if let data = UserDefaults.standard.data(forKey: dhtEntryPointKey),
           let entryPoint = try? JSONDecoder().decode(DHTEntryPoint.self, from: data) {
            return entryPoint
        }

        if let legacyEntryPoint = legacyDHTEntryPoint() {
            saveDHTEntryPoint(legacyEntryPoint)
            return legacyEntryPoint
        }

        return defaultDHTEntryPoint
    }

    static func saveDHTEntryPoint(_ entryPoint: DHTEntryPoint) {
        guard let data = try? JSONEncoder().encode(entryPoint) else {
            return
        }

        UserDefaults.standard.set(data, forKey: dhtEntryPointKey)
    }

    private static func legacyDHTEntryPoint() -> DHTEntryPoint? {
        guard let data = UserDefaults.standard.data(forKey: legacyDHTBootstrapNodesKey),
              let nodes = try? JSONDecoder().decode([LegacyDHTBootstrapNode].self, from: data) else {
            return nil
        }

        return nodes.first { $0.isEnabled && $0.isValid }.map {
            DHTEntryPoint(host: $0.host, port: $0.port)
        }
    }
}

private struct LegacyDHTBootstrapNode: Codable {
    var host: String
    var port: Int
    var isEnabled: Bool

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }
}

@MainActor
final class AppConfigurationStore: ObservableObject {
    @Published var dhtEntryPoint: DHTEntryPoint
    @Published private(set) var savedDHTEntryPoint: DHTEntryPoint

    init() {
        let dhtEntryPoint = AppConfigurationPersistence.dhtEntryPoint()
        self.dhtEntryPoint = dhtEntryPoint
        self.savedDHTEntryPoint = dhtEntryPoint
    }

    var hasPendingChanges: Bool {
        dhtEntryPoint != savedDHTEntryPoint
    }

    func resetDHTEntryPoint() {
        dhtEntryPoint = AppConfigurationPersistence.defaultDHTEntryPoint
    }

    func reload() {
        let dhtEntryPoint = AppConfigurationPersistence.dhtEntryPoint()
        self.dhtEntryPoint = dhtEntryPoint
        savedDHTEntryPoint = dhtEntryPoint
    }

    func discardChanges() {
        dhtEntryPoint = savedDHTEntryPoint
    }

    func apply() -> AppConfigurationChangeSet {
        let dhtEntryPointChanged = dhtEntryPoint != savedDHTEntryPoint

        if dhtEntryPointChanged {
            AppConfigurationPersistence.saveDHTEntryPoint(dhtEntryPoint)
            savedDHTEntryPoint = dhtEntryPoint
        }

        return AppConfigurationChangeSet(dhtEntryPointChanged: dhtEntryPointChanged)
    }
}
