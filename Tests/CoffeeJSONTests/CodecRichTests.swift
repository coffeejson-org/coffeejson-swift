import Testing
import Foundation
@testable import CoffeeJSON

/// Step classification, grind/gear rendering, and forward-compat — all pure.
/// Rescaling cumulative grams to a storage model is consumer policy and has no
/// test here.
@Suite("CoffeeJSON codec — steps, grind, gear, forward-compat")
struct CodecRichTests {
    @Test("imports timed pour steps in order, with the finish time, as faithful cumulative grams")
    func importsPourSteps() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"at_s":0,"to_water":{"value":30,"unit":"gram"}},{"at_s":30,"to_water":{"value":150,"unit":"gram"}},{"at_s":75,"to_water":{"value":250,"unit":"gram"}}],
          "finish_s":150}]}
        """#)
        #expect(r.pourSteps.map(\.atSeconds) == [0, 30, 75])
        #expect(r.pourSteps.map(\.cumulativeWaterGrams) == [30, 150, 250])
        #expect(r.finishSeconds == 150)
    }

    @Test("the default step kind is pour; a custom label is preserved")
    func defaultKindPourAndCustomLabel() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"pour","at_s":0,"to_water":{"value":30,"unit":"gram"},"label":"Big Bloom"}]}]}
        """#)
        #expect(r.pourSteps.first?.label == "Big Bloom")
    }

    @Test("an absent (derived) label stays nil so a consumer renders its own")
    func absentLabelStaysNil() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"at_s":0,"to_water":{"value":30,"unit":"gram"}}]}]}
        """#)
        #expect(r.pourSteps.first?.label == nil)
    }

    @Test("a to_water above the recipe total is carried through faithfully (no clamping in the pure layer)")
    func overTotalToWaterIsFaithful() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"at_s":0,"to_water":{"value":9999,"unit":"gram"}}]}]}
        """#)
        #expect(r.pourSteps.first?.cumulativeWaterGrams == 9999)
    }

    @Test("non-pour and untimed steps are surfaced read-only in order, never imported as pours")
    func nonPourStepsAreReadOnly() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[
            {"kind":"prep","instruction":"rinse filter, preheat"},
            {"at_s":0,"to_water":{"value":30,"unit":"gram"}},
            {"kind":"flip","instruction":"invert the AeroPress"}
          ]}]}
        """#)
        #expect(r.pourSteps.count == 1)
        #expect(r.readOnlySteps.map(\.instruction) == ["rinse filter, preheat", "invert the AeroPress"])
        #expect(r.readOnlySteps.map(\.kind) == ["prep", "flip"])
    }

    @Test("an unknown step kind is treated as read-only, never a failure")
    func unknownKindIsReadOnly() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"levitate","instruction":"do a barrel roll"},{"at_s":10,"to_water":{"value":250,"unit":"gram"}}]}]}
        """#)
        #expect(r.pourSteps.count == 1)
        // The unrecognized kind is carried verbatim, not folded into a catch-all.
        #expect(r.readOnlySteps.map(\.kind) == ["levitate"])
        #expect(r.readOnlySteps.map(\.instruction) == ["do a barrel roll"])
    }

    @Test("a water-bearing step is scheduled on its data, not its kind: a timed bloom becomes a pour")
    func waterBearingKindIsScheduledOnData() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"bloom","at_s":0,"to_water":{"value":45,"unit":"gram"},"label":"Bloom"}]}]}
        """#)
        #expect(r.pourSteps.map(\.atSeconds) == [0])
        #expect(r.pourSteps.map(\.cumulativeWaterGrams) == [45])
        #expect(r.pourSteps.first?.label == "Bloom")
        #expect(r.readOnlySteps.isEmpty)
    }

    @Test("data wins over kind: a non-pour step carrying at_s + to_water is a pour, even when it also carries an instruction")
    func dataWinsOverNonPourKind() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"prep","at_s":10,"to_water":{"value":60,"unit":"gram"},"instruction":"pour to 60g while the kettle settles"}]}]}
        """#)
        #expect(r.pourSteps.map(\.cumulativeWaterGrams) == [60])
        #expect(r.readOnlySteps.isEmpty)
    }

    @Test("a step missing either at_s or to_water is never a pour, whatever its kind — its instruction reads read-only")
    func missingEitherHalfIsNeverAPour() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[
            {"kind":"pour","at_s":30,"instruction":"pour slowly — no target set"},
            {"kind":"pour","to_water":{"value":120,"unit":"gram"},"instruction":"top up to 120g when you're ready"}
          ]}]}
        """#)
        #expect(r.pourSteps.isEmpty)
        // A stated at_s is kept as the cue it is — reported, never discarded,
        // and never spliced into the instruction.
        #expect(r.readOnlySteps.map(\.atSeconds) == [30, nil])
        #expect(r.readOnlySteps.map(\.instruction) == [
            "pour slowly — no target set", "top up to 120g when you're ready",
        ])
    }

    @Test("a bare-kind step surfaces read-only instead of vanishing — the spec's own tamp example")
    func bareKindStepSurfaces() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","method":"espresso","basis":"yield",
          "coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"},
          "steps":[{"kind":"distribute"},{"kind":"tamp"},{"kind":"pull","at_s":0}]}]}
        """#)
        #expect(r.pourSteps.isEmpty)
        #expect(r.readOnlySteps.map(\.kind) == ["distribute", "tamp", "pull"])
        #expect(r.readOnlySteps.map(\.atSeconds) == [nil, nil, 0])
        #expect(r.readOnlySteps.allSatisfy { $0.instruction == nil })
    }

    // The three bodies below are the format's own conformance cases for
    // `action_duration_s`, and not one of them is a pour: a press and a steep
    // carry a duration *because* they move no water, so the duration is the
    // whole of what they state. A projection that renders them to prose keeps
    // the sentence and drops the number.

    @Test("a timed pour keeps the sentence the author wrote for it")
    func pourKeepsItsInstruction() throws {
        // Verbatim from a published guide: every pour it states carries an
        // instruction, and the instruction is what a brewing surface shows
        // while the pour runs.
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"April Selection — April Hybrid Brewer",
          "coffee":{"value":14,"unit":"gram"},"water":{"value":240,"unit":"gram"},
          "steps":[
            {"at_s":0,"to_water":{"value":40,"unit":"gram"},"action_duration_s":10,"instruction":"open the valve; pour 40 g in a circle"},
            {"at_s":40,"to_water":{"value":140,"unit":"gram"},"action_duration_s":10,"instruction":"close the valve; pour 100 g — 60 g in a circle and 40 g in the centre"},
            {"at_s":80,"to_water":{"value":240,"unit":"gram"},"action_duration_s":10,"instruction":"open the valve; pour 100 g — 60 g in a circle and 40 g in the centre"}
          ]}]}
        """#)
        #expect(r.pourSteps.map(\.instruction) == [
            "open the valve; pour 40 g in a circle",
            "close the valve; pour 100 g — 60 g in a circle and 40 g in the centre",
            "open the valve; pour 100 g — 60 g in a circle and 40 g in the centre",
        ])
    }

    @Test("a pour that states no instruction carries none, and a blank one states nothing")
    func pourWithoutInstruction() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[
            {"at_s":0,"to_water":{"value":50,"unit":"gram"}},
            {"at_s":30,"to_water":{"value":250,"unit":"gram"},"instruction":"   "}
          ]}]}
        """#)
        #expect(r.pourSteps.map(\.instruction) == [nil, nil])
    }

    @Test("a press keeps how long the plunge takes — the format's own case for the field")
    func pressKeepsItsDuration() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Inverted AeroPress","coffee":{"value":15,"unit":"gram"},"water":{"value":220,"unit":"gram"},
          "steps":[
            {"kind":"prep","instruction":"assemble inverted, rinse filter"},
            {"kind":"pour","at_s":0,"to_water":{"value":220,"unit":"gram"},"instruction":"add all water"},
            {"kind":"stir","at_s":10,"instruction":"stir 3x gently"},
            {"kind":"flip","instruction":"cap, flip onto cup"},
            {"kind":"press","at_s":30,"action_duration_s":25,"instruction":"press slowly"}
          ]}]}
        """#)
        #expect(r.pourSteps.count == 1)
        let press = try #require(r.readOnlySteps.last)
        #expect(press.kind == "press")
        #expect(press.atSeconds == 30)
        #expect(press.actionDurationSeconds == 25)
        #expect(press.instruction == "press slowly")
    }

    @Test("a steep keeps the minute it steeps for")
    func steepKeepsItsDuration() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Hario Switch — steep then drain","coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"},
          "steps":[
            {"kind":"valve_close","at_s":0,"instruction":"Check the switch is shut."},
            {"kind":"pour","at_s":0,"to_water":{"value":300,"unit":"gram"},"instruction":"Pour to 300 g."},
            {"kind":"wait","at_s":30,"action_duration_s":60,"instruction":"Steep for a minute."},
            {"kind":"valve_open","at_s":90,"instruction":"Open the switch and let it drain."},
            {"kind":"drawdown","at_s":90,"instruction":"Drains by about 2:30."}
          ]}]}
        """#)
        #expect(r.readOnlySteps.map(\.kind) == ["valve_close", "wait", "valve_open", "drawdown"])
        let steep = try #require(r.readOnlySteps.first { $0.kind == "wait" })
        #expect(steep.actionDurationSeconds == 60)
        #expect(steep.atSeconds == 30)
        // The prose says a minute. The number does not depend on parsing it
        // back out of the prose.
        #expect(steep.instruction == "Steep for a minute.")
    }

    @Test("a read-only step carries its cue and its kind as data, not as rendered text")
    func readOnlyStepIsNotRendered() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"pour","at_s":30,"instruction":"pour slowly — no target set"}]}]}
        """#)
        let step = try #require(r.readOnlySteps.first)
        #expect(step.atSeconds == 30)
        #expect(step.kind == "pour")
        #expect(step.instruction == "pour slowly — no target set")
        #expect(step.label == nil)
    }

    @Test("a step stating nothing at all is dropped; one stating only a kind is not")
    func emptyStepDropsAndBareKindSurvives() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{},{"kind":"tamp"}]}]}
        """#)
        #expect(r.readOnlySteps.map(\.kind) == ["tamp"])
    }

    @Test("a windowed to_water schedules on the midpoint and reports the derivation")
    func windowedPourSchedulesAndReports() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"pour","at_s":45,"to_water":{"min":200,"max":220,"unit":"gram"}}]}]}
        """#)
        #expect(r.pourSteps.map(\.cumulativeWaterGrams) == [210])
        #expect(r.derivedQuantities.contains(.steps))
        #expect(r.readOnlySteps.isEmpty)
    }

    @Test("a ratio computed from a midpointed operand is marked derived")
    func ratioFromWindowIsDerived() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"min":14,"max":16,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}
        """#)
        #expect(r.coffeeGrams == 15)
        #expect(r.derivedQuantities.contains(.coffee))
        #expect(r.derivedQuantities.contains(.ratio))
    }

    @Test("a missing required member names itself instead of reading as malformed")
    func missingUnitNamesTheField() throws {
        let json = #"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15},"water":{"value":250,"unit":"gram"}}]}
        """#
        #expect(throws: ImportError.validation(.missingRequiredField("unit"))) {
            _ = try Codec.decodeDocument(Data(json.utf8))
        }
    }

    @Test("encode stamps the build's version — a decoded envelope's claim never re-emits")
    func encodeStampsCurrentVersion() throws {
        let document = Document(
            version: "banana",
            recipes: [Recipe(title: "x", coffee: .grams(15), water: .grams(250))])
        let emitted = try Codec.encode(document)
        let reread = try Codec.decodeDocument(emitted)
        #expect(reread.recipes.first?.title == "x")
        let object = try #require(try JSONSerialization.jsonObject(with: emitted) as? [String: Any])
        #expect(object["coffeejson"] as? String == Codec.currentVersion)
    }

    @Test("generator.url rides the wire, on the envelope and not on the recipe")
    func generatorUrlRoundTrips() throws {
        let document = Document(
            version: Codec.currentVersion,
            recipes: [Recipe(title: "x", coffee: .grams(15), water: .grams(250))],
            generator: Generator(name: "ExampleApp", version: "1.0", url: "https://example.app"))
        let emitted = try Codec.encode(document)
        let object = try #require(try JSONSerialization.jsonObject(with: emitted) as? [String: Any])
        #expect((object["generator"] as? [String: Any])?["url"] as? String == "https://example.app")
        // And it is not duplicated down onto the recipe.
        let recipe = try #require((object["recipes"] as? [[String: Any]])?.first)
        #expect(recipe["generator"] == nil)
        #expect(recipe["source"] == nil)
    }

    @Test("builds a faithful grind description from grinder, setting and microns")
    func grindDescription() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "grind":{"grinder":{"id":"comandante-c40","label":"Comandante C40"},"setting":"22 clicks","microns_approx":700}}]}
        """#)
        let g = try #require(r.grindDescription)
        #expect(g.contains("Comandante C40"))
        #expect(g.contains("22 clicks"))
        #expect(g.contains("700"))
    }

    @Test("captures method, brewer label and microns for the preview")
    func capturesPreviewExtras() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "method":"pour_over","brewer":{"id":"hario-v60","label":"Hario V60"},"grind":{"microns_approx":700}}]}
        """#)
        #expect(r.methodSlug == "pour_over")
        #expect(r.brewerLabel == "Hario V60")
        #expect(r.micronsApprox == 700)
    }

    @Test("brewer label falls back to brand + model when no label is given")
    func brewerLabelFallback() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "brewer":{"id":"custom","brand":"Acme","model":"Dripper 9000"}}]}
        """#)
        #expect(r.brewerLabel == "Acme Dripper 9000")
    }

    @Test("a rich document with a full bean block imports the recipe and ignores the bean")
    func ignoresBeanBlock() throws {
        let r = try decodeRecipe(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Sunday V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
          "bean":{"name":"Nano Challa","roaster":{"name":"Onyx"},"origin":{"type":"single","items":[{"country":"ET","region":"Guji"}]},
                  "process":["washed"],"roast_level":"medium_light","roaster_notes":["blueberry","floral"]},
          "future_field":{"x":1}}]}
        """#)
        #expect(r.title == "Sunday V60")
        #expect(r.coffeeGrams == 15)
        #expect(r.pourSteps.isEmpty)
    }
}
