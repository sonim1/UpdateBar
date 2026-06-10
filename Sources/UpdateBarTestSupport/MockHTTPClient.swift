import Foundation
import UpdateBarCore

public final class MockHTTPClient: HTTPClient {
    public var responses: [String: Data]
    public var postResponses: [String: [Data]]
    public var postErrors: [String: Error]
    public private(set) var requestedURLs: [String] = []
    public private(set) var postedRequests: [PostedRequest] = []

    public init(
        responses: [String: Data] = [:],
        postResponses: [String: [Data]] = [:],
        postErrors: [String: Error] = [:]
    ) {
        self.responses = responses
        self.postResponses = postResponses
        self.postErrors = postErrors
    }

    public func get(url: URL, headers: [String: String]) throws -> Data {
        requestedURLs.append(url.absoluteString)
        guard let data = responses[url.absoluteString] else {
            throw MockError.missingResponse(url.absoluteString)
        }
        return data
    }

    public func post(url: URL, headers: [String: String], body: Data) throws -> Data {
        let key = url.absoluteString
        postedRequests.append(PostedRequest(url: key, headers: headers, body: body))
        if let error = postErrors[key] {
            throw error
        }
        guard var responses = postResponses[key], !responses.isEmpty else {
            throw MockError.missingResponse(key)
        }
        let response = responses.removeFirst()
        postResponses[key] = responses
        return response
    }

    public struct PostedRequest {
        public var url: String
        public var headers: [String: String]
        public var body: Data
    }

    public enum MockError: Error, CustomStringConvertible {
        case missingResponse(String)
        case requestFailed(String)

        public var description: String {
            switch self {
            case let .missingResponse(url):
                return "\(url): missing mock response"
            case let .requestFailed(message):
                return message
            }
        }
    }
}
