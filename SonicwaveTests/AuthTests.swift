import Testing
import Foundation
@testable import Sonicwave

/// Auth token + salt behavior. See docs/02-opensubsonic-api.md, docs/08-testing.md.
struct AuthTests {
    @Test func md5TokenMatchesKnownVector() {
        // From the Subsonic API docs example: password "sesame", salt "c19b2d".
        let token = SubsonicClient.md5Hex("sesame" + "c19b2d")
        #expect(token == "26719a1196d2a940705a59634eb18eab")
    }

    @Test func md5OfEmptyString() {
        #expect(SubsonicClient.md5Hex("") == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test func saltIsRandomAndCorrectLength() {
        let saltA = SubsonicClient.randomSalt(length: 12)
        let saltB = SubsonicClient.randomSalt(length: 12)
        #expect(saltA.count == 12)
        #expect(saltB.count == 12)
        #expect(saltA != saltB)
    }

    @Test func authFailureCodesAreDetected() {
        #expect(SubsonicError.api(code: 40, message: "x").isAuthFailure)
        #expect(SubsonicError.api(code: 41, message: "x").isAuthFailure)
        #expect(SubsonicError.api(code: 50, message: "x").isAuthFailure)
        #expect(!SubsonicError.api(code: 70, message: "x").isAuthFailure)
        #expect(!SubsonicError.transport("x").isAuthFailure)
    }
}
