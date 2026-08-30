import Foundation

// The mechanism under the export seam. The fidelity contract is stated on
// ``Codec/encode(beans:recipes:tastings:generator:)``, which is what a consumer
// calls; nothing here is API.

/// What ``RecipeConvertible`` states, in the shape the re-emit consumes.
struct RecipeOverlay: Sendable {
    /// The verbatim bytes of a previously-carried `recipe` object — e.g. an
    /// ``ImportedRecipe/rawJSON`` slice captured on decode.
    var raw: Data

    /// The only keys that transfer from the typed recipe on re-emit. Everything
    /// else rides `raw`.
    var ownedKeys: Set<Recipe.WireKey>
}

/// ``RecipeOverlay`` for the other entity the format defines. Two types rather
/// than one generic: a shared `RawRepresentable & CodingKey` bound erases both
/// key sets to `String` and loses the type safety the split buys.
struct BeanOverlay: Sendable {
    /// The verbatim bytes of a previously-carried `bean` object — e.g. an
    /// ``ImportedBean/rawJSON`` slice captured on decode.
    var raw: Data

    /// The only keys that transfer from the typed bean on re-emit. Everything
    /// else rides `raw`.
    var ownedKeys: Set<Bean.WireKey>
}

extension Codec {
    /// Faithful re-emit: encode `document`, then replace each `recipes[i]` with
    /// its typed values overlaid onto `recipeOverlays[i]`'s carried raw, on the
    /// contract ``encode(beans:recipes:tastings:generator:)`` states.
    ///
    /// Lenient edges each fall back to the plain typed bytes for that element: a
    /// `nil` overlay, a `raw` that is not a JSON object, and any index past the
    /// end of the overlay array. Key ordering is not promised. Throws only what
    /// ``encode(_:)`` throws.
    ///
    /// `beanOverlays` applies the identical contract to `beans`, and defaults to
    /// empty because a recipe-only document has no beans to overlay.
    static func encode(
        _ document: Document,
        recipeOverlays: [RecipeOverlay?],
        beanOverlays: [BeanOverlay?] = []
    ) throws -> Data {
        let typed = try encode(document)
        // Reparse the just-encoded document. If that fails, the typed bytes are
        // already a valid emit, so return them.
        guard var root = try? JSONSerialization.jsonObject(with: typed) as? [String: Any]
        else { return typed }

        // NFC after the merge, covering both the typed value that crossed over
        // and the raw value that stayed. Only *owned* keys cross, so an unowned
        // linking key would otherwise ride out in whatever form its producer
        // used — a document that arrived linked and leaves unlinked, with
        // nothing thrown. Not an exception to "every non-owned raw key passes
        // through verbatim": NFC is the form the format requires a producer to
        // emit, and this path is a producer. Ownership still decides which
        // *value* survives.
        if var recipes = root["recipes"] as? [[String: Any]] {
            for index in recipes.indices {
                guard index < recipeOverlays.count, let overlay = recipeOverlays[index] else { continue }
                recipes[index] = normalizingLinkKeys(
                    LinkingKeys.recipe,
                    in: overlaid(
                        typed: recipes[index], with: overlay.raw,
                        ownedKeys: overlay.ownedKeys.map(\.rawValue)))
            }
            root["recipes"] = recipes
        }

        if var beans = root["beans"] as? [[String: Any]] {
            for index in beans.indices {
                guard index < beanOverlays.count, let overlay = beanOverlays[index] else { continue }
                beans[index] = normalizingLinkKeys(
                    LinkingKeys.bean,
                    in: overlaid(
                        typed: beans[index], with: overlay.raw,
                        ownedKeys: overlay.ownedKeys.map(\.rawValue)))
            }
            root["beans"] = beans
        }

        return (try? JSONSerialization.data(withJSONObject: root)) ?? typed
    }

    /// Re-emit a document carrying verbatim bean payloads only — the bean-side
    /// counterpart of the recipe overlay call, for a bean-only share.
    static func encode(_ document: Document, beanOverlays: [BeanOverlay?]) throws -> Data {
        try encode(document, recipeOverlays: [], beanOverlays: beanOverlays)
    }

    /// Overlay one element: start from the verbatim `raw`, then for each owned
    /// key copy the typed element's value — present overwrites, absent removes
    /// (assigning `nil` deletes the key). A `raw` that is not a JSON object
    /// yields the typed element unchanged.
    ///
    /// Keys arrive as strings because `Recipe.WireKey` and `Bean.WireKey` are
    /// distinct types over the same rule, which lives here once.
    private static func overlaid(
        typed: [String: Any], with raw: Data, ownedKeys: some Sequence<String>
    ) -> [String: Any] {
        guard var result = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return typed }
        for key in ownedKeys {
            result[key] = typed[key]
        }
        return result
    }
}
