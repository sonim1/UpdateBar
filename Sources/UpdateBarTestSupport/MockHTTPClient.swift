import Foundation
import UpdateBarCore

public final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [String: Data]
    private var _finalURLs: [String: String]
    private var _postResponses: [String: [Data]]
    private var _postErrors: [String: Error]
    private var _requestedURLs: [String] = []
    private var _postedRequests: [PostedRequest] = []

    public var responses: [String: Data] {
        get { lock.withLock { _responses } }
        set { lock.withLock { _responses = newValue } }
    }

    public var finalURLs: [String: String] {
        get { lock.withLock { _finalURLs } }
        set { lock.withLock { _finalURLs = newValue } }
    }

    public var postResponses: [String: [Data]] {
        get { lock.withLock { _postResponses } }
        set { lock.withLock { _postResponses = newValue } }
    }

    public var postErrors: [String: Error] {
        get { lock.withLock { _postErrors } }
        set { lock.withLock { _postErrors = newValue } }
    }

    public var requestedURLs: [String] { lock.withLock { _requestedURLs } }
    public var postedRequests: [PostedRequest] { lock.withLock { _postedRequests } }

    public init(
        responses: [String: Data] = [:],
        finalURLs: [String: String] = [:],
        postResponses: [String: [Data]] = [:],
        postErrors: [String: Error] = [:]
    ) {
        _responses = responses
        _finalURLs = finalURLs
        _postResponses = postResponses
        _postErrors = postErrors
    }

    public func get(
        url: URL,
        headers: [String: String],
        requireHTTPSFinalURL: Bool = false
    ) throws -> Data {
        let key = url.absoluteString
        return try lock.withLock {
            _requestedURLs.append(key)
            if requireHTTPSFinalURL,
                let finalURL = _finalURLs[key].flatMap({ URL(string: $0) }),
                finalURL.scheme?.lowercased() != "https"
            {
                let message = "\(finalURL.absoluteString): https redirect not allowed"
                throw LatestError.invalidSource(message)
            }
            guard let data = _responses[key] else {
                throw MockError.missingResponse(key)
            }
            return data
        }
    }

    public func post(url: URL, headers: [String: String], body: Data) throws -> Data {
        let key = url.absoluteString
        return try lock.withLock {
            _postedRequests.append(PostedRequest(url: key, headers: headers, body: body))
            if let error = _postErrors[key] {
                throw error
            }
            guard var responses = _postResponses[key], !responses.isEmpty else {
                throw MockError.missingResponse(key)
            }
            let response = responses.removeFirst()
            _postResponses[key] = responses
            return response
        }
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
            case .missingResponse(let url):
                return "\(url): missing mock response"
            case .requestFailed(let message):
                return message
            }
        }
    }
}
