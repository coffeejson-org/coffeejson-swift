import Foundation

/// A validated, canonical-units recipe produced by `Codec.decodeDocument`.
///
/// Pure and consumer-agnostic. Timed pours are carried as ``pourSteps``
/// (cumulative grams, exactly as sent), and values are *not* range-checked here:
/// a consumer applies its own representable bounds.
public struct ImportedRecipe: Equatable, Hashable, Sendable {
    /// The recipe's document-scoped `id`, when it declared one.
    ///
    /// **Not an identity, which is why this type deliberately does not conform to
    /// `Identifiable`.** The label is optional, two recipes in one document may
    /// state the same one, and the same label in two documents names two
    /// different recipes; `ID` as `String?` would collapse every unnamed recipe
    /// into one. List by **array position** instead, the way this package
    /// addresses them, and mint a durable identity yourself if you need one.
    public var id: String?
    public var title: String
    public var coffeeGrams: Double
    /// Total brew water in canonical grams, or `nil` when this recipe states no
    /// water *mass* at all — two different situations rather than two spellings
    /// of zero. A **yield-basis** recipe has no brew water to state; a
    /// **volume-stated** one published milliliters, and no mass⇄volume conversion
    /// is defined. ``waterStatedByVolume`` says which, and ``waterMilliliters``
    /// carries the author's number.
    ///
    /// Never substitute zero: zero is a quantity a person could pour, and this is
    /// the absence of one.
    public var waterGrams: Double?
    /// Water-to-coffee ratio, or `nil` when this recipe supports none.
    ///
    /// Stated by the author where they gave one, computed from the two masses
    /// where they gave those, and absent where neither is available — a
    /// volume-stated water and a non-positive dose each leave nothing to divide.
    /// Whether it came from arithmetic on a midpointed window is recorded under
    /// ``DerivedQuantities/ratio``.
    public var ratio: Double?
    /// The wire stated brew water **by volume**, so ``waterGrams`` and ``ratio``
    /// are `nil`: display from ``waterMilliliters`` and never invent a mass. This
    /// separates the two absences — `waterGrams == nil` alone says only that no
    /// mass was stated.
    public var waterStatedByVolume: Bool
    /// The stated brew-water volume in milliliters when
    /// ``waterStatedByVolume`` — the author's number, or a stated window's
    /// midpoint. `nil` otherwise.
    public var waterMilliliters: Double?
    public var waterTemperatureCelsius: Double?
    /// Which quantities were **derived from a stated window** rather than
    /// published as points. Empty for a recipe stated entirely in points.
    ///
    /// A publisher who writes "18.5 - 19 grams" stated a window on purpose, and
    /// this projection takes the midpoint. That number is the consumer's model,
    /// not the author's figure — **a surface that shows it must say so**, or
    /// render the window from ``rawJSON``.
    public var derivedQuantities: DerivedQuantities

    /// The filter basket (espresso), when stated.
    public var basket: Gear?
    /// The brew filter this recipe calls for. A source that offers a choice
    /// states none.
    public var filter: Filter?

    /// The sender's grind as one display string, composed from the grinder, the
    /// setting and the microns. Not a wire field: `grind.setting` is only its
    /// middle term, and ``grindSize`` and ``micronsApprox`` beside it are the
    /// verbatim ones.
    public var grindDescription: String?
    /// Qualitative grind size, verbatim — read it through ``KnownGrindSize``.
    /// Kept out of ``grindDescription`` because it is a vocabulary token a
    /// consumer localizes, not prose the sender wrote.
    public var grindSize: String?
    /// Timed pour steps, in order — `at_s` plus cumulative grams, as sent.
    public var pourSteps: [ImportedPourStep]
    /// Drawdown cue, in seconds from the start of the brew.
    public var finishSeconds: Double?

    /// Raw `method` slug (e.g. `pour_over`) for display.
    public var methodSlug: String?
    public var brewerLabel: String?
    public var micronsApprox: Double?
    /// Every step the brew model could not schedule as a pour, in order —
    /// surfaced as data rather than as a rendered line.
    public var readOnlySteps: [ImportedReadOnlyStep]
    /// Beverage mass in the cup, canonical grams — set on a yield-basis recipe;
    /// a water-basis recipe may still carry it when the sender measured yield.
    public var yieldGrams: Double?
    /// Espresso-style, and canonical bar.
    public var pressureBar: Double?
    public var preinfusionSeconds: Double?
    /// Which quantity this recipe is stated in terms of.
    /// ``QuantityBasis/whenUnstated`` when the wire carried no `basis`; an
    /// unrecognized value derives from the quantities present, which is the
    /// spec's derive rule.
    public var basis: QuantityBasis
    public var notes: String?
    /// Liquids added beyond the brew water.
    public var additions: [Addition]
    /// Who authored this recipe — attribution that survives re-share. Absent
    /// when the document carried no author with a usable name.
    public var author: ImportedParty?
    /// Where this recipe was originally published (schema.org `isBasedOn`).
    public var basedOn: String?
    /// An empty wire array reads the same as absent.
    public var images: [String]
    /// The preview text, as against ``notes``.
    public var description: String?
    /// The day this recipe was first published, as its publisher stated it. A
    /// calendar day carries no instant, so a consumer converts it with its own
    /// calendar for display and never formats it as a `Date` in a zone. `nil`
    /// when the wire carried none or an unparseable one, the same rule as a
    /// bean's roast date.
    public var datePublished: CalendarDay?
    /// The `id` of the bean this recipe references, verbatim. Resolve it with
    /// ``ImportedDocument/associatedBean(forRecipeAt:)``: an unresolved reference
    /// means *unlinked*, never an error.
    public var beanRef: String?
    /// Whether the producer marked this the recommended brew. `false` when the
    /// wire carried no value — absent and `false` are spec-equivalent.
    public var recommended: Bool
    /// The verbatim JSON bytes of this recipe's object, or `nil` when the slice
    /// could not be recovered. Carries every key, including ones this type does
    /// not model, so a consumer can round-trip what it would otherwise drop.
    public var rawJSON: Data?

    public init(
        id: String? = nil,
        title: String,
        coffeeGrams: Double,
        waterGrams: Double?,
        ratio: Double?,
        waterStatedByVolume: Bool = false,
        waterMilliliters: Double? = nil,
        waterTemperatureCelsius: Double? = nil,
        derivedQuantities: DerivedQuantities = [],
        basket: Gear? = nil,
        filter: Filter? = nil,
        grindDescription: String? = nil,
        grindSize: String? = nil,
        pourSteps: [ImportedPourStep] = [],
        finishSeconds: Double? = nil,
        methodSlug: String? = nil,
        brewerLabel: String? = nil,
        micronsApprox: Double? = nil,
        readOnlySteps: [ImportedReadOnlyStep] = [],
        yieldGrams: Double? = nil,
        pressureBar: Double? = nil,
        preinfusionSeconds: Double? = nil,
        basis: QuantityBasis = .water,
        notes: String? = nil,
        additions: [Addition] = [],
        author: ImportedParty? = nil,
        basedOn: String? = nil,
        images: [String] = [],
        description: String? = nil,
        datePublished: CalendarDay? = nil,
        beanRef: String? = nil,
        recommended: Bool = false,
        rawJSON: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.coffeeGrams = coffeeGrams
        self.waterGrams = waterGrams
        self.ratio = ratio
        self.waterStatedByVolume = waterStatedByVolume
        self.waterMilliliters = waterMilliliters
        self.waterTemperatureCelsius = waterTemperatureCelsius
        self.derivedQuantities = derivedQuantities
        self.basket = basket
        self.filter = filter
        self.grindDescription = grindDescription
        self.grindSize = grindSize
        self.pourSteps = pourSteps
        self.finishSeconds = finishSeconds
        self.methodSlug = methodSlug
        self.brewerLabel = brewerLabel
        self.micronsApprox = micronsApprox
        self.readOnlySteps = readOnlySteps
        self.yieldGrams = yieldGrams
        self.pressureBar = pressureBar
        self.preinfusionSeconds = preinfusionSeconds
        self.basis = basis
        self.notes = notes
        self.additions = additions
        self.author = author
        self.basedOn = basedOn
        self.images = images
        self.description = description
        self.datePublished = datePublished
        self.beanRef = beanRef
        self.recommended = recommended
        self.rawJSON = rawJSON
    }
}

/// A single timed pour as it came off the wire: an absolute trigger time and the
/// cumulative water the scale should read by the *end* of the step (grams,
/// exactly as sent — a consumer clamps or rescales to its own model).
public struct ImportedPourStep: Equatable, Hashable, Sendable {
    public var atSeconds: Double
    public var cumulativeWaterGrams: Double
    public var label: String?
    /// How to pour, not how much ("center then circle"). Carried rather than
    /// pre-rendered so a consumer lays it out itself.
    public var instruction: String?
    /// The wire `kind`, verbatim (`nil` = unstated, which the spec defaults to
    /// `pour`), so a consumer can localize known kinds instead of guessing from
    /// position.
    public var kind: String?
    /// How long the pour runs, where ``atSeconds`` is when it is cued. Against
    /// this step's share of the water it gives a pour rate.
    public var actionDurationSeconds: Double?

    public init(
        atSeconds: Double,
        cumulativeWaterGrams: Double,
        label: String? = nil,
        instruction: String? = nil,
        kind: String? = nil,
        actionDurationSeconds: Double? = nil
    ) {
        self.atSeconds = atSeconds
        self.cumulativeWaterGrams = cumulativeWaterGrams
        self.label = label
        self.instruction = instruction
        self.kind = kind
        self.actionDurationSeconds = actionDurationSeconds
    }
}

/// A step the brew model could not schedule as a pour — it stated no `at_s`, or
/// no water target this projection can read as grams. The spec calls this
/// treatment *read-only*: a consumer shows it, and must never fail on a kind it
/// does not implement.
///
/// Carried member by member rather than rendered to a line, because rendering is
/// where the content goes: a `press` or a `wait` carries a duration *because* it
/// moves no water, and `kind` and `at_s` are a token to localize and a cue to
/// time rather than words to splice into English here.
public struct ImportedReadOnlyStep: Equatable, Hashable, Sendable {
    /// The wire `kind`, verbatim. An unrecognized kind is carried, never folded
    /// into a catch-all.
    public var kind: String?
    /// Seconds from brew start at which the document cues this step. `nil` means
    /// sequential or user-paced.
    public var atSeconds: Double?
    /// How long this step's action takes — the plunge, the steep, the stir.
    public var actionDurationSeconds: Double?
    public var instruction: String?
    /// The author's customized label, when they set one. Absent for a derived or
    /// default label, which the spec requires publishers to omit so each
    /// consumer renders its own.
    public var label: String?

    public init(
        kind: String? = nil,
        atSeconds: Double? = nil,
        actionDurationSeconds: Double? = nil,
        instruction: String? = nil,
        label: String? = nil
    ) {
        self.kind = kind
        self.atSeconds = atSeconds
        self.actionDurationSeconds = actionDurationSeconds
        self.instruction = instruction
        self.label = label
    }

    /// A wholly empty step object says nothing and is not carried.
    var statesSomething: Bool {
        kind != nil || atSeconds != nil || actionDurationSeconds != nil
            || instruction != nil || label != nil
    }
}

/// Which quantities on an ``ImportedRecipe`` were derived from a stated window
/// rather than published as a point. The window *is* the author's number, so the
/// obligation is the spec's: a consumer must never present a derived point as
/// the author's figure.
public struct DerivedQuantities: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ``ImportedRecipe/coffeeGrams`` is the midpoint of a stated dose window.
    public static let coffee = DerivedQuantities(rawValue: 1 << 0)
    /// ``ImportedRecipe/waterGrams`` is a water window's midpoint — or, for a
    /// recipe stating a dose at a ratio, a windowed *dose*'s midpoint scaled by
    /// that ratio. Two stated points derive an exact water and set nothing here.
    public static let water = DerivedQuantities(rawValue: 1 << 1)
    /// ``ImportedRecipe/yieldGrams`` is the midpoint of a stated yield window.
    public static let yield = DerivedQuantities(rawValue: 1 << 2)
    /// ``ImportedRecipe/waterTemperatureCelsius`` is a temperature window's
    /// midpoint.
    public static let waterTemperature = DerivedQuantities(rawValue: 1 << 3)
    /// ``ImportedRecipe/pressureBar`` is a pressure window's midpoint.
    public static let pressure = DerivedQuantities(rawValue: 1 << 4)
    /// At least one timed pour's target is a `to_water` window's midpoint.
    public static let steps = DerivedQuantities(rawValue: 1 << 5)
    /// ``ImportedRecipe/ratio`` was computed from at least one midpointed
    /// operand, so the number is the codec's rather than a stated ratio.
    public static let ratio = DerivedQuantities(rawValue: 1 << 6)
}

extension DerivedQuantities {
    /// Record that `quantity`'s single number is a stated window's midpoint — the
    /// plain rule, so the two places that do *not* follow it stay written out and
    /// stay visible as different.
    mutating func insert(_ member: DerivedQuantities, ifWindow quantity: Quantity?) {
        if quantity?.isWindow == true { insert(member) }
    }
}
