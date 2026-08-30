import Foundation

/// A `recipe` object on the wire. Every field is optional at this structural
/// layer; `Codec` enforces which are required. Unknown fields are ignored,
/// which is the forward-compat contract
/// (<https://coffeejson.org/docs/spec/01-overview.md>).
public struct Recipe: Codable, Sendable, Equatable {
    /// Document-scoped identifier, so this recipe can be named from outside the
    /// document and by a tasting's `recipe_ref`. A local label, never a global
    /// id. Emitted in NFC by ``Codec/encode(_:)`` because the match is
    /// byte-exact.
    public var id: String?
    public var title: String?
    /// How the coffee is brewed — the closed vocabulary ``KnownBrewMethod``
    /// names, as a free string so an unrecognized token round-trips. Descriptive:
    /// ``basis`` is the structural switch a consumer keys on.
    public var method: String?
    /// The structural discriminator (`"water"` | `"yield"`), kept as the raw wire
    /// string; `Codec` resolves it into a ``QuantityBasis``.
    public var basis: String?
    public var brewer: Gear?
    public var coffee: Quantity?
    public var water: Quantity?
    /// Beverage mass in the cup — the yield-basis counterpart to `water`.
    public var yield: Quantity?
    public var ratio: Double?
    public var waterTemp: Quantity?
    /// Espresso-style, and canonical bar.
    public var pressure: Quantity?
    public var preinfusionSeconds: Double?
    public var grind: Grind?
    /// The filter basket (espresso).
    public var basket: Gear?
    public var filter: Filter?
    public var steps: [Step]?
    public var finishSeconds: Double?
    public var lang: String?
    /// The publisher's **own** translations, keyed by BCP-47 tag. Wording only —
    /// quantities, gear and enums are the recipe and never vary by language.
    public var localizations: [String: RecipeLocalization]?
    /// Long-form guidance: character, tips, troubleshooting.
    public var notes: String?
    /// Liquids added beyond the brew `water`. `ratio` stays water/coffee.
    public var additions: [Addition]?
    /// Who authored this recipe — attribution that must survive re-share.
    public var author: Party?
    /// Where this recipe was originally published (schema.org `isBasedOn`) —
    /// distinct from the document's `generator`, which is software provenance,
    /// and from `author.url`.
    public var basedOn: String?
    public var images: [String]?
    /// One- or two-sentence summary — the preview text, distinct from `title`
    /// (the name) and `notes` (long-form guidance).
    public var description: String?
    /// ISO calendar date this recipe was first published — distinct from the
    /// coffee's `roast_date`.
    public var datePublished: String?
    /// The `id` of the bean this recipe is for — an **exact, case-sensitive**
    /// match. An unresolved reference leaves the recipe unlinked, never fails,
    /// and never falls back to co-location. Emitted in NFC by
    /// ``Codec/encode(_:)``, because the match is byte-exact.
    public var beanRef: String?
    /// The producer's recommended brew, typically the roaster's pick for the
    /// associated coffee. Absent and `false` are spec-equivalent.
    public var recommended: Bool?

    /// Every key this package models on a wire `recipe` object. Public so a
    /// consumer can name wire keys without string literals, and it *is* the type
    /// `Codable` synthesis reads, so the two cannot describe different key
    /// sets.
    public enum WireKey: String, CodingKey, CaseIterable, Sendable {
        case id, title, method, basis, brewer, coffee, water, yield, ratio
        case waterTemp = "water_temp"
        case pressure
        case preinfusionSeconds = "preinfusion_s"
        case grind, basket, filter, steps
        case finishSeconds = "finish_s"
        case lang, localizations, notes, additions, author
        case basedOn = "based_on"
        case images, description
        case datePublished = "date_published"
        case beanRef = "bean_ref"
        case recommended
    }

    typealias CodingKeys = WireKey

    public init(
        id: String? = nil,
        title: String? = nil,
        method: String? = nil,
        basis: String? = nil,
        brewer: Gear? = nil,
        coffee: Quantity? = nil,
        water: Quantity? = nil,
        yield: Quantity? = nil,
        ratio: Double? = nil,
        waterTemp: Quantity? = nil,
        pressure: Quantity? = nil,
        preinfusionSeconds: Double? = nil,
        grind: Grind? = nil,
        basket: Gear? = nil,
        filter: Filter? = nil,
        steps: [Step]? = nil,
        finishSeconds: Double? = nil,
        lang: String? = nil,
        localizations: [String: RecipeLocalization]? = nil,
        notes: String? = nil,
        additions: [Addition]? = nil,
        author: Party? = nil,
        basedOn: String? = nil,
        images: [String]? = nil,
        description: String? = nil,
        datePublished: String? = nil,
        beanRef: String? = nil,
        recommended: Bool? = nil
    ) {
        self.title = title
        self.id = id
        self.method = method
        self.basis = basis
        self.brewer = brewer
        self.coffee = coffee
        self.water = water
        self.yield = yield
        self.ratio = ratio
        self.waterTemp = waterTemp
        self.pressure = pressure
        self.preinfusionSeconds = preinfusionSeconds
        self.grind = grind
        self.basket = basket
        self.filter = filter
        self.steps = steps
        self.finishSeconds = finishSeconds
        self.lang = lang
        self.localizations = localizations
        self.notes = notes
        self.additions = additions
        self.author = author
        self.basedOn = basedOn
        self.images = images
        self.description = description
        self.datePublished = datePublished
        self.beanRef = beanRef
        self.recommended = recommended
    }
}

/// The brew methods the spec defines — a typed **view** over ``Recipe/method``,
/// never a gate on it. Read one with `init?(rawValue:)`: a token outside the set
/// reads as `nil`, and ``other`` is a method a producer can write rather than a
/// landing pad for the ones it cannot.
///
/// This says what the format defines, never what a product must offer: a
/// consumer is free to present a subset, and the localized name for each token
/// is its own — this package ships no resources.
public enum KnownBrewMethod: String, Sendable, Equatable, CaseIterable {
    case pourOver = "pour_over"
    case immersion
    case aeropress
    case frenchPress = "french_press"
    case moka
    case coldBrew = "cold_brew"
    case siphon
    case cezve
    case drip
    case capsule
    case espresso
    case other
}

/// A piece of equipment (brewer, grinder, or basket). `id` is a canonical
/// registry slug or the literal `"custom"`. A consumer must not fail on an
/// unrecognized `id`; it falls back to `label`, then `brand` / `model`.
public struct Gear: Codable, Sendable, Equatable, Hashable {
    public var id: String?
    public var brand: String?
    public var model: String?
    public var label: String?

    public init(id: String? = nil, brand: String? = nil, model: String? = nil, label: String? = nil) {
        self.id = id
        self.brand = brand
        self.model = model
        self.label = label
    }
}

/// The brew filter. Material is the part that affects the cup: paper retains
/// oils and fines, metal lets them through, cloth sits between. The product is
/// usually implied by the brewer, so it is a free label rather than a registry.
///
/// A source that states a *choice* ("either paper or mesh") states no filter, and
/// one that states an *absence* ("a French press doesn't use a paper filter") is
/// stating the metal mesh positively. Both are producer-side calls.
public struct Filter: Codable, Sendable, Equatable, Hashable {
    /// `paper` · `metal` · `cloth` · `other`. A free string on the wire, so a
    /// producer's unrecognized value round-trips verbatim.
    /// ``KnownFilterMaterial`` is the typed view over this field.
    public var material: String?
    /// The filter as the source names it, when that says more than the material
    /// — a product ("V60-02"), a form (a tea bag), or the brewer's own part.
    public var label: String?

    public init(material: String? = nil, label: String? = nil) {
        self.material = material
        self.label = label
    }
}

/// The filter materials the spec defines — a typed **view** over
/// ``Filter/material``, never a gate on it. Read one with `init?(rawValue:)`: a
/// token outside the set reads as `nil`, and ``other`` is a material a producer
/// can write rather than a landing pad for the ones it cannot. A consumer that
/// wants every token in one category applies the spec's fallback itself, where
/// the token is shown.
public enum KnownFilterMaterial: String, Sendable, Equatable, CaseIterable {
    case paper
    case metal
    case cloth
    case other
}

/// Structured grind. `setting` is free text on the sender's own grinder ("22
/// clicks") and is never coerced to a number; `microns_approx` is the only
/// roughly-portable axis and is explicitly approximate.
public struct Grind: Codable, Sendable, Equatable {
    public var grinder: Gear?
    public var setting: String?
    public var micronsApprox: Double?
    /// Qualitative coarseness on the standard perceptual scale — the vocabulary
    /// ``KnownGrindSize`` names. A free string on the wire, so a value outside
    /// the scale degrades to *unstated* for that axis instead of failing the
    /// decode, and the sender's own `setting` is then what a reader prefers.
    public var size: String?

    enum CodingKeys: String, CodingKey {
        case grinder, setting
        case micronsApprox = "microns_approx"
        case size
    }

    public init(
        grinder: Gear? = nil,
        setting: String? = nil,
        micronsApprox: Double? = nil,
        size: String? = nil
    ) {
        self.grinder = grinder
        self.setting = setting
        self.micronsApprox = micronsApprox
        self.size = size
    }
}

/// The grind sizes the spec defines — a typed **view** over ``Grind/size``,
/// never a gate on it. Read one with `init?(rawValue:)`: a token outside the
/// scale reads as `nil`, which is also the whole answer here — the scale has no
/// catch-all member, and a size the format does not define leaves the grinder's
/// own ``Grind/setting`` as what a reader prefers.
///
/// Declared coarsest-last, so `allCases` is the perceptual scale in order.
public enum KnownGrindSize: String, Sendable, Equatable, CaseIterable {
    case extraFine = "extra_fine"
    case fine
    case mediumFine = "medium_fine"
    case medium
    case mediumCoarse = "medium_coarse"
    case coarse
    case extraCoarse = "extra_coarse"
}

/// A single brew step. `kind` defaults to `pour`; an absent `at_s` means the
/// step is sequential or user-paced. Array order is authoritative.
///
/// `to_water` is the **cumulative** water the scale should read by the end of
/// this step — pour *up to* this amount, not the amount added.
public struct Step: Codable, Sendable, Equatable {
    /// What this step does — the closed vocabulary ``KnownStepKind`` names, as a
    /// free string so an unrecognized token round-trips. Absent means `pour`.
    public var kind: String?
    public var atSeconds: Double?
    public var toWater: Quantity?
    public var instruction: String?
    public var label: String?
    /// How long this step's action takes, in seconds — distinct from `at_s`,
    /// which is when it is cued. With this step's share of the pour it gives a
    /// pour rate, which is why a publisher states it.
    public var actionDurationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case kind
        case atSeconds = "at_s"
        case toWater = "to_water"
        case instruction, label
        case actionDurationSeconds = "action_duration_s"
    }

    public init(
        kind: String? = nil,
        atSeconds: Double? = nil,
        toWater: Quantity? = nil,
        instruction: String? = nil,
        label: String? = nil,
        actionDurationSeconds: Double? = nil
    ) {
        self.kind = kind
        self.atSeconds = atSeconds
        self.toWater = toWater
        self.instruction = instruction
        self.label = label
        self.actionDurationSeconds = actionDurationSeconds
    }
}

/// The step kinds the spec defines — a typed **view** over ``Step/kind``, never
/// a gate on it. Read one with `init?(rawValue:)`: a token outside the set reads
/// as `nil`, and ``other`` is a kind an author can write rather than a landing
/// pad for the ones this set has no id for.
///
/// An **absent** kind is a different question from an unrecognized one, and the
/// format answers it: see ``whenUnstated``.
public enum KnownStepKind: String, Sendable, Equatable, CaseIterable {
    case pour
    case bloom
    case prep
    case wait
    case stir
    case flip
    case valveOpen = "valve_open"
    case valveClose = "valve_close"
    case press
    case drawdown
    case distribute
    case tamp
    case pull
    case other

    /// What the format means by an **absent** `kind`: ``pour``. Declared by the
    /// schema (`$defs/step/properties/kind`, `"default": "pour"`) and by the
    /// recipe spec, so it is the format's answer and not a reader's guess —
    /// vended here so every reader applies the same one.
    ///
    /// A default, never a fold. ``Step/kind`` stays an optional free string, so
    /// the two cases stay distinguishable: an absent field is this value, and a
    /// present one goes through `init?(rawValue:)`, where `nil` still means
    /// *outside the set* and the sender's own word is still on the wire.
    public static let whenUnstated: KnownStepKind = .pour
}

/// One locale's wording for a recipe — the publisher's own translation, keyed in
/// ``Recipe/localizations`` by BCP-47 tag.
///
/// Every member is optional: a publisher who translated only the title states
/// only the title, and an absent field falls back to the base recipe's. No
/// quantities, no gear and no enums, because a translation that changed a dose
/// would be a different recipe rather than the same one in another language.
public struct RecipeLocalization: Codable, Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var notes: String?
    /// Per-step wording, **positional** against the base recipe's `steps`: entry
    /// *i* translates step *i*. Use ``steps(pairedWith:)`` rather than indexing
    /// this directly — a length mismatch must not pair an instruction with the
    /// wrong pour.
    public var steps: [StepLocalization]?

    public init(
        title: String? = nil,
        description: String? = nil,
        notes: String? = nil,
        steps: [StepLocalization]? = nil
    ) {
        self.title = title
        self.description = description
        self.notes = notes
        self.steps = steps
    }

    /// This localization's step wording aligned to `baseSteps`, or `nil` when the
    /// two disagree on length.
    ///
    /// The spec makes length equality a hard condition and a mismatch a
    /// whole-array discard, because misalignment is the failure that matters: an
    /// untranslated step is merely unhelpful, while step 3's instruction shown
    /// against step 2's pour is confidently wrong. Returning `nil` rather than a
    /// best-effort zip makes that non-negotiable at the call site.
    public func steps(pairedWith baseSteps: [Step]?) -> [StepLocalization]? {
        guard let steps, steps.count == (baseSteps?.count ?? 0) else { return nil }
        return steps
    }
}

/// One step's wording in one locale. Timing and water targets are never here —
/// they are the brew, identical in every language.
public struct StepLocalization: Codable, Sendable, Equatable {
    public var instruction: String?
    public var label: String?

    public init(instruction: String? = nil, label: String? = nil) {
        self.instruction = instruction
        self.label = label
    }
}
