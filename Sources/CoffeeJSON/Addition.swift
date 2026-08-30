import Foundation

/// A liquid added to the brew beyond the brew `water` — ice, milk, syrup. An
/// `ice` addition is what marks a recipe iced. Additions are separate inputs:
/// `ratio` stays `water / coffee` (<https://coffeejson.org/schema/1.0>).
public struct Addition: Codable, Sendable, Equatable, Hashable {
    /// What is added — an **open registry**: any non-empty string, with
    /// `ice` · `milk` · `sugar` · `syrup` · `water` · `cream` recommended. A
    /// value outside that set is carried verbatim, never folded into a
    /// catch-all, because rewriting another producer's vocabulary loses their
    /// document. ``KnownAdditionType`` is the typed view over this field.
    public var type: String
    /// How much is added, by mass. Optional: a source that lists an addition
    /// without a quantity has still stated that it is there, and for `ice` that
    /// is what marks the recipe iced.
    public var amount: Quantity?
    public var temperature: Quantity?
    /// Free-text detail (brand, prep, sweetener kind).
    public var note: String?

    /// The added mass in canonical grams, or `nil` when the producer stated no
    /// amount, stated a window, or used an unrecognized unit.
    public var amountGrams: Double? { amount?.grams }

    /// Canonical celsius, or `nil`.
    public var temperatureCelsius: Double? { temperature?.celsius }

    /// The marker that makes a recipe iced.
    public var isIce: Bool { type == KnownAdditionType.ice.rawValue }

    enum CodingKeys: String, CodingKey { case type, amount, temperature, note }

    public init(type: String, amount: Quantity? = nil, temperature: Quantity? = nil, note: String? = nil) {
        self.type = type
        self.amount = amount
        self.temperature = temperature
        self.note = note
    }
}

/// The addition types the spec recommends — a typed **view** over
/// ``Addition/type``, never a gate on it. Read one with `init?(rawValue:)`: the
/// registry is open, so a value outside the recommended set reads as `nil` and
/// the producer's own word stays on the wire.
public enum KnownAdditionType: String, Sendable, Equatable, CaseIterable {
    case ice
    case milk
    case sugar
    case syrup
    case water
    case cream
}
