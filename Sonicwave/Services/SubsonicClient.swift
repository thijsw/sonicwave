import Foundation
import CryptoKit

/// Actor that performs all OpenSubsonic HTTP. Builds authenticated requests,
/// decodes the response envelope, and maps failures to `SubsonicError`.
/// See docs/01-architecture.md and docs/02-opensubsonic-api.md.
actor SubsonicClient {
    /// Protocol version we advertise. 1.16.1 is broadly supported.
    static let protocolVersion = "1.16.1"
    static let clientName = "Sonicwave"

    private let credentials: CredentialStore
    private let session: URLSession
    private let decoder: JSONDecoder

    init(credentials: CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
        self.decoder = SubsonicClient.makeDecoder()
    }

    // MARK: - Public API

    var isConfigured: Bool { credentials.load() != nil }

    /// Performs an endpoint call and returns the decoded body.
    func send<Body: Decodable & Sendable>(_ endpoint: Endpoint, as _: Body.Type) async throws(SubsonicError) -> Body {
        let wrapper: SubsonicResponseWrapper<Body> = try await perform(endpoint)
        guard let body = wrapper.response.body else {
            throw SubsonicError.decoding("missing body for \(endpoint.method)")
        }
        return body
    }

    /// Performs an endpoint call that returns no payload (ping, star, etc.) and
    /// returns the server identity/capability info.
    @discardableResult
    func sendStatus(_ endpoint: Endpoint) async throws(SubsonicError) -> ServerInfo {
        let wrapper: SubsonicResponseWrapper<EmptyBody> = try await perform(endpoint)
        return wrapper.response.info
    }

    /// Connection test. Returns server identity (type/version/openSubsonic).
    func ping() async throws(SubsonicError) -> ServerInfo {
        try await sendStatus(.ping)
    }

    /// Test a candidate set of credentials without persisting them. Used by the
    /// Settings "Test Connection" button.
    func testConnection(_ candidate: ServerCredentials) async throws(SubsonicError) -> ServerInfo {
        let request: URLRequest
        do {
            request = try buildRequest(for: .ping, using: candidate)
        } catch let error as SubsonicError {
            throw error
        } catch {
            throw SubsonicError.invalidURL
        }
        let wrapper: SubsonicResponseWrapper<EmptyBody> = try await execute(request, method: "ping")
        return wrapper.response.info
    }

    /// Builds an authenticated streaming URL for the given song id. Honors the
    /// transcoding settings (format/maxBitRate) when provided.
    func streamURL(songId: String, format: String? = nil, maxBitRate: Int? = nil,
                   timeOffset: Int? = nil) throws(SubsonicError) -> URL {
        guard let creds = credentials.load() else { throw SubsonicError.notConfigured }
        var items: [URLQueryItem] = [.init(name: "id", value: songId)]
        if let format { items.append(.init(name: "format", value: format)) }
        if let maxBitRate { items.append(.init(name: "maxBitRate", value: String(maxBitRate))) }
        if let timeOffset { items.append(.init(name: "timeOffset", value: String(timeOffset))) }
        do {
            return try url(for: Endpoint("stream", items), using: creds)
        } catch let error as SubsonicError {
            throw error
        } catch {
            throw SubsonicError.invalidURL
        }
    }

    /// Builds an authenticated cover-art URL for the given id at a target size.
    func coverArtURL(id: String, size: Int? = nil) throws(SubsonicError) -> URL {
        guard let creds = credentials.load() else { throw SubsonicError.notConfigured }
        var items: [URLQueryItem] = [.init(name: "id", value: id)]
        if let size { items.append(.init(name: "size", value: String(size))) }
        do {
            return try url(for: Endpoint("getCoverArt", items), using: creds)
        } catch let error as SubsonicError {
            throw error
        } catch {
            throw SubsonicError.invalidURL
        }
    }

    // MARK: - Request execution

    private func perform<Body: Decodable & Sendable>(
        _ endpoint: Endpoint
    ) async throws(SubsonicError) -> SubsonicResponseWrapper<Body> {
        guard let creds = credentials.load() else { throw SubsonicError.notConfigured }
        let request: URLRequest
        do {
            request = try buildRequest(for: endpoint, using: creds)
        } catch let error as SubsonicError {
            throw error
        } catch {
            throw SubsonicError.invalidURL
        }
        return try await execute(request, method: endpoint.method)
    }

    private func execute<Body: Decodable & Sendable>(
        _ request: URLRequest, method: String
    ) async throws(SubsonicError) -> SubsonicResponseWrapper<Body> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SubsonicError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        let wrapper: SubsonicResponseWrapper<Body>
        do {
            wrapper = try decoder.decode(SubsonicResponseWrapper<Body>.self, from: data)
        } catch {
            throw SubsonicError.decoding(error.localizedDescription)
        }
        if wrapper.response.info.status != "ok" {
            let err = wrapper.response.error
            throw SubsonicError.api(code: err?.code ?? 0, message: err?.message ?? "Unknown error")
        }
        return wrapper
    }

    // MARK: - URL / auth construction

    private func buildRequest(for endpoint: Endpoint, using creds: ServerCredentials) throws -> URLRequest {
        let finalURL = try url(for: endpoint, using: creds)
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        return request
    }

    private func url(for endpoint: Endpoint, using creds: ServerCredentials) throws -> URL {
        guard var components = URLComponents(url: creds.baseURL, resolvingAgainstBaseURL: false) else {
            throw SubsonicError.invalidURL
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + "/rest/" + endpoint.method + ".view"

        var items: [URLQueryItem] = [
            .init(name: "v", value: Self.protocolVersion),
            .init(name: "c", value: Self.clientName),
            .init(name: "f", value: "json")
        ]
        items += authItems(for: creds)
        items += endpoint.queryItems
        components.queryItems = items

        guard let url = components.url else { throw SubsonicError.invalidURL }
        return url
    }

    private func authItems(for creds: ServerCredentials) -> [URLQueryItem] {
        switch creds.authMethod {
        case .apiKey:
            // OpenSubsonic API-key auth extension.
            return [.init(name: "apiKey", value: creds.secret)]
        case .tokenSalt:
            let salt = Self.randomSalt()
            let token = Self.md5Hex(creds.secret + salt)
            return [
                .init(name: "u", value: creds.username),
                .init(name: "t", value: token),
                .init(name: "s", value: salt)
            ]
        }
    }

    // MARK: - Helpers

    static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func randomSalt(length: Int = 12) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &generator)! })
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Value-type format styles (Sendable), unlike ISO8601DateFormatter.
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { dateDecoder in
            let container = try dateDecoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = (try? withFraction.parse(string)) ?? (try? plain.parse(string)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(string)")
        }
        return decoder
    }
}
