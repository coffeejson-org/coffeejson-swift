import Testing
import Foundation
@testable import CoffeeJSON

/// `localizations` carries a publisher's own translation of their own text.
/// The rules that matter are what it may NOT carry, and what happens when a
/// step overlay does not line up with the steps it claims to translate.
@Suite("Localizations")
struct LocalizationTests {
    @Test("a bilingual bag decodes both languages, on both entities")
    func bilingualRoundTrip() throws {
        let doc = try decodeWireDocument(#"""
        {"coffeejson":"1.0",
         "beans":[{"name":"エチオピア","lang":"ja","roaster_notes":["ジャスミン","ピーチ"],
                   "localizations":{"en":{"name":"Ethiopia","roaster_notes":["Jasmine","Peach"]}}}],
         "recipes":[{"title":"4:6メソッド","lang":"ja",
                     "coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"},
                     "localizations":{"en":{"title":"4:6 Method"}}}]}
        """#)
        #expect(doc.beans?.first?.localizations?["en"]?.name == "Ethiopia")
        #expect(doc.beans?.first?.localizations?["en"]?.roasterNotes == ["Jasmine", "Peach"])
        #expect(doc.recipes?.first?.localizations?["en"]?.title == "4:6 Method")
        // The base is untouched — a localization adds a reading, never replaces one.
        #expect(doc.beans?.first?.name == "エチオピア")
        #expect(doc.recipes?.first?.title == "4:6メソッド")
    }

    @Test("it survives a re-emit byte-for-byte through the codec")
    func survivesReemit() throws {
        let original = Document(
            version: Codec.currentVersion,
            recipes: [Recipe(
                title: "4:6メソッド", coffee: .grams(20), water: .grams(300), lang: "ja",
                localizations: ["en": RecipeLocalization(title: "4:6 Method")])])
        let round = try JSONDecoder().decode(Document.self, from: try Codec.encode(original))
        #expect(round.recipes?.first?.localizations?["en"]?.title == "4:6 Method")
    }

    @Test("step wording pairs by position when the lengths agree")
    func stepsPairWhenLengthsAgree() {
        let base = [Step(atSeconds: 0), Step(atSeconds: 45), Step(atSeconds: 90)]
        let loc = RecipeLocalization(steps: [
            StepLocalization(instruction: "first pour"),
            StepLocalization(),                                  // deliberately untranslated
            StepLocalization(instruction: "third pour"),
        ])
        let paired = loc.steps(pairedWith: base)
        #expect(paired?.count == 3)
        #expect(paired?[0].instruction == "first pour")
        #expect(paired?[1].instruction == nil)
        #expect(paired?[2].instruction == "third pour")
    }

    @Test("a length mismatch discards the whole step overlay, in both directions")
    func lengthMismatchDiscardsOverlay() {
        // The failure this guards is misalignment, not absence: showing step 3's
        // instruction against step 2's pour is confidently wrong, while showing
        // no translation is merely unhelpful. So a short overlay is not zipped
        // to its prefix, and a long one is not truncated.
        let base = [Step(atSeconds: 0), Step(atSeconds: 45), Step(atSeconds: 90)]
        let short = RecipeLocalization(steps: [StepLocalization(instruction: "first pour")])
        let long = RecipeLocalization(steps: (0..<5).map { StepLocalization(instruction: "pour \($0)") })
        #expect(short.steps(pairedWith: base) == nil)
        #expect(long.steps(pairedWith: base) == nil)
    }

    @Test("no step overlay, and no base steps, both read as nothing to pair")
    func absentOverlayPairsToNil() {
        #expect(RecipeLocalization(title: "x").steps(pairedWith: [Step(atSeconds: 0)]) == nil)
        #expect(RecipeLocalization(steps: []).steps(pairedWith: nil)?.isEmpty == true)
    }

    @Test("a non-text member in a localization is ignored, never applied")
    func nonTextMemberIgnored() throws {
        // The authoring schema rejects this outright; a consumer meeting one in
        // the wild must not let it change the brew.
        let doc = try decodeWireDocument(#"""
        {"coffeejson":"1.0",
         "recipes":[{"title":"4:6メソッド","lang":"ja",
                     "coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"},
                     "localizations":{"en":{"title":"4:6 Method","coffee":{"value":18,"unit":"gram"}}}}]}
        """#)
        #expect(doc.recipes?.first?.localizations?["en"]?.title == "4:6 Method")
        #expect(doc.recipes?.first?.coffee?.grams == 20)   // the dose is the recipe's, in every language
    }
}
