import Foundation

/// A `bean` object on the wire — the identity of a coffee: where it comes from,
/// how it was processed and roasted, and what the roaster says it tastes like
/// (<https://coffeejson.org/docs/spec/04-bean.md>).
///
/// Every field is optional at this structural layer; semantics live in
/// `ImportedBean`. Unknown fields are ignored (forward-compat). A **blend** is
/// still one bean, expressed by `origin.type == "blend"` with several
/// `origin.items`, never by the plural `beans` envelope key.
public struct Bean: Codable, Sendable, Equatable {
    /// Document-scoped identifier so a recipe can reference this bean via
    /// `bean_ref` — a **local label, not an identity**: unique within `beans`
    /// (case-sensitive), never stable across documents. Emitted in NFC by
    /// ``Codec/encode(_:)`` because the match is byte-exact.
    public var id: String?
    public var name: String?
    /// The company that roasted and sells this coffee.
    public var roaster: Party?
    /// The roaster's canonical product page. Reference metadata, not a claim.
    public var url: String?
    /// Absolute image URLs — typically the roaster's product photography.
    public var images: [String]?
    public var origin: Origin?
    /// The **set** of post-harvest processes present in this coffee. Two or more
    /// mean either that one coffee underwent both (a "Double Anaerobic Honey" is
    /// an anaerobic fermentation and a honey drying) or, on a blend stated at bag
    /// level, that the bag contains coffee of each. Order carries no meaning.
    ///
    /// The list is the only shape read or emitted: a bare string is a decode
    /// failure, as the schema says. Each token names the closed vocabulary
    /// ``KnownProcess``, as a free string so an unrecognized one round-trips.
    public var process: [String]?
    /// Post-harvest **drying** method, distinct from `process`.
    public var dryingMethod: String?
    public var varietals: [String]?
    /// How dark the roast is on the spec's six-point scale — the closed
    /// vocabulary ``KnownRoastLevel`` names, as a free string so an unrecognized
    /// token round-trips.
    public var roastLevel: String?
    public var roastAgtron: Int?
    /// The window, in days from the roast date, in which the roaster recommends
    /// brewing — degassing at the near end, freshness at the far one.
    public var restDays: RestDays?
    public var roastDate: String?
    /// The roasting machine the coffee is produced on, as printed ("Diedrich
    /// CR-70"). Distinct from ``roaster``, which is the company.
    public var productionRoaster: String?
    public var decaf: Bool?
    /// How the coffee is sold — the closed vocabulary ``KnownBeanForm`` names,
    /// as a free string so an unrecognized token round-trips.
    public var form: String?
    /// The extraction style the roaster developed this roast for — the closed
    /// vocabulary ``KnownPreferredExtraction`` names, as a free string so an
    /// unrecognized token round-trips. A declared claim, never a restriction.
    public var preferredExtraction: String?
    /// Roaster-declared certifications and production claims.
    public var certifications: [String]?
    public var roasterNotes: [String]?
    public var description: String?
    /// BCP-47 tag for this bean's human text — its own, because a bag's prose is
    /// often not the language of the recipe beside it.
    public var lang: String?
    /// The roaster's **own** translations, keyed by BCP-47 tag. Wording only:
    /// origin, process, varietals and roast are the coffee's identity and do not
    /// change with the language it is described in.
    public var localizations: [String: BeanLocalization]?

    /// Every key this package models on a wire `bean` object — the counterpart of
    /// ``Recipe/WireKey``, since both entities can be imported, edited and
    /// re-shared. Public so a consumer can name wire keys without string
    /// literals, and it *is* the type `Codable` synthesis reads.
    public enum WireKey: String, CodingKey, CaseIterable, Sendable {
        case id, name, roaster, url, images, origin, process
        case dryingMethod = "drying_method"
        case varietals
        case roastLevel = "roast_level"
        case roastAgtron = "roast_agtron"
        case restDays = "rest_days"
        case roastDate = "roast_date"
        case productionRoaster = "production_roaster"
        case decaf, form
        case preferredExtraction = "preferred_extraction"
        case certifications
        case roasterNotes = "roaster_notes"
        case description, lang, localizations
    }

    typealias CodingKeys = WireKey

    public init(
        id: String? = nil,
        name: String? = nil,
        roaster: Party? = nil,
        url: String? = nil,
        images: [String]? = nil,
        origin: Origin? = nil,
        process: [String]? = nil,
        dryingMethod: String? = nil,
        varietals: [String]? = nil,
        roastLevel: String? = nil,
        roastAgtron: Int? = nil,
        restDays: RestDays? = nil,
        roastDate: String? = nil,
        productionRoaster: String? = nil,
        decaf: Bool? = nil,
        form: String? = nil,
        preferredExtraction: String? = nil,
        certifications: [String]? = nil,
        roasterNotes: [String]? = nil,
        description: String? = nil,
        lang: String? = nil,
        localizations: [String: BeanLocalization]? = nil
    ) {
        self.id = id
        self.name = name
        self.roaster = roaster
        self.url = url
        self.images = images
        self.origin = origin
        self.process = process
        self.dryingMethod = dryingMethod
        self.varietals = varietals
        self.roastLevel = roastLevel
        self.roastAgtron = roastAgtron
        self.restDays = restDays
        self.roastDate = roastDate
        self.productionRoaster = productionRoaster
        self.decaf = decaf
        self.form = form
        self.preferredExtraction = preferredExtraction
        self.certifications = certifications
        self.roasterNotes = roasterNotes
        self.description = description
        self.lang = lang
        self.localizations = localizations
    }
}

/// The roast levels the spec defines — a typed **view** over ``Bean/roastLevel``,
/// never a gate on it. Read one with `init?(rawValue:)`: a token outside the set
/// reads as `nil`, because folding it in would report a level the roaster never
/// stated. The spec's per-field fallback is a consumer's matching-and-display
/// rule, applied where the token is shown.
///
/// Declared light-first, so `allCases` is the scale in order. The localized name
/// for each step belongs to the consumer; this package ships no resources.
public enum KnownRoastLevel: String, Sendable, Equatable, CaseIterable {
    case light
    case lightMedium = "light_medium"
    case medium
    case mediumDark = "medium_dark"
    case dark
    case extraDark = "extra_dark"
}

/// The extraction styles a roast may be developed for — a typed **view** over
/// ``Bean/preferredExtraction``, never a gate on it. Read one with
/// `init?(rawValue:)`: a token outside the set reads as `nil`.
///
/// `omni` is the roaster saying the roast suits both, not a third style — a
/// consumer offering an espresso/filter switch shows an omni roast under each.
public enum KnownPreferredExtraction: String, Sendable, Equatable, CaseIterable {
    case espresso
    case filter
    case omni
}

/// The forms the spec defines a coffee may be sold in — a typed **view** over
/// ``Bean/form``, never a gate on it. Read one with `init?(rawValue:)`: a token
/// outside the set reads as `nil`, and ``other`` is a form a producer can write
/// rather than a landing pad for the ones it cannot.
///
/// This says what the format defines, never what a product must offer: a
/// consumer may reasonably decline to let a user pick `instant`.
public enum KnownBeanForm: String, Sendable, Equatable, CaseIterable {
    case bean
    case ground
    case pod
    case dripBag = "drip_bag"
    case instant
    case other
}

/// The post-harvest processes the spec defines — a typed **view** over
/// ``Bean/process`` and ``OriginItem/process``, never a gate on them. Read one
/// with `init?(rawValue:)`: a token outside the set reads as `nil`, and
/// ``other`` is a process a producer can write rather than a landing pad for the
/// ones it cannot. A consumer that wants every token in one category applies the
/// spec's fallback itself, where the token is shown.
///
/// Both fields are list-valued, so a whole list reads as
/// `bean.process?.map(KnownProcess.init(rawValue:))` — one entry per token,
/// `nil` where this set has no id for it.
public enum KnownProcess: String, Sendable, Equatable, CaseIterable {
    case washed
    case natural
    case pulpedNatural = "pulped_natural"
    case honey
    case anaerobic
    case carbonicMaceration = "carbonic_maceration"
    case wetHulled = "wet_hulled"
    case other
}

/// One locale's wording for a coffee — the roaster's own translation, keyed in
/// ``Bean/localizations`` by BCP-47 tag.
///
/// The coffee's identity is deliberately absent: origin, process, varietals,
/// roast level and dates are the same facts in every language, so translating
/// them would be restating rather than rewording.
public struct BeanLocalization: Codable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    /// A **whole replacement** for the base list, never a positional overlay:
    /// descriptor lists get rewritten in translation rather than mapped
    /// one-to-one, and a roaster printing four notes in one language and three
    /// in another has published exactly that.
    public var roasterNotes: [String]?

    enum CodingKeys: String, CodingKey {
        case name, description
        case roasterNotes = "roaster_notes"
    }

    public init(name: String? = nil, description: String? = nil, roasterNotes: [String]? = nil) {
        self.name = name
        self.description = description
        self.roasterNotes = roasterNotes
    }
}

/// The coffee's origin: a single origin or a blend. `type` is a convenience label;
/// a consumer should derive the effective type from `items.count` when absent
/// (one item → single, more → blend).
public struct Origin: Codable, Sendable, Equatable {
    /// Single origin or blend — the closed vocabulary ``KnownOriginType`` names,
    /// as a free string so an unrecognized token round-trips.
    public var type: String?
    public var items: [OriginItem]?

    public init(type: String? = nil, items: [OriginItem]? = nil) {
        self.type = type
        self.items = items
    }
}

/// The origin kinds the spec defines — a typed **view** over ``Origin/type``,
/// never a gate on it. Read one with `init?(rawValue:)`: a token outside the set
/// reads as `nil`, and so does an absent `type`, which the format expects a
/// consumer to derive from `items.count` rather than read here.
public enum KnownOriginType: String, Sendable, Equatable, CaseIterable {
    case single
    case blend
}

/// One component of an origin — a farm, washing station or cooperative, and
/// where it sits. `country` is an ISO 3166-1 alpha-2 code.
public struct OriginItem: Codable, Sendable, Equatable {
    /// The component coffee or lot as the roaster labels it ("Lot No. 1") — what
    /// identifies this component in a blend whose parts are themselves named
    /// coffees. Distinct from ``Bean/name``, which names the bag.
    public var name: String?
    public var country: String?
    public var region: String?
    /// The parties credited with producing this component. An array because
    /// sources routinely name more than one — a farmer and their farm, a
    /// cooperative and its washing station — and a single field would force a
    /// choice the source did not make. A singular `producer` string is an unknown
    /// key, ignored like any other.
    public var producers: [Party]?
    public var altitude: Altitude?
    /// The processes for **this component**, when a blend states them per origin
    /// rather than for the bag. Bean-level `process` is the bag-level claim, and
    /// where both appear the item is the more specific. Same vocabulary,
    /// ``KnownProcess``.
    public var process: [String]?
    /// This component's varieties — the per-component counterpart of
    /// ``Bean/varietals``, for blends whose components differ.
    public var varietals: [String]?
    public var harvestTime: String?
    /// This component's share of a **blend**, `0`–`100`. Blends only.
    public var percentage: Double?

    /// `CaseIterable` so a test can pin this key set whole, for the reason
    /// ``Document/CodingKeys`` gives.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, country, region, producers, altitude, process, varietals
        case harvestTime = "harvest_time"
        case percentage
    }

    public init(
        name: String? = nil,
        country: String? = nil,
        region: String? = nil,
        producers: [Party]? = nil,
        altitude: Altitude? = nil,
        process: [String]? = nil,
        varietals: [String]? = nil,
        harvestTime: String? = nil,
        percentage: Double? = nil
    ) {
        self.name = name
        self.country = country
        self.region = region
        self.producers = producers
        self.altitude = altitude
        self.process = process
        self.varietals = varietals
        self.harvestTime = harvestTime
        self.percentage = percentage
    }
}

/// The roaster's recommended brewing window in **days from the roast date**.
/// At least one bound: a roaster who says only "at least 14 days" states
/// ``min`` alone.
public struct RestDays: Codable, Sendable, Equatable, Hashable {
    /// Days from roast before the roaster recommends brewing — the rest or
    /// degassing period.
    public var min: Double?
    /// Days from roast beyond which the roaster no longer recommends it.
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }
}

/// Altitude as a single value or an elevation band, with a unit identifier
/// (`meter` or `foot`) — the unit-id principle of `Quantity`, but ranges are
/// permitted because origins are commonly listed as bands.
public struct Altitude: Codable, Sendable, Equatable {
    public var value: Double?
    public var min: Double?
    public var max: Double?
    public var unit: String?

    public init(value: Double? = nil, min: Double? = nil, max: Double? = nil, unit: String? = nil) {
        self.value = value
        self.min = min
        self.max = max
        self.unit = unit
    }
}
