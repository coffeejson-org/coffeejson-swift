import Foundation

/// A measured quantity as it appears on the wire — either a single magnitude,
/// `{ "value": …, "unit": … }`, or a stated window, `{ "min": …, "max": …,
/// "unit": … }`.
///
/// Units are **canonical semantic identifiers**, locale-neutral and stable:
/// `gram`, `celsius`. A producer may emit an alternate (`ounce`, `fahrenheit`)
/// and the consumer converts; display symbols are never serialized
/// (<https://coffeejson.org/docs/spec/03-recipe.md>). An unrecognized unit —
/// including a display symbol like `g` or `°C` — is treated as **absent**,
/// because the consumer never guesses. ``KnownMassUnit`` and its siblings are
/// the typed views over this field, one set per kind of measurement.
///
/// Brew water is the one quantity a publisher may state by volume, so
/// `milliliter` appears there; no mass⇄volume conversion is defined, because
/// water's density moves with temperature.
///
/// ## Windows
///
/// Publishers routinely state a window rather than a point — an espresso yield of
/// 32–34 g, a dose scaled to the size of your press. The window is the author's
/// number; a midpoint is not. So ``grams`` / ``celsius`` / ``bar`` return `nil`
/// for a window rather than inventing a point, and a consumer that needs one
/// number reads the bounds and decides explicitly. It must never present a
/// derived point as the author's figure.
public struct Quantity: Codable, Equatable, Sendable, Hashable {
    /// A single stated magnitude. Mutually exclusive with ``min``/``max``: a
    /// producer states the window or the point, never both.
    public var value: Double?
    public var min: Double?
    public var max: Double?
    public var unit: String

    /// Constructing an unrecognized unit is legal — the wire allows it — and it
    /// reads as absent.
    public init(value: Double? = nil, min: Double? = nil, max: Double? = nil, unit: String) {
        self.value = value
        self.min = min
        self.max = max
        self.unit = unit
    }

    /// A mass in canonical grams.
    public static func grams(_ value: Double) -> Quantity {
        Quantity(value: value, unit: KnownMassUnit.gram.rawValue)
    }

    /// A mass window in canonical grams.
    public static func grams(min: Double, max: Double) -> Quantity {
        Quantity(min: min, max: max, unit: KnownMassUnit.gram.rawValue)
    }

    /// A volume of brew water in canonical milliliters. Water only: no other
    /// quantity in v1.0 admits a volume unit.
    public static func milliliters(_ value: Double) -> Quantity {
        Quantity(value: value, unit: KnownWaterUnit.milliliter.rawValue)
    }

    /// A temperature in canonical Celsius.
    public static func celsius(_ value: Double) -> Quantity {
        Quantity(value: value, unit: KnownTemperatureUnit.celsius.rawValue)
    }

    /// A temperature window in canonical Celsius.
    public static func celsius(min: Double, max: Double) -> Quantity {
        Quantity(min: min, max: max, unit: KnownTemperatureUnit.celsius.rawValue)
    }

    /// A pressure in canonical bar — v1.0's only pressure unit.
    public static func bar(_ value: Double) -> Quantity {
        Quantity(value: value, unit: KnownPressureUnit.bar.rawValue)
    }

    /// A pressure window in canonical bar.
    public static func bar(min: Double, max: Double) -> Quantity {
        Quantity(min: min, max: max, unit: KnownPressureUnit.bar.rawValue)
    }

    /// Whether the producer stated a window rather than a single magnitude.
    public var isWindow: Bool { value == nil && (min != nil || max != nil) }

    /// Whether the producer stated any magnitude at all. A quantity carrying
    /// none is malformed and reads as absent throughout.
    public var hasMagnitude: Bool { value != nil || min != nil || max != nil }

    /// Canonical mass, or `nil` for a non-mass unit. Converted through the
    /// unit view's Foundation bridge, so the token→unit mapping lives in one
    /// place for this package and its consumers alike.
    private func asGrams(_ n: Double?) -> Double? {
        guard let n, let known = KnownMassUnit(rawValue: unit) else { return nil }
        // The canonical unit is returned untouched. A round trip through the
        // dimension's base unit is arithmetic on a number that was already the
        // answer, and it can come back a few ulps off the author's own figure.
        guard known != .gram else { return n }
        return Measurement(value: n, unit: known.foundationUnit).converted(to: .grams).value
    }

    /// Canonical temperature, or `nil` for a non-temperature unit.
    private func asCelsius(_ n: Double?) -> Double? {
        guard let n, let known = KnownTemperatureUnit(rawValue: unit) else { return nil }
        guard known != .celsius else { return n }   // canonical already; see ``asGrams``
        return Measurement(value: n, unit: known.foundationUnit).converted(to: .celsius).value
    }

    /// Canonical volume, or `nil` when this quantity states a mass instead —
    /// the two-case bridge makes that the caller's explicit branch, because the
    /// format defines no conversion between them.
    private func asMilliliters(_ n: Double?) -> Double? {
        guard let n, case let .volume(volumeUnit) = KnownWaterUnit(rawValue: unit)?.foundationUnit
        else { return nil }
        guard volumeUnit != .milliliters else { return n }   // canonical already; see ``asGrams``
        return Measurement(value: n, unit: volumeUnit).converted(to: .milliliters).value
    }

    /// The single stated value in canonical grams. `nil` for an unrecognized
    /// mass unit **or for a window** — see the type's Windows note.
    public var grams: Double? { asGrams(value) }
    public var minGrams: Double? { asGrams(min) }
    public var maxGrams: Double? { asGrams(max) }

    /// The single stated value in canonical Celsius, `nil` for an unrecognized
    /// unit or a window.
    public var celsius: Double? { asCelsius(value) }
    public var minCelsius: Double? { asCelsius(min) }
    public var maxCelsius: Double? { asCelsius(max) }

    /// The single stated value in canonical bar, `nil` for an unrecognized unit
    /// or a window.
    public var bar: Double? { asBar(value) }
    public var minBar: Double? { asBar(min) }
    public var maxBar: Double? { asBar(max) }

    /// Canonical pressure. One unit is defined, so this converts nothing today
    /// and states where a second one would arrive.
    private func asBar(_ n: Double?) -> Double? {
        guard let n, let known = KnownPressureUnit(rawValue: unit) else { return nil }
        guard known != .bar else { return n }   // canonical already; see ``asGrams``
        return Measurement(value: n, unit: known.foundationUnit).converted(to: .bars).value
    }

    /// The midpoint of a stated window in canonical grams, or the one bound
    /// present when the producer gave only one.
    ///
    /// **Never present this as the author's figure.** It is a consumer's model of
    /// a window the author deliberately left open — label it, or render the
    /// window itself.
    public var midpointGrams: Double? { midpoint(minGrams, maxGrams) }
    /// Same derivation and caveat as ``midpointGrams``, in canonical Celsius.
    public var midpointCelsius: Double? { midpoint(minCelsius, maxCelsius) }
    /// Same derivation and caveat as ``midpointGrams``, in canonical bar.
    public var midpointBar: Double? { midpoint(minBar, maxBar) }

    private func midpoint(_ lo: Double?, _ hi: Double?) -> Double? {
        switch (lo, hi) {
        case let (lo?, hi?): return (lo + hi) / 2
        case let (lo?, nil): return lo
        case let (nil, hi?): return hi
        case (nil, nil): return nil
        }
    }

    /// The single number a consumer must brew with: the stated value when the
    /// producer gave one, otherwise the window's midpoint. `nil` for an
    /// unrecognized unit or no stated magnitude.
    ///
    /// Pair with ``isWindow`` — when that is `true` this number is **derived**
    /// and must be labeled as such wherever it is shown.
    public var effectiveGrams: Double? { grams ?? midpointGrams }
    /// Same derivation and labeling obligation as ``effectiveGrams``.
    public var effectiveCelsius: Double? { celsius ?? midpointCelsius }
    /// Same derivation and labeling obligation as ``effectiveGrams``.
    public var effectiveBar: Double? { bar ?? midpointBar }

    /// The single stated volume in canonical milliliters, `nil` when this is not
    /// a volume **or for a window** — see the type's Windows note.
    /// **No mass⇄volume conversion is defined**: 225 mL of water at
    /// 92 °C is ≈216.8 g, so a consumer that needs the other kind applies its own
    /// model and must not present the result as the author's figure.
    public var milliliters: Double? { asMilliliters(value) }
    public var minMilliliters: Double? { asMilliliters(min) }
    public var maxMilliliters: Double? { asMilliliters(max) }

    /// Same derivation and caveat as ``midpointGrams``, in canonical
    /// milliliters. Vended like its three siblings, so a consumer that must
    /// label a derived volume reads the midpoint rather than recomputing it.
    public var midpointMilliliters: Double? { midpoint(minMilliliters, maxMilliliters) }

    /// Same derivation and labeling obligation as ``effectiveGrams``; `nil`
    /// when this is not a volume.
    public var effectiveMilliliters: Double? { milliliters ?? midpointMilliliters }
}
