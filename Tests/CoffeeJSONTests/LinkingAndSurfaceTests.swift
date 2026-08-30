import Foundation
import Testing
import CoffeeJSON
import CoffeeJSONSchemaTesting

// Deliberately a PLAIN import — no `@testable` anywhere in this file. Every
// suite here exercises exactly what a second consumer can do: construct wire
// DTOs typed, read stored properties, resolve association. If anything in
// this file stops compiling, an outside consumer just lost that capability.
@Suite("CoffeeJSON linking fields")
struct LinkingFieldTests {
    @Test("bean id, recipe bean_ref, and recommended decode and project")
    func linkingFieldsDecode() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"id":"nano-challa","name":"Nano Challa"}],
         "recipes":[{"title":"V60","bean_ref":"nano-challa","recommended":true,
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.beans[0].id == "nano-challa")
        #expect(imported.recipes[0].beanRef == "nano-challa")
        #expect(imported.recipes[0].recommended == true)
    }

    @Test("recommended is false when absent — absent and false are spec-equivalent")
    func recommendedDefaultsFalse() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0","recipes":[{"title":"V60",
         "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.recipes[0].recommended == false)
        #expect(imported.recipes[0].beanRef == nil)
    }

    @Test("explicit reference wins and matches byte-exactly")
    func explicitReferenceResolves() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"id":"a","name":"First"},{"id":"b","name":"Second"}],
         "recipes":[{"title":"For B","bean_ref":"b",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.associatedBean(forRecipeAt: 0)?.name == "Second")
    }

    @Test("an unresolved reference leaves the recipe unlinked — never a fallback to co-location")
    func unresolvedReferenceNeverFallsBack() throws {
        // One co-located bean, but the recipe's explicit ref points elsewhere:
        // the broken reference wins over co-location, per the envelope rule.
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"id":"nano-challa","name":"Nano Challa"}],
         "recipes":[{"title":"V60","bean_ref":"NANO-CHALLA",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.associatedBean(forRecipeAt: 0) == nil)
    }

    @Test("co-location associates the single bean when no reference is carried")
    func coLocationSingleBean() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"name":"Nano Challa"}],
         "recipes":[{"title":"V60",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.associatedBean(forRecipeAt: 0)?.name == "Nano Challa")
        #expect(imported.recipesShareSingleBean)
    }

    @Test("multiple beans without references stay unlinked")
    func multiBeanNoReferenceUnlinked() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"id":"a","name":"First"},{"id":"b","name":"Second"}],
         "recipes":[{"title":"V60",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.associatedBean(forRecipeAt: 0) == nil)
    }

    @Test("a duplicated bean id makes references to it unresolved, never an error")
    func duplicatedIdResolvesToNone() throws {
        let imported = try decodeDocument("""
        {"coffeejson":"1.0",
         "beans":[{"id":"dup","name":"First"},{"id":"dup","name":"Second"}],
         "recipes":[{"title":"V60","bean_ref":"dup",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """)
        #expect(imported.associatedBean(forRecipeAt: 0) == nil)
    }

    @Test("encode emits id and bean_ref in NFC, so byte-exact matching survives normalization forms")
    func encodeNormalizesLinkingFieldsToNFC() throws {
        // "café" with a decomposed é (e + combining acute) — canonically equal
        // to the precomposed form (so Swift's String == cannot tell them
        // apart) but byte-different, which is exactly why the spec pins NFC on
        // emit: the reference match is on bytes.
        let decomposed = "cafe\u{0301}"
        let precomposed = decomposed.precomposedStringWithCanonicalMapping
        #expect(!Array(decomposed.utf8).elementsEqual(Array(precomposed.utf8))) // the probe is real
        let document = Document(
            version: "1.0",
            beans: [Bean(id: decomposed, name: "Café lot")],
            recipes: [Recipe(title: "V60", coffee: .grams(15), water: .grams(250), beanRef: decomposed)])
        let data = try Codec.encode(document)
        // The emitted bytes carry no combining acute (U+0301 = 0xCC 0x81):
        // both linking fields left in NFC.
        let bytes = Array(data)
        let combiningAcute: [UInt8] = [0xCC, 0x81]
        let containsCombining = bytes.count >= 2 && (0...(bytes.count - 2)).contains { i in
            bytes[i] == combiningAcute[0] && bytes[i + 1] == combiningAcute[1]
        }
        #expect(!containsCombining)
        let round = try Codec.decodeDocument(data)
        // Compared on the UTF-8 view, because `String ==` is canonical
        // equivalence and would pass on either normalization form.
        let beanID = try #require(round.beans[0].id)
        let beanRef = try #require(round.recipes[0].beanRef)
        #expect(beanID.utf8.elementsEqual(precomposed.utf8))
        #expect(beanRef.utf8.elementsEqual(precomposed.utf8))
        #expect(round.associatedBean(forRecipeAt: 0)?.name == "Café lot")
    }

    @Test("encode emits a recipe's own id in NFC, so a tasting that names it still resolves")
    func encodeNormalizesRecipeIdToNFC() throws {
        // `recipe_ref` is normalized on emit, so an un-normalized `recipes[].id`
        // guarantees the two ends of the reference disagree: a document that
        // arrived linked would leave unlinked, with nothing thrown.
        let decomposed = "cafe\u{0301}"
        let document = Document(
            version: "1.0",
            recipes: [Recipe(id: decomposed, title: "V60", coffee: .grams(15), water: .grams(250))],
            tastings: [Tasting(recipeRef: decomposed, rating: 4)])
        let round = try Codec.decodeDocument(try Codec.encode(document))
        #expect(round.associatedRecipe(forTastingAt: 0)?.title == "V60")
    }

    @Test("reference matching is byte-exact — canonically-equal normalization forms do not link")
    func referenceMatchIsByteExact() throws {
        // A hand-authored document that never went through this encoder: the
        // bean id is decomposed, the reference precomposed. Swift's String ==
        // would call them equal; the spec's byte-exact rule says unlinked.
        let json = """
        {"coffeejson":"1.0",
         "beans":[{"id":"cafe\\u0301","name":"Café lot"}],
         "recipes":[{"title":"V60","bean_ref":"caf\\u00e9",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """
        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.associatedBean(forRecipeAt: 0) == nil)
    }
}

/// The symmetric public surface, proven WITHOUT `@testable`: if any of this
/// stops compiling, a second consumer just lost the same capability.
@Suite("CoffeeJSON public surface")
struct PublicSurfaceTests {
    @Test("a wire quantity is constructible with an arbitrary unit, and readable")
    func quantityConstructibleAndReadable() {
        let q = CoffeeJSON.Quantity(value: 12.5, unit: "stone")
        #expect(q.value == 12.5)
        #expect(q.unit == "stone")
        #expect(q.grams == nil) // unrecognized unit reads as absent, publicly
        #expect(CoffeeJSON.Quantity.grams(15).grams == 15)
    }

    @Test("the full Recipe memberwise init round-trips through the codec")
    func recipeMemberwiseInitComplete() throws {
        let recipe = CoffeeJSON.Recipe(
            title: "Full surface",
            method: "pour_over",
            brewer: CoffeeJSON.Gear(id: "hario-v60", brand: "Hario", model: "V60"),
            coffee: .grams(15),
            water: .grams(250),
            ratio: 16.7,
            waterTemp: .celsius(93),
            grind: CoffeeJSON.Grind(setting: "22 clicks"),
            steps: [CoffeeJSON.Step(kind: "bloom", atSeconds: 0, toWater: .grams(45))],
            finishSeconds: 180,
            lang: "en",
            notes: "long-form guidance",
            additions: [CoffeeJSON.Addition(type: "ice", amount: .grams(100))],
            author: CoffeeJSON.Party(name: "Someone", type: "person"),
            basedOn: "https://example.com/post",
            images: ["https://example.com/a.jpg"],
            description: "one-line summary",
            datePublished: "2026-07-01",
            beanRef: "lot-1",
            recommended: true)
        let document = CoffeeJSON.Document(
            version: "1.0",
            beans: [CoffeeJSON.Bean(id: "lot-1", name: "Lot One")],
            recipes: [recipe],
            generator: CoffeeJSON.Generator(name: "TestKit", version: "1"))
        let round = try Codec.decodeDocument(try Codec.encode(document))
        let r = round.recipes[0]
        #expect(round.generator?.name == "TestKit")
        #expect(r.notes == "long-form guidance")
        #expect(r.author?.name == "Someone")
        #expect(r.basedOn == "https://example.com/post")
        #expect(r.images == ["https://example.com/a.jpg"])
        #expect(r.description == "one-line summary")
        #expect(r.datePublished != nil)
        #expect(r.additions.first?.isIce == true)
        #expect(round.associatedBean(forRecipeAt: 0)?.name == "Lot One")
    }

    /// A fully-populated document, built through the public memberwise inits, so
    /// equality is exercised down the whole nesting chain rather than at a leaf.
    private func nestedDocument(altitudeMin: Double) -> CoffeeJSON.Document {
        CoffeeJSON.Document(
            version: "1.0",
            beans: [CoffeeJSON.Bean(
                id: "lot-1", name: "Nano Challa",
                roaster: CoffeeJSON.Party(name: "Example", type: "organization"),
                origin: CoffeeJSON.Origin(type: "single", items: [CoffeeJSON.OriginItem(
                    name: "Lot No. 1", country: "ET",
                    producers: [CoffeeJSON.Party(name: "A Farmer", role: "producer")],
                    altitude: CoffeeJSON.Altitude(min: altitudeMin, max: 2000, unit: "meter"))]),
                restDays: CoffeeJSON.RestDays(min: 7, max: 60))],
            recipes: [CoffeeJSON.Recipe(
                title: "V60", coffee: .grams(15), water: .grams(250),
                grind: CoffeeJSON.Grind(setting: "22 clicks", size: "medium_fine"),
                steps: [CoffeeJSON.Step(atSeconds: 0, toWater: .grams(45))],
                additions: [CoffeeJSON.Addition(type: "ice", amount: .grams(100))],
                author: CoffeeJSON.Party(name: "Someone", type: "person"),
                beanRef: "lot-1")],
            generator: CoffeeJSON.Generator(name: "TestKit", version: "1"))
    }

    /// Which layer a failure belongs to, recovered by a consumer with a
    /// three-arm switch and no `default` — that exhaustiveness is half the point.
    private enum Layer { case transport, decode, validation }

    private func layer(of body: () throws -> Void) -> Layer? {
        do {
            try body()
            return nil
        } catch let error as ImportError {
            switch error {
            case .transport: return .transport
            case .decode: return .decode
            case .validation: return .validation
            }
        } catch {
            Issue.record("threw \(error), which is not an ImportError")
            return nil
        }
    }

    @Test("a consumer can branch on the layer without matching every case")
    func errorsCarryTheirLayer() {
        #expect(layer { _ = try CoffeeJSON.ShareLink.importDocument(fromScanned: "just some text") } == .transport)
        #expect(layer { _ = try Codec.decodeDocument(Data("not json at all".utf8)) } == .decode)
        #expect(layer {
            _ = try Codec.decodeDocument(Data(#"""
            {"coffeejson":"1.0","recipes":[{"coffee":{"value":15,"unit":"gram"},
             "water":{"value":250,"unit":"gram"}}]}
            """#.utf8))
        } == .validation)
    }

    @Test("the payload cap is readable from outside, and it is the cap actually enforced")
    func payloadCapIsPublicAndAgreesWithEnforcement() throws {
        // Pins the frozen transport contract value: a later edit to the number
        // fails here rather than silently moving what consumers were told.
        #expect(CoffeeJSON.ShareLink.maxPayloadBytes == 8192)

        let small = CoffeeJSON.Document(
            version: "1.0",
            recipes: [CoffeeJSON.Recipe(title: "V60", coffee: .grams(15), water: .grams(250))])
        #expect(try Codec.encode(small).count <= CoffeeJSON.ShareLink.maxPayloadBytes)

        // What makes the constant worth publishing: a published number that
        // disagreed with the enforced one would be worse than none at all.
        let huge = CoffeeJSON.Document(
            version: "1.0",
            recipes: [CoffeeJSON.Recipe(
                title: String(repeating: "x", count: 10_000),
                coffee: .grams(15), water: .grams(250))])
        #expect(try Codec.encode(huge).count > CoffeeJSON.ShareLink.maxPayloadBytes)
        #expect(throws: ImportError.transport(.tooLarge)) {
            try CoffeeJSON.ShareLink.shareURL(for: huge, host: "example.com")
        }
    }

    @Test("the imported projections can be held in sets and used as dictionary keys")
    func importedProjectionsAreHashable() throws {
        let imported = try Codec.decodeDocument(Data(#"""
        {"coffeejson":"1.0",
         "beans":[{"id":"lot-1","name":"Nano Challa"}],
         "recipes":[{"title":"V60","bean_ref":"lot-1",
                     "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}},
                    {"title":"Aeropress",
                     "coffee":{"value":18,"unit":"gram"},"water":{"value":220,"unit":"gram"}}]}
        """#.utf8))

        let recipes = imported.recipes
        #expect(Set(recipes).count == 2)
        // A conformance that hashed everything alike would still put two distinct
        // recipes in a set of two, but could not keep a duplicate out.
        #expect(Set([recipes[0], recipes[0]]).count == 1)

        let byBean: [CoffeeJSON.ImportedBean: String] = [imported.beans[0]: "the bag"]
        #expect(byBean[imported.beans[0]] == "the bag")

        // The whole chain hashes: Generator, every bean, every recipe.
        #expect(Set([imported]).count == 1)
    }

    @Test("wire documents compare structurally, all the way down the nesting")
    func wireDocumentsAreEquatable() {
        #expect(nestedDocument(altitudeMin: 1800) == nestedDocument(altitudeMin: 1800))
        // An `==` that returned true for everything would pass the first. This
        // differs only in an `Altitude.min` four levels down.
        #expect(nestedDocument(altitudeMin: 1800) != nestedDocument(altitudeMin: 1600))
    }

    @Test("wire DTO stored properties are publicly readable")
    func wireStoredPropertiesReadable() {
        let document = CoffeeJSON.Document(
            version: "1.0",
            recipes: [CoffeeJSON.Recipe(title: "Readable", coffee: .grams(15), water: .grams(250))])
        #expect(document.version == "1.0")
        #expect(document.recipes?.first?.title == "Readable")
        #expect(document.recipes?.first?.coffee?.value == 15)
        let addition = CoffeeJSON.Addition(type: "milk", amount: .grams(60), temperature: .celsius(60))
        #expect(addition.amount?.unit == "gram")
        #expect(addition.temperature?.value == 60)
    }

    @Test("the vended media type is the one the spec declares",
          .enabled(if: SchemaSource.file(at: "docs/spec/07-versioning.md") != nil))
    func mediaTypeMatchesTheSpec() throws {
        let url = try #require(SchemaSource.file(at: "docs/spec/07-versioning.md"))
        let declared = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .first { $0.hasPrefix("application/") }
        #expect(declared.map(String.init) == Codec.mediaType)
    }
}
