import Compression
import Foundation

/// Parses and builds a CoffeeJSON **share link**, which carries the whole
/// document inside the URL and so works offline with no backend:
///
///     https://<host>/r?d=<base64url( utf8( CoffeeJSON-document-JSON ) )>
///     myapp://import?d=<base64url( … )>             // custom-scheme handoff
///
/// The payload rides in the `d` **query** item, not a `#fragment`: messaging
/// linkifiers keep the query and drop a trailing fragment, leaving it
/// un-tappable. The trade-off is that the payload is visible to the `/r` host on
/// a web-fallback open, accepted so the host can render a preview card; an
/// app→app Universal Link still hands off on-device.
///
/// Parsing reads the `?d=` query item **only**. The transport defines no
/// `#fragment` form and nothing emits one, so reading one would be tolerance
/// nobody can rely on and nobody can safely remove later.
///
/// This type deliberately shares its name with SwiftUI's `ShareLink` view — the
/// spec noun wins, and a SwiftUI-importing consumer qualifies it as
/// `CoffeeJSON.ShareLink`.
///
/// The `for:` label of ``shareURL(for:scheme:host:path:)`` is one consumers
/// extend with overloads on their own types, so another `for:` overload here is
/// a source break to price rather than an addition.
public enum ShareLink {
    /// Hard cap on the payload, in **decoded** bytes — the transport contract
    /// (<https://coffeejson.org/docs/transport.md>: "8192 bytes (decoded)").
    /// Counting the *encoded* string instead would cap the document at ~6 KB,
    /// because base64 expands 4/3, rejecting documents the spec accepts.
    ///
    /// Measured against ``Codec/encode(_:)``'s output, not the URL's length.
    /// ``ImportError/Transport/tooLarge`` is the enforcement.
    public static let maxPayloadBytes = 8192

    /// Cheap pre-decode guard on a **plain** payload's encoded string, so a
    /// pathological URL is rejected without allocating its decode: `⌈8192 × 4/3⌉`,
    /// the longest base64url that can still decode to within ``maxPayloadBytes``.
    ///
    /// It bounds the document only because it rests on base64's fixed 4/3
    /// expansion, and it is the **plain** form's alone. Nothing like it bounds a
    /// compressed payload: a conformant zlib stream may carry any number of
    /// stored blocks, each with 5 bytes of framing, so a stream inflating to
    /// within ``maxPayloadBytes`` has no upper bound on its own length. The spec
    /// bounds the output, and ``inflated(_:)`` enforces that.
    static let maxEncodedLength = 10_924

    /// Parse a share link into a validated `ImportedDocument`.
    public static func importDocument(from url: URL) throws -> ImportedDocument {
        try Codec.decodeDocument(payload(from: url))
    }

    /// Parse whatever a scanner handed you: a `String` in, a document or a
    /// stated reason out. A QR scanner produces text rather than a `URL`, and the
    /// steps between the two — require http(s), read `d`, dispatch the payload on
    /// one byte and never retry the other form — are where the binding gets
    /// implemented wrong. This is those steps, once.
    ///
    /// **The scheme is checked before the payload is read.** An implementation
    /// that decodes first and checks later has already treated hostile input as a
    /// share link, and a consumer that then opens what it scanned has executed
    /// it. The format's scan-vector corpus pins this case by name.
    ///
    /// Any host is accepted: a share link is self-contained, so refusing one for
    /// arriving on someone else's domain would make the format a walled garden,
    /// and the host is safe to ignore because nothing is trusted to it.
    public static func importDocument(fromScanned scanned: String) throws -> ImportedDocument {
        guard let url = URL(string: scanned), url.scheme != nil else {
            throw ImportError.transport(.notAURL)
        }
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else {
            throw ImportError.transport(.notHTTP(scheme: url.scheme))
        }
        return try importDocument(from: url)
    }

    /// Build a share link: `<scheme>://<host><path>?d=<base64url(utf8(json))>`.
    ///
    /// `scheme` / `host` / `path` are injected so this layer stays neutral. The
    /// defaults yield a Universal Link `https://<host>/r?d=…`; a caller can also
    /// build a custom-scheme handoff `<scheme>://<host>?d=…`.
    ///
    /// Throws ``ImportError/Transport/tooLarge`` past ``maxPayloadBytes``, and
    /// propagates whatever ``Codec/encode(_:)`` throws — in practice
    /// ``ImportError/Validation/nonRepresentableValue(field:)``. Either way it is
    /// an ``ImportError``, never a Foundation `EncodingError`.
    public static func shareURL(
        for document: Document,
        scheme: String = "https",
        host: String,
        path: String = "/r"
    ) throws -> URL {
        try shareURL(forEncodedDocument: try Codec.encode(document), scheme: scheme, host: host, path: path)
    }

    /// Build a share link from an **already-encoded** document — for a consumer
    /// that assembles the payload bytes itself, to carry fields the typed
    /// `Document` cannot express. Same transport and cap as
    /// ``shareURL(for:scheme:host:path:)``.
    public static func shareURL(
        forEncodedDocument data: Data,
        scheme: String = "https",
        host: String,
        path: String = "/r"
    ) throws -> URL {
        guard data.count <= maxPayloadBytes else {
            throw ImportError.transport(.tooLarge)
        }
        let payload = base64URLEncoded(data)
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: "d", value: payload)]
        guard let url = components.url else {
            throw ImportError.transport(.invalidLink)
        }
        return url
    }

    /// The link's payload bytes, base64url-decoded and **uncapped** — or `nil`
    /// when the URL carries no usable `d`.
    ///
    /// For triage: a caller deciding whether a URL is one of this format's, or
    /// what it carries, before committing to a decode. ``importDocument(from:)``
    /// is the entry point that parses and validates; this is the bytes alone.
    ///
    /// **It does not enforce ``maxPayloadBytes``, deliberately.** That constant
    /// is public so a caller applies it where its own policy says to, which may
    /// be nowhere; `importDocument` remains the capped default.
    ///
    /// Uncapped is safe only because there is **no decompression branch** here:
    /// base64's fixed 3/4 ratio bounds the output by the input. The compressed
    /// read path stays inside the capped entry point, where its bomb bound is
    /// enforced — do not add a zlib branch here.
    ///
    /// So these are the **payload** bytes as sent, not necessarily a document: a
    /// compressed link from another implementation yields its compressed stream.
    /// Feed such a link to ``importDocument(from:)``, which reads both.
    ///
    /// `nil` covers no `d`, an empty one, and one that is not base64url — three
    /// cases a triaging caller treats alike, so nothing here throws.
    public static func payloadBytes(from url: URL) -> Data? {
        guard let encoded = encodedPayload(from: url) else { return nil }
        return base64URLDecoded(encoded)
    }

    /// The `d` query item's value, or `nil` when it is absent or empty. A
    /// `#fragment` is not parsed.
    private static func encodedPayload(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value,
              !encoded.isEmpty else { return nil }
        return encoded
    }

    /// Extract and base64url-decode the `d` query item, capped.
    static func payload(from url: URL) throws -> Data {
        guard let encoded = encodedPayload(from: url) else {
            throw ImportError.transport(.noPayload)
        }
        // Only the plain form has a length a bound can be derived for, so the
        // discriminator is read from the first quantum before it applies. A
        // quantum that does not decode skips the guard and fails at the full
        // decode, which names the fault properly.
        if firstPayloadByte(ofBase64URL: encoded) == 0x7B, encoded.count > maxEncodedLength {
            throw ImportError.transport(.tooLarge)
        }
        guard let data = base64URLDecoded(encoded) else {
            throw ImportError.transport(.malformedBase64)
        }
        return try documentBytes(from: data)
    }

    /// The payload's first byte, read from its first base64url quantum alone —
    /// four characters, three bytes — or `nil` when that quantum does not decode.
    private static func firstPayloadByte(ofBase64URL encoded: String) -> UInt8? {
        base64URLDecoded(String(encoded.prefix(4)))?.first
    }

    /// The encoding discriminator: one byte, decided once, never retried.
    ///
    /// A document is a JSON *object*, so a plain payload begins `{`; a zlib
    /// stream (RFC 1950) carries CM 8 in its first byte's low nibble and passes
    /// the header's modulo-31 check, which `0x7B` cannot. The two forms cannot
    /// overlap.
    ///
    /// Two rules that are wrong to "simplify": the test is on the **nibble**, not
    /// on `0x78`, because a producer using a smaller window legitimately emits
    /// `0x08`–`0x68`; and the branch is committed to *before* either form is
    /// attempted, because parsing first and decompressing on failure would put
    /// back the ambiguity the discriminator exists to remove.
    static func documentBytes(from payload: Data) throws -> Data {
        let data = Data(payload) // normalize indices; a slice may not start at 0
        guard let first = data.first else { throw ImportError.transport(.unrecognizedEncoding) }
        if first == 0x7B {
            guard data.count <= maxPayloadBytes else { throw ImportError.transport(.tooLarge) }
            return data
        }
        guard data.count > 1 else { throw ImportError.transport(.unrecognizedEncoding) }
        let second = data[1]
        let isZlib = first & 0x0F == 8
            && second & 0x20 == 0 // no preset dictionary
            && (Int(first) << 8 | Int(second)) % 31 == 0
        guard isZlib else { throw ImportError.transport(.unrecognizedEncoding) }
        return try inflated(data)
    }

    /// Decompress a zlib stream, refusing to produce more than
    /// ``maxPayloadBytes``.
    ///
    /// Apple's Compression framework speaks raw DEFLATE and knows nothing of the
    /// zlib frame, so the 2-byte header and the trailing big-endian Adler-32 are
    /// handled here. The checksum is not optional: damage that leaves the deflate
    /// data intact — a mangled tail — is invisible without it.
    ///
    /// The destination is deliberately **one byte larger than the cap**.
    /// `compression_decode_buffer` fills the buffer and returns its size when the
    /// output does not fit, with no error, so a buffer of exactly the cap could
    /// not tell a document of exactly 8192 bytes from a truncated megabyte. One
    /// extra byte makes the overrun observable and bounds the memory an attacker
    /// can cost us at 8 KiB either way.
    private static func inflated(_ data: Data) throws -> Data {
        // 2 header bytes, at least 1 deflate byte, 4 checksum bytes.
        guard data.count >= 7 else { throw ImportError.transport(.damagedCompression) }
        let deflate = data.subdata(in: 2 ..< (data.count - 4))
        let expected = data.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        let capacity = maxPayloadBytes + 1
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { destination -> Int in
            deflate.withUnsafeBytes { source -> Int in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity, src, deflate.count, nil, COMPRESSION_ZLIB)
            }
        }
        // A stream can legitimately inflate to nothing, and the decoder reports
        // that with the same 0 it reports a failure with. The frame's checksum
        // separates them — Adler-32 over no bytes is 1 — so an empty inflate
        // fails at the parser, where the corpus puts it, not at the frame.
        guard written > 0 || expected == 1 else { throw ImportError.transport(.damagedCompression) }
        guard written <= maxPayloadBytes else { throw ImportError.transport(.tooLarge) }
        out.removeSubrange(written ..< capacity)
        guard adler32(out) == expected else { throw ImportError.transport(.damagedCompression) }
        return out
    }

    /// Adler-32 (RFC 1950 §9), the checksum in a zlib frame's tail.
    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }

    /// Unpadded base64url: `+`→`-`, `/`→`_`, and no `=` padding.
    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The inverse of ``base64URLEncoded``, or `nil` for invalid base64url.
    private static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
