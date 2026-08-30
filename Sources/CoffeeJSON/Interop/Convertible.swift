import Foundation

/// A consumer's recipe model, projected onto the wire — the carry-raw fidelity
/// contract adopted as one conformance instead of assembled by hand.
///
/// A conformer states three things and ``Codec/encode(beans:recipes:tastings:generator:)``
/// does the rest: pairing each model with its raw, aligning the indices, and
/// running the re-emit. That call is the package's one export seam; the
/// mechanism under it is not API.
///
/// `generator` is an **envelope** member and never an owned key: the software
/// that wrote a document names itself once for the file, not once per recipe.
/// Pass it to the encode entry point.
public protocol RecipeConvertible {
    /// The typed projection of the fields this model holds.
    var wireRecipe: Recipe { get }

    /// The verbatim `recipe` payload this model carried in on import — an
    /// ``ImportedRecipe/rawJSON`` slice — or `nil` for a model the consumer
    /// built itself, which emits its typed bytes alone.
    var carriedRecipeJSON: Data? { get }

    /// The wire keys ``wireRecipe`` is authoritative for: present wins over the
    /// raw, absent strips it. Everything else rides the raw verbatim.
    ///
    /// **Per instance, deliberately.** A model varies its policy by value and
    /// this package must not know why — a read-only import owns nothing and
    /// rides its raw whole, an edited row owns its column set, a consumer that
    /// re-links on share may always own `bean_ref`. A static answer would force
    /// one policy per type and push the exception back into the hand-assembly
    /// this protocol exists to delete.
    var ownedRecipeKeys: Set<Recipe.WireKey> { get }
}

/// A consumer's bean model, projected onto the wire — the ``RecipeConvertible``
/// contract for the other entity the format defines, on the same terms.
///
/// Both entities can be imported, edited and re-shared, so both need the same
/// seam: a roaster's bag stating a compound process, several credited parties or
/// a rest window has to survive an edit-and-re-share whether or not the consumer
/// models those fields.
public protocol BeanConvertible {
    /// The typed projection of the fields this model holds.
    var wireBean: Bean { get }

    /// The verbatim `bean` payload this model carried in on import — an
    /// ``ImportedBean/rawJSON`` slice — or `nil` for a model the consumer built
    /// itself.
    var carriedBeanJSON: Data? { get }

    /// The wire keys ``wireBean`` is authoritative for. Per instance, for the
    /// reason ``RecipeConvertible/ownedRecipeKeys`` gives.
    var ownedBeanKeys: Set<Bean.WireKey> { get }
}

extension Codec {
    /// Encode a document straight from consumer models — **the export seam**:
    /// each model's typed projection overlaid on the raw it carried, owned keys
    /// authoritative and every other raw key verbatim. ``encode(_:)`` is the
    /// other way out, and it emits the typed projection alone.
    ///
    /// The fidelity contract, in full:
    ///
    /// - an **owned** key is authoritative from the typed projection: present ⇒
    ///   the typed value wins over the raw; absent ⇒ stripped from the raw, so
    ///   no stale value leaks;
    /// - **every other raw key** passes through verbatim — unknown and future
    ///   fields included — and an *unowned* typed key never clobbers the raw:
    ///   ownership is the single authority;
    /// - a model carrying **no raw** emits its typed bytes alone;
    /// - **provenance is never auto-stamped.** It lives on the envelope as
    ///   `generator`, which is why it is a parameter here and not an owned key.
    ///
    /// Key ordering is not promised. Throws only what ``encode(_:)`` throws.
    ///
    /// A collection that is empty is omitted from the envelope rather than
    /// emitted empty, per the format's rule. The document-level "at least one of
    /// `beans` or `recipes`" rule is unchanged and unenforced here: this entry
    /// point adds no validation.
    ///
    /// The emitted version is always ``currentVersion``, so there is no version
    /// parameter to pass: an emit states what *this* producer wrote.
    ///
    /// `tastings` ride **typed-only**, which is parity rather than a compromise:
    /// the primitive has no tasting overlay either. They are carried here because
    /// the format forbids a tastings-only document — a consumer with tastings
    /// always has beans or recipes too, so an entry point that could not carry
    /// them would send that consumer back to the primitive for its whole
    /// document. If tasting fidelity on re-emit is ever needed, the primitive
    /// gains a `TastingOverlay` first and this follows it.
    ///
    /// For a share link, encode and then build:
    ///
    ///     let bytes = try Codec.encode(recipes: models)
    ///     let url = try ShareLink.shareURL(forEncodedDocument: bytes, host: host)
    public static func encode(
        beans: [any BeanConvertible] = [],
        recipes: [any RecipeConvertible] = [],
        tastings: [Tasting] = [],
        generator: Generator? = nil
    ) throws -> Data {
        let document = Document(
            version: currentVersion,
            beans: beans.isEmpty ? nil : beans.map(\.wireBean),
            recipes: recipes.isEmpty ? nil : recipes.map(\.wireRecipe),
            tastings: tastings.isEmpty ? nil : tastings,
            generator: generator)
        // One overlay per element, in the same order, so index alignment is by
        // construction rather than by the caller remembering. A model carrying no
        // raw maps to nil, which the primitive already reads as "typed bytes".
        return try encode(
            document,
            recipeOverlays: recipes.map { model in
                model.carriedRecipeJSON.map {
                    RecipeOverlay(raw: $0, ownedKeys: model.ownedRecipeKeys)
                }
            },
            beanOverlays: beans.map { model in
                model.carriedBeanJSON.map {
                    BeanOverlay(raw: $0, ownedKeys: model.ownedBeanKeys)
                }
            })
    }
}
