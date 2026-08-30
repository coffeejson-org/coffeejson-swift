import Foundation
import Testing
@testable import CoffeeJSON

/// Volume-stated brew water (`milliliter` — legal on `water` only). No
/// mass⇄volume conversion is defined, so such a recipe has a water and no mass
/// for it: `waterGrams` and `ratio` are absent rather than zero, and the codec
/// must *say* the water was stated by volume and surface the stated volume, so
/// no consumer has to reverse-engineer the absence.
struct VolumeWaterTests {
    private func recipe(_ waterJSON: String, extra: String = "") throws -> ImportedRecipe {
        let json = """
        {"coffeejson":"1.0","recipes":[{"title":"Switch","method":"pour_over",
         "coffee":{"value":14,"unit":"gram"},"water":\(waterJSON)\(extra)}]}
        """
        let document = try Codec.decodeDocument(Data(json.utf8))
        return try #require(document.recipes.first)
    }

    @Test func pointVolumeSetsFlagAndMilliliters() throws {
        let r = try recipe(#"{"value":225,"unit":"milliliter"}"#)
        #expect(r.waterStatedByVolume)
        #expect(r.waterMilliliters == 225)
        #expect(r.waterGrams == nil)
        #expect(r.ratio == nil)
        // A stated point is the author's number — nothing was derived.
        #expect(!r.derivedQuantities.contains(.water))
    }

    @Test func windowedVolumeMidpointsAndRecordsDerivation() throws {
        let r = try recipe(#"{"min":200,"max":250,"unit":"milliliter"}"#)
        #expect(r.waterStatedByVolume)
        #expect(r.waterMilliliters == 225)
        #expect(r.derivedQuantities.contains(.water))
    }

    @Test func gramWaterIsNotVolumeStated() throws {
        let r = try recipe(#"{"value":250,"unit":"gram"}"#)
        #expect(!r.waterStatedByVolume)
        #expect(r.waterMilliliters == nil)
        #expect(r.waterGrams == 250)
    }

    @Test func windowedGramWaterStaysMassAndDerived() throws {
        let r = try recipe(#"{"min":240,"max":260,"unit":"gram"}"#)
        #expect(!r.waterStatedByVolume)
        #expect(r.waterMilliliters == nil)
        #expect(r.waterGrams == 250)
        #expect(r.derivedQuantities.contains(.water))
    }

    @Test func yieldBasisIsNeverVolumeStated() throws {
        let json = """
        {"coffeejson":"1.0","recipes":[{"title":"Shot","method":"espresso","basis":"yield",
         "coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"}}]}
        """
        let document = try Codec.decodeDocument(Data(json.utf8))
        let r = try #require(document.recipes.first)
        #expect(!r.waterStatedByVolume)
        #expect(r.waterMilliliters == nil)
    }

    @Test func effectiveMillilitersMirrorsEffectiveGrams() {
        #expect(Quantity.milliliters(225).effectiveMilliliters == 225)
        #expect(Quantity(min: 200, max: 250, unit: "milliliter").effectiveMilliliters == 225)
        #expect(Quantity.grams(250).effectiveMilliliters == nil)
    }

    @Test func midpointMillilitersMirrorsMidpointGrams() {
        // The volume set now vends the midpoint its three siblings do, so a
        // consumer labeling a derived volume reads it instead of recomputing.
        #expect(Quantity(min: 200, max: 250, unit: "milliliter").midpointMilliliters == 225)
        #expect(Quantity.milliliters(225).midpointMilliliters == nil)
        #expect(Quantity(min: 200, max: 250, unit: "gram").midpointMilliliters == nil)
    }
}
