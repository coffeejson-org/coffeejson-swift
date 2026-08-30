import Testing
import Foundation
@testable import CoffeeJSON

/// `importDocument(fromScanned:)` — the string-in, document-out entry a scanner
/// actually needs. These mirror the format's published scan-vector corpus,
/// scheme cases included: a `javascript:` or `data:` URL can carry a
/// well-formed payload, so the scheme check runs before the payload is read.
@Suite("Scanned link")
struct ScannedLinkTests {
    /// A valid minimal document, plain-JSON payload, on a foreign host.
    private let link = "https://apps.example/r?d=eyJjb2ZmZWVqc29uIjoiMS4wIiwicmVjaXBlcyI6W3sidGl0bGUiOiJFdmVyeWRheSBWNjAiLCJjb2ZmZWUiOnsidmFsdWUiOjE1LCJ1bml0IjoiZ3JhbSJ9LCJ3YXRlciI6eyJ2YWx1ZSI6MjUwLCJ1bml0IjoiZ3JhbSJ9fV19"

    @Test("a scanned share link on any host yields its document")
    func acceptsAnyHost() throws {
        let doc = try ShareLink.importDocument(fromScanned: link)
        #expect(doc.recipes.first?.title == "Everyday V60")
    }

    @Test("plain text is refused as text, never searched for a payload")
    func plainTextRejected() {
        #expect(throws: ImportError.transport(.notAURL)) {
            try ShareLink.importDocument(fromScanned: "Everyday V60 — 15 g / 250 g")
        }
    }

    @Test("a valid payload on a javascript: scheme is refused for the scheme")
    func hostileSchemeRejectedBeforeDecoding() throws {
        // The payload here is the SAME one `acceptsAnyHost` decodes. The point
        // is that a correct implementation never gets far enough to notice —
        // rejecting on content would let a `javascript:` URL through whenever
        // its payload happened to be well-formed.
        let payload = String(link.split(separator: "=", maxSplits: 1)[1])
        for hostile in ["javascript:alert(1)?d=\(payload)", "data:text/html,<b>x</b>?d=\(payload)"] {
            do {
                _ = try ShareLink.importDocument(fromScanned: hostile)
                Issue.record("decoded a \(hostile.prefix(11)) URL")
            } catch let error as ImportError {
                if case .transport(.notHTTP) = error {} else {
                    Issue.record("rejected as \(error), not for its scheme")
                }
            } catch {
                Issue.record("threw \(error)")
            }
        }
    }

    @Test("the scheme check is case-insensitive")
    func schemeCaseInsensitive() throws {
        let doc = try ShareLink.importDocument(fromScanned: link.replacingOccurrences(
            of: "https://", with: "HTTPS://"))
        #expect(doc.recipes.count == 1)
    }

    @Test("payload failures keep their own names — the scheme gate adds no dialect")
    func payloadReasonsUnchanged() {
        #expect(throws: ImportError.transport(.noPayload)) {
            try ShareLink.importDocument(fromScanned: "https://apps.example/r")
        }
        #expect(throws: ImportError.transport(.malformedBase64)) {
            try ShareLink.importDocument(fromScanned: "https://apps.example/r?d=!!!not-base64url")
        }
    }
}
