import Foundation

// The units the format defines, one closed set per kind — typed **views** over
// ``Quantity/unit`` and ``Altitude/unit``, never gates on them. Canonical
// semantic identifiers, never a display symbol like `g` or `°C`; an
// unrecognized unit reads as `nil`, because a quantity whose unit this package
// cannot name is one it must not convert.
//
// One set per kind because which units a field admits is part of what the field
// means, and only water may be stated by volume.
//
// `foundationUnit` is the one token→unit mapping, shared with consumers. It
// stops at the unit: **this package never formats a quantity.** No
// `MeasurementFormatter`, no locale, no symbol.

/// The units a mass may be stated in — a dose, a yield, an addition.
public enum KnownMassUnit: String, Sendable, Equatable, CaseIterable {
    case gram
    case ounce

    public var foundationUnit: UnitMass {
        switch self {
        case .gram: return .grams
        case .ounce: return .ounces
        }
    }
}

/// The units brew water may be stated in. Water is the one quantity a publisher
/// may state by volume, and **no mass⇄volume conversion is defined**: water's
/// density moves with temperature, so 225 mL at 92 °C is ≈216.8 g, not 225 g.
public enum KnownWaterUnit: String, Sendable, Equatable, CaseIterable {
    case gram
    case ounce
    case milliliter

    /// The two dimensions the format admits for water, kept apart.
    ///
    /// Two cases rather than one `Dimension`, because `Dimension` would let a
    /// caller ask for milliliters in grams and get a number back: `Measurement`
    /// converts through base units, and across dimensions that arithmetic is
    /// meaningless rather than refused. The format defines no mass⇄volume
    /// conversion for exactly the reason that would be wrong — water's density
    /// moves with temperature — so a caller switching on this is a caller
    /// facing the choice the format asked it to make.
    public enum FoundationUnit: Equatable, Sendable {
        case mass(UnitMass)
        case volume(UnitVolume)
    }

    /// This token as a Foundation unit, tagged with its dimension.
    public var foundationUnit: FoundationUnit {
        switch self {
        case .gram: return .mass(.grams)
        case .ounce: return .mass(.ounces)
        case .milliliter: return .volume(.milliliters)
        }
    }
}

/// The units a temperature may be stated in.
public enum KnownTemperatureUnit: String, Sendable, Equatable, CaseIterable {
    case celsius
    case fahrenheit

    public var foundationUnit: UnitTemperature {
        switch self {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        }
    }
}

/// The units a pressure may be stated in — one, so far.
public enum KnownPressureUnit: String, Sendable, Equatable, CaseIterable {
    case bar

    public var foundationUnit: UnitPressure {
        switch self {
        case .bar: return .bars
        }
    }
}

/// The units a growing altitude may be stated in.
public enum KnownAltitudeUnit: String, Sendable, Equatable, CaseIterable {
    case meter
    case foot

    public var foundationUnit: UnitLength {
        switch self {
        case .meter: return .meters
        case .foot: return .feet
        }
    }
}
