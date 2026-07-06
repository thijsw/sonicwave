import Foundation
import Security

/// The persisted server connection + authentication material.
/// See docs/02-opensubsonic-api.md and docs/07-distribution.md.
struct ServerCredentials: Sendable, Equatable {
    var baseURL: URL
    var username: String
    /// The authentication secret. For token+salt auth this is the password;
    /// for API-key auth it is the API key.
    var secret: String
    var authMethod: AuthMethod

    enum AuthMethod: String, Sendable, CaseIterable, Codable {
        case tokenSalt
        case apiKey
    }
}

/// Abstraction over credential persistence so the client and tests can be
/// decoupled from the Keychain. See docs/08-testing.md.
protocol CredentialStore: Sendable {
    func load() -> ServerCredentials?
    func save(_ credentials: ServerCredentials) throws
    func clear() throws
}

/// Keychain-backed credential storage. Stores the server URL, username,
/// auth method, and secret as a single generic-password item keyed by the
/// app's service identifier. The raw secret never leaves the Keychain except
/// when building authenticated requests; the derived token is never persisted.
final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service = "nl.huell.sonicwave.credentials"
    private let account = "primary-server"

    private struct Payload: Codable {
        var baseURL: URL
        var username: String
        var secret: String
        var authMethod: ServerCredentials.AuthMethod
    }

    func load() -> ServerCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return ServerCredentials(
            baseURL: payload.baseURL,
            username: payload.username,
            secret: payload.secret,
            authMethod: payload.authMethod
        )
    }

    func save(_ credentials: ServerCredentials) throws {
        let payload = Payload(
            baseURL: credentials.baseURL,
            username: credentials.username,
            secret: credentials.secret,
            authMethod: credentials.authMethod
        )
        let data = try JSONEncoder().encode(payload)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: Error {
    let status: OSStatus
    var localizedDescription: String {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

/// In-memory credential store for tests and previews.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ServerCredentials?

    init(_ initial: ServerCredentials? = nil) { stored = initial }

    func load() -> ServerCredentials? { lock.withLock { stored } }
    func save(_ credentials: ServerCredentials) throws { lock.withLock { stored = credentials } }
    func clear() throws { lock.withLock { stored = nil } }
}
