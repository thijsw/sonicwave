import Testing
import Foundation
@testable import Sonicwave

/// Regression test for `ArtworkCache`. `clientBox` was declared `weak`, so the
/// inline `ClientBox(client)` AppModel assigned had no other owner and
/// deallocated immediately — leaving `clientBox` nil and artwork never loading.
@MainActor
struct ArtworkCacheTests {
    @Test func clientBoxIsRetained() {
        let creds = ServerCredentials(baseURL: URL(string: "https://example.com")!,
                                      username: "u", secret: "s", authMethod: .tokenSalt)
        let client = SubsonicClient(credentials: InMemoryCredentialStore(creds))

        ArtworkCache.shared.clientBox = ClientBox(client)
        #expect(ArtworkCache.shared.clientBox != nil)
    }
}
