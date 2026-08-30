import Testing
import Foundation
import CoffeeJSON
import CoffeeJSONSchemaTesting

/// Every Swift sample the README prints, compiled and run. A sample that cannot
/// compile teaches a stranger a call that does not exist, and a README is the
/// one place nothing else catches that. Manifest fragments are the exception:
/// `.package`, `.product` and `.testTarget` are `Package.swift` syntax and have
/// no home in a test.
///
/// A plain import, like the sample a reader writes.
@Suite("README samples")
struct ReadmeSamplesTests {
    /// The document behind "A scanned link, end to end".
    private static let source = CoffeeJSON.Document(
        version: "1.0",
        beans: [CoffeeJSON.Bean(id: "lot-1", name: "Nano Challa", roastDate: "2026-06-20")],
        recipes: [CoffeeJSON.Recipe(
            title: "Tetsu Kasuya 4:6",
            method: "pour_over",
            coffee: .grams(20),
            water: .grams(300),
            steps: [CoffeeJSON.Step(atSeconds: 0, toWater: .grams(60)),
                    CoffeeJSON.Step(atSeconds: 45, toWater: .grams(120))],
            beanRef: "lot-1")])

    @Test("a scanned link decodes into the fields the sample prints")
    func scannedLinkEndToEnd() throws {
        let scannedText = try CoffeeJSON.ShareLink.shareURL(
            for: Self.source, host: "apps.example").absoluteString

        let imported = try CoffeeJSON.ShareLink.importDocument(fromScanned: scannedText)
        let recipe = try #require(imported.recipes.first)

        #expect(recipe.title == "Tetsu Kasuya 4:6")
        #expect(recipe.methodSlug == "pour_over")
        #expect(recipe.coffeeGrams == 20)
        #expect(recipe.waterGrams == 300)
        #expect(recipe.ratio == 15)
        #expect(recipe.pourSteps.map(\.atSeconds) == [0, 45])
        #expect(recipe.pourSteps.map(\.cumulativeWaterGrams) == [60, 120])
    }

    @Test("an import failure names its kind, and a validation fault names none")
    func failureKinds() {
        let thrown = #expect(throws: ImportError.self) {
            try CoffeeJSON.ShareLink.importDocument(fromScanned: "not a url at all")
        }
        #expect(thrown?.kind?.rawValue == "not_a_url")
        #expect(ImportError.validation(.missingRequiredField("title")).kind == nil)
    }

    @Test("the dated-field sample reads a day and crosses to an instant and back")
    func calendarDaySample() throws {
        let bean = try #require(
            try CoffeeJSON.Codec.decodeDocument(
                CoffeeJSON.Codec.encode(Self.source)).beans.first)
        let pickedDate = Date(timeIntervalSince1970: 1_781_000_000)

        #expect(bean.roastDate?.iso8601 == "2026-06-20")
        #expect(bean.roastDate?.date(in: .current) != nil)
        #expect(CalendarDay(pickedDate, in: .current) != nil)
        #expect(CalendarDay(year: 2026, month: 6, day: 20)?.iso8601 == "2026-06-20")
    }

    @Test("the translation sample pairs wording with steps")
    func localizationSample() throws {
        let bytes = Data(#"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
          "water":{"value":250,"unit":"gram"},
          "steps":[{"at_s":0,"to_water":{"value":50,"unit":"gram"}},
                   {"at_s":30,"to_water":{"value":250,"unit":"gram"}}],
          "localizations":{"en":{"steps":[{"instruction":"Bloom"},{"instruction":"Pour"}]}}}]}
        """#.utf8)

        let recipe = try JSONDecoder().decode(Document.self, from: bytes).recipes?.first
        let english = recipe?.localizations?["en"]

        #expect(english?.steps(pairedWith: recipe?.steps)?[1].instruction == "Pour")
    }

    @Test("the typed-view sample reads a token and a list of them")
    func tokenViewSample() throws {
        let recipe = CoffeeJSON.Recipe(title: "V60", method: "pour_over")
        let bean = CoffeeJSON.Bean(name: "Nano Challa", process: ["anaerobic", "koji_natural"])

        #expect(recipe.method.flatMap(KnownBrewMethod.init(rawValue:)) == .pourOver)
        #expect(bean.process?.map(KnownProcess.init(rawValue:)) == [.anaerobic, nil])
    }

    /// The carry-raw sample's conformer, verbatim.
    private struct StoredRecipe: RecipeConvertible {
        var title: String
        var grams: Double
        var rawJSON: Data?
        var isEditable: Bool

        var wireRecipe: Recipe { Recipe(title: title, coffee: .grams(grams), water: .grams(250)) }
        var carriedRecipeJSON: Data? { rawJSON }
        // Per instance: a row the user never edited owns nothing and rides its raw.
        var ownedRecipeKeys: Set<Recipe.WireKey> { isEditable ? [.title, .coffee] : [] }
    }

    @Test("the carry-raw sample encodes and then builds a link")
    func carryRawSample() throws {
        let rows = [StoredRecipe(
            title: "Edited", grams: 18,
            rawJSON: Data(#"""
                {"title":"Original","coffee":{"value":15,"unit":"gram"},
                 "water":{"value":250,"unit":"gram"},
                 "notes":"a field the model never modeled"}
                """#.utf8),
            isEditable: true)]

        let bytes = try Codec.encode(recipes: rows)      // beans: and tastings: too
        let url = try ShareLink.shareURL(forEncodedDocument: bytes, host: "apps.example")

        let round = try ShareLink.importDocument(from: url)
        #expect(round.recipes.first?.title == "Edited")
        #expect(round.recipes.first?.coffeeGrams == 18)   // owned: the typed value wins
        #expect(round.recipes.first?.waterGrams == 250)   // unowned: the raw rides out
        let raw = try #require(round.recipes.first?.rawJSON)
        let object = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(object["notes"] as? String == "a field the model never modeled")
    }

    @Test("what this package emits conforms", .enabled(if: SchemaSource.isAvailable))
    func emitConforms() throws {
        let bytes = try Codec.encode(Self.source)
        let validator = SchemaValidator(schema: try #require(SchemaSource.root))
        #expect(validator.validate(try JSONSerialization.jsonObject(with: bytes)).isEmpty)
    }

    @Test("the validator implements every keyword the schema uses",
          .enabled(if: SchemaSource.isAvailable))
    func subsetIsComplete() throws {
        #expect(SchemaValidator.unimplementedKeywords(in: try #require(SchemaSource.root)).isEmpty)
    }
}
