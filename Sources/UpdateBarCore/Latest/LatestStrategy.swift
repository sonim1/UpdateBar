import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient {
    func get(url: URL, headers: [String: String]) throws -> Data
    func post(url: URL, headers: [String: String], body: Data) throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(url: URL, headers: [String: String]) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try send(request: request, headers: headers)
    }

    public func post(url: URL, headers: [String: String], body: Data) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        return try send(request: request, headers: headers)
    }

    private func send(request initialRequest: URLRequest, headers: [String: String]) throws -> Data {
        var request = initialRequest
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                box.result = .failure(error)
            } else {
                box.result = .success(data ?? Data())
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try box.result!.get()
    }
}

private final class ResponseBox: @unchecked Sendable {
    var result: Result<Data, Error>?
}

public struct LatestContext {
    public var httpClient: HTTPClient
    public var commandRunner: CommandRunning
    public var githubToken: String?

    public init(httpClient: HTTPClient, commandRunner: CommandRunning, githubToken: String? = nil) {
        self.httpClient = httpClient
        self.commandRunner = commandRunner
        self.githubToken = githubToken
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
        case let .invalidSource(message): message
        case let .missingField(message): message
        case let .commandFailed(message): message
        case let .parseFailed(message): message
        }
    }
}
