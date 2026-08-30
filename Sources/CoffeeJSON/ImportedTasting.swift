import Foundation

/// A validated, canonical-units tasting produced by `Codec.decodeDocument`.
///
/// Flat, like its siblings: the wire's nested `perceived` and `measured` objects
/// become named scalars, because the nesting exists on the wire to mark the seam
/// rather than to be navigated. The seam survives in the names.
public struct ImportedTasting: Equatable, Hashable, Sendable {
    /// Document-scoped identifier, verbatim as sent. A local label — and, as on
    /// ``ImportedBean``, deliberately not an `Identifiable` conformance: it is
    /// optional, it may repeat within one document, and it means nothing outside
    /// the document that carried it.
    public var id: String?
    /// The recipe reference as sent — resolve it with
    /// ``ImportedDocument/associatedRecipe(forTastingAt:)``.
    public var recipeRef: String?
    /// The coffee reference as sent — resolve it with
    /// ``ImportedDocument/associatedBean(forTastingAt:)``, which honors this
    /// over the referenced recipe's.
    public var beanRef: String?

    /// 1–5, as sent. Attributed opinion, never a property of the coffee.
    public var rating: Int?
    /// Perceived extraction, -1 (sour, under) … 0 (balanced) … 1 (bitter, over).
    /// A judgment — never render it as an extraction yield.
    public var perceivedExtraction: Double?
    /// Perceived strength, -1 (thin) … 0 (about right) … 1 (heavy).
    public var perceivedStrength: Double?
    /// What the drinker tasted, verbatim and in order. Display text, not ids:
    /// two match after folding case and trimming surrounding whitespace, and by
    /// no looser rule.
    public var descriptors: [String]
    public var note: String?
    /// BCP-47 tag for ``note`` and ``descriptors``.
    public var lang: String?

    /// Total dissolved solids, percent by mass.
    public var tds: Double?
    /// The beverage mass actually weighed, canonical grams. A stated window
    /// contributes no point here, for the reason ``Quantity`` gives.
    public var measuredYieldGrams: Double?

    /// Extraction yield for this cup, as a percentage — **derived**, never sent.
    ///
    ///     extraction yield % = (beverage mass × TDS %) ÷ dose
    ///
    /// The format does not carry this number: storing it beside the measurements
    /// it comes from would give one quantity two homes that can drift apart. It
    /// states the arithmetic instead, and both reference implementations do it
    /// here, so two consumers cannot disagree about it privately.
    ///
    /// The beverage mass is this tasting's own ``measuredYieldGrams`` when it has
    /// one and the referenced recipe's yield otherwise — the measurement of this
    /// cup before the mass it was brewed against. The dose is that recipe's, so
    /// a tasting resolving no recipe derives nothing.
    ///
    /// `nil` whenever an input is missing or non-positive.
    public var extractionYieldPercent: Double?

    public init(
        id: String? = nil,
        recipeRef: String? = nil,
        beanRef: String? = nil,
        rating: Int? = nil,
        perceivedExtraction: Double? = nil,
        perceivedStrength: Double? = nil,
        descriptors: [String] = [],
        note: String? = nil,
        lang: String? = nil,
        tds: Double? = nil,
        measuredYieldGrams: Double? = nil,
        extractionYieldPercent: Double? = nil
    ) {
        self.id = id
        self.recipeRef = recipeRef
        self.beanRef = beanRef
        self.rating = rating
        self.perceivedExtraction = perceivedExtraction
        self.perceivedStrength = perceivedStrength
        self.descriptors = descriptors
        self.note = note
        self.lang = lang
        self.tds = tds
        self.measuredYieldGrams = measuredYieldGrams
        self.extractionYieldPercent = extractionYieldPercent
    }
}
