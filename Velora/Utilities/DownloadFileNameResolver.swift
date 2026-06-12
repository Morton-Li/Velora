import Foundation

struct DownloadFileNameResolver {
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func suggestedFileName(from rawURL: String) async -> String? {
        guard let url = downloadURL(from: rawURL) else {
            return nil
        }

        if let remoteFileName = await remoteFileName(from: url) {
            return remoteFileName
        }

        return localFileName(from: url)
    }

    static func sanitizedFileName(_ rawFileName: String) -> String? {
        let trimmedFileName = rawFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFileName.isEmpty else {
            return nil
        }

        let lastComponent = trimmedFileName
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? trimmedFileName

        let invalidCharacters = CharacterSet(charactersIn: "/:\0").union(.controlCharacters)
        let sanitized = lastComponent
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return nil
        }

        return sanitized
    }

    private static func remoteFileName(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<400).contains(httpResponse.statusCode) else {
                return nil
            }

            if let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
               let fileName = fileName(fromContentDisposition: contentDisposition) {
                return fileName
            }

            if let responseURL = httpResponse.url, responseURL != url {
                return localFileName(from: responseURL)
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func localFileName(from url: URL) -> String? {
        let pathComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return sanitizedFileName(pathComponent)
    }

    private static func downloadURL(from rawURL: String) -> URL? {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              url.host != nil,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        return url
    }

    private static func fileName(fromContentDisposition header: String) -> String? {
        let parameters = contentDispositionParameters(from: header)

        if let encodedFileName = parameters["filename*"],
           let decodedFileName = decodedExtendedFileName(encodedFileName),
           let sanitizedFileName = sanitizedFileName(decodedFileName) {
            return sanitizedFileName
        }

        if let fileName = parameters["filename"],
           let sanitizedFileName = sanitizedFileName(fileName) {
            return sanitizedFileName
        }

        return nil
    }

    private static func contentDispositionParameters(from header: String) -> [String: String] {
        splitHeaderParameters(header)
            .dropFirst()
            .reduce(into: [:]) { parameters, part in
                guard let equalsIndex = part.firstIndex(of: "=") else {
                    return
                }

                let name = part[..<equalsIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = part[part.index(after: equalsIndex)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                parameters[name] = unquotedHeaderValue(String(value))
            }
    }

    private static func splitHeaderParameters(_ header: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isInsideQuotes = false
        var isEscaped = false

        for character in header {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\", isInsideQuotes {
                current.append(character)
                isEscaped = true
                continue
            }

            if character == "\"" {
                isInsideQuotes.toggle()
                current.append(character)
                continue
            }

            if character == ";", !isInsideQuotes {
                parts.append(current)
                current.removeAll(keepingCapacity: true)
                continue
            }

            current.append(character)
        }

        parts.append(current)
        return parts
    }

    private static func unquotedHeaderValue(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return value
        }

        var unquoted = ""
        var isEscaped = false

        for character in value.dropFirst().dropLast() {
            if isEscaped {
                unquoted.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                unquoted.append(character)
            }
        }

        return unquoted
    }

    private static func decodedExtendedFileName(_ value: String) -> String? {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return value.removingPercentEncoding
        }

        let charset = parts[0].lowercased()
        let encodedValue = String(parts[2])

        guard charset == "utf-8" || charset == "us-ascii" else {
            return encodedValue.removingPercentEncoding
        }

        return encodedValue.removingPercentEncoding
    }
}
