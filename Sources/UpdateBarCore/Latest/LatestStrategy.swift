import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol HTTPClient {
    func get(
        url: URL,
        headers: [String: String],
        requireHTTPSFinalURL: Bool
    ) throws -> Data
    func post(url: URL, headers: [String: String], body: Data) throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(
        url: URL,
        headers: [String: String],
        requireHTTPSFinalURL: Bool = false
    ) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try send(
            request: request,
            headers: headers,
            requireHTTPSFinalURL: requireHTTPSFinalURL
        )
    }

    public func post(url: URL, headers: [String: String], body: Data) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        return try send(request: request, headers: headers, requireHTTPSFinalURL: false)
    }

    private func send(
        request initialRequest: URLRequest,
        headers: [String: String],
        requireHTTPSFinalURL: Bool
    ) throws -> Data {
        var request = initialRequest
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.result = .failure(error)
            } else if requireHTTPSFinalURL,
                let finalURL = response?.url,
                finalURL.scheme?.lowercased() != "https"
            {
                let message = "\(finalURL.absoluteString): https redirect not allowed"
                box.result = .failure(LatestError.invalidSource(message))
            } else {
                box.result = .success(data ?? Data())
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        guard let result = box.result else {
            throw LatestError.parseFailed("http response missing")
        }
        return try result.get()
    }
}

private final class ResponseBox: @unchecked Sendable {
    var result: Result<Data, Error>?
}

public struct LatestContext {
    public var httpClient: HTTPClient
    public var commandRunner: CommandRunning
    public var githubToken: String?
    public var requireHTTPSSource: Bool

    public init(
        httpClient: HTTPClient,
        commandRunner: CommandRunning,
        githubToken: String? = nil,
        requireHTTPSSource: Bool = true
    ) {
        self.httpClient = httpClient
        self.commandRunner = commandRunner
        self.githubToken = githubToken
        self.requireHTTPSSource = requireHTTPSSource
    }
}

public protocol LatestStrategy {
    func latest(for recipe: Recipe, context: LatestContext) throws -> String
}

public enum LatestError: Error, CustomStringConvertible, Equatable {
    case invalidSource(String)
    case missingField(String)
    case commandFailed(String)
    case parseFailed(String)

    public var description: String {
        switch self {
        case .invalidSource(let message): SecretRedactor.redact(message)
        case .missingField(let message): SecretRedactor.redact(message)
        case .commandFailed(let message): SecretRedactor.redact(message)
        case .parseFailed(let message): SecretRedactor.redact(message)
        }
    }
}
