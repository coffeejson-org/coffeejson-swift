/// Which quantity a recipe is stated in terms of — the structural switch a
/// consumer keys on, where `method` is descriptive only. `water` is the default
/// when the wire states none.
///
/// The typed **view** over ``Recipe/basis`` as well, on the same terms as the
/// `Known*` views: `init?(rawValue:)` reads a token, and one outside the set
/// reads as `nil`. It carries the semantic name rather than a `Known` one
/// because ``ImportedRecipe/basis`` is this type too, already resolved — the
/// codec derives an absent or unrecognized basis from the quantities the recipe
/// states, which is the rule the format itself gives.
public enum QuantityBasis: String, Codable, Sendable, Equatable, CaseIterable {
    case water
    case yield

    /// What the format means by an **absent** `basis`: ``water``. Declared by
    /// the schema (`$defs/recipe/properties/basis`, `"default": "water"`), so it
    /// is the format's answer and not a reader's guess. ``Codec`` applies it,
    /// and it is vended for a reader working from ``Recipe/basis`` directly.
    ///
    /// This is the *absent* case only. An **unrecognized** basis is a separate
    /// rule the spec also states — derive the effective basis from the
    /// quantities present — because a new basis value changes which quantity is
    /// required, and falling back to this one would misread the recipe.
    public static let whenUnstated: QuantityBasis = .water
}
