import Testing
import Foundation
@testable import Sonicwave

/// Server-address normalization. See docs/02-opensubsonic-api.md.
@MainActor
struct ConnectionTests {
    private func norm(_ address: String) -> String? {
        ConnectionModel.normalizedBaseURL(from: address)?.absoluteString
    }

    @Test func keepsPlainHTTPSBase() {
        #expect(norm("https://navidrome.example.com") == "https://navidrome.example.com")
    }

    @Test func dropsTrailingSlash() {
        #expect(norm("https://navidrome.example.com/") == "https://navidrome.example.com")
    }

    @Test func stripsAppSuffixFromBrowserURL() {
        #expect(norm("https://navidrome.example.com/app") == "https://navidrome.example.com")
        #expect(norm("https://navidrome.example.com/app/") == "https://navidrome.example.com")
    }

    @Test func dropsQueryAndFragment() {
        #expect(norm("https://navidrome.example.com/app/#/album/123") == "https://navidrome.example.com")
    }

    @Test func assumesHTTPSWhenSchemeMissing() {
        #expect(norm("navidrome.example.com") == "https://navidrome.example.com")
    }

    @Test func preservesLegitimateSubpath() {
        #expect(norm("https://example.com/navidrome") == "https://example.com/navidrome")
    }

    @Test func rejectsEmpty() {
        #expect(norm("   ") == nil)
    }

    @Test func atsBlockGetsActionableTransportMessage() {
        let err = SubsonicError.transport(
            from: URLError(.appTransportSecurityRequiresSecureConnection))
        #expect(err.userMessage.contains("https://"))
        #expect(err.userMessage.contains("nas.local"))
    }

    @Test func otherURLErrorsKeepTheirDescription() {
        let err = SubsonicError.transport(from: URLError(.timedOut))
        if case let .transport(message) = err {
            #expect(message == URLError(.timedOut).localizedDescription)
        } else {
            Issue.record("expected .transport")
        }
    }
}
