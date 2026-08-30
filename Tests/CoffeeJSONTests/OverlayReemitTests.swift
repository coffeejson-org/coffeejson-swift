import Testing
import Foundation
@testable import CoffeeJSON

/// The re-emit half of carry-raw, now a package primitive: encode a document but
/// overlay each recipe's typed values onto a carried verbatim raw. Owned keys are
/// authoritative from the typed recipe (present wins, absent strips); every other
/// raw key — unknown and future fields included — passes through verbatim.
@Suite("CoffeeJSON overlay re-emit")
struct OverlayReemitTests {
    private func recipeObjects(_ data: Data) throws -> [[String: Any]] {
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["recipes"] as? [[String: Any]])
    }

    private func firstRecipeObject(_ data: Data) throws -> [String: Any] {
        try #require(try recipeObjects(data).first)
    }

    private func document(_ recipes: Recipe...) -> Document {
        Document(version: Codec.currentVersion, recipes: recipes)
    }

    @Test("an owned key takes the typed value; every non-owned raw key (unknown/future included) passes through verbatim")
    func ownedWinsAndNonOwnedPassesThrough() throws {
        // The raw carries a stale title, a display-only field, and a future/unknown key.
        let raw = Data(#"""
        {"title":"STALE","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
         "roaster_tip":"drink within 20 min","x_future":{"k":1}}
        """#.utf8)
        let overlay = RecipeOverlay(
            raw: raw, ownedKeys: [.title, .coffee, .water])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "Fresh", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [overlay]))

        #expect(recipe["title"] as? String == "Fresh")                             // owned → typed wins
        #expect(recipe["roaster_tip"] as? String == "drink within 20 min")         // non-owned raw survives
        #expect((recipe["x_future"] as? [String: Any])?["k"] as? Double == 1)      // future key survives
    }

    @Test("an owned key absent from the typed recipe is stripped from the raw, so no stale value leaks")
    func ownedButAbsentStripsStaleValue() throws {
        let raw = Data(#"""
        {"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"notes":"OLD NOTE"}
        """#.utf8)
        // The typed recipe owns `notes` but carries none.
        let overlay = RecipeOverlay(
            raw: raw, ownedKeys: [.title, .coffee, .water, .notes])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "x", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [overlay]))

        #expect(recipe["notes"] == nil)
    }

    @Test("an unowned key present in the typed recipe never clobbers the raw — ownership is the only authority")
    func unownedTypedKeyIsIgnored() throws {
        let raw = Data(#"""
        {"title":"RAW TITLE","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}
        """#.utf8)
        // The typed recipe carries a different title, but `title` is not owned.
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.coffee, .water])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "TYPED TITLE", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [overlay]))

        #expect(recipe["title"] as? String == "RAW TITLE")
    }

    @Test("a narrow ownedKeys set re-emits a carried espresso raw verbatim, re-stamping only what it owns (carry-raw port)")
    func espressoVerbatimReemitRestampsOwnedKey() throws {
        // A carried raw espresso recipe, exactly as captured in ImportedRecipe.rawJSON.
        let raw = Data(#"""
        {"title":"Onyx Monarch","method":"espresso","basis":"yield",
         "coffee":{"value":19,"unit":"gram"},"yield":{"value":47,"unit":"gram"},
         "water_temp":{"value":93,"unit":"celsius"},"grind":{"setting":"Niche 15"},
         "pressure":{"value":9,"unit":"bar"},"preinfusion_s":3.5,"finish_s":26.5,
         "notes":"as the roaster wrote it"}
        """#.utf8)
        // The consumer maps a typed recipe whose only owned key is the one it re-stamps.
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.notes])
        let emitted = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "Onyx Monarch", notes: "edited by the sender")),
            recipeOverlays: [overlay]))

        #expect(emitted["basis"] as? String == "yield")
        #expect(emitted["method"] as? String == "espresso")
        #expect((emitted["yield"] as? [String: Any])?["value"] as? Double == 47)
        #expect((emitted["pressure"] as? [String: Any])?["value"] as? Double == 9)
        #expect(emitted["preinfusion_s"] as? Double == 3.5)
        #expect(emitted["finish_s"] as? Double == 26.5)
        #expect(emitted["water"] == nil)               // yield-basis carries no water
        #expect(emitted["steps"] == nil)
        #expect(emitted["notes"] as? String == "edited by the sender")  // re-stamped
    }

    @Test("an owned key absent from the typed recipe strips the raw's value (deliberate tightening)")
    func ownedButAbsentStripsRawValue() throws {
        let raw = Data(#"""
        {"title":"x","coffee":{"value":18,"unit":"gram"},"notes":"as the roaster wrote it"}
        """#.utf8)
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.notes])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "x", coffee: .grams(18))),   // no notes
            recipeOverlays: [overlay]))

        #expect(recipe["notes"] == nil)
    }

    @Test("a nil overlay falls back to the typed bytes for that recipe")
    func nilOverlayFallsBackToTyped() throws {
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "Typed", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [nil]))

        #expect(recipe["title"] as? String == "Typed")
    }

    @Test("an unparseable raw falls back to the typed bytes for that recipe")
    func unparseableRawFallsBackToTyped() throws {
        let overlay = RecipeOverlay(raw: Data("not json".utf8), ownedKeys: [.title])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "Typed", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [overlay]))

        #expect(recipe["title"] as? String == "Typed")
    }

    @Test("an overlay array shorter than recipes leaves the tail on the typed path")
    func shortOverlayArrayLeavesTailTyped() throws {
        let raw = Data(#"{"title":"raw-first","coffee":{"value":15,"unit":"gram"},"extra":"kept"}"#.utf8)
        let recipes = try recipeObjects(Codec.encode(
            document(
                Recipe(title: "First", coffee: .grams(15), water: .grams(250)),
                Recipe(title: "Second", coffee: .grams(18), water: .grams(300))),
            recipeOverlays: [RecipeOverlay(raw: raw, ownedKeys: [.coffee])]))   // only one overlay

        #expect(recipes.count == 2)
        #expect(recipes[0]["extra"] as? String == "kept")       // overlay applied to the head
        #expect(recipes[1]["title"] as? String == "Second")     // tail stays on the typed path
    }

    @Test("an overlay array longer than recipes ignores the extras")
    func longOverlayArrayIgnoresExtras() throws {
        let raw = Data(#"{"title":"raw","coffee":{"value":15,"unit":"gram"},"extra":"kept"}"#.utf8)
        let recipes = try recipeObjects(Codec.encode(
            document(Recipe(title: "Only", coffee: .grams(15), water: .grams(250))),
            recipeOverlays: [
                RecipeOverlay(raw: raw, ownedKeys: [.coffee]),
                RecipeOverlay(raw: Data("{}".utf8), ownedKeys: []),   // stray extra, must be ignored
            ]))

        #expect(recipes.count == 1)
        #expect(recipes[0]["extra"] as? String == "kept")
    }

    @Test("a multi-recipe document overlays each recipe by its own index; empty ownedKeys is pure verbatim")
    func multiRecipeOverlaysPerIndex() throws {
        let rawA = Data(#"{"title":"A-raw","coffee":{"value":15,"unit":"gram"},"a_extra":1}"#.utf8)
        let rawB = Data(#"{"title":"B-raw","coffee":{"value":18,"unit":"gram"},"b_extra":2}"#.utf8)
        let recipes = try recipeObjects(Codec.encode(
            document(
                Recipe(title: "A-typed", coffee: .grams(15), water: .grams(250)),
                Recipe(title: "B-typed", coffee: .grams(18), water: .grams(300))),
            recipeOverlays: [
                RecipeOverlay(raw: rawA, ownedKeys: [.title]),   // A: title owned → typed wins, a_extra survives
                RecipeOverlay(raw: rawB, ownedKeys: []),         // B: nothing owned → pure verbatim raw
            ]))

        #expect(recipes[0]["title"] as? String == "A-typed")
        #expect(recipes[0]["a_extra"] as? Double == 1)
        #expect(recipes[1]["title"] as? String == "B-raw")       // B rides its raw verbatim
        #expect(recipes[1]["b_extra"] as? Double == 2)
    }

    @Test("a re-emit that owns grind and steps carries the size and the per-pour duration back out")
    func ownedGrindAndStepsKeepSizeAndDuration() throws {
        // A consumer that rebuilds grind and steps from its own columns owns
        // both keys, so the raw's versions are replaced wholesale. What it can
        // model is what survives — which is why these two have to be modeled.
        let raw = Data(#"""
        {"title":"Hybrid","coffee":{"value":14,"unit":"gram"},"water":{"value":240,"unit":"gram"},
         "grind":{"size":"medium"},
         "steps":[{"at_s":0,"to_water":{"value":40,"unit":"gram"},"action_duration_s":10}]}
        """#.utf8)
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.title, .coffee, .water, .grind, .steps])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(
                title: "Hybrid", coffee: .grams(14), water: .grams(240),
                grind: Grind(size: "medium_fine"),
                steps: [Step(atSeconds: 0, toWater: .grams(40), actionDurationSeconds: 12)])),
            recipeOverlays: [overlay]))

        #expect((recipe["grind"] as? [String: Any])?["size"] as? String == "medium_fine")
        let steps = try #require(recipe["steps"] as? [[String: Any]])
        #expect(steps.first?["action_duration_s"] as? Double == 12)
    }

    @Test("an unowned grind rides the raw, size and all")
    func unownedGrindKeepsItsSizeVerbatim() throws {
        let raw = Data(#"""
        {"title":"V60","coffee":{"value":24,"unit":"gram"},"water":{"value":360,"unit":"gram"},
         "grind":{"size":"medium_fine"}}
        """#.utf8)
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.title, .coffee, .water])
        let recipe = try firstRecipeObject(Codec.encode(
            document(Recipe(title: "V60", coffee: .grams(24), water: .grams(360))),
            recipeOverlays: [overlay]))

        #expect((recipe["grind"] as? [String: Any])?["size"] as? String == "medium_fine")
    }

    @Test("an unowned recipe id is written out in NFC, so a tasting that names it still resolves")
    func unownedRecipeIdIsNormalized() throws {
        // The raw's `id` is decomposed and the overlay does not own `id`, so it
        // rides the raw untouched — while the tasting's `recipe_ref` goes down the
        // typed path and is normalized. Without a normalization on the merged
        // element the two ends disagree and the link is silently lost.
        let decomposed = "cafe\u{0301}"
        let raw = Data("""
        {"id":"cafe\\u0301","title":"V60","coffee":{"value":15,"unit":"gram"},
         "water":{"value":250,"unit":"gram"},"roaster_tip":"drink soon"}
        """.utf8)
        let overlay = RecipeOverlay(raw: raw, ownedKeys: [.title, .coffee, .water])
        let data = try Codec.encode(
            Document(
                version: Codec.currentVersion,
                recipes: [Recipe(id: decomposed, title: "V60", coffee: .grams(15), water: .grams(250))],
                tastings: [Tasting(recipeRef: decomposed, rating: 4)]),
            recipeOverlays: [overlay])

        let round = try Codec.decodeDocument(data)
        #expect(round.associatedRecipe(forTastingAt: 0)?.title == "V60")
        // The unowned key still rides the raw: normalization decides a form, never
        // which value survives.
        #expect(try firstRecipeObject(data)["roaster_tip"] as? String == "drink soon")
    }
}
