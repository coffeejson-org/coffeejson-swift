import Foundation

/// Decodes and validates a CoffeeJSON document into an `ImportedDocument`.
///
/// The wire format is specified at <https://coffeejson.org>. Structural decoding
/// lives in the DTO layer (`Document`); this type owns the *format semantics*:
/// the version gate, required fields, unit conversion, and step/grind mapping.
/// Consumer-specific concerns — representable-range bounds, rescaling pours to a
/// storage model — live with the consumer.
public enum Codec {
    /// The one CoffeeJSON **major** version this build understands.
    public static let supportedMajorVersion = 1

    /// The version this build **emits**, stamped into every document `encode`
    /// produces. Its major is ``supportedMajorVersion``.
    public static let currentVersion = "1.0"

    /// The format's reserved media type — the `Content-Type` and `Accept` a
    /// CoffeeJSON document travels under. Registration awaits publication; until
    /// then it is the recommended type for headers and file associations.
    public static let mediaType = "application/vnd.coffeejson+json"

    /// Serialize a document to CoffeeJSON bytes with canonical **units** — the
    /// inverse of ``decodeDocument(_:)``. Nil fields are omitted, so no `null`s
    /// reach the wire.
    ///
    /// There is **no canonical byte form**, and not merely across encode paths:
    /// neither this one nor the overlay re-emit is order-stable, so encoding the
    /// same document twice in one process can produce two different byte strings.
    /// A content hash of these bytes identifies a *mint*, not a recipe — do not
    /// build a dedupe or identity contract on byte equality. Canonicalize first
    /// if you need one.
    public static func encode(_ document: Document) throws -> Data {
        var document = document
        // An emit states what *this* producer wrote, never what a decoded
        // envelope once said.
        document.version = currentVersion
        document.beans = document.beans?.map { normalizingLinkKeys($0, LinkingKeys.bean) }
        document.recipes = document.recipes?.map { normalizingLinkKeys($0, LinkingKeys.recipe) }
        document.tastings = document.tastings?.map { normalizingLinkKeys($0, LinkingKeys.tasting) }
        do {
            return try JSONEncoder().encode(document)
        } catch let error as EncodingError {
            // A `Double` JSON cannot write is the only way this fails. Rethrown
            // in this package's vocabulary: a caller matching on `ImportError`
            // cannot see an `EncodingError`.
            guard case let .invalidValue(_, context) = error else { throw ImportError.decode(.notJSON) }
            throw ImportError.validation(.nonRepresentableValue(field: leafFieldName(context.codingPath)))
        }
    }

    /// Decode a whole document into an `ImportedDocument`. Each collection is an
    /// array and an absent one reads as empty. Throws `.emptyDocument` when
    /// neither `beans` nor `recipes` carries anything — tastings alone do not
    /// make a document, because a tasting evaluates something.
    public static func decodeDocument(_ data: Data) throws -> ImportedDocument {
        let document = try decodedAndGated(data)
        // One untyped parse for every collection's verbatim slices. Best-effort:
        // a raw payload is what a consumer falls back *from*, never a condition
        // of import, so a failure here leaves `rawJSON` nil and nothing else.
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rawBeanSlices = rawObjects(in: root, key: "beans")
        let beans = (document.beans ?? []).enumerated().map { index, wire -> ImportedBean in
            var imported = importedBean(from: wire)
            imported.rawJSON = index < rawBeanSlices.count ? rawBeanSlices[index] : nil   // nil-in-place preserves alignment
            return imported
        }
        let rawSlices = rawObjects(in: root, key: "recipes")
        let recipes = try (document.recipes ?? []).enumerated().map { index, wire -> ImportedRecipe in
            var imported = try importedRecipe(from: wire)
            imported.rawJSON = index < rawSlices.count ? rawSlices[index] : nil
            return imported
        }
        guard !beans.isEmpty || !recipes.isEmpty else {
            throw ImportError.decode(.emptyDocument)
        }
        // Tastings carry no verbatim slice: nothing re-emits one, so capturing
        // the bytes would be fidelity that goes nowhere.
        let tastings = (document.tastings ?? []).map { importedTasting(from: $0, recipes: recipes) }
        return ImportedDocument(
            beans: beans, recipes: recipes, tastings: tastings, generator: document.generator)
    }

    /// Decode a single **recipe object**, not a document envelope — e.g. to read
    /// a stored raw payload on demand. No version gate, since there is no
    /// envelope; `rawJSON` is set to the input. Throws ``ImportError`` only,
    /// never a Foundation `DecodingError`.
    public static func importedRecipe(from data: Data) throws -> ImportedRecipe {
        var imported = try importedRecipe(from: decodeObject(Recipe.self, from: data))
        imported.rawJSON = data
        return imported
    }

    /// The bean counterpart of ``importedRecipe(from:)``, on the same terms.
    public static func importedBean(from data: Data) throws -> ImportedBean {
        var imported = importedBean(from: try decodeObject(Bean.self, from: data))
        imported.rawJSON = data
        return imported
    }

    /// JSON-decode a bare `recipe` or `bean` object, reporting failures as
    /// ``ImportError``.
    ///
    /// `envelopeKey: nil` is what makes this object mode: with no `coffeejson`
    /// member out here, no key is the format's identity and no fault can be a
    /// verdict on the envelope, so a missing key names itself and a wrong type
    /// names its field, both without exception.
    private static func decodeObject<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Before parsing, for the reason ``decodedAndGated(_:)`` gives.
        guard String(data: data, encoding: .utf8) != nil else { throw ImportError.decode(.notUTF8) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw importError(from: error, envelopeKey: nil)
        } catch {
            throw ImportError.decode(.notJSON)
        }
    }

    /// The document's already-parsed root, sliced per element of one collection.
    ///
    /// Takes the parsed root rather than the bytes because every collection comes
    /// out of the same document: parsing per call meant three passes over one
    /// payload. The transport caps a share link, but this decoder is public and
    /// uncapped, so a document read from a file paid that in full.
    private static func rawObjects(in root: [String: Any], key: String) -> [Data?] {
        guard let elements = root[key] as? [Any] else { return [] }
        // Index-preserving on purpose: a slice that fails to re-serialize maps
        // to nil in place, so a later element can never inherit an earlier
        // element's bytes (`rawJSON` attaches by position).
        return elements.map { try? JSONSerialization.data(withJSONObject: $0) }
    }

    /// JSON-decode the envelope and apply the version gate.
    ///
    /// Three failures, not one, matching the names the scan-vector corpus uses:
    /// `.notUTF8` for bytes that are not text, `.notJSON` for text that is not
    /// JSON, `.notADocument` for JSON that is not this format. A reader told only
    /// "malformed" cannot tell which of the three to fix. Faults *inside* a
    /// document are a fourth thing and name their field instead.
    private static func decodedAndGated(_ data: Data) throws -> Document {
        // Before parsing: JSONDecoder reports a UTF-8 fault and a syntax fault
        // through one case, and they are different defects.
        guard String(data: data, encoding: .utf8) != nil else { throw ImportError.decode(.notUTF8) }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch let error as DecodingError {
            throw importError(from: error, envelopeKey: "coffeejson")
        } catch {
            throw ImportError.decode(.notJSON)
        }
        // Support is decided by the MAJOR component; forward-compat handles
        // minors. Equality, not a ceiling: a build implements the majors it
        // carries, and it carries exactly one. An older major is a different set
        // of rules, not a subset of this one.
        let major = majorVersion(document.version)
        guard major == supportedMajorVersion else {
            throw ImportError.decode(.unsupportedVersion(
                documentMajor: major, supportedMajor: supportedMajorVersion))
        }
        return document
    }

    /// Translate a `DecodingError` into this package's vocabulary.
    ///
    /// `envelopeKey` names the member carrying the format's identity, and passing
    /// it is what makes this the *envelope* reading. With it, two faults are
    /// verdicts on the format rather than on a field, and they are the two the
    /// spec's reference reader stops at: a document lacking that key is not this
    /// format, and one whose identity member is not a string leaves it unreadable.
    /// Pass `nil` for a bare object, where no key can mean either thing.
    ///
    /// Everything else names a field. The blast radius is unchanged — the whole
    /// parse still fails — but `.notADocument` for one bad value would say the
    /// format was wrong when one field was.
    private static func importError(
        from error: DecodingError, envelopeKey: String?
    ) -> ImportError {
        if case let .keyNotFound(key, _) = error {
            if let envelopeKey, key.stringValue == envelopeKey { return .decode(.notADocument) }
            return .validation(.missingRequiredField(key.stringValue))
        }
        if case let .typeMismatch(_, context) = error {
            let named = context.codingPath.filter { $0.intValue == nil }
            guard let field = named.last?.stringValue else {
                // JSON that is not an object names no field in the first place.
                return .decode(.notADocument)
            }
            if let envelopeKey, named.count == 1, field == envelopeKey { return .decode(.notADocument) }
            return .validation(.wrongFieldType(field: field))
        }
        return .decode(.notJSON)
    }

    /// The leaf of a coding path, or the empty string when it names none. The
    /// leaf and not the path: an array index is where a fault sat, not what is
    /// wrong with it, and the wire key is the name the document itself uses.
    private static func leafFieldName(_ codingPath: [any CodingKey]) -> String {
        codingPath.filter { $0.intValue == nil }.last?.stringValue ?? ""
    }

    /// The major of the wire's `MAJOR.MINOR` version, or `nil` for a string
    /// outside that grammar.
    ///
    /// The spec states two components and no patch, so `"1"` and `"1.0.0"` are
    /// both unreadable rather than generously rounded to 1. ASCII digits only —
    /// `Int` would otherwise accept other scripts' digits and a `+`/`-` sign —
    /// and no leading zero on the major, which would be a second spelling of one
    /// number.
    private static func majorVersion(_ version: String) -> Int? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy(isASCIIDigits),
              parts[0] == "0" || !parts[0].hasPrefix("0")
        else { return nil }
        return Int(parts[0])
    }

    private static func isASCIIDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }
}

/// Unicode NFC on the format's linking keys, for both producer paths.
extension Codec {
    /// Every key association matches on, paired with the wire name it carries.
    ///
    /// A reference matches byte for byte, so a producer emits all of these in
    /// NFC — two normalization forms of one visible string otherwise fail to
    /// link, silently (spec envelope § Association). One table, because a key
    /// one producer path knows and the other does not is that same silence.
    struct LinkingKey<Element> {
        let property: WritableKeyPath<Element, String?>
        let wireName: String
    }

    // Computed, because a `WritableKeyPath` is not `Sendable` and a stored
    // static would be shared mutable state to the compiler. Three literals.
    enum LinkingKeys {
        static var bean: [LinkingKey<Bean>] {
            [.init(property: \.id, wireName: Bean.WireKey.id.rawValue)]
        }
        static var recipe: [LinkingKey<Recipe>] {
            [.init(property: \.id, wireName: Recipe.WireKey.id.rawValue),
             .init(property: \.beanRef, wireName: Recipe.WireKey.beanRef.rawValue)]
        }
        static var tasting: [LinkingKey<Tasting>] {
            [.init(property: \.id, wireName: Tasting.CodingKeys.id.rawValue),
             .init(property: \.recipeRef, wireName: Tasting.CodingKeys.recipeRef.rawValue),
             .init(property: \.beanRef, wireName: Tasting.CodingKeys.beanRef.rawValue)]
        }
    }

    /// A typed element with its linking keys in NFC — the ``encode(_:)`` path,
    /// where each key is a property.
    static func normalizingLinkKeys<Element>(
        _ element: Element, _ links: [LinkingKey<Element>]
    ) -> Element {
        var element = element
        for link in links {
            element[keyPath: link.property] =
                element[keyPath: link.property]?.precomposedStringWithCanonicalMapping
        }
        return element
    }

    /// A merged element with its linking keys in NFC — the overlay path, where
    /// each key is a wire name and a non-string value is left alone, because
    /// coercing one would destroy the caller's data.
    static func normalizingLinkKeys<Element>(
        _ links: [LinkingKey<Element>], in element: [String: Any]
    ) -> [String: Any] {
        var element = element
        for link in links {
            guard let value = element[link.wireName] as? String else { continue }
            element[link.wireName] = value.precomposedStringWithCanonicalMapping
        }
        return element
    }
}
