import Foundation

/// Why a CoffeeJSON document could not be imported.
///
/// Three layers, because a reader that cannot tell them apart cannot say
/// anything useful. Retrying helps for a transport fault and never for the other
/// two; only validation can name what to fix.
///
/// Representable-range bounds are deliberately absent. A value outside what a
/// *consumer* can store is that consumer's policy and its own error to declare;
/// this type describes the format, not anyone's model of it.
public enum ImportError: Error, Equatable, Sendable {
    /// The link, the URL, or the payload envelope — nothing was decoded yet.
    case transport(Transport)
    /// Bytes were read, and they are not this format.
    case decode(Decode)
    /// A document decoded, and then failed one of the format's own rules — a
    /// fault *in* a document rather than a verdict on the format, which is why
    /// it names a field instead of indicting the whole thing.
    case validation(Validation)

    // The `Transport` and `Decode` case names are the format's published
    // scan-vector corpus, in the order a decode meets them, so an implementation
    // in any language runs that corpus and reports the same outcomes. Renaming
    // one here without renaming it there puts two dialects on one operation.

    /// The failure's name in the format's shared vocabulary — the same twelve
    /// tokens `@coffeejson/core` vends as `DECODE_ERROR_KINDS`, so a report, a
    /// log line or a metric reads the same across implementations.
    ///
    /// `nil` where the format names no kind: every validation fault, which is a
    /// fault *in* a document rather than a verdict on it, and a link this
    /// package could not build, which is a producer's fault and not a reader's.
    public var kind: Kind? {
        switch self {
        case .transport(.noPayload): .noPayload
        case .transport(.malformedBase64): .malformedBase64
        case .transport(.unrecognizedEncoding): .unrecognizedEncoding
        case .transport(.damagedCompression): .damagedCompression
        case .transport(.tooLarge): .tooLarge
        case .transport(.notAURL): .notAURL
        case .transport(.notHTTP): .notHTTP
        case .transport(.invalidLink): nil
        case .decode(.notUTF8): .notUTF8
        case .decode(.notJSON): .notJSON
        case .decode(.notADocument): .notADocument
        case .decode(.emptyDocument): .emptyDocument
        case .decode(.unsupportedVersion): .unsupportedVersion
        case .validation: nil
        }
    }

    /// The names ``ImportError/kind`` reports, in the order a decode meets them.
    /// A raw value is the format's token and is pinned by the shared
    /// scan-vector corpus; renaming one here alone puts two dialects on one
    /// operation.
    public enum Kind: String, Sendable, CaseIterable {
        case notAURL = "not_a_url"
        case notHTTP = "not_http"
        case noPayload = "no_payload"
        case malformedBase64 = "malformed_base64"
        case unrecognizedEncoding = "unrecognized_encoding"
        case damagedCompression = "damaged_compression"
        case tooLarge = "too_large"
        case notUTF8 = "not_utf8"
        case notJSON = "not_json"
        case notADocument = "not_a_document"
        case unsupportedVersion = "unsupported_version"
        case emptyDocument = "empty_document"
    }

    /// Nothing was read: the link, the URL, or the payload envelope was wrong
    /// before any bytes could become JSON.
    public enum Transport: Error, Equatable, Sendable {
        /// No `d` parameter, or an empty one.
        case noPayload
        /// Characters outside the base64url alphabet.
        case malformedBase64
        /// The first byte is neither `{` nor a zlib header.
        case unrecognizedEncoding
        /// A bad zlib frame, or a failed checksum.
        case damagedCompression
        /// Over the 8192-byte cap, as sent or after inflating.
        case tooLarge
        /// The scanned text is not a URL at all — a QR carrying plain text.
        /// ``ShareLink/importDocument(fromScanned:)`` only.
        case notAURL
        /// A URL on a scheme the binding does not define — `javascript:`,
        /// `data:`. Refused for its scheme **before** the payload is read, so a
        /// valid payload on a hostile scheme never reaches a decoder.
        /// ``ShareLink/importDocument(fromScanned:)`` only.
        case notHTTP(scheme: String?)
        /// The link could not be built or read as a URL — a producer-side
        /// failure, not a payload one.
        case invalidLink
    }

    /// Bytes were read and are not this format. Retrying will not help.
    public enum Decode: Error, Equatable, Sendable {
        case notUTF8
        /// Valid UTF-8, but not JSON.
        case notJSON
        /// JSON, but not a CoffeeJSON document — no `coffeejson` member, or one
        /// that is not a string. A string member states a version, so its fault
        /// is ``unsupportedVersion(documentMajor:supportedMajor:)``.
        case notADocument
        /// Neither a non-empty `beans` nor a non-empty `recipes` collection.
        ///
        /// A decode verdict rather than a validation one: the corpus reaches it
        /// in the order a decode meets it, before any rule about content runs.
        case emptyDocument
        /// The document's major version is not the one this build supports.
        ///
        /// `documentMajor` is `nil` when the `coffeejson` member is not the
        /// format's `MAJOR.MINOR` grammar: a string stating no major is as
        /// unreadable as one stating a major nobody implements.
        case unsupportedVersion(documentMajor: Int?, supportedMajor: Int)
    }

    /// A document that decoded, and then failed one of the format's rules. These
    /// carry detail the decode cases do not, and they are not part of the
    /// cross-language vocabulary.
    public enum Validation: Error, Equatable, Sendable {
        /// A required field (`title`, `coffee`, and `water` or `yield` per the
        /// recipe's basis) was absent — or, for a measurement, carried a unit
        /// this package does not recognize, which reads as absent.
        case missingRequiredField(String)
        /// A modeled field carried the wrong JSON type, named by its **wire
        /// key** so the name matches what the document says.
        ///
        /// Deliberately outside the shared decode vocabulary: the corpus reaches
        /// its verdict from the envelope alone and never inspects a field, so an
        /// implementation running it still reports `not_a_document` for every
        /// input the corpus defines. This only splits inputs it never reaches.
        case wrongFieldType(field: String)
        /// A numeric field carried a value JSON has no way to write — an
        /// infinity or a NaN — named by its **wire key**, or by the empty string
        /// when the encoder's coding path names no field.
        ///
        /// The one *emit*-side failure, since a decoder never meets one.
        /// Reported rather than coerced because there is no honest substitute:
        /// writing `0`, or dropping the field, would put a number on the wire
        /// the producer never stated.
        case nonRepresentableValue(field: String)
    }
}
