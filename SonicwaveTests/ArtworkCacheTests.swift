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

    @Test func retryDelayParsesAndClampsRetryAfter() {
        func response(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429,
                            httpVersion: nil, headerFields: headers)!
        }
        #expect(ArtworkCache.retryDelay(from: response(["Retry-After": "5"])) == 5)
        #expect(ArtworkCache.retryDelay(from: response(["Retry-After": "900"])) == 30)  // clamp
        #expect(ArtworkCache.retryDelay(from: response([:])) == 2)                      // default
        #expect(ArtworkCache.retryDelay(from: response(["Retry-After": "soon"])) == 2)  // junk
    }

    @Test func limiterCapsConcurrencyAndRunsEveryBody() async {
        let limiter = AsyncLimiter(limit: 3)
        let gauge = ConcurrencyGauge()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await limiter.run {
                        await gauge.enter()
                        await Task.yield()
                        await gauge.exit()
                    }
                }
            }
        }
        let (peak, total) = await (gauge.peak, gauge.completed)
        #expect(peak <= 3)
        #expect(total == 20)
    }
}

private actor ConcurrencyGauge {
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var completed = 0
    func enter() { active += 1; peak = max(peak, active) }
    func exit() { active -= 1; completed += 1 }
}
