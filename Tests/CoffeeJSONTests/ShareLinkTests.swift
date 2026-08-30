import Testing
import Foundation
@testable import CoffeeJSON

@Suite("ShareLink parse")
struct ShareLinkTests {
    private let validJSON = #"{"coffeejson":"1.0","recipes":[{"title":"Link V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#

    /// Build a `?d=` query link — the transport this package parses.
    private func queryLink(_ json: String, base: String = "https://example.com/r") -> URL {
        let payload = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "\(base)?d=\(payload)")!
    }

    @Test("parses the shipping ?d= query share link into a recipe")
    func parsesQueryLink() throws {
        let r = try #require(try ShareLink.importDocument(from: queryLink(validJSON)).recipes.first)
        #expect(r.title == "Link V60")
        #expect(r.coffeeGrams == 15)
    }

    @Test("parses a custom-scheme ?d= link")
    func parsesCustomScheme() throws {
        let r = try #require(try ShareLink.importDocument(from: queryLink(validJSON, base: "myapp://import")).recipes.first)
        #expect(r.title == "Link V60")
    }

    @Test("a link with no d query item is rejected")
    func rejectsMissingPayload() {
        #expect(throws: ImportError.transport(.noPayload)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r")!)
        }
    }

    @Test("a #fragment payload is ignored — the transport is query-only")
    func fragmentIsNotParsed() {
        // Even a well-formed payload in the fragment is not read; only `?d=` is.
        let payload = Data(validJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(throws: ImportError.transport(.noPayload)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r#\(payload)")!)
        }
    }

    @Test("a non-base64url d value is rejected")
    func rejectsNonBase64URL() {
        #expect(throws: ImportError.transport(.malformedBase64)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r?d=....")!)
        }
    }

    @Test("a tampered d value that isn't valid JSON is rejected")
    func rejectsTampered() {
        // `eyJhIjo` is base64url for `{"a":` — it begins '{', so the
        // discriminator hands it to the parser, which is where it fails.
        #expect(throws: ImportError.decode(.notJSON)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r?d=eyJhIjo")!)
        }
    }

    @Test("a payload that is neither form is turned away before any parse")
    func rejectsUnknownEncoding() {
        // "YWJj" is valid base64url for "abc": it decodes, but it is neither a
        // JSON document nor a zlib stream, so no parse is attempted at all.
        #expect(throws: ImportError.transport(.unrecognizedEncoding)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r?d=YWJj")!)
        }
    }

    @Test("an oversized plain d value is rejected before decoding")
    func rejectsOversized() {
        // Past the pre-decode guard (⌈8192 × 4/3⌉ = 10,924 chars), so this is
        // refused without ever allocating the decode. The first quantum decodes
        // to `{`, which is what puts it in the plain form the guard bounds.
        let huge = "eyJh" + String(repeating: "A", count: 12_000)
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r?d=\(huge)")!)
        }
    }

    @Test("round-trips a rich recipe through a link")
    func roundTripsRich() throws {
        let json = #"{"coffeejson":"1.0","recipes":[{"title":"Rich","coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"},"water_temp":{"value":92,"unit":"celsius"},"steps":[{"at_s":0,"to_water":{"value":45,"unit":"gram"}},{"at_s":40,"to_water":{"value":300,"unit":"gram"}}],"finish_s":140}]}"#
        let r = try #require(try ShareLink.importDocument(from: queryLink(json)).recipes.first)
        #expect(r.waterTemperatureCelsius == 92)
        #expect(r.pourSteps.count == 2)
    }

    @Test("shareURL(forEncodedDocument:) builds a link the importer round-trips")
    func encodedDocumentRoundTrips() throws {
        let bytes = Data(#"{"coffeejson":"1.0","recipes":[{"title":"Raw","coffee":{"value":18,"unit":"gram"},"water":{"value":250,"unit":"gram"},"notes":"x"}]}"#.utf8)
        let url = try ShareLink.shareURL(forEncodedDocument: bytes, host: "example.com")
        let recipe = try #require(try ShareLink.importDocument(from: url).recipes.first)
        #expect(recipe.title == "Raw")
        #expect(recipe.notes == "x")
    }

    @Test("shareURL(forEncodedDocument:) enforces the payload cap")
    func encodedDocumentTooLarge() {
        let big = Data(repeating: 0x41, count: 9000)   // 9000 decoded bytes, past the 8192 cap
        #expect(throws: ImportError.transport(.tooLarge)) {
            _ = try ShareLink.shareURL(forEncodedDocument: big, host: "example.com")
        }
    }

    /// The cap is 8192 **decoded** bytes
    /// (<https://coffeejson.org/docs/transport.md>, `@coffeejson/core`) — not
    /// encoded characters. Comparing the base64url string length against 8192
    /// caps the document at ~6 KB instead: a rich
    /// bag-to-brew doc the web mints and renders fine would be unreadable here.
    @Test("a document between the base64url-inflated size and the byte cap round-trips")
    func documentInsideByteCapRoundTrips() throws {
        let padding = String(repeating: "x", count: 6_800)
        let json = #"{"coffeejson":"1.0","recipes":[{"title":"Big","coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"},"notes":"\#(padding)"}]}"#
        let bytes = Data(json.utf8)
        #expect(bytes.count > 6_144)    // beyond what an encoded-length cap allows
        #expect(bytes.count <= 8_192)   // but legal per the transport spec

        let url = try ShareLink.shareURL(forEncodedDocument: bytes, host: "example.com")
        let recipe = try #require(try ShareLink.importDocument(from: url).recipes.first)
        #expect(recipe.title == "Big")
        #expect(recipe.notes == padding)
    }

    @Test("a payload over the byte cap is rejected even though it decodes")
    func decodedPayloadOverCapRejected() {
        // 8193 decoded bytes → 10,924 encoded chars: under any pre-decode guard,
        // over the real cap. Only a post-decode byte check catches this. It
        // begins '{' so the cap, not the discriminator, is what rejects it.
        let over = Data([0x7B]) + Data(repeating: 0x41, count: 8_192)
        let encoded = over.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.importDocument(from: URL(string: "https://example.com/r?d=\(encoded)")!)
        }
    }
}

/// The bytes accessor beside the two `importDocument` entry points: it hands
/// back what the `?d=` item carried, and — unlike them — it caps nothing.
@Suite("ShareLink payload bytes")
struct ShareLinkPayloadBytesTests {
    private func link(_ payload: Data) throws -> URL {
        try CoffeeJSON.ShareLink.shareURL(forEncodedDocument: payload, host: "example.com")
    }

    @Test("a well-formed link hands back exactly the bytes that were encoded")
    func roundTripsTheBytes() throws {
        let sent = Data(#"{"coffeejson":"1.0","recipes":[]}"#.utf8)
        let bytes = try #require(CoffeeJSON.ShareLink.payloadBytes(from: try link(sent)))
        #expect(bytes == sent)
    }

    @Test("every base64 remainder class round-trips, since the transport drops padding")
    func handlesEveryPaddingClass() throws {
        // 3n, 3n+1 and 3n+2 input lengths encode to 0, 2 and 1 padding characters.
        for length in [30, 31, 32] {
            let sent = Data(repeating: 0x7B, count: length)
            let bytes = try #require(CoffeeJSON.ShareLink.payloadBytes(from: try link(sent)))
            #expect(bytes == sent, "length \(length)")
        }
    }

    @Test("a payload over the cap comes back whole here and is refused by the capped entry point")
    func doesNotEnforceTheCap() throws {
        // The divergence, pinned: without this test the next reader adds the cap
        // back and silently takes the accessor's whole purpose with it.
        let oversized = Data(repeating: 0x7B, count: CoffeeJSON.ShareLink.maxPayloadBytes + 1)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.com"
        components.path = "/r"
        components.queryItems = [URLQueryItem(
            name: "d",
            value: oversized.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: ""))]
        let url = try #require(components.url)

        let bytes = try #require(CoffeeJSON.ShareLink.payloadBytes(from: url))
        #expect(bytes.count == CoffeeJSON.ShareLink.maxPayloadBytes + 1)
        #expect(throws: ImportError.transport(.tooLarge)) {
            try CoffeeJSON.ShareLink.importDocument(from: url)
        }
    }

    @Test("no d, an empty d, and a d that is not base64url all read as nil")
    func unusableLinksReadAsNil() throws {
        for query in ["", "?d=", "?e=abc", "?d=not base64url!!"] {
            let url = try #require(URL(string: "https://example.com/r\(query)"))
            #expect(CoffeeJSON.ShareLink.payloadBytes(from: url) == nil, "query \(query)")
        }
    }
}
