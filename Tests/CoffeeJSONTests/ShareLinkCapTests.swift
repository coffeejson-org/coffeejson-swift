import Testing
import Foundation
@testable import CoffeeJSON

/// The transport cap's boundary on a compressed payload.
///
/// These payloads are built rather than borrowed, because the case only exists
/// for input no compressor shrinks: the streams are framed as stored deflate
/// blocks, the shape a compressor falls back to when its input does not
/// compress, so the encoded link is longer than the same document sent plain.
@Suite("ShareLink payload cap")
struct ShareLinkCapTests {
    /// A document of exactly `bytes` bytes whose `notes` string is noise.
    private func document(ofBytes bytes: Int) -> Data {
        let prefix = #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"notes":""#
        let suffix = #""}]}"#
        return Data((prefix + noise(bytes - prefix.count - suffix.count) + suffix).utf8)
    }

    /// Deterministic base64-alphabet noise, so a failure reproduces.
    private func noise(_ count: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var state: UInt64 = 0x2545_F491
        return String((0 ..< count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return alphabet[Int((state >> 33) % 64)]
        })
    }

    /// `data` in a zlib frame (RFC 1950) carrying `blocks` stored deflate
    /// blocks: 2-byte header, then per block `BFINAL | BTYPE 00`, LEN, its
    /// complement and the bytes, and the big-endian Adler-32.
    private func zlibStored(_ data: Data, blocks: Int = 1) -> Data {
        var out = Data([0x78, 0x01])
        let size = (data.count + blocks - 1) / blocks
        for start in stride(from: 0, to: data.count, by: size) {
            let chunk = data[start ..< Swift.min(start + size, data.count)]
            let length = UInt16(chunk.count)
            out.append(contentsOf: [
                start + size >= data.count ? 0x01 : 0x00,
                UInt8(length & 0xFF), UInt8(length >> 8),
                UInt8(~length & 0xFF), UInt8(~length >> 8),
            ])
            out.append(chunk)
        }
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let checksum = (b << 16) | a
        out.append(contentsOf: (0 ..< 4).map { UInt8((checksum >> (24 - 8 * $0)) & 0xFF) })
        return out
    }

    private func link(_ payload: Data) throws -> URL {
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try #require(URL(string: "https://example.com/r?d=\(encoded)"))
    }

    private func encodedLength(_ url: URL) throws -> Int {
        try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value).count
    }

    @Test("an incompressible document at the cap imports in its compressed form")
    func incompressibleAtTheCapImports() throws {
        let url = try link(zlibStored(document(ofBytes: ShareLink.maxPayloadBytes)))
        // The link this case is about: past the plain form's bound, and legal.
        #expect(try encodedLength(url) > ShareLink.maxEncodedLength)
        let recipe = try #require(try ShareLink.importDocument(from: url).recipes.first)
        #expect(recipe.title == "x")
    }

    @Test("the same document one byte over the cap is refused")
    func incompressibleOverTheCapIsRefused() throws {
        let url = try link(zlibStored(document(ofBytes: ShareLink.maxPayloadBytes + 1)))
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.importDocument(from: url)
        }
    }

    @Test("a stream of many stored blocks imports, however long the frame runs")
    func manyStoredBlocksImport() throws {
        // A conformant stream may carry any number of stored blocks, each with
        // 5 bytes of framing, so its own length has no upper bound — only its
        // output does. 200 blocks put this link far past the plain form's bound.
        let url = try link(zlibStored(document(ofBytes: ShareLink.maxPayloadBytes), blocks: 200))
        #expect(try encodedLength(url) > ShareLink.maxEncodedLength + 1000)
        let recipe = try #require(try ShareLink.importDocument(from: url).recipes.first)
        #expect(recipe.title == "x")
    }

    @Test("the same many-block stream one byte over the cap is refused by the inflater")
    func manyStoredBlocksOverTheCapAreRefused() throws {
        let url = try link(zlibStored(document(ofBytes: ShareLink.maxPayloadBytes + 1), blocks: 200))
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.importDocument(from: url)
        }
    }
}
