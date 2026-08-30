import Foundation

/// A JSON Schema (draft 2020-12 *subset*) validator — exactly the keywords the
/// CoffeeJSON 1.0 schema uses (`type`, `required`, `properties`, `items`,
/// `enum`, `const`, `pattern`, `minimum`/`exclusiveMinimum`/`maximum`,
/// `minItems`/`minLength`, `$ref`, `allOf`, `anyOf`, `if`/`then`/`else`,
/// `dependentSchemas`, `dependentRequired`, `propertyNames`,
/// `additionalProperties`, and boolean subschemas).
///
/// **For test targets.** It answers the question a producer of this format has
/// to answer about itself: *does what I encode conform to the published
/// schema?* Nothing else reads a document a producer **writes** back against the
/// rules the format states — a decoder's coverage of the schema's keys only
/// proves it can read them.
///
/// It is not a JSON Schema library, and it refuses to look like one: a keyword
/// in schema position that it does not implement is reported as an error on
/// every document it appears in, rather than skipped. A subset that silently
/// ignores what it does not know is a gate that quietly stops enforcing a rule
/// the moment the schema gains one. ``unimplementedKeywords(in:)`` is the same
/// check over a whole schema, including the branches no test document reaches.
///
/// `format` is deliberately an annotation (the draft-2020-12 default), which is
/// sufficient here: no fixture in the format's corpus is rejected on `format`
/// alone. Booleans are distinguished from numbers via `CFBoolean`, so a
/// `type: number` schema never accepts `true`.
public struct SchemaValidator {
    /// Every keyword this validator acts on, as data rather than as prose in the
    /// comment above, so a check can compare it against a schema.
    ///
    /// Annotations are listed too, though they assert nothing. Their presence is
    /// what makes "unlisted means unenforced" true: a keyword absent here is
    /// absent because nobody has considered it, not because it was judged inert.
    public static let understoodKeywords: Set<String> = [
        // Asserted.
        "type", "required", "properties", "items", "enum", "const", "pattern",
        "minimum", "exclusiveMinimum", "maximum", "minItems", "minLength",
        "$ref", "allOf", "anyOf", "if", "then", "else", "dependentSchemas",
        "dependentRequired", "propertyNames", "additionalProperties",
        // Annotations and document furniture — inert by design, not by neglect.
        "$schema", "$id", "$defs", "$comment", "title", "description",
        "examples", "default", "format", "deprecated", "readOnly", "writeOnly",
    ]

    public let root: [String: Any]

    /// A validator over one parsed schema — `JSONSerialization`'s object for the
    /// published `coffeejson-1.0.schema.json`, which ``SchemaSource`` loads.
    public init(schema: [String: Any]) { self.root = schema }

    /// True when the instance conforms to the whole schema.
    public func isValid(_ instance: Any) -> Bool { validate(instance).isEmpty }

    /// Validation error strings, empty when valid. Paths are for diagnostics only.
    public func validate(_ instance: Any) -> [String] {
        validate(instance, against: root, at: "")
    }

    /// The keywords `schema` uses in schema position that this validator does
    /// not implement — empty when the subset is complete for that schema.
    ///
    /// Assert on this once in a test target, alongside the document cases. A
    /// document-level run only reaches the branches its documents exercise;
    /// this walks every branch, so a rule stated in one nobody tests still
    /// reports.
    public static func unimplementedKeywords(in schema: [String: Any]) -> [String] {
        var used: Set<String> = []
        keywords(inSchema: schema, into: &used)
        return used.subtracting(understoodKeywords).sorted()
    }

    /// Collect the keywords used in every **schema position** of a document.
    ///
    /// Position matters, and a naive walk over every key is wrong: in
    /// `{"properties": {"type": {...}}}` the inner `type` is a *field name* the
    /// format defines, not a keyword. So the walk descends deliberately —
    /// `properties` and `$defs` hold maps of name→schema, `items`/`if`/`then`/
    /// `else` hold one schema, `allOf`/`anyOf` hold arrays of them — and reads
    /// keys only where a schema actually is.
    static func keywords(inSchema node: Any, into found: inout Set<String>) {
        guard let schema = node as? [String: Any] else { return }
        for (key, value) in schema {
            found.insert(key)
            switch key {
            case "properties", "$defs", "dependentSchemas":
                for (_, sub) in (value as? [String: Any]) ?? [:] {
                    keywords(inSchema: sub, into: &found)
                }
            case "items", "if", "then", "else", "not", "additionalProperties", "contains":
                keywords(inSchema: value, into: &found)
            case "allOf", "anyOf", "oneOf", "prefixItems":
                for sub in (value as? [Any]) ?? [] {
                    keywords(inSchema: sub, into: &found)
                }
            default:
                break // a value, not a schema — its keys are data
            }
        }
    }

    private func validate(_ instance: Any, against schemaAny: Any, at path: String) -> [String] {
        // A boolean subschema: `true` accepts anything, `false` rejects anything
        // (the espresso branch uses `water: false` / `ratio: false`).
        if isBoolean(schemaAny) {
            return (schemaAny as? NSNumber)?.boolValue == true ? [] : ["\(path): must not be present"]
        }
        guard let schema = schemaAny as? [String: Any] else { return [] }
        var errors: [String] = []

        // A keyword this validator does not implement is an error, not a
        // shrug: ignoring it would drop whatever rule it states while every
        // test kept passing.
        for keyword in schema.keys.sorted() where !Self.understoodKeywords.contains(keyword) {
            errors.append("\(path): schema keyword `\(keyword)` is not implemented by this validator")
        }

        if let ref = schema["$ref"] as? String {
            errors += validateRef(instance, ref: ref, at: path)
        }
        // `type` is a name or a list of them, and the list form must not read as
        // absent: an unhandled *shape* of an implemented keyword drops its rule
        // as silently as an unimplemented keyword would.
        if let type = schema["type"] {
            let names = (type as? String).map { [$0] } ?? (type as? [String]) ?? []
            if !names.isEmpty, !names.contains(where: { matchesType(instance, $0) }) {
                errors.append("\(path): expected type \(names.joined(separator: " or "))")
            }
        }
        if let required = schema["required"] as? [String], let object = instance as? [String: Any] {
            for key in required where object[key] == nil { errors.append("\(path)/\(key): required") }
        }
        if let properties = schema["properties"] as? [String: Any], let object = instance as? [String: Any] {
            for (key, subschema) in properties where object[key] != nil {
                errors += validate(object[key]!, against: subschema, at: "\(path)/\(key)")
            }
        }
        // `dependentSchemas`: a key's *presence* pulls in a subschema applied to
        // the whole object. The measurement types use it to make `value` and
        // `min`/`max` mutually exclusive — state the window or the point, never
        // both — via boolean `false` subschemas, which the branch at the top of
        // this function already rejects.
        if let dependentSchemas = schema["dependentSchemas"] as? [String: Any],
           let object = instance as? [String: Any] {
            for (key, subschema) in dependentSchemas where object[key] != nil {
                errors += validate(instance, against: subschema, at: path)
            }
        }
        // `dependentRequired`: a key's presence makes other keys required.
        // `localizations` uses it to demand `lang` — an overlay with no stated
        // base language says nothing about what it translates.
        if let dependentRequired = schema["dependentRequired"] as? [String: [String]],
           let object = instance as? [String: Any] {
            for (key, alsoRequired) in dependentRequired where object[key] != nil {
                for other in alsoRequired where object[other] == nil {
                    errors.append("\(path)/\(other): required when \(key) is present")
                }
            }
        }
        // `propertyNames`: every KEY is validated as a string instance against
        // the subschema. `localizations` uses it to require BCP-47 tags, so
        // `{"english": …}` is caught at the key, not the value.
        if let propertyNames = schema["propertyNames"], let object = instance as? [String: Any] {
            for key in object.keys where !validate(key, against: propertyNames, at: "\(path)/\(key)").isEmpty {
                errors.append("\(path)/\(key): property name is not allowed here")
            }
        }
        // `additionalProperties`: the schema for every key `properties` does not
        // name. A boolean `false` rejects them outright; a subschema validates
        // each one, which is how `localizations` types its per-locale values.
        if let additional = schema["additionalProperties"], let object = instance as? [String: Any] {
            let named = Set((schema["properties"] as? [String: Any] ?? [:]).keys)
            for (key, value) in object where !named.contains(key) {
                errors += validate(value, against: additional, at: "\(path)/\(key)")
            }
        }
        if let items = schema["items"], let array = instance as? [Any] {
            for (index, element) in array.enumerated() {
                errors += validate(element, against: items, at: "\(path)/\(index)")
            }
        }
        if let allOf = schema["allOf"] as? [Any] {
            for subschema in allOf { errors += validate(instance, against: subschema, at: path) }
        }
        if let anyOf = schema["anyOf"] as? [Any],
           !anyOf.contains(where: { validate(instance, against: $0, at: path).isEmpty }) {
            errors.append("\(path): matched none of anyOf")
        }
        if let ifSchema = schema["if"] {
            if validate(instance, against: ifSchema, at: path).isEmpty {
                if let then = schema["then"] { errors += validate(instance, against: then, at: path) }
            } else if let elseSchema = schema["else"] {
                errors += validate(instance, against: elseSchema, at: path)
            }
        }
        if let enumValues = schema["enum"] as? [Any],
           !enumValues.contains(where: { jsonEqual($0, instance) }) {
            errors.append("\(path): not one of enum")
        }
        if let constValue = schema["const"], !jsonEqual(constValue, instance) {
            errors.append("\(path): not the const value")
        }
        if let pattern = schema["pattern"] as? String, let string = instance as? String, !isBoolean(instance),
           (try? NSRegularExpression(pattern: pattern))?
               .firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) == nil {
            errors.append("\(path): does not match pattern")
        }
        if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue,
           let number = asNumber(instance), number < minimum {
            errors.append("\(path): below minimum")
        }
        if let exclusiveMinimum = (schema["exclusiveMinimum"] as? NSNumber)?.doubleValue,
           let number = asNumber(instance), number <= exclusiveMinimum {
            errors.append("\(path): not above exclusiveMinimum")
        }
        if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue,
           let number = asNumber(instance), number > maximum {
            errors.append("\(path): above maximum")
        }
        if let minItems = schema["minItems"] as? Int, let array = instance as? [Any], array.count < minItems {
            errors.append("\(path): fewer than minItems")
        }
        if let minLength = schema["minLength"] as? Int, let string = instance as? String, string.count < minLength {
            errors.append("\(path): shorter than minLength")
        }
        return errors
    }

    private func validateRef(_ instance: Any, ref: String, at path: String) -> [String] {
        let prefix = "#/$defs/"
        guard ref.hasPrefix(prefix),
              let defs = root["$defs"] as? [String: Any],
              let subschema = defs[String(ref.dropFirst(prefix.count))] else {
            return ["\(path): unresolved $ref \(ref)"]
        }
        return validate(instance, against: subschema, at: path)
    }

    /// `JSONSerialization` bridges both JSON booleans and numbers to `NSNumber`;
    /// only `CFBoolean` reliably distinguishes a JSON `true`/`false`.
    private func isBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    private func asNumber(_ value: Any) -> Double? {
        isBoolean(value) ? nil : (value as? NSNumber)?.doubleValue
    }

    private func matchesType(_ value: Any, _ type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String && !isBoolean(value)
        case "number": return asNumber(value) != nil
        // A number with no fractional part, which is `4.0` as well as `4` — the
        // draft's rule, and the one the schema's `rating` rests on. Folding this
        // into `number` accepted a 3.5-star rating the published schema refuses.
        case "integer": return asNumber(value).map { $0.truncatingRemainder(dividingBy: 1) == 0 } ?? false
        case "boolean": return isBoolean(value)
        case "null": return value is NSNull
        default: return true
        }
    }

    private func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        if isBoolean(a) || isBoolean(b) {
            return isBoolean(a) && isBoolean(b)
                && (a as? NSNumber)?.boolValue == (b as? NSNumber)?.boolValue
        }
        if let stringA = a as? String, let stringB = b as? String { return stringA == stringB }
        if let numberA = asNumber(a), let numberB = asNumber(b) { return numberA == numberB }
        return false
    }
}
