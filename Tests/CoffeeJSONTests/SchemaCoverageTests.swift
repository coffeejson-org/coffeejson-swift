import Testing
import Foundation
@testable import CoffeeJSON

/// Fields the published schema defines that a typed consumer must be able to
/// read. Absence here is not a decode failure — an unmodeled key is skipped
/// silently — which is exactly why it needs a test: the gap is invisible until
/// someone asks why their bag's language vanished.
@Suite("Schema coverage")
struct SchemaCoverageTests {
    @Test("a recipe carries its document-scoped id")
    func recipeId() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"id":"morning","title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        #expect(r.id == "morning")
    }

    @Test("an espresso recipe carries its basket")
    func recipeBasket() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"Shot","basket":{"id":"vst-18g","label":"VST 18 g"},"coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"},"basis":"yield"}]}"#)
        #expect(r.basket?.label == "VST 18 g")
    }

    @Test("a recipe carries the qualitative grind size")
    func recipeGrindSize() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"V60","grind":{"size":"medium_fine"},"coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        #expect(r.grindSize == "medium_fine")
        // The size is a vocabulary token a consumer localizes, not the sender's
        // own prose — so it stays out of the free-text grind display.
        #expect(r.grindDescription == nil)
    }

    @Test("a size outside the scale is carried verbatim rather than failing the decode")
    func unrecognizedGrindSizeDegrades() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"Ibrik","grind":{"size":"turkish"},"coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        #expect(r.grindSize == "turkish")
        #expect(KnownGrindSize(rawValue: "turkish") == nil)
    }

    @Test("the typed view names every step of the scale, and only those")
    func knownGrindSizeNamesTheScale() {
        #expect(KnownGrindSize.allCases.map(\.rawValue) == [
            "extra_fine", "fine", "medium_fine", "medium",
            "medium_coarse", "coarse", "extra_coarse",
        ])
        #expect(KnownGrindSize(rawValue: "medium_coarse") == .mediumCoarse)
        #expect(KnownGrindSize(rawValue: "turkish") == nil)   // outside the scale
    }

    @Test("a timed pour carries how long its action takes")
    func stepActionDuration() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"steps":[{"at_s":0,"to_water":{"value":50,"unit":"gram"},"action_duration_s":10}]}]}"#)
        #expect(r.pourSteps.first?.actionDurationSeconds == 10)
    }

    @Test("a timed pour that states no duration carries none")
    func stepWithoutActionDuration() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"steps":[{"at_s":0,"to_water":{"value":50,"unit":"gram"}}]}]}"#)
        #expect(r.pourSteps.first?.actionDurationSeconds == nil)
    }

    // Both bodies below are verbatim from the public corpus: these two fields
    // are stated by documents that already exist, and a decode that drops them
    // loses what those publishers wrote.

    @Test("a published guide's grind size survives the decode")
    func publishedGrindSize() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Equator Coffees — Hario V60","method":"pour_over",
          "brewer":{"id":"hario-v60","brand":"Hario"},
          "coffee":{"value":24,"unit":"gram"},"water":{"value":360,"unit":"gram"},"ratio":15,
          "water_temp":{"value":205,"unit":"fahrenheit"},
          "grind":{"size":"medium_fine"},
          "filter":{"material":"paper","label":"Hario V60 filters"},
          "finish_s":210,"lang":"en"}]}
        """#)
        #expect(r.grindSize == "medium_fine")
        #expect(KnownGrindSize(rawValue: try #require(r.grindSize)) == .mediumFine)
    }

    @Test("a published guide's per-pour durations survive the decode")
    func publishedActionDurations() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"April Selection — April Hybrid Brewer","method":"pour_over",
          "coffee":{"value":14,"unit":"gram"},"water":{"value":240,"unit":"gram"},
          "grind":{"grinder":{"id":"mahlkonig-ek43","brand":"Mahlkönig","model":"EK43"}},
          "steps":[
            {"at_s":0,"to_water":{"value":40,"unit":"gram"},"action_duration_s":10,"instruction":"open the valve; pour 40 g in a circle"},
            {"at_s":40,"to_water":{"value":140,"unit":"gram"},"action_duration_s":10,"instruction":"close the valve; pour 100 g"},
            {"at_s":80,"to_water":{"value":240,"unit":"gram"},"action_duration_s":10,"instruction":"open the valve; pour 100 g"}],
          "lang":"en"}]}
        """#)
        #expect(r.pourSteps.map(\.actionDurationSeconds) == [10, 10, 10])
    }

    @Test("a bean carries the language of its own prose")
    func beanLang() throws {
        let b = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","lang":"ja","description":"エチオピアの豆"}]}"#)
        #expect(b.lang == "ja")
    }

    @Test("a bean carries the machine it was roasted on")
    func beanProductionRoaster() throws {
        let b = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","production_roaster":"Diedrich CR-70"}]}"#)
        #expect(b.productionRoaster == "Diedrich CR-70")
    }

    @Test("a bean carries the extraction style it was roasted for")
    func beanPreferredExtraction() throws {
        let b = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","preferred_extraction":"espresso"}]}"#)
        #expect(b.preferredExtraction == "espresso")
    }

    @Test("an origin item carries the component coffee's own name")
    func originItemName() throws {
        let b = try decodeBean(#"""
        {"coffeejson":"1.0","beans":[{"name":"Hell Yeah! Blend","origin":{"type":"blend","items":[
          {"name":"Honduras Pacayal Honey","country":"HN","percentage":60},
          {"name":"Peru Aproeco","country":"PE","percentage":40}]}}]}
        """#)
        let items = try #require(b.origin?.items)
        #expect(items.map(\.name) == ["Honduras Pacayal Honey", "Peru Aproeco"])
    }

    @Test("a fully-stated origin item arrives whole")
    func originItemStatedInFull() throws {
        let b = try decodeBean(#"""
        {"coffeejson":"1.0","beans":[{"name":"Orange County","origin":{"items":[
          {"name":"Lot No. 1","country":"CR","region":"Tarrazú",
           "producers":[{"name":"Ivan Solis","role":"producer"}],"process":["washed"]}]}}]}
        """#)
        let item = try #require(b.origin?.items.first)
        #expect(item.name == "Lot No. 1")
        #expect(item.region == "Tarrazú")
        #expect(item.producers.map(\.name) == ["Ivan Solis"])
        #expect(item.process == ["washed"])
    }

    @Test("an origin item that names no component carries none")
    func originItemWithoutName() throws {
        let b = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","origin":{"items":[{"country":"ET"}]}}]}"#)
        #expect(b.origin?.items.first?.name == nil)
    }

    // `Document` decodes by hand, so a member whose read line was never written
    // stays nil forever: the compiler says nothing and the synthesized encoder
    // still emits it. `Bean` and `OriginItem` decode by synthesis and are pinned
    // anyway, to catch a key added to one side of `CodingKeys` only.
    //
    // Each pin needs both of its assertions. `before == after` catches a decoder
    // that dropped a key it was handed. `before == CodingKeys.allCases` catches
    // what the round trip cannot see: a new member defaults to nil, so a stale
    // fixture never emits its key and the round trip agrees with itself about a
    // field it never tested.

    private func roundTripKeys(_ value: some Codable) throws -> (before: Set<String>, after: Set<String>) {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(type(of: value), from: encoded)
        let reencoded = try JSONEncoder().encode(decoded)
        func keys(_ data: Data) throws -> Set<String> {
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Set(object.keys)
        }
        return (try keys(encoded), try keys(reencoded))
    }

    @Test("an origin item round-trips every key the encoder writes")
    func originItemRoundTripsEveryKey() throws {
        let item = OriginItem(
            name: "Lot No. 1", country: "CR", region: "Tarrazú",
            producers: [Party(name: "Ivan Solis", url: "u", type: "person", role: "producer")],
            altitude: Altitude(value: 1700, min: 1600, max: 1800, unit: "meter"),
            process: ["washed"], varietals: ["Caturra"], harvestTime: "2025", percentage: 60)
        let (before, after) = try roundTripKeys(item)
        #expect(before == Set(OriginItem.CodingKeys.allCases.map(\.rawValue)))
        #expect(before == after)
    }

    @Test("a bean round-trips every key the encoder writes")
    func beanRoundTripsEveryKey() throws {
        let bean = Bean(
            id: "b", name: "Nano Challa", roaster: Party(name: "r", url: "u", type: "organization"),
            url: "u", images: ["i"], origin: Origin(type: "single", items: [OriginItem(country: "ET")]),
            process: ["washed"], dryingMethod: "raised_bed", varietals: ["Heirloom"],
            roastLevel: "light", roastAgtron: 72, restDays: RestDays(min: 7, max: 60),
            roastDate: "2026-01-01", productionRoaster: "Diedrich CR-70", decaf: false,
            form: "whole_bean", preferredExtraction: "filter", certifications: ["organic"],
            roasterNotes: ["peach"], description: "d", lang: "en",
            localizations: ["ja": BeanLocalization(name: "n", description: "d", roasterNotes: ["桃"])])
        let (before, after) = try roundTripKeys(bean)
        #expect(before == Set(Bean.CodingKeys.allCases.map(\.rawValue)))
        #expect(before == after)
    }

    @Test("a tasting round-trips every key it declares")
    func tastingRoundTripsEveryKey() throws {
        let tasting = Tasting(
            id: "monday", recipeRef: "r", beanRef: "b", rating: 4,
            perceived: PerceivedAxes(extraction: -0.2, strength: 0.1),
            descriptors: ["blackberry", "dark chocolate"], note: "n", lang: "en",
            measured: MeasuredCup(tds: 1.38, yield: .grams(258)))
        let (before, after) = try roundTripKeys(tasting)
        #expect(before == Set(Tasting.CodingKeys.allCases.map(\.rawValue)))
        #expect(before == after)
    }

    @Test("the hand-written document decoder reads every key the encoder writes")
    func documentRoundTripsEveryKey() throws {
        let document = Document(
            version: "1.0", beans: [Bean(name: "n")], recipes: [Recipe(title: "t")],
            tastings: [Tasting(rating: 4)],
            generator: Generator(name: "a", version: "1", url: "u"))
        let (before, after) = try roundTripKeys(document)
        #expect(before == Set(Document.CodingKeys.allCases.map(\.rawValue)))
        #expect(before == after)
    }

    @Test("a published blend's component names survive the decode")
    func publishedOriginItemNames() throws {
        let b = try decodeBean(#"""
        {"coffeejson":"1.0","beans":[{"name":"Orange County - Costa Rica","origin":{"type":"single","items":[
          {"name":"Lot No. 1","country":"CR","region":"Tarrazú",
           "producers":[{"name":"Ivan Solis","role":"producer","type":"person"},
                        {"name":"Finca Voo","role":"farm"}],
           "altitude":{"value":1700,"unit":"meter"}}]}}]}
        """#)
        let item = try #require(b.origin?.items.first)
        #expect(item.name == "Lot No. 1")
        #expect(item.producers.map(\.name) == ["Ivan Solis", "Finca Voo"])
        #expect(item.altitude?.valueMeters == 1700)
    }
}
