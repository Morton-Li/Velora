import Foundation
import Darwin

final class Aria2ProcessController {
    private let runtime: Aria2Runtime
    private var process: Process?

    init(runtime: Aria2Runtime) {
        self.runtime = runtime
    }

    func startIfNeeded() throws {
        if let process, process.isRunning {
            return
        }

        let process = Process()
        process.executableURL = runtime.executableURL
        process.currentDirectoryURL = runtime.workingDirectoryURL
        var arguments = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(runtime.endpointURL.port ?? 6800)",
            "--rpc-secret=\(runtime.secret)",
            "--dir=\(runtime.downloadsDirectoryURL.path)",
            "--input-file=\(runtime.sessionFileURL.path)",
            "--save-session=\(runtime.sessionFileURL.path)",
            "--save-session-interval=30",
            "--continue=true",
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--log=\(runtime.logFileURL.path)",
            "--log-level=notice"
        ]

        if let caCertificateURL = runtime.caCertificateURL {
            arguments.append("--ca-certificate=\(caCertificateURL.path)")
        }

        process.arguments = arguments

        try process.run()
        self.process = process
    }

    func ensureRunning() throws {
        guard let process else {
            throw Aria2ProcessError.notStarted
        }

        guard process.isRunning else {
            throw Aria2ProcessError.exited(status: process.terminationStatus)
        }
    }

    func stop() {
        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()

            let deadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        self.process = nil
    }

    deinit {
        stop()
    }
}

enum Aria2ProcessError: LocalizedError {
    case notStarted
    case exited(status: Int32)

    var errorDescription: String? {
        switch self {
        case .notStarted:
            "aria2c process was not started."
        case .exited(let status):
            "aria2c exited before RPC became available. Exit status: \(status)."
        }
    }
}
