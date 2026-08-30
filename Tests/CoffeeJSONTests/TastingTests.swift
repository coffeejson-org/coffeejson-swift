import Testing
import Foundation
@testable import CoffeeJSON

/// The format's third entity. Before it was modeled, a document could carry
/// tastings and this package would decode past them in silence — an unmodeled
/// key is skipped, not rejected, so nothing failed and nothing arrived.
@Suite("Tasting")
struct TastingTests {
    private let full = #"""
    {"coffeejson":"1.0",
     "beans":[{"id":"nano-challa","name":"Nano Challa"},{"id":"las-brisas","name":"Las Brisas"}],
     "recipes":[{"id":"roasters-v60","title":"Roaster's V60","bean_ref":"nano-challa",
                 "coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"},
                 "yield":{"value":262,"unit":"gram"}}],
     "tastings":[{"id":"monday","recipe_ref":"roasters-v60","bean_ref":"las-brisas","rating":4,
                  "perceived":{"extraction":-0.2,"strength":0.1},
                  "descriptors":["blackberry","dark chocolate"],
                  "note":"their method, my bag","lang":"en",
                  "measured":{"tds":1.38,"yield":{"value":258,"unit":"gram"}}}]}
    """#

    @Test("every stated field survives the decode")
    func everyField() throws {
        let t = try #require(try decodeDocument(full).tastings.first)
        #expect(t.id == "monday")
        #expect(t.recipeRef == "roasters-v60")
        #expect(t.beanRef == "las-brisas")
        #expect(t.rating == 4)
        #expect(t.perceivedExtraction == -0.2)
        #expect(t.perceivedStrength == 0.1)
        #expect(t.descriptors == ["blackberry", "dark chocolate"])
        #expect(t.note == "their method, my bag")
        #expect(t.lang == "en")
        #expect(t.tds == 1.38)
        #expect(t.measuredYieldGrams == 258)
    }

    @Test("recipe_ref resolves byte-exactly, with no positional fallback")
    func recipeAssociation() throws {
        let d = try decodeDocument(full)
        #expect(d.associatedRecipe(forTastingAt: 0)?.title == "Roaster's V60")

        // One recipe, no reference: co-location associates a coffee, never a
        // recipe, so this stays unlinked.
        let anon = try decodeDocument(#"""
        {"coffeejson":"1.0","recipes":[{"id":"only","title":"Only",
          "coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"}}],
         "tastings":[{"rating":5}]}
        """#)
        #expect(anon.associatedRecipe(forTastingAt: 0) == nil)
    }

    @Test("an unresolved recipe_ref leaves the tasting unlinked rather than failing")
    func unresolvedRecipeRef() throws {
        let d = try decodeDocument(#"""
        {"coffeejson":"1.0","recipes":[{"id":"only","title":"Only",
          "coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"}}],
         "tastings":[{"recipe_ref":"nowhere"}]}
        """#)
        #expect(d.tastings.count == 1)
        #expect(d.associatedRecipe(forTastingAt: 0) == nil)
    }

    // The substitution case. Answering with the recipe's coffee here would name
    // a coffee that was never in the cup.
    @Test("the tasting's own bean_ref beats the referenced recipe's")
    func beanRefWins() throws {
        let d = try decodeDocument(full)
        #expect(d.associatedBean(forTastingAt: 0)?.name == "Las Brisas")
        #expect(d.associatedBean(forRecipeAt: 0)?.name == "Nano Challa")
    }

    @Test("a single co-located bean associates a tasting that names none")
    func beanColocation() throws {
        let d = try decodeDocument(#"""
        {"coffeejson":"1.0","beans":[{"id":"solo","name":"Solo"}],
         "recipes":[{"id":"r","title":"R","coffee":{"value":18,"unit":"gram"},
                     "water":{"value":300,"unit":"gram"}}],
         "tastings":[{"recipe_ref":"r","rating":5}]}
        """#)
        #expect(d.associatedBean(forTastingAt: 0)?.name == "Solo")
    }

    @Test("several beans and no bean_ref associates none")
    func beanAmbiguity() throws {
        let d = try decodeDocument(#"""
        {"coffeejson":"1.0","beans":[{"id":"a","name":"A"},{"id":"b","name":"B"}],
         "recipes":[{"id":"r","title":"R","coffee":{"value":18,"unit":"gram"},
                     "water":{"value":300,"unit":"gram"}}],
         "tastings":[{"recipe_ref":"r"}]}
        """#)
        #expect(d.associatedBean(forTastingAt: 0) == nil)
    }

    // A tasting evaluates something, so it cannot be the something.
    @Test("a tastings-only document is empty, not a document")
    func tastingsAloneAreNotADocument() {
        #expect(throws: ImportError.decode(.emptyDocument)) {
            try Codec.decodeDocument(Data(#"{"coffeejson":"1.0","tastings":[{"rating":5}]}"#.utf8))
        }
    }

    @Test("a document round-trips its tastings through encode")
    func roundTrip() throws {
        let original = Document(
            version: "1.0",
            recipes: [Recipe(id: "r", title: "R", coffee: .grams(18), water: .grams(300))],
            tastings: [Tasting(
                id: "t", recipeRef: "r", rating: 4,
                perceived: PerceivedAxes(extraction: -0.2),
                descriptors: ["floral"], note: "n", lang: "en",
                measured: MeasuredCup(tds: 1.38, yield: .grams(258)))])
        let decoded = try JSONDecoder().decode(Document.self, from: try Codec.encode(original))
        #expect(decoded.tastings == original.tastings)
    }

    // The reference match is byte-exact, so the normalization form a producer
    // emits is load-bearing — the same rule `bean_ref` already follows.
    @Test("emit normalizes a tasting's three reference keys to NFC")
    func emitNormalizesReferences() throws {
        let decomposed = "cafe\u{0301}"
        let data = try Codec.encode(Document(
            version: "1.0",
            recipes: [Recipe(title: "R", coffee: .grams(18), water: .grams(300))],
            tastings: [Tasting(id: decomposed, recipeRef: decomposed, beanRef: decomposed)]))
        // Byte-level on purpose: Swift's `contains` compares by canonical
        // equivalence, so it would report the decomposed form present in the
        // precomposed output and pass no matter what was emitted. The reference
        // match this rule exists for is byte-exact too.
        let bytes = Array(data)
        #expect(!bytes.contains(subsequence: Array(decomposed.utf8)))
        #expect(bytes.contains(subsequence: Array("caf\u{00E9}".utf8)))
    }

    @Test("junk in the tastings array is skipped rather than throwing the document away")
    func forwardCompat() throws {
        // Unknown members inside a tasting are ignored, as everywhere else.
        let d = try decodeDocument(#"""
        {"coffeejson":"1.0","recipes":[{"id":"r","title":"R","coffee":{"value":18,"unit":"gram"},
          "water":{"value":300,"unit":"gram"}}],
         "tastings":[{"recipe_ref":"r","rating":4,"mood":"content","perceived":{"body":0.5}}]}
        """#)
        let t = try #require(d.tastings.first)
        #expect(t.rating == 4)
        #expect(t.perceivedExtraction == nil)
    }
}

/// The number the format declines to store, and asks every consumer to compute.
/// Two reference implementations that computed it differently — or one that did
/// not compute it at all — would be the disagreement not storing it was meant
/// to avoid.
@Suite("Derived extraction yield")
struct ExtractionYieldTests {
    private func yield(tasting: String, recipe: String = "", ref: String = "r") throws -> Double? {
        let json = """
        {"coffeejson":"1.0","recipes":[{"id":"r","title":"R",
          "coffee":{"value":18,"unit":"gram"},"water":{"value":300,"unit":"gram"}\(recipe)}],
         "tastings":[{"recipe_ref":"\(ref)",\(tasting)}]}
        """
        return try Codec.decodeDocument(Data(json.utf8)).tastings.first?.extractionYieldPercent
    }

    @Test("(beverage mass x tds) / dose, from the recipe's target yield")
    func fromRecipeYield() throws {
        // 262 g x 1.38 % / 18 g = 20.0867 %
        let ey = try #require(try yield(
            tasting: #""measured":{"tds":1.38}"#,
            recipe: #","yield":{"value":262,"unit":"gram"}"#))
        #expect(abs(ey - 20.0867) < 0.001)
    }

    @Test("the weighed beverage beats the recipe's target")
    func measuredYieldWins() throws {
        let ey = try #require(try yield(
            tasting: #""measured":{"tds":1.38,"yield":{"value":258,"unit":"gram"}}"#,
            recipe: #","yield":{"value":262,"unit":"gram"}"#))
        #expect(abs(ey - 19.78) < 0.01)
    }

    @Test("an immersion recipe with no target yield still derives, given a weighed cup")
    func immersion() throws {
        let ey = try #require(try yield(
            tasting: #""measured":{"tds":1.31,"yield":{"value":431,"unit":"gram"}}"#))
        #expect(abs(ey - 31.3672) < 0.001)
    }

    @Test("an ounce reading converts before dividing")
    func unitConversion() throws {
        let metric = try #require(try yield(
            tasting: #""measured":{"tds":1.4,"yield":{"value":250,"unit":"gram"}}"#))
        let imperial = try #require(try yield(
            tasting: #""measured":{"tds":1.4,"yield":{"value":8.8184904874,"unit":"ounce"}}"#))
        #expect(abs(metric - imperial) < 0.0001)
    }

    @Test("a missing input derives nothing rather than guessing")
    func missingInputs() throws {
        #expect(try yield(tasting: #""rating":4"#) == nil)                       // no tds
        #expect(try yield(tasting: #""measured":{"tds":1.38}"#) == nil)          // no beverage mass
        // No resolved recipe, so no dose to divide by.
        #expect(try yield(
            tasting: #""measured":{"tds":1.4,"yield":{"value":250,"unit":"gram"}}"#,
            ref: "nowhere") == nil)
    }

    // A window is the author's number and a midpoint is not, so `Quantity.grams`
    // states none — and a derivation that invented one would publish a figure
    // nobody wrote.
    @Test("a windowed beverage mass derives nothing")
    func windowedYield() throws {
        #expect(try yield(tasting: #""measured":{"tds":9,"yield":{"min":32,"max":34,"unit":"gram"}}"#) == nil)
    }

    @Test("a non-positive reading derives nothing")
    func nonPositive() throws {
        #expect(try yield(tasting: #""measured":{"tds":0,"yield":{"value":250,"unit":"gram"}}"#) == nil)
        #expect(try yield(tasting: #""measured":{"tds":1.4,"yield":{"value":0,"unit":"gram"}}"#) == nil)
    }
}


private extension Array where Element: Equatable {
    /// Literal subsequence search — the byte-level counterpart of
    /// `String.contains`, which compares by canonical equivalence.
    func contains(subsequence: [Element]) -> Bool {
        guard !subsequence.isEmpty, count >= subsequence.count else { return subsequence.isEmpty }
        for start in 0...(count - subsequence.count)
        where Array(self[start..<(start + subsequence.count)]) == subsequence { return true }
        return false
    }
}
