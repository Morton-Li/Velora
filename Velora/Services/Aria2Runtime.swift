import Foundation

struct Aria2Runtime {
    let executableURL: URL
    let endpointURL: URL
    let secret: String
    let workingDirectoryURL: URL
    let downloadsDirectoryURL: URL
    let sessionFileURL: URL
    let dhtFileURL: URL
    let logFileURL: URL
    let caCertificateURL: URL?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        port: Int = 6800,
        secret: String = UUID().uuidString
    ) throws {
        guard let executableURL = bundle.url(forResource: "aria2c", withExtension: nil, subdirectory: "bin") else {
            throw Aria2RuntimeError.missingExecutable
        }

        let supportRootURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Velora", isDirectory: true)

        let workingDirectoryURL = supportRootURL.appendingPathComponent("aria2", isDirectory: true)
        let downloadsDirectoryURL = try fileManager.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let sessionFileURL = workingDirectoryURL.appendingPathComponent("aria2.session")
        let dhtFileURL = workingDirectoryURL.appendingPathComponent("dht.dat")
        let logFileURL = workingDirectoryURL.appendingPathComponent("aria2.log")

        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadsDirectoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: sessionFileURL.path) {
            fileManager.createFile(atPath: sessionFileURL.path, contents: nil)
        }

        self.executableURL = executableURL
        self.endpointURL = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        self.secret = secret
        self.workingDirectoryURL = workingDirectoryURL
        self.downloadsDirectoryURL = downloadsDirectoryURL
        self.sessionFileURL = sessionFileURL
        self.dhtFileURL = dhtFileURL
        self.logFileURL = logFileURL
        self.caCertificateURL = Self.caCertificateURL(fileManager: fileManager)
    }

    private static func caCertificateURL(fileManager: FileManager) -> URL? {
        let candidatePaths = [
            "/etc/ssl/cert.pem",
            "/private/etc/ssl/cert.pem"
        ]

        return candidatePaths
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}

enum Aria2RuntimeError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "Bundled aria2c executable was not found."
        }
    }
}
