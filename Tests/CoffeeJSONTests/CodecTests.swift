import Testing
import Foundation
@testable import CoffeeJSON

/// Format-level decode + validation (pure). Representable-range rejection is
/// consumer policy and has no test here.
@Suite("CoffeeJSON codec — validation")
struct CodecTests {
    @Test("decodes a minimal valid recipe into canonical grams and a derived ratio")
    func decodesMinimal() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """#)
        #expect(r.title == "V60")
        #expect(r.coffeeGrams == 15)
        #expect(r.waterGrams == 250)
        let ratio = try #require(r.ratio)
        #expect(abs(ratio - 250.0 / 15.0) < 0.0001)
        #expect(r.waterTemperatureCelsius == nil)
    }

    @Test("converts alternate units to canonical on import")
    func convertsUnits() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"oz","coffee":{"value":0.5,"unit":"ounce"},"water":{"value":8,"unit":"ounce"},"water_temp":{"value":200,"unit":"fahrenheit"}}]}
        """#)
        #expect(abs(r.coffeeGrams - 14.1748) < 0.01)
        #expect(abs(try #require(r.waterGrams) - 226.796) < 0.01)
        let temp = try #require(r.waterTemperatureCelsius)
        #expect(abs(temp - 93.333) < 0.01)
    }

    @Test("rejects a newer major version")
    func rejectsNewerMajor() {
        #expect(throws: ImportError.decode(.unsupportedVersion(documentMajor: 2, supportedMajor: 1))) {
            try decodeRecipe(#"{"coffeejson":"2.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    // Support is one major, so an older one is as unsupported as a newer one:
    // this build cannot read rules it never carried.
    @Test("rejects an older major version")
    func rejectsOlderMajor() {
        #expect(throws: ImportError.decode(.unsupportedVersion(documentMajor: 0, supportedMajor: 1))) {
            try decodeRecipe(#"{"coffeejson":"0.9","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    @Test("accepts a newer minor within the supported major")
    func acceptsNewerMinor() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.7","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        #expect(r.title == "x")
    }

    // The wire states MAJOR.MINOR and nothing else, so a spelling outside that
    // grammar states no major to gate on — reported as unsupported rather than
    // as a document of some other format, because the envelope is this one's.
    @Test("rejects a version outside the MAJOR.MINOR grammar", arguments: ["1", "01.0", "1.0.0"])
    func rejectsMalformedVersion(_ version: String) {
        #expect(throws: ImportError.decode(.unsupportedVersion(documentMajor: nil, supportedMajor: 1))) {
            try decodeRecipe(#"{"coffeejson":"\#(version)","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    @Test("accepts a two-digit minor")
    func acceptsTwoDigitMinor() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.10","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        #expect(r.title == "x")
    }

    @Test("rejects malformed JSON")
    func rejectsMalformed() {
        #expect(throws: ImportError.decode(.notJSON)) {
            try decodeRecipe("{not json")
        }
    }

    @Test("requires title, coffee, and water")
    func requiresFields() {
        #expect(throws: ImportError.validation(.missingRequiredField("title"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
        #expect(throws: ImportError.validation(.missingRequiredField("coffee"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","water":{"value":250,"unit":"gram"}}]}"#)
        }
        #expect(throws: ImportError.validation(.missingRequiredField("water"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"}}]}"#)
        }
    }

    // `coffee` is required either way; of `water` and `ratio`, a recipe needs
    // one and the schema is satisfied. Only a recipe carrying neither states no
    // brew at all.

    @Test("a recipe stating a dose and a ratio imports, with the water the ratio implies")
    func doseAndRatioImports() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Base 1:15","method":"pour_over",
          "coffee":{"value":20,"unit":"gram"},"ratio":15,
          "water_temp":{"value":94,"unit":"celsius"}}]}
        """#)
        #expect(r.coffeeGrams == 20)
        #expect(r.waterGrams == 300)
        #expect(r.ratio == 15)
        // Nothing was stated by volume, and nothing was midpointed: 20 g at
        // 1:15 is exactly 300 g.
        #expect(r.waterStatedByVolume == false)
        #expect(r.waterMilliliters == nil)
        #expect(r.derivedQuantities == [])
    }

    @Test("a windowed dose at a stated ratio derives the water from the midpoint, and flags only that")
    func windowedDoseAtAStatedRatio() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x",
          "coffee":{"min":18,"max":20,"unit":"gram"},"ratio":15}]}
        """#)
        #expect(r.coffeeGrams == 19)
        // The midpoint of 18–20 at 1:15 is the midpoint of 270–300 either way,
        // so the single number this type can hold is the same one.
        #expect(r.waterGrams == 285)
        #expect(r.derivedQuantities.contains(.coffee))
        #expect(r.derivedQuantities.contains(.water))
        // The ratio is the author's, stated and used verbatim — nothing about
        // it was computed, midpointed or otherwise.
        #expect(r.ratio == 15)
        #expect(!r.derivedQuantities.contains(.ratio))
    }

    @Test("a stated dose and a plainly computed ratio stay unflagged, as they always have")
    func statedWaterKeepsItsUnflaggedRatio() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"}}]}"#)
        #expect(r.ratio == 15)
        #expect(r.derivedQuantities == [])
    }

    @Test("a water object stating no magnitude is fixed by a stated ratio")
    func emptyWaterObjectWithARatio() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},
          "water":{"unit":"gram"},"ratio":16}]}
        """#)
        #expect(r.waterGrams == 240)
        #expect(r.ratio == 16)
    }

    @Test("a ratio that states no proportion cannot fix a missing water")
    func unusableRatioStillThrows() {
        for ratio in ["0", "-15"] {
            #expect(throws: ImportError.validation(.missingRequiredField("water"))) {
                try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"ratio":\#(ratio)}]}"#)
            }
        }
    }

    @Test("a recipe stating neither water nor ratio is the one the schema calls invalid")
    func neitherWaterNorRatioThrows() {
        #expect(throws: ImportError.validation(.missingRequiredField("water"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"}}]}"#)
        }
    }

    @Test("a required measurement with an unrecognized unit counts as missing")
    func unknownUnitIsMissing() {
        #expect(throws: ImportError.validation(.missingRequiredField("coffee"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"ml"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    @Test("requires a non-blank title")
    func rejectsBlankTitle() {
        #expect(throws: ImportError.validation(.missingRequiredField("title"))) {
            try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"   ","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    @Test("prefers explicit coffee/water over an inconsistent wire ratio")
    func prefersExplicitMasses() throws {
        let r = try decodeRecipe(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"ratio":99}]}"#)
        #expect(abs(try #require(r.ratio) - 250.0 / 15.0) < 0.0001)
    }

    @Test("a ratio with nothing to compute it from is absent, not zero")
    func unavailableRatioIsAbsent() throws {
        // A dose of zero leaves nothing to divide by, and this document states
        // no `ratio` either. There is no proportion here; `0` would have read as
        // one, and read as a measurement.
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","basis":"yield",
          "coffee":{"value":0,"unit":"gram"},"yield":{"value":36,"unit":"gram"}}]}
        """#)
        #expect(r.coffeeGrams == 0)
        #expect(r.yieldGrams == 36)
        #expect(r.waterGrams == nil)   // yield basis states no brew water
        #expect(r.ratio == nil)
    }

    @Test("a document with no beans or recipes throws emptyDocument")
    func emptyDocument() {
        #expect(throws: ImportError.decode(.emptyDocument)) {
            try decodeRecipe(#"{"coffeejson":"1.0"}"#)
        }
    }

    @Test("captures the generator from the envelope")
    func capturesGenerator() throws {
        let doc = try Codec.decodeDocument(Data(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}],"generator":{"name":"ExampleApp","version":"2.0.0"}}"#.utf8))
        #expect(doc.generator?.name == "ExampleApp")
        #expect(doc.generator?.version == "2.0.0")
    }

    @Test("a recipe-level `source` is ignored — provenance is an envelope member")
    func recipeLevelSourceIgnored() throws {
        // Forward-compat says an unknown key is skipped, not rejected. This pins
        // that a recipe-level `source` reaches no reader.
        let doc = try Codec.decodeDocument(Data(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"source":{"name":"ExampleApp"}}]}"#.utf8))
        #expect(doc.generator == nil)
        #expect(doc.recipes.count == 1)
    }

    @Test("a generator that names no software is dropped, not half-decoded")
    func namelessGeneratorDropped() throws {
        // `name` is required by the schema; a document that omits it states
        // nothing, and the decoder must not surface an empty marker.
        let doc = try Codec.decodeDocument(Data(#"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}],"generator":{"version":"2.0.0"}}"#.utf8))
        #expect(doc.generator == nil)
    }

    @Test("decodes a yield-basis (espresso) recipe: yield/pressure/preinfusion carried, water=0, ratio=yield/coffee, basis=.yield")
    func decodesYieldBasis() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Shot","method":"espresso","basis":"yield",
          "coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"},
          "pressure":{"value":9,"unit":"bar"},"preinfusion_s":4,"finish_s":28}]}
        """#)
        #expect(r.basis == .yield)
        #expect(r.coffeeGrams == 18)
        #expect(r.yieldGrams == 36)
        #expect(r.waterGrams == nil)
        #expect(abs(try #require(r.ratio) - 36.0 / 18.0) < 0.0001)
        #expect(r.pressureBar == 9)
        #expect(r.preinfusionSeconds == 4)
        #expect(r.finishSeconds == 28)
        #expect(r.methodSlug == "espresso")
    }

    // Forbidding `water` on a yield basis is the schema's; the codec's job is to
    // require `yield`.
    @Test("a yield-basis recipe missing `yield` is rejected")
    func yieldBasisMissingYield() {
        #expect(throws: ImportError.validation(.missingRequiredField("yield"))) { _ = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","basis":"yield","coffee":{"value":18,"unit":"gram"}}]}
        """#) }
    }

    @Test("an unknown basis derives from the quantities present: yield-only → yield-basis")
    func unknownBasisDerivesYieldFromData() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Concentrate","basis":"concentrate",
          "coffee":{"value":100,"unit":"gram"},"yield":{"value":500,"unit":"gram"}}]}
        """#)
        #expect(r.basis == .yield)
        #expect(r.yieldGrams == 500)
        #expect(r.waterGrams == nil)
    }

    @Test("an unknown basis derives from the quantities present: water present → water-basis")
    func unknownBasisDerivesWaterFromData() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Odd","basis":"concentrate",
          "coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """#)
        #expect(r.basis == .water)
        #expect(r.waterGrams == 250)
    }

    @Test("an unknown basis derives from the quantities present: ratio beats a yield")
    func unknownBasisDerivesWaterFromRatio() throws {
        // The derive runs in the spec's order, because a water-basis recipe MAY
        // state a yield too: water *or ratio* first, only then yield.
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Odd","basis":"concentrate",
          "coffee":{"value":20,"unit":"gram"},"ratio":15,"yield":{"value":36,"unit":"gram"}}]}
        """#)
        #expect(r.basis == .water)
        #expect(r.ratio == 15)
        #expect(r.waterGrams == 300)
        #expect(r.yieldGrams == 36)
    }

    @Test("encode → decode preserves a yield-basis recipe's modeled fields")
    func yieldBasisRoundTrips() throws {
        let document = Document(
            version: Codec.currentVersion,
            recipes: [Recipe(
                title: "Shot",
                method: "espresso",
                basis: "yield",
                coffee: .grams(18),
                yield: .grams(36),
                pressure: .bar(9),
                preinfusionSeconds: 4,
                finishSeconds: 28)])
        let data = try Codec.encode(document)
        let r = try #require(try Codec.decodeDocument(data).recipes.first)

        #expect(r.basis == .yield)
        #expect(r.coffeeGrams == 18)
        #expect(r.yieldGrams == 36)
        #expect(r.waterGrams == nil)
        #expect(abs(try #require(r.ratio) - 36.0 / 18.0) < 0.0001)
        #expect(r.pressureBar == 9)
        #expect(r.preinfusionSeconds == 4)
        #expect(r.finishSeconds == 28)
        #expect(r.methodSlug == "espresso")
    }
}
