import Testing
import Foundation
@testable import Sonicwave

/// Verifies authenticated URL construction for streaming/cover-art, covering
/// both auth methods. See docs/02-opensubsonic-api.md, docs/08-testing.md.
struct RequestBuildingTests {
    private func client(method: ServerCredentials.AuthMethod) -> SubsonicClient {
        let creds = ServerCredentials(
            baseURL: URL(string: "https://music.example.com")!,
            username: "thijs",
            secret: "sesame",
            authMethod: method
        )
        return SubsonicClient(credentials: InMemoryCredentialStore(creds))
    }

    @Test func streamURLUsesTokenSaltAuth() async throws {
        let url = try await client(method: .tokenSalt).streamURL(songId: "s1")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(comps.path == "/rest/stream.view")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["id"] == "s1")
        #expect(items["u"] == "thijs")
        #expect(items["f"] == "json")
        #expect(items["c"] == SubsonicClient.clientName)
        #expect(items["t"] != nil)        // token present
        #expect(items["s"] != nil)        // salt present
        #expect(items["apiKey"] == nil)   // not used in token mode
        #expect(!url.absoluteString.contains("sesame")) // secret never in URL
    }

    @Test func streamURLAppliesTranscodingParams() async throws {
        let url = try await client(method: .tokenSalt)
            .streamURL(songId: "s1", format: "opus", maxBitRate: 192)
        let items = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["format"] == "opus")
        #expect(items["maxBitRate"] == "192")
    }

    @Test func coverArtURLUsesApiKeyAuth() async throws {
        let url = try await client(method: .apiKey).coverArtURL(id: "al-1", size: 300)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(comps.path == "/rest/getCoverArt.view")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["apiKey"] == "sesame")
        #expect(items["size"] == "300")
        #expect(items["t"] == nil) // token not used in api-key mode
    }

    @Test func notConfiguredThrows() async {
        let client = SubsonicClient(credentials: InMemoryCredentialStore(nil))
        await #expect(throws: SubsonicError.notConfigured) {
            _ = try await client.streamURL(songId: "s1")
        }
    }
}
