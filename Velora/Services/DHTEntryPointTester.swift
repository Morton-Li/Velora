import Foundation

struct DHTEntryPointTestResult: Equatable, Sendable {
    let endpoint: String
    let responseTime: TimeInterval
}

enum DHTEntryPointTester {
    nonisolated static func test(_ entryPoint: DHTEntryPoint) async throws -> DHTEntryPointTestResult {
        try await Task.detached(priority: .userInitiated) {
            try performTest(entryPoint)
        }.value
    }

    private nonisolated static func performTest(_ entryPoint: DHTEntryPoint) throws -> DHTEntryPointTestResult {
        let host = entryPoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(entryPoint.port) else {
            throw DHTEntryPointTestError.invalidEntryPoint
        }

        guard let executableURL = Bundle.main.url(forResource: "aria2c", withExtension: nil, subdirectory: "bin") else {
            throw DHTEntryPointTestError.missingExecutable
        }

        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Velora-DHT-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = workspaceURL
        process.arguments = [
            "--enable-dht=true",
            "--enable-peer-exchange=false",
            "--dht-entry-point=\(entryPoint.endpoint)",
            "--dht-file-path=\(workspaceURL.appendingPathComponent("dht.dat").path)",
            "--bt-metadata-only=true",
            "--summary-interval=0",
            "--console-log-level=info",
            "--log-level=info",
            "--dir=\(workspaceURL.path)",
            randomMagnetURI()
        ]

        let outputURL = workspaceURL.appendingPathComponent("dht-test.log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        process.standardOutput = outputHandle
        process.standardError = outputHandle

        let startedAt = Date()
        try process.run()

        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()

        try? outputHandle.synchronize()
        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard output.contains("Message received: dht response ping") ||
                output.contains("Message received: dht response get_peers") else {
            throw DHTEntryPointTestError.noDHTResponse
        }

        return DHTEntryPointTestResult(endpoint: entryPoint.endpoint, responseTime: Date().timeIntervalSince(startedAt))
    }

    private nonisolated static func randomMagnetURI() -> String {
        let bytes = (0..<20).map { _ in String(format: "%02x", UInt8.random(in: UInt8.min...UInt8.max)) }.joined()
        return "magnet:?xt=urn:btih:\(bytes)"
    }
}

private enum DHTEntryPointTestError: LocalizedError {
    case invalidEntryPoint
    case missingExecutable
    case noDHTResponse

    var errorDescription: String? {
        switch self {
        case .invalidEntryPoint:
            "Enter a host and a port from 1 to 65535."
        case .missingExecutable:
            "Bundled download engine was not found."
        case .noDHTResponse:
            "The DHT entry point did not respond to the download engine."
        }
    }
}
