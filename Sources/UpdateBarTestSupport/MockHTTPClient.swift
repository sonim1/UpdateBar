import Foundation
import UpdateBarCore

public final class MockHTTPClient: HTTPClient {
    public var responses: [String: Data]
    public var finalURLs: [String: String]
    public var postResponses: [String: [Data]]
    public var postErrors: [String: Error]
    public private(set) var requestedURLs: [String] = []
    public private(set) var postedRequests: [PostedRequest] = []

    public init(
        responses: [String: Data] = [:],
        finalURLs: [String: String] = [:],
        postResponses: [String: [Data]] = [:],
        postErrors: [String: Error] = [:]
    ) {
        self.responses = responses
        self.finalURLs = finalURLs
        self.postResponses = postResponses
        self.postErrors = postErrors
    }

    public func get(
        url: URL,
        headers: [String: String],
        requireHTTPSFinalURL: Bool = false
    ) throws -> Data {
        let key = url.absoluteString
        requestedURLs.append(key)
        if requireHTTPSFinalURL,
            let finalURL = finalURLs[key].flatMap({ URL(string: $0) }),
            finalURL.scheme?.lowercased() != "https"
        {
            let message = "\(finalURL.absoluteString): https redirect not allowed"
            throw LatestError.invalidSource(message)
        }
        guard let data = responses[key] else {
            throw MockError.missingResponse(key)
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
