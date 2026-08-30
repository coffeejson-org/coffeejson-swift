import Foundation

/// The CoffeeJSON document envelope: a `coffeejson` version marker plus three
/// **optional array** collections. There are no singular keys — a single coffee,
/// recipe or tasting is an array of one. `beans` or `recipes` must be non-empty;
/// `tastings` does not satisfy that rule, because a tasting evaluates something
/// the document must also carry.
///
/// This layer describes the JSON shape only. That rule, the version gate and
/// unit conversion live in `Codec`. Unknown fields are ignored on decode
/// (forward-compat) and nil collections are omitted on encode, so empty arrays
/// and `null`s never reach the wire.
public struct Document: Codable, Sendable, Equatable {
    public var version: String
    public var beans: [Bean]?
    public var recipes: [Recipe]?
    /// How the brewed cups turned out. Each points back at what it evaluates —
    /// a `recipe_ref` at the brew, a `bean_ref` at the coffee — and the two
    /// resolve independently.
    public var tastings: [Tasting]?
    /// The software that wrote this document. Informational — a consumer must
    /// not depend on it, or change how it imports because of it.
    public var generator: Generator?

    /// `CaseIterable` so a test can pin the key set whole. Without it the pin
    /// sees only the keys a fixture happened to populate — blind to exactly the
    /// member someone forgot.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version = "coffeejson"
        case beans, recipes, tastings, generator
    }

    public init(
        version: String,
        beans: [Bean]? = nil,
        recipes: [Recipe]? = nil,
        tastings: [Tasting]? = nil,
        generator: Generator? = nil
    ) {
        self.version = version
        self.beans = beans
        self.recipes = recipes
        self.tastings = tastings
        self.generator = generator
    }

    /// Hand-written so a malformed `generator` cannot fail the import.
    ///
    /// The spec says a consumer must not change how it imports a document
    /// because of `generator`, and throwing the document away over it is the
    /// most extreme form of doing exactly that. `name` stays required for
    /// producers; a *reader* meeting a generator without one drops the marker
    /// and keeps the coffee.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        beans = try c.decodeIfPresent([Bean].self, forKey: .beans)
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes)
        tastings = try c.decodeIfPresent([Tasting].self, forKey: .tastings)
        generator = try? c.decodeIfPresent(Generator.self, forKey: .generator)
    }
}

/// Informational provenance: which software wrote this document. It belongs to
/// the **document** rather than to any recipe or bean inside it — one file is
/// written once, by one program — so a bean-only document can carry it and a
/// multi-recipe document states it once.
///
/// `name` is not optional: a generator that names no software states nothing.
/// Not necessarily an application — a hosted service, a build script, a
/// command-line tool or a language model names itself in the same member.
public struct Generator: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var version: String?
    /// The producing software's home — never where a recipe was published, which
    /// is the recipe's `based_on`.
    public var url: String?

    public init(name: String, version: String? = nil, url: String? = nil) {
        self.name = name
        self.version = version
        self.url = url
    }
}
