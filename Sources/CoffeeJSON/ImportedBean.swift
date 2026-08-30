import Foundation

/// A validated, canonical-units bean produced by `Codec.decodeDocument` — the
/// bean counterpart of `ImportedRecipe`.
///
/// Wire strings with a factual normal form are normalized (altitude → meters,
/// `roast_date` → ``CalendarDay``); everything else passes through unchanged, so a
/// consumer that does not recognize a value still keeps it.
public struct ImportedBean: Equatable, Hashable, Sendable {
    /// Document-scoped identifier, verbatim as sent — the target of a recipe's
    /// `bean_ref`. A local label, never an identity across documents.
    ///
    /// Which is why this type deliberately does **not** conform to
    /// `Identifiable`. The label is optional, it may repeat inside one document
    /// — ``ImportedDocument/associatedBean(forRecipeAt:)`` treats a repeated one
    /// as unresolvable rather than picking a winner — and it means nothing
    /// outside the document that carried it. A conformance would hand `String?`
    /// to `ID` and quietly merge every unnamed coffee into one row.
    ///
    /// List these by **array position** instead, the same way this package
    /// addresses them. A durable identity is the consumer's to mint and store.
    public var id: String?
    public var name: String?
    public var roaster: ImportedParty?
    public var url: String?
    public var images: [String]
    public var origin: ImportedOrigin?
    /// The set of post-harvest processes present in this coffee. One element is
    /// the common case; more mean a compound process or, on a blend stated at
    /// bag level, that the bag contains coffee of each.
    public var process: [String]
    public var dryingMethod: String?
    public var varietals: [String]
    public var roastLevel: String?
    public var roastAgtron: Int?
    /// The window, in days from roast, the roaster recommends brewing in.
    public var restDays: RestDays?
    /// The day this coffee was roasted, as the roaster stated it. A calendar
    /// day carries no instant, so a consumer converts it with its own calendar
    /// for display and never formats it as a `Date` in a zone.
    public var roastDate: CalendarDay?
    /// The machine, as printed. Distinct from ``roaster``, which is the company.
    public var productionRoaster: String?
    public var decaf: Bool?
    public var form: String?
    /// A claim about the roast, not a limit on it.
    public var preferredExtraction: String?
    public var certifications: [String]
    public var roasterNotes: [String]
    public var description: String?
    /// BCP-47 tag for this bean's own prose.
    public var lang: String?

    /// The verbatim bytes of this bean's wire object — what a model hands back
    /// as ``BeanConvertible/carriedBeanJSON`` on re-emit, so a consumer that
    /// models a subset of the format keeps everything else rather than
    /// destroying it. `nil` for a bean the consumer built itself.
    public var rawJSON: Data?

    public init(
        id: String? = nil,
        name: String? = nil,
        roaster: ImportedParty? = nil,
        url: String? = nil,
        images: [String] = [],
        origin: ImportedOrigin? = nil,
        process: [String] = [],
        dryingMethod: String? = nil,
        varietals: [String] = [],
        roastLevel: String? = nil,
        roastAgtron: Int? = nil,
        restDays: RestDays? = nil,
        roastDate: CalendarDay? = nil,
        productionRoaster: String? = nil,
        decaf: Bool? = nil,
        form: String? = nil,
        preferredExtraction: String? = nil,
        certifications: [String] = [],
        roasterNotes: [String] = [],
        description: String? = nil,
        lang: String? = nil,
        rawJSON: Data? = nil
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
        self.rawJSON = rawJSON
    }
}

/// A single origin, or a blend of several `items`.
public struct ImportedOrigin: Equatable, Hashable, Sendable {
    public var type: String?
    public var items: [ImportedOriginItem]

    public init(type: String? = nil, items: [ImportedOriginItem] = []) {
        self.type = type
        self.items = items
    }
}

/// One component of an origin, with altitude already converted to meters.
public struct ImportedOriginItem: Equatable, Hashable, Sendable {
    /// The component coffee or lot as the roaster labels it — what identifies a
    /// blend's parts where those parts are named coffees.
    public var name: String?
    public var country: String?
    public var region: String?
    /// The parties credited with producing this component. An entry without a
    /// usable name is dropped rather than failing the import.
    public var producers: [ImportedParty]
    public var altitude: ImportedAltitude?
    /// This component's post-harvest processes, when stated per origin.
    public var process: [String]
    public var varietals: [String]
    public var harvestTime: String?
    public var percentage: Double?

    public init(
        name: String? = nil,
        country: String? = nil,
        region: String? = nil,
        producers: [ImportedParty] = [],
        altitude: ImportedAltitude? = nil,
        process: [String] = [],
        varietals: [String] = [],
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

/// Altitude in **canonical meters** — a single value and/or a min/max band.
/// An unrecognized unit yields `nil` (treated as absent), like measurements.
public struct ImportedAltitude: Equatable, Hashable, Sendable {
    public var valueMeters: Double?
    public var minMeters: Double?
    public var maxMeters: Double?

    public init(valueMeters: Double? = nil, minMeters: Double? = nil, maxMeters: Double? = nil) {
        self.valueMeters = valueMeters
        self.minMeters = minMeters
        self.maxMeters = maxMeters
    }
}
