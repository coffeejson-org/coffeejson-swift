import Testing
import Foundation
@testable import CoffeeJSON

/// The wire shapes the format gained when measurements learned to state a
/// window and origins learned to credit more than one party. Every JSON body
/// here is taken from a real transcription in the public corpus, because the
/// point of these types is to carry what publishers actually publish.
@Suite("CoffeeJSON windows and the new fields")
struct WindowsAndNewFieldsTests {

    @Test("a windowed dose and yield decode, and neither reads as a point")
    func windowedEspressoDecodes() throws {
        // Cat & Cloud publish "18.5 - 19 grams" in for "32 - 34 grams" out.
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"The Answer — espresso","basis":"yield",
          "coffee":{"min":18.5,"max":19,"unit":"gram"},
          "yield":{"min":32,"max":34,"unit":"gram"}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let coffee = try #require(doc.recipes?.first?.coffee)

        #expect(coffee.isWindow)
        #expect(coffee.hasMagnitude)
        // The single-value accessor refuses to invent a point.
        #expect(coffee.grams == nil)
        #expect(coffee.minGrams == 18.5)
        #expect(coffee.maxGrams == 19)
        #expect(coffee.midpointGrams == 18.75)
    }

    @Test("a window imports into the brew model as a midpoint, and says that it did")
    func windowDerivationIsRecorded() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"The Answer — espresso","basis":"yield",
          "coffee":{"min":18.5,"max":19,"unit":"gram"},
          "yield":{"min":32,"max":34,"unit":"gram"}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))

        #expect(imported.recipes[0].coffeeGrams == 18.75)
        #expect(imported.recipes[0].yieldGrams == 33)
        // The obligation: a surface showing these numbers must label them.
        #expect(imported.recipes[0].derivedQuantities.contains(.coffee))
        #expect(imported.recipes[0].derivedQuantities.contains(.yield))
        #expect(!imported.recipes[0].derivedQuantities.contains(.water))
    }

    @Test("a recipe stated entirely in points reports no derivation")
    func pointRecipeDerivesNothing() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
          "water":{"value":250,"unit":"gram"},"water_temp":{"value":94,"unit":"celsius"}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.recipes[0].coffeeGrams == 15)
        #expect(imported.recipes[0].derivedQuantities.isEmpty)
    }

    @Test("an equipment-scaled recipe keeps its window and its ratio")
    func equipmentScaledRecipe() throws {
        // Equator size the French Press recipe to the reader's press: the
        // coupling they publish is the ratio, and the ratio is already a field.
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"French Press",
          "coffee":{"min":25,"max":45,"unit":"gram"},
          "water":{"min":375,"max":675,"unit":"gram"},"ratio":15}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let recipe = try #require(doc.recipes?.first)
        #expect(recipe.coffee?.minGrams == 25)
        #expect(recipe.water?.maxGrams == 675)
        #expect(recipe.ratio == 15)

        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.recipes[0].derivedQuantities.contains(.coffee))
        #expect(imported.recipes[0].derivedQuantities.contains(.water))
    }

    @Test("a one-sided window reads as the bound the publisher gave")
    func oneSidedWindow() throws {
        let q = Quantity(min: 14, unit: "gram")
        #expect(q.isWindow)
        #expect(q.grams == nil)
        #expect(q.midpointGrams == 14)
        #expect(q.effectiveGrams == 14)
    }

    @Test("a window converts bound by bound, so an ounce window stays a window")
    func ounceWindowConverts() throws {
        let q = Quantity(min: 1, max: 2, unit: "ounce")
        let lo = try #require(q.minGrams)
        let hi = try #require(q.maxGrams)
        #expect(abs(lo - 28.3495) < 0.001)
        #expect(abs(hi - 56.699) < 0.001)
        #expect(q.grams == nil)
    }

    @Test("a temperature window reads its bounds in celsius, even from a non-canonical unit")
    func temperatureWindowReadsBounds() {
        let celsiusWindow = Quantity(min: 90, max: 96, unit: "celsius")
        #expect(celsiusWindow.minCelsius == 90)
        #expect(celsiusWindow.maxCelsius == 96)

        let fahrenheitWindow = Quantity(min: 195, max: 205, unit: "fahrenheit")
        #expect(abs(fahrenheitWindow.minCelsius! - 90.5556) < 0.001)
        #expect(abs(fahrenheitWindow.maxCelsius! - 96.1111) < 0.001)
    }

    @Test("a pressure window reads its bounds in bar, and the factory round-trips them")
    func pressureWindowReadsBounds() {
        let window = Quantity.bar(min: 6, max: 9)
        #expect(window.minBar == 6)
        #expect(window.maxBar == 9)
    }

    @Test("a volume window reads its bounds in milliliters")
    func volumeWindowReadsBounds() {
        let window = Quantity(min: 200, max: 260, unit: "milliliter")
        #expect(window.minMilliliters == 200)
        #expect(window.maxMilliliters == 260)
    }

    @Test("a window stated in a unit its dimension does not know reads nil on both bounds")
    func windowInUnknownUnitReadsNilBounds() {
        let notATemperature = Quantity(min: 1, max: 2, unit: "gram")
        #expect(notATemperature.minCelsius == nil)
        #expect(notATemperature.maxCelsius == nil)

        let notAPressure = Quantity(min: 1, max: 2, unit: "psi")
        #expect(notAPressure.minBar == nil)
        #expect(notAPressure.maxBar == nil)

        let notAVolume = Quantity(min: 1, max: 2, unit: "liter")
        #expect(notAVolume.minMilliliters == nil)
        #expect(notAVolume.maxMilliliters == nil)
    }

    @Test("brew water stated in milliliters survives, and never converts to a mass")
    func volumeStatedWater() throws {
        // ONIBUS publish every guide's water in cc.
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"ハンドドリップ","coffee":{"value":13,"unit":"gram"},
          "water":{"value":225,"unit":"milliliter"},"water_temp":{"value":92,"unit":"celsius"}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let water = try #require(doc.recipes?.first?.water)

        #expect(water.milliliters == 225)
        // 225 mL at 92 °C is ~216.8 g. No conversion is defined, so none happens.
        #expect(water.grams == nil)
        #expect(water.effectiveGrams == nil)
    }

    @Test("a volume-stated recipe still imports rather than failing on a missing mass")
    func volumeStatedWaterImports() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"ハンドドリップ","coffee":{"value":13,"unit":"gram"},
          "water":{"value":225,"unit":"milliliter"}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.recipes[0].coffeeGrams == 13)
        #expect(imported.recipes[0].waterGrams == nil)   // no mass was stated, and none is invented
        #expect(imported.recipes[0].title == "ハンドドリップ")
    }

    @Test("a water object with no magnitude at all is still a missing water")
    func waterWithoutMagnitudeStillFails() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"t","coffee":{"value":13,"unit":"gram"},
          "water":{"unit":"gram"}}]}
        """#
        #expect(throws: ImportError.validation(.missingRequiredField("water"))) {
            _ = try Codec.decodeDocument(Data(json.utf8))
        }
    }

    @Test("a compound process carries every part the roaster named")
    func compoundProcess() throws {
        // PHILOCOFFEA state "Double Anaerobic Honey" — every part is in the
        // vocabulary, and before the set only one of them fitted.
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"La Mina","roaster":{"name":"PHILOCOFFEA"},
          "url":"https://philocoffea.com","process":["anaerobic","honey"]}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        #expect(doc.beans?.first?.process == ["anaerobic", "honey"])

        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.beans.first?.process.count == 2)
    }

    @Test("a blend states its processes as a set without assigning them")
    func unassignedBlendProcessSet() throws {
        // Cat & Cloud publishes "Washed, Natural" for a multi-origin blend
        // without saying which component is which.
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"The Answer","roaster":{"name":"Cat & Cloud"},
          "url":"https://catandcloud.com","process":["washed","natural"]}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.beans.first?.process == ["washed", "natural"])
    }

    @Test("wet-hulled is a process the vocabulary now names")
    func wetHulled() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"Equator Blend","roaster":{"name":"Equator"},
          "url":"https://www.equatorcoffees.com","origin":{"type":"blend","items":[
            {"region":"Dolok Sanggul, Lintong","process":["wet_hulled"]}]}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let item = try #require(doc.beans?.first?.origin?.items?.first)
        #expect(item.region == "Dolok Sanggul, Lintong")
        #expect(item.process == ["wet_hulled"])

        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.beans.first?.origin?.items.first?.process == ["wet_hulled"])
    }

    @Test("an origin credits a producer and a cooperative, not one or the other")
    func roledProducers() throws {
        // A roaster credits "Producer" and "Union" as separate rows, so
        // `producers` is a list of roled entries rather than one string.
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"Ethiopia Suke","roaster":{"name":"Linea Caffe"},
          "url":"https://lineacaffe.com","origin":{"type":"single","items":[
            {"country":"ET","region":"Oromia","producers":[
              {"name":"Tesfaye Bekele","role":"producer","type":"person"},
              {"name":"Suke Quto Coffee Farms","role":"cooperative"}]}]}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let item = try #require(doc.beans?.first?.origin?.items?.first)

        #expect(item.producers?.count == 2)
        #expect(item.producers?[0].name == "Tesfaye Bekele")
        #expect(item.producers?[0].type == "person")
        #expect(item.producers?[0].role.flatMap(KnownProducerRole.init(rawValue:)) == .producer)
        #expect(item.producers?[1].role.flatMap(KnownProducerRole.init(rawValue:)) == .cooperative)
    }

    @Test("a party with a name and no role is kept — the source named it")
    func producerWithoutRole() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"b","roaster":{"name":"r"},"url":"https://x.test",
          "origin":{"type":"single","items":[{"country":"CO","producers":[{"name":"Multiple producers"}]}]}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let item = try #require(imported.beans.first?.origin?.items.first)
        #expect(item.producers.count == 1)
        #expect(item.producers[0].name == "Multiple producers")
        #expect(item.producers[0].role == nil)
    }

    @Test("an unrecognized role is carried verbatim, never folded away")
    func unknownRoleSurvives() throws {
        let party = Party(name: "Some Party", role: "importer")
        #expect(party.role == "importer")
        #expect(KnownProducerRole(rawValue: "importer") == nil)   // unknown to the typed view…
        #expect(party.name == "Some Party")                       // …and still displayable
    }

    @Test("a producer entry with no usable name is dropped, not failed")
    func namelessProducerDropped() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"b","roaster":{"name":"r"},"url":"https://x.test",
          "origin":{"type":"single","items":[{"country":"CO","producers":[{"role":"farm"},{"name":"  "},{"name":"Real Farm","role":"farm"}]}]}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let item = try #require(imported.beans.first?.origin?.items.first)
        #expect(item.producers.count == 1)
        #expect(item.producers[0].name == "Real Farm")
    }

    @Test("a blend's components each carry their own varieties")
    func perComponentVarietals() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"Equator Blend","roaster":{"name":"Equator"},
          "url":"https://www.equatorcoffees.com","origin":{"type":"blend","items":[
            {"region":"Lintong","varietals":["Onanganjang","Sigararutang"]},
            {"country":"KE","varietals":["SL28","SL34","Ruiru 11"]}]}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let items = try #require(imported.beans.first?.origin?.items)
        #expect(items[0].varietals == ["Onanganjang", "Sigararutang"])
        #expect(items[1].varietals == ["SL28", "SL34", "Ruiru 11"])
    }

    @Test("a recipe states the filter the water passes through")
    func filterDecodes() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"Chemex","coffee":{"value":45,"unit":"gram"},
          "water":{"value":720,"unit":"gram"},
          "filter":{"material":"paper","label":"Chemex filters, folded three layers on the spout side"}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let filter = try #require(doc.recipes?.first?.filter)
        #expect(filter.material == "paper")
        #expect(filter.material.flatMap(KnownFilterMaterial.init(rawValue:)) == .paper)
        #expect(filter.label?.hasPrefix("Chemex filters") == true)
    }

    @Test("an unrecognized filter material reads as nil, and the wire keeps the word")
    func unknownFilterMaterial() throws {
        let filter = Filter(material: "nylon")
        #expect(KnownFilterMaterial(rawValue: "nylon") == nil)
        #expect(filter.material == "nylon")
    }

    @Test("a bean states the window it wants to be brewed in")
    func restDaysDecodes() throws {
        // LIGHT UP: rest about two weeks, drink within two months.
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"Acacia Hills","roaster":{"name":"LIGHT UP COFFEE"},
          "url":"https://lightupcoffee.com","rest_days":{"min":14,"max":60}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let rest = try #require(doc.beans?.first?.restDays)
        #expect(rest.min == 14)
        #expect(rest.max == 60)
    }

    @Test("a roaster who says only \"at least 14 days\" states one bound")
    func restDaysLowerBoundOnly() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"El Morito","roaster":{"name":"April"},
          "url":"https://www.aprilcoffeeroasters.com","rest_days":{"min":14}}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let rest = try #require(doc.beans?.first?.restDays)
        #expect(rest.min == 14)
        #expect(rest.max == nil)
    }

    @Test("ice with no stated amount still marks the recipe iced")
    func unquantifiedIce() throws {
        // The whole point of making amount optional: a required quantity was
        // taking a semantic flag down with it.
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"Iced 4:6","coffee":{"value":20,"unit":"gram"},
          "water":{"value":300,"unit":"gram"},"additions":[{"type":"ice"}]}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let addition = try #require(imported.recipes[0].additions.first)
        #expect(addition.isIce)
        #expect(addition.amount == nil)
        #expect(addition.amountGrams == nil)
    }

    @Test("a quantified addition still reads its mass")
    func quantifiedIce() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"アイス","coffee":{"value":18,"unit":"gram"},
          "water":{"value":150,"unit":"milliliter"},"additions":[{"type":"ice","amount":{"value":160,"unit":"gram"}}]}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let addition = try #require(imported.recipes[0].additions.first)
        #expect(addition.isIce)
        #expect(addition.amountGrams == 160)
    }

    @Test("the valve and wait kinds ride through as stated")
    func newStepKinds() throws {
        // ONIBUS's Switch guide actually moves the valve mid-brew.
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"スイッチ","coffee":{"value":13,"unit":"gram"},
          "water":{"value":215,"unit":"milliliter"},"steps":[
            {"kind":"valve_close","instruction":"スイッチを閉じた状態かを確認して"},
            {"kind":"bloom","at_s":0,"to_water":{"value":50,"unit":"milliliter"},"instruction":"50ccのお湯を注ぎ"},
            {"kind":"valve_open","instruction":"スイッチを開け"},
            {"kind":"wait","instruction":"待つ"},
            {"kind":"drawdown","instruction":"落ち切り"}]}]}
        """#
        let doc = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        let steps = try #require(doc.recipes?.first?.steps)
        let kinds = steps.compactMap(\.kind)
        #expect(kinds == ["valve_close", "bloom", "valve_open", "wait", "drawdown"])
    }

    @Test("a step's water is scheduled on its data, so a milliliter pour is not a mass cue")
    func volumePourIsNotAMassSchedule() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"t","coffee":{"value":13,"unit":"gram"},
          "water":{"value":225,"unit":"milliliter"},"steps":[
            {"kind":"bloom","at_s":0,"to_water":{"value":40,"unit":"milliliter"},"instruction":"40cc"}]}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        // The step carries at_s and to_water, but the water is a volume and the
        // pour schedule is in grams — so it surfaces read-only rather than as a
        // mass cue the consumer would brew wrong.
        #expect(imported.recipes[0].pourSteps.isEmpty)
        #expect(imported.recipes[0].readOnlySteps.contains { $0.instruction == "40cc" })
    }

    @Test("every new shape survives an encode/decode round trip")
    func roundTrip() throws {
        let document = Document(
            version: "1.0",
            beans: [Bean(
                name: "La Mina",
                roaster: Party(name: "PHILOCOFFEA"),
                url: "https://philocoffea.com",
                origin: Origin(type: "single", items: [OriginItem(
                    country: "CO",
                    producers: [Party(name: "Franco Lopez", type: nil, role: "producer")],
                    varietals: ["Caturra"])]),
                process: ["anaerobic", "honey"],
                restDays: RestDays(min: 14))],
            recipes: [Recipe(
                title: "Espresso",
                basis: "yield",
                coffee: .grams(min: 18.5, max: 19),
                yield: .grams(min: 32, max: 34),
                filter: Filter(material: "paper", label: "V60-02"),
                steps: [Step(kind: "valve_open", instruction: "open")],
                additions: [Addition(type: "ice")])])

        let data = try Codec.encode(document)
        let back = try JSONDecoder().decode(Document.self, from: data)

        #expect(back.beans?.first?.process == ["anaerobic", "honey"])
        #expect(back.beans?.first?.restDays?.min == 14)
        #expect(back.beans?.first?.origin?.items?.first?.producers?.first?.role == "producer")
        #expect(back.beans?.first?.origin?.items?.first?.varietals == ["Caturra"])
        #expect(back.recipes?.first?.coffee?.minGrams == 18.5)
        #expect(back.recipes?.first?.yield?.maxGrams == 34)
        #expect(back.recipes?.first?.filter?.material == "paper")
        #expect(back.recipes?.first?.steps?.first?.kind == "valve_open")
        #expect(back.recipes?.first?.additions?.first?.amount == nil)
    }
}
