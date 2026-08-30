import Testing
import Foundation
@testable import CoffeeJSON
import CoffeeJSONSchemaTesting

/// Does what this package encodes conform to the published schema?
///
/// The question a reference implementation exists to answer, and the one nothing
/// here could answer before. `SchemaCoverageTests` proves the typed layer can
/// *read* every key the schema declares; these tests read back a byte this
/// package *writes* and hold it against the format's own rules.
///
/// Both emit paths are covered, because they are different code: the typed
/// encoder serializes a `Document`, and the overlay re-emit merges typed values
/// onto carried raw bytes through `JSONSerialization`. A document that conforms
/// out of one says nothing about the other.
@Suite("Emit conformance")
struct EmitConformanceTests {
    private func validator() throws -> SchemaValidator {
        SchemaValidator(schema: try #require(SchemaSource.root))
    }

    private func validate(_ data: Data) throws -> [String] {
        try validator().validate(try JSONSerialization.jsonObject(with: data))
    }

    /// A document exercising the breadth of what the typed layer can state:
    /// both bases, a window, a bean with an origin and credits, a tasting, and
    /// the localizations whose keywords the validator gained last.
    private func richDocument() -> Document {
        Document(
            version: Codec.currentVersion,
            beans: [Bean(
                id: "lot-1", name: "Nano Challa",
                roaster: Party(name: "Example Roastery", url: "https://example.com", type: "organization"),
                images: ["https://example.com/bag.jpg"],
                origin: Origin(type: "single", items: [OriginItem(
                    name: "Lot No. 1", country: "ET", region: "Jimma",
                    producers: [Party(name: "A Farmer", type: "person", role: "producer"),
                                Party(name: "A Cooperative", role: "cooperative")],
                    altitude: Altitude(min: 1800, max: 2000, unit: "meter"),
                    process: ["washed"], varietals: ["Heirloom"], percentage: 100)]),
                process: ["washed"], dryingMethod: "raised_bed", varietals: ["Heirloom"],
                roastLevel: "light_medium", roastAgtron: 72,
                restDays: RestDays(min: 7, max: 60), roastDate: "2026-01-14",
                productionRoaster: "Diedrich CR-70", decaf: false, form: "drip_bag",
                preferredExtraction: "filter", certifications: ["organic"],
                roasterNotes: ["peach", "jasmine"], description: "A washed Ethiopian.",
                lang: "en",
                localizations: ["ja": BeanLocalization(name: "ナノ・チャラ", roasterNotes: ["桃"])])],
            recipes: [
                Recipe(
                    id: "morning", title: "4:6 Method", method: "pour_over",
                    brewer: Gear(id: "hario-v60", brand: "Hario", model: "V60"),
                    coffee: .grams(20), water: .grams(300), ratio: 15,
                    waterTemp: .celsius(min: 92, max: 94),
                    grind: Grind(setting: "22 clicks", micronsApprox: 700, size: "medium_fine"),
                    filter: Filter(material: "paper", label: "V60-02"),
                    steps: [Step(kind: "bloom", atSeconds: 0, toWater: .grams(60),
                                 instruction: "wet the bed", actionDurationSeconds: 10),
                            Step(kind: "tamp")],
                    finishSeconds: 210, lang: "en",
                    localizations: ["ja": RecipeLocalization(
                        title: "4:6メソッド",
                        steps: [StepLocalization(instruction: "蒸らす"), StepLocalization()])],
                    notes: "Scale the pours to taste.",
                    additions: [Addition(type: "ice", amount: .grams(100))],
                    author: Party(name: "Someone", type: "person"),
                    basedOn: "https://example.com/post",
                    images: ["https://example.com/brew.jpg"],
                    description: "A staple pour-over.",
                    datePublished: "2026-07-01", beanRef: "lot-1", recommended: true),
                Recipe(
                    id: "shot", title: "Shot", method: "espresso", basis: "yield",
                    brewer: Gear(id: "custom", label: "A lever"),
                    coffee: .grams(18), yield: .grams(36),
                    waterTemp: .celsius(93), pressure: .bar(9), preinfusionSeconds: 3.5,
                    basket: Gear(id: "vst-18g", label: "VST 18 g"),
                    finishSeconds: 27),
            ],
            tastings: [Tasting(
                id: "monday", recipeRef: "morning", beanRef: "lot-1", rating: 4,
                perceived: PerceivedAxes(extraction: -0.2, strength: 0.1),
                descriptors: ["blackberry"], note: "Bright.", lang: "en",
                measured: MeasuredCup(tds: 1.38, yield: .grams(258)))],
            generator: Generator(name: "CoffeeJSON for Swift", version: "1.0"))
    }

    @Test("the typed encoder emits a conforming document", .enabled(if: SchemaSource.isAvailable))
    func typedEmitConforms() throws {
        let errors = try validate(try Codec.encode(richDocument()))
        #expect(errors.isEmpty, "the typed encoder emitted a non-conforming document: \(errors)")
    }

    @Test("the overlay re-emit path emits a conforming document",
          .enabled(if: SchemaSource.isAvailable))
    func overlayEmitConforms() throws {
        // The raw carries keys this package models and keys it does not, so the
        // merge has both kinds to write back out.
        let rawRecipe = Data(#"""
        {"title":"STALE","coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"},
         "method":"pour_over","finish_s":210,"x_future":{"cup_score":88}}
        """#.utf8)
        let rawBean = Data(#"""
        {"name":"STALE","roaster":{"name":"Example Roastery"},"process":["anaerobic","honey"],
         "rest_days":{"min":14},"roast_level":"light_medium","x_future":{"lot":"A"}}
        """#.utf8)

        let data = try Codec.encode(
            Document(
                version: Codec.currentVersion,
                beans: [Bean(id: "lot-1", name: "Nano Challa")],
                recipes: [Recipe(id: "morning", title: "4:6 Method",
                                 coffee: .grams(20), water: .grams(300), beanRef: "lot-1")]),
            recipeOverlays: [RecipeOverlay(raw: rawRecipe, ownedKeys: [.id, .title, .coffee, .water, .beanRef])],
            beanOverlays: [BeanOverlay(raw: rawBean, ownedKeys: [.id, .name])])

        let errors = try validate(data)
        #expect(errors.isEmpty, "the overlay re-emit emitted a non-conforming document: \(errors)")
    }

    @Test("a share link's payload is a conforming document", .enabled(if: SchemaSource.isAvailable))
    func sharedPayloadConforms() throws {
        let url = try ShareLink.shareURL(for: richDocument(), host: "example.com")
        let payload = try #require(ShareLink.payloadBytes(from: url))
        #expect(try validate(payload).isEmpty)
    }

    @Test("every document these tests round-trip also decodes", .enabled(if: SchemaSource.isAvailable))
    func emittedDocumentsDecode() throws {
        // Conformance and readability are different claims, and a gate that
        // proved only the first would let this package emit what it cannot read.
        let imported = try Codec.decodeDocument(try Codec.encode(richDocument()))
        #expect(imported.recipes.count == 2)
        #expect(imported.beans.count == 1)
        #expect(imported.tastings.count == 1)
        #expect(imported.associatedBean(forRecipeAt: 0)?.name == "Nano Challa")
    }

    @Test("the gate bites: a document outside a closed enum is rejected",
          .enabled(if: SchemaSource.isAvailable))
    func theGateRejectsAMalformedDocument() throws {
        // The control for every assertion above. A validator that returned
        // "valid" for everything would satisfy all of them, so one deliberately
        // wrong document has to come back rejected.
        var document = richDocument()
        document.beans?[0].roastLevel = "medium_light"   // the transposition, not in the enum
        let errors = try validate(try Codec.encode(document))
        #expect(!errors.isEmpty, "a roast level outside the schema's enum was accepted")
    }
}
