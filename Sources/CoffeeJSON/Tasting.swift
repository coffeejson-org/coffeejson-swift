import Foundation

/// A `tasting` object on the wire: how one brewed cup actually turned out. The
/// only top-level collection that does not on its own make a valid document,
/// because a tasting evaluates something the document must also carry
/// (<https://coffeejson.org/docs/spec/05-tasting.md>).
///
/// The shape says that an **impression** and a **measurement** are different
/// kinds of statement about one cup: `rating`, `perceived` and `descriptors` are
/// one person's opinion on one occasion; `measured` is what an instrument read,
/// which anyone with the same instrument reproduces. A consumer must never
/// present one as the other.
///
/// Not a journal entry: no timestamp, no drinker identity, no inventory state.
public struct Tasting: Codable, Sendable, Equatable {
    /// Document-scoped identifier, so this cup can be named from outside the
    /// document. A local label, never a global id, and never a timestamp.
    public var id: String?
    /// The `id` of the recipe this cup was brewed from — an **exact,
    /// case-sensitive** match. An unresolved reference leaves the tasting
    /// unlinked and never fails, and there is no positional fallback.
    public var recipeRef: String?
    /// The `id` of the bean that was brewed. This **wins over the referenced
    /// recipe's own `bean_ref`**: the two disagreeing is not a malformed
    /// document, it is "I brewed your recipe with my coffee", the ordinary case
    /// for a recipe somebody else published.
    public var beanRef: String?
    /// How much the drinker liked this cup, 1–5. An attributed opinion about one
    /// brew on one occasion — never a quality score for the coffee, and never
    /// comparable across producers.
    public var rating: Int?
    public var perceived: PerceivedAxes?
    /// What the drinker tasted, in their own words. Display text carried
    /// verbatim, not ids; `06-vocabularies.md` gives the comparison rule (fold
    /// case, trim, no further).
    public var descriptors: [String]?
    public var note: String?
    /// BCP-47 tag hinting the language of ``note`` and ``descriptors``. There is
    /// no `localizations` counterpart: nobody publishes translations of their
    /// own tasting note.
    public var lang: String?
    public var measured: MeasuredCup?

    /// `CaseIterable` so a package test can pin this key set against the schema.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case recipeRef = "recipe_ref"
        case beanRef = "bean_ref"
        case rating, perceived, descriptors, note, lang, measured
    }

    public init(
        id: String? = nil,
        recipeRef: String? = nil,
        beanRef: String? = nil,
        rating: Int? = nil,
        perceived: PerceivedAxes? = nil,
        descriptors: [String]? = nil,
        note: String? = nil,
        lang: String? = nil,
        measured: MeasuredCup? = nil
    ) {
        self.id = id
        self.recipeRef = recipeRef
        self.beanRef = beanRef
        self.rating = rating
        self.perceived = perceived
        self.descriptors = descriptors
        self.note = note
        self.lang = lang
        self.measured = measured
    }
}

/// The two dial-in axes as the drinker **perceived** them, each running -1 to 1
/// with 0 meaning "about right". That scale belongs to these two dimensions
/// rather than to the member holding them — a perceived *intensity* would be a
/// magnitude with no middle — so nothing may assume every member here runs -1 to
/// 1.
///
/// Impressions, not readings: ``extraction`` is what somebody tasted, not an
/// extraction yield, and must not be rendered as a percentage.
public struct PerceivedAxes: Codable, Sendable, Equatable, Hashable {
    /// -1 sour, acidic, under-extracted … 0 balanced … 1 bitter, over-extracted.
    public var extraction: Double?
    /// -1 weak, watery, thin … 0 about right … 1 strong, heavy, muddy.
    public var strength: Double?

    public init(extraction: Double? = nil, strength: Double? = nil) {
        self.extraction = extraction
        self.strength = strength
    }
}

/// What an instrument read from the finished beverage — measured fact, in its
/// own member so no consumer can render it as an impression.
///
/// Extraction yield is deliberately **not** carried: it derives from these two
/// and the recipe's dose, and storing it as well would give one quantity two
/// homes that can disagree. ``ImportedTasting/extractionYieldPercent`` computes
/// it instead.
public struct MeasuredCup: Codable, Sendable, Equatable, Hashable {
    /// Total dissolved solids, percent by mass, off a refractometer. Filter
    /// coffee lands near 1.2–1.6 and espresso near 8–12; concentrates and cold
    /// brew legitimately exceed both.
    public var tds: Double?
    /// The beverage mass actually **weighed** — a scale reading of this cup, as
    /// against a recipe's `yield`, which is the mass it aimed at. A consumer
    /// deriving extraction yield prefers this one.
    public var yield: Quantity?

    public init(tds: Double? = nil, yield: Quantity? = nil) {
        self.tds = tds
        self.yield = yield
    }
}
