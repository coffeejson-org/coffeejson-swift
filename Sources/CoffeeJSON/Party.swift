import Foundation

/// A `party` object on the wire — a person or organization credited on a
/// document (schema.org Person/Organization-aligned). Reused wherever a credit
/// appears: a bean's `roaster`, a recipe's `author`, an origin item's
/// `producers`.
///
/// Every field is optional at this structural layer; the spec's requirement that
/// a party carry a non-empty `name` is enforced by ``ImportedParty``. `type` is
/// a free string carried exactly as sent — an unknown value is never rejected,
/// and an absent one stays absent, because the format states no kind there and
/// this package does not invent one.
///
/// A consumer that needs a kind infers it from the field doing the crediting: an
/// `author` reads as a person, a `roaster` as an organization, a producer whose
/// ``role`` is `farm`, `cooperative`, `washing_station` or `mill` as an
/// organization. That is a display rule, and it belongs where the credit is
/// shown.
///
/// One type, because the schema defines one `party` shape for every credit —
/// so a consumer renders them all with one code path.
public struct Party: Codable, Sendable, Equatable {
    public var name: String?
    public var url: String?
    public var type: String?
    /// What this party did, where the format defines a role at all — an origin
    /// item's `producers`. An **open registry**: `producer` · `farm` ·
    /// `cooperative` · `washing_station` · `mill` · `exporter` are recommended,
    /// an unrecognized one is carried verbatim, and a consumer that does not
    /// know a role still displays the name. Read it through
    /// ``KnownProducerRole``.
    ///
    /// Absent when the source credits a name without saying what it did, which
    /// is an honest reading rather than a gap — and absent on an `author` or a
    /// `roaster`, where the format states no role to carry.
    public var role: String?

    public init(
        name: String? = nil, url: String? = nil, type: String? = nil, role: String? = nil
    ) {
        self.name = name
        self.url = url
        self.type = type
        self.role = role
    }
}

/// A validated party produced by the codec: `name` is guaranteed non-empty.
///
/// A wire party without a usable name projects as absent where the format has
/// one credit (a `roaster`, an `author`) and is dropped where it has a list
/// (`producers`) — attribution metadata never fails an import either way.
public struct ImportedParty: Equatable, Hashable, Sendable {
    public var name: String
    public var url: String?
    public var type: String?
    /// What this party did, verbatim as sent. See ``Party/role``.
    public var role: String?

    public init(name: String, url: String? = nil, type: String? = nil, role: String? = nil) {
        self.name = name
        self.url = url
        self.type = type
        self.role = role
    }
}

/// The party kinds the spec defines — a typed **view** over ``Party/type``,
/// never a gate on it. Read one with `init?(rawValue:)`: a token outside the set
/// reads as `nil`, and so does an absent `type`, which is the common case — most
/// credits state a name and leave the kind to be inferred from the field that
/// carries them.
public enum KnownPartyType: String, Sendable, Equatable, CaseIterable {
    case person
    case organization
}

/// The producer roles the spec recommends — a typed **view** over
/// ``Party/role``, never a gate on it. Read one with `init?(rawValue:)`: the
/// registry is open, so a value outside the recommended set reads as `nil` and
/// still displays from ``Party/name``.
public enum KnownProducerRole: String, Sendable, Equatable, CaseIterable {
    case producer
    case farm
    case cooperative
    case washingStation = "washing_station"
    case mill
    case exporter
}
