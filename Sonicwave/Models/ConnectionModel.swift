import Foundation
import Observation

/// Observable server-connection + authentication state. Backs the Settings
/// window and gates library loading. See docs/02-opensubsonic-api.md.
@MainActor
@Observable
final class ConnectionModel {
    enum State: Equatable {
        case unconfigured
        case connecting
        case connected(ServerInfo)
        case failed(String)
    }

    private(set) var state: State = .unconfigured

    // Editable form fields (bound by the Settings UI).
    var serverAddress: String = ""
    var username: String = ""
    var secret: String = ""
    var authMethod: ServerCredentials.AuthMethod = .tokenSalt

    /// Transcoding preferences (persisted in UserDefaults, applied at stream time).
    var transcodeEnabled: Bool
    var transcodeFormat: String
    var transcodeMaxBitRate: Int

    private let client: SubsonicClient
    private let credentials: CredentialStore

    init(client: SubsonicClient, credentials: CredentialStore) {
        self.client = client
        self.credentials = credentials

        let defaults = UserDefaults.standard
        self.transcodeEnabled = defaults.bool(forKey: "transcodeEnabled")
        self.transcodeFormat = defaults.string(forKey: "transcodeFormat") ?? "mp3"
        self.transcodeMaxBitRate = defaults.integer(forKey: "transcodeMaxBitRate") == 0
            ? 320 : defaults.integer(forKey: "transcodeMaxBitRate")

        if let existing = credentials.load() {
            serverAddress = existing.baseURL.absoluteString
            username = existing.username
            secret = existing.secret
            authMethod = existing.authMethod
            state = .unconfigured // verified lazily via refresh()
        }
    }

    var isConfigured: Bool { credentials.load() != nil }

    /// Build credentials from the current form, or nil if the form is invalid.
    private func formCredentials() -> ServerCredentials? {
        guard let url = Self.normalizedBaseURL(from: serverAddress) else { return nil }
        return ServerCredentials(baseURL: url, username: username, secret: secret, authMethod: authMethod)
    }

    /// Normalize a user-entered server address into a clean API base URL:
    /// assume `https://` when no scheme is given, and drop query/fragment, any
    /// trailing slash, and Navidrome's `/app` web-UI suffix (a common
    /// copy-from-browser mistake that would make requests 404). A legitimate
    /// reverse-proxy subpath (e.g. `/navidrome`) is preserved.
    static func normalizedBaseURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text), comps.scheme != nil, comps.host != nil else {
            return nil
        }
        comps.query = nil
        comps.fragment = nil
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/app") { path.removeLast("/app".count) }
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        return comps.url
    }

    /// Verify the current form against the server without persisting.
    func testConnection() async {
        guard let candidate = formCredentials() else {
            state = .failed("Enter a valid server address (including http:// or https://).")
            return
        }
        state = .connecting
        do {
            let info = try await client.testConnection(candidate)
            state = .connected(info)
        } catch let error as SubsonicError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Test then persist the credentials to the Keychain on success.
    func saveAndConnect() async {
        guard let candidate = formCredentials() else {
            state = .failed("Enter a valid server address (including http:// or https://).")
            return
        }
        state = .connecting
        do {
            let info = try await client.testConnection(candidate)
            try credentials.save(candidate)
            persistTranscodePrefs()
            // Re-scope the artwork cache to the (possibly new) server.
            ArtworkCache.shared.setServer(baseURL: candidate.baseURL)
            state = .connected(info)
        } catch let error as SubsonicError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Re-verify already-saved credentials (e.g. at launch).
    func refresh() async {
        guard isConfigured else { state = .unconfigured; return }
        state = .connecting
        do {
            let info = try await client.ping()
            state = .connected(info)
        } catch let error as SubsonicError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        try? credentials.clear()
        ArtworkCache.shared.setServer(baseURL: nil)
        state = .unconfigured
    }

    func persistTranscodePrefs() {
        let defaults = UserDefaults.standard
        defaults.set(transcodeEnabled, forKey: "transcodeEnabled")
        defaults.set(transcodeFormat, forKey: "transcodeFormat")
        defaults.set(transcodeMaxBitRate, forKey: "transcodeMaxBitRate")
    }
}
