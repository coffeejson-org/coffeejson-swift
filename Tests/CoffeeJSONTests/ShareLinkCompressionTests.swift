import Testing
import Foundation
@testable import CoffeeJSON

/// The compressed payload form.
///
/// Every payload below was produced by a *different* implementation — Node's
/// zlib, the same one the format's scan-vector corpus uses — so these tests
/// prove interoperability rather than that this package agrees with itself.
/// They decode the same document as `ShareLinkTests` reads in plain form.
@Suite("ShareLink compressed payloads")
struct ShareLinkCompressionTests {
    /// The plain payload's document, for comparison: title `Link V60`, 15 g, 250 g.
    private func link(_ payload: String) -> URL {
        URL(string: "https://example.com/r?d=\(payload)")!
    }

    private let compressed =
        "eNpdy7EKgzAUQNFfkTsHUUGH9w3OLqVDkGdJ1SgxtkPIv0vpUjrfcxPjNk2qz2PzCHVZYQg6ul0P5JaILi6K0Ds_F0P3yd8DSbzscipSt4bTu4jwCHYlG942avghTVv9mXzPF7cHJ6s"
    /// The same document from a producer using a smaller window: the stream
    /// begins `0x18`, not `0x78`.
    private let smallWindow =
        "GNNdy7EKgzAUQNFfkTsHUUGH9w3OLqVDkGdJ1SgxtkPIv0vpUjrfcxPjNk2qz2PzCHVZYQg6ul0P5JaILi6K0Ds_F0P3yd8DSbzscipSt4bTu4jwCHYlG942avghTVv9mXzPF7cHJ6s"
    /// `compressed` with its final checksum byte flipped. The deflate data is
    /// untouched, so only the Adler-32 check catches it.
    private let damaged =
        "eNpdy7EKgzAUQNFfkTsHUUGH9w3OLqVDkGdJ1SgxtkPIv0vpUjrfcxPjNk2qz2PzCHVZYQg6ul0P5JaILi6K0Ds_F0P3yd8DSbzscipSt4bTu4jwCHYlG942avghTVv9mXzPF7cHJ1Q"
    /// 172 characters that inflate to 9136 bytes.
    private let inflatesPastCap =
        "eNrt2jEKwkAYROGryNSLJEIs9gzWNmIRwh9ZjRtJNlEIe3cJWIhX8H3tmyPMoqZvW7Pr2Ed5ldtCToM14WGj_GlRCqkzeR1CvG2O-zXHPq1RLwAAAAAAAAAAAAAAAOAPyH1ONvKL5rqbTL6snKYYkrwuQ31XdnrWyYavya4qfjb5nN-OW6Zy"
    /// The same document gzipped — a real compression format, and not one of
    /// the two this transport defines.
    private let gzipped =
        "H4sIAAAAAAAAE13LsQqDMBRA0V-ROwdRQYf3Dc4upUOQZ0nVKDG2Q8i_S-lSOt9zE-M2TarPY_MIdVlhCDq6XQ_kloguLorQOz8XQ_fJ3wNJvOxyKlK3htO7iPAIdiUb3jZq-CFNW_2ZfM8X_rqjy30AAAA"

    @Test("a compressed payload yields the same document as the plain form")
    func decodesCompressed() throws {
        let r = try #require(try ShareLink.importDocument(from: link(compressed)).recipes.first)
        #expect(r.title == "Link V60")
        #expect(r.coffeeGrams == 15)
        #expect(r.waterGrams == 250)
    }

    @Test("a small-window stream decodes — the dispatch is on the nibble, not on 0x78")
    func decodesSmallWindow() throws {
        let r = try #require(try ShareLink.importDocument(from: link(smallWindow)).recipes.first)
        #expect(r.title == "Link V60")
    }

    @Test("a damaged compressed payload is rejected, not repaired")
    func rejectsDamaged() {
        #expect(throws: ImportError.transport(.damagedCompression)) {
            try ShareLink.importDocument(from: link(damaged))
        }
    }

    @Test("a payload that inflates past the cap is rejected at the cap")
    func rejectsInflationPastCap() {
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.importDocument(from: link(inflatesPastCap))
        }
    }

    @Test("a stream that inflates to nothing fails at the parser, not at the frame")
    func rejectsEmptyInflate() {
        // A well-formed zlib stream whose output is zero bytes: the dispatch and
        // the inflate both succeed, so the verdict belongs one step later.
        #expect(throws: ImportError.decode(.notJSON)) {
            try ShareLink.importDocument(from: link("eJwDAAAAAAE"))
        }
    }

    @Test("a third encoding is unrecognized rather than guessed at")
    func rejectsGzip() {
        #expect(throws: ImportError.transport(.unrecognizedEncoding)) {
            try ShareLink.importDocument(from: link(gzipped))
        }
    }

    @Test("a payload that is neither JSON nor a zlib stream is unrecognized")
    func rejectsArbitraryBytes() {
        // "[1,2,3]" — valid JSON, but a document is an object, so it never
        // reaches the parser.
        #expect(throws: ImportError.transport(.unrecognizedEncoding)) {
            try ShareLink.importDocument(from: link("WzEsMiwzXQ"))
        }
    }

    @Test("the plain form still decodes — both forms are read, permanently")
    func stillDecodesPlain() throws {
        let json = #"{"coffeejson":"1.0","recipes":[{"title":"Link V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#
        let payload = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let r = try #require(try ShareLink.importDocument(from: link(payload)).recipes.first)
        #expect(r.title == "Link V60")
    }

    @Test("this package still mints the plain form — producers convert last")
    func stillMintsPlain() throws {
        let document = try Codec.decodeDocument(Data(
            #"{"coffeejson":"1.0","recipes":[{"title":"Link V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#.utf8
        ))
        _ = document
        let url = try ShareLink.shareURL(
            forEncodedDocument: Data(#"{"coffeejson":"1.0","recipes":[]}"#.utf8),
            host: "example.com"
        )
        let minted = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value)
        // 'e' + 'y' is base64url for a payload beginning '{'.
        #expect(minted.hasPrefix("ey"))
    }
}
