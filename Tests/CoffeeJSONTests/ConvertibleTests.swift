import Testing
import Foundation
@testable import CoffeeJSON

/// A consumer-shaped recipe model: a few columns it edits, the verbatim payload
/// it carried in, and an ownership policy that varies **per value** — which is
/// what a real stateful consumer has and what a static requirement could not
/// express.
private struct ColumnarRecipe: RecipeConvertible {
    var title: String
    var coffeeGrams: Double
    var waterGrams: Double
    var beanRef: String?
    var carriedRecipeJSON: Data?
    /// `true` for a row imported and never edited: it rides its raw whole.
    var isReadOnly: Bool = false

    var wireRecipe: Recipe {
        Recipe(
            title: title, coffee: .grams(coffeeGrams), water: .grams(waterGrams),
            beanRef: beanRef)
    }

    var ownedRecipeKeys: Set<Recipe.WireKey> {
        isReadOnly ? [] : [.title, .coffee, .water, .beanRef]
    }
}

/// The bean counterpart, on the same terms.
private struct ColumnarBean: BeanConvertible {
    var id: String?
    var name: String
    var carriedBeanJSON: Data?
    var isReadOnly: Bool = false

    var wireBean: Bean { Bean(id: id, name: name) }

    var ownedBeanKeys: Set<Bean.WireKey> {
        isReadOnly ? [] : [.id, .name]
    }
}

/// The seam is sugar, and these prove it: for the same inputs the generic path
/// emits the same document as the hand-assembled primitive — every key, every
/// value, on both collections. A difference means the sugar added behavior,
/// which is the whole thing under test.
///
/// **Compared after canonicalizing key order, not byte-for-byte.** Raw byte
/// equality looks like the stronger assertion and is in fact an unsound one
/// here: `Codec.encode` promises no canonical byte form, and neither encoder is
/// order-stable across two calls in one process — the same call twice produces
/// two different byte strings. A byte comparison would fail on the ordering the
/// package explicitly refuses to promise, while saying nothing extra about the
/// content. Sorting keys recursively removes exactly that freedom and nothing
/// else, and the negative control at the bottom proves the comparison can still
/// fail.
@Suite("Convertible export seam")
struct ConvertibleTests {
    /// The same JSON with every object's keys sorted, so two emissions of one
    /// document compare equal while any difference in content still shows.
    private func canonical(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func expectSameDocument(
        _ sugar: Data, _ hand: Data,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(try canonical(sugar) == canonical(hand), comment, sourceLocation: sourceLocation)
    }

    private let rawRecipe = Data(#"""
    {"title":"STALE","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
     "method":"pour_over","roaster_tip":"drink within 20 min","x_future":{"k":1}}
    """#.utf8)

    private let rawBean = Data(#"""
    {"name":"STALE","roaster":{"name":"Example Roastery"},"process":["anaerobic","honey"],
     "rest_days":{"min":14},"x_future":{"lot":"A"}}
    """#.utf8)

    /// The re-emit driven directly, with the three pieces assembled by hand —
    /// the mechanism the seam exists to do for a consumer, written out once so
    /// the tests can hold the seam against it. Reachable here only because the
    /// suite is `@testable`: it is not API.
    private func handAssembled(
        beans: [ColumnarBean] = [],
        recipes: [ColumnarRecipe] = [],
        tastings: [Tasting] = [],
        generator: Generator? = nil
    ) throws -> Data {
        let document = Document(
            version: Codec.currentVersion,
            beans: beans.isEmpty ? nil : beans.map(\.wireBean),
            recipes: recipes.isEmpty ? nil : recipes.map(\.wireRecipe),
            tastings: tastings.isEmpty ? nil : tastings,
            generator: generator)
        return try Codec.encode(
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

    @Test("a model with no carried raw emits the same bytes as the typed path")
    func noRawIsSugar() throws {
        let model = ColumnarRecipe(
            title: "V60", coffeeGrams: 15, waterGrams: 250, beanRef: nil,
            carriedRecipeJSON: nil)
        try expectSameDocument(try Codec.encode(recipes: [model]),
                               try handAssembled(recipes: [model]))
    }

    @Test("a model with a raw and an owned set emits the same bytes as the overlay path")
    func rawWithOwnedKeysIsSugar() throws {
        let model = ColumnarRecipe(
            title: "Fresh", coffeeGrams: 15, waterGrams: 250, beanRef: "lot-1",
            carriedRecipeJSON: rawRecipe)
        try expectSameDocument(try Codec.encode(recipes: [model]),
                               try handAssembled(recipes: [model]))
    }

    @Test("an empty owned set rides the raw whole, identically on both paths")
    func rawWithEmptyOwnedSetIsSugar() throws {
        let model = ColumnarRecipe(
            title: "IGNORED", coffeeGrams: 99, waterGrams: 99, beanRef: nil,
            carriedRecipeJSON: rawRecipe, isReadOnly: true)
        try expectSameDocument(try Codec.encode(recipes: [model]),
                               try handAssembled(recipes: [model]))
    }

    @Test("mixed collections agree, and order is preserved on both paths")
    func mixedCollectionsAreSugar() throws {
        let beans = [
            ColumnarBean(id: "lot-1", name: "Nano Challa", carriedBeanJSON: rawBean),
            ColumnarBean(id: "lot-2", name: "Suke Quto", carriedBeanJSON: nil),
        ]
        let recipes = [
            ColumnarRecipe(title: "First", coffeeGrams: 15, waterGrams: 250,
                           beanRef: "lot-1", carriedRecipeJSON: rawRecipe),
            ColumnarRecipe(title: "Second", coffeeGrams: 18, waterGrams: 300,
                           beanRef: "lot-2", carriedRecipeJSON: nil),
        ]
        let tastings = [Tasting(recipeRef: "r", rating: 4)]
        let generator = Generator(name: "A Producer", version: "1.0")

        try expectSameDocument(
            try Codec.encode(beans: beans, recipes: recipes,
                             tastings: tastings, generator: generator),
            try handAssembled(beans: beans, recipes: recipes,
                              tastings: tastings, generator: generator))
    }

    @Test("an empty collection is omitted from the envelope, on both paths")
    func emptyCollectionsAreOmitted() throws {
        let bean = ColumnarBean(id: "lot-1", name: "Nano Challa", carriedBeanJSON: nil)
        let data = try Codec.encode(beans: [bean])
        try expectSameDocument(data, try handAssembled(beans: [bean]))

        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["beans"] != nil)
        #expect(root["recipes"] == nil)     // omitted, not emitted empty
        #expect(root["tastings"] == nil)
        #expect(root["generator"] == nil)
    }

    @Test("ownership varies per instance: one type, two values, two documents")
    func ownershipIsPerInstance() throws {
        // The requirement a static property could not express, so this is the
        // test that pins the choice rather than merely exercising it.
        let edited = ColumnarRecipe(
            title: "Edited", coffeeGrams: 16, waterGrams: 260, beanRef: nil,
            carriedRecipeJSON: rawRecipe)
        var readOnly = edited
        readOnly.isReadOnly = true

        func title(of data: Data) throws -> String? {
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let recipes = try #require(root["recipes"] as? [[String: Any]])
            return recipes.first?["title"] as? String
        }

        let editedTitle = try title(of: Codec.encode(recipes: [edited]))
        let readOnlyTitle = try title(of: Codec.encode(recipes: [readOnly]))
        #expect(editedTitle == "Edited")
        #expect(readOnlyTitle == "STALE")
    }

    @Test("a conforming recipe model round-trips, and the raw it did not own survives")
    func recipeConformerRoundTrips() throws {
        let model = ColumnarRecipe(
            title: "Fresh", coffeeGrams: 15, waterGrams: 250, beanRef: nil,
            carriedRecipeJSON: rawRecipe)
        let data = try Codec.encode(recipes: [model])

        let imported = try Codec.decodeDocument(data)
        #expect(imported.recipes.first?.title == "Fresh")           // owned wins
        #expect(imported.recipes.first?.methodSlug == "pour_over")  // unowned rides the raw

        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recipe = try #require((root["recipes"] as? [[String: Any]])?.first)
        #expect(recipe["roaster_tip"] as? String == "drink within 20 min")
        #expect((recipe["x_future"] as? [String: Any])?["k"] as? Double == 1)
    }

    @Test("a conforming bean model round-trips, and the raw it did not own survives")
    func beanConformerRoundTrips() throws {
        let model = ColumnarBean(id: "lot-1", name: "Nano Challa", carriedBeanJSON: rawBean)
        let data = try Codec.encode(beans: [model])

        let imported = try Codec.decodeDocument(data)
        #expect(imported.beans.first?.name == "Nano Challa")               // owned wins
        #expect(imported.beans.first?.process == ["anaerobic", "honey"])   // unowned survives
        #expect(imported.beans.first?.restDays?.min == 14)
    }

    @Test("a link is two steps, and its payload is the document that was encoded")
    func linkIsTwoSteps() throws {
        // The seam deliberately adds nothing to the transport, so this is the
        // documented path rather than a workaround.
        let model = ColumnarRecipe(
            title: "V60", coffeeGrams: 15, waterGrams: 250, beanRef: nil,
            carriedRecipeJSON: nil)
        let bytes = try Codec.encode(recipes: [model])
        let url = try CoffeeJSON.ShareLink.shareURL(forEncodedDocument: bytes, host: "example.com")
        #expect(CoffeeJSON.ShareLink.payloadBytes(from: url) == bytes)
    }

    @Test("the comparison can fail — a different owned set produces a different document")
    func theComparisonBites() throws {
        // A suite comparing two paths that are supposed to agree is the easiest
        // possible way to write a test that always passes. This is the assertion
        // that says it does not.
        let model = ColumnarRecipe(
            title: "Fresh", coffeeGrams: 15, waterGrams: 250, beanRef: nil,
            carriedRecipeJSON: rawRecipe)
        var readOnly = model
        readOnly.isReadOnly = true
        let sugar = try canonical(try Codec.encode(recipes: [model]))
        let differentOwnership = try canonical(try handAssembled(recipes: [readOnly]))
        #expect(sugar != differentOwnership)
    }
}
