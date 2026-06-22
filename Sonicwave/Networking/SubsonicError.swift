import Foundation

/// Typed errors surfaced by `SubsonicClient`. See docs/02-opensubsonic-api.md.
enum SubsonicError: Error, Sendable, Equatable {
    case notConfigured
    case invalidURL
    case transport(String)
    case http(status: Int)
    case decoding(String)
    /// A Subsonic API-level failure carrying the server's error code + message.
    case api(code: Int, message: String)

    /// Whether the error indicates the user must re-authenticate.
    var isAuthFailure: Bool {
        if case let .api(code, _) = self {
            return code == 40 || code == 41 || code == 50
        }
        return false
    }

    var userMessage: String {
        switch self {
        case .notConfigured: return "No server is configured. Open Settings to connect."
        case .invalidURL: return "The server address is not a valid URL."
        case let .transport(message): return "Could not reach the server: \(message)"
        case let .http(status): return "The server returned HTTP \(status)."
        case let .decoding(message): return "Unexpected response from the server: \(message)"
        case let .api(code, message): return "Server error \(code): \(message)"
        }
    }
}
