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

    // MARK: formPost (large playlist mutations — issue #1)

    @Test func playlistMutationsAreFlaggedForFormPost() {
        #expect(Endpoint.createPlaylist(playlistId: "p1", songIds: ["s1"]).usesFormPost)
        #expect(Endpoint.updatePlaylist(id: "p1", songIdsToAdd: ["s1"]).usesFormPost)
        #expect(!Endpoint.ping.usesFormPost)
        #expect(!Endpoint.openSubsonicExtensions.usesFormPost)
        #expect(!Endpoint.playlist(id: "p1").usesFormPost)  // reads stay GET
    }

    @Test func formPostRequestCarriesParamsInBodyNotURL() async throws {
        let creds = ServerCredentials(
            baseURL: URL(string: "https://music.example.com")!,
            username: "thijs", secret: "sesame", authMethod: .tokenSalt)
        let client = SubsonicClient(credentials: InMemoryCredentialStore(creds))
        let endpoint = Endpoint.createPlaylist(
            playlistId: "p1", songIds: (1...2000).map { "song-\($0)" })
        let request = try await client.formPostRequest(for: endpoint, using: creds)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.query() == nil)                       // nothing in the URL
        #expect(request.url?.path() == "/rest/createPlaylist.view")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("application/x-www-form-urlencoded") == true)

        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("songId=song-2000"))
        #expect(body.contains("u=thijs"))
        #expect(body.contains("f=json"))
        #expect(!body.contains("sesame"))                          // secret still never plaintext
    }

    @Test func formBodyEscapesPlusAndReservedCharacters() {
        let body = String(decoding: SubsonicClient.formBody(items: [
            .init(name: "name", value: "Rock + Roll & Friends")
        ]), as: UTF8.self)
        // '+' must be %2B (form decoding reads literal '+' as a space).
        #expect(body == "name=Rock%20%2B%20Roll%20%26%20Friends")
    }

    @Test func extensionsBodyDecodes() throws {
        let json = Data("""
        {"openSubsonicExtensions":[
            {"name":"formPost","versions":[1]},
            {"name":"songLyrics","versions":[1,2]}
        ]}
        """.utf8)
        let body = try JSONDecoder().decode(OpenSubsonicExtensionsBody.self, from: json)
        #expect(body.openSubsonicExtensions?.contains { $0.name == "formPost" } == true)
    }
}
