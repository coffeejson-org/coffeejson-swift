import Testing
import Foundation
@testable import CoffeeJSON

@Suite("CoffeeJSON document decode")
struct DocumentTests {
    @Test("the minimal valid document decodes title, coffee, water")
    func minimalDocument() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Everyday V60",
                      "coffee": { "value": 15,  "unit": "gram" },
                      "water":  { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        #expect(doc.version == "1.0")
        let recipe = try #require(doc.recipes?.first)
        #expect(recipe.title == "Everyday V60")
        #expect(recipe.coffee?.grams == 15)
        #expect(recipe.water?.grams == 250)
        #expect(doc.recipes?.count == 1)
    }

    @Test("a rich document decodes every modeled recipe field")
    func richDocument() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ {
            "title": "Sunday V60",
            "method": "pour_over",
            "brewer": { "id": "hario-v60", "brand": "Hario", "model": "V60", "label": "Hario V60" },
            "coffee": { "value": 15,  "unit": "gram" },
            "water":  { "value": 250, "unit": "gram" },
            "ratio": 16.7,
            "water_temp": { "value": 94, "unit": "celsius" },
            "grind": { "grinder": { "id": "comandante-c40", "label": "Comandante C40" },
                       "setting": "22 clicks", "microns_approx": 700 },
            "steps": [
              { "at_s": 0,  "to_water": { "value": 30,  "unit": "gram" }, "instruction": "gentle bloom, swirl" },
              { "at_s": 30, "to_water": { "value": 150, "unit": "gram" } },
              { "at_s": 75, "to_water": { "value": 250, "unit": "gram" } }
            ],
            "finish_s": 150,
            "lang": "en"
          } ],
          "generator": { "name": "ExampleApp", "version": "2.0.0" } }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let r = try #require(doc.recipes?.first)
        #expect(r.method == "pour_over")
        #expect(r.brewer?.id == "hario-v60")
        #expect(r.brewer?.label == "Hario V60")
        #expect(r.ratio == 16.7)
        #expect(r.waterTemp?.celsius == 94)
        #expect(r.grind?.setting == "22 clicks")
        #expect(r.grind?.micronsApprox == 700)
        #expect(r.grind?.grinder?.id == "comandante-c40")
        #expect(r.steps?.count == 3)
        #expect(r.steps?.first?.toWater?.grams == 30)
        #expect(r.steps?.first?.atSeconds == 0)
        #expect(r.finishSeconds == 150)
        #expect(doc.generator?.name == "ExampleApp")
        #expect(doc.generator?.version == "2.0.0")
    }

    @Test("a recipes[] library document decodes the array")
    func recipesArrayDocument() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "A", "coffee": {"value":15,"unit":"gram"}, "water": {"value":250,"unit":"gram"} },
                       { "title": "B", "coffee": {"value":18,"unit":"gram"}, "water": {"value":300,"unit":"gram"} } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        #expect(doc.beans == nil)
        #expect(doc.recipes?.count == 2)
        #expect(doc.recipes?[1].title == "B")
    }

    @Test("recipe attribution and publication metadata decode: author, based_on, images, description, date_published")
    func attributionAndPublicationFieldsDecode() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Ultimate V60",
            "coffee": { "value": 15, "unit": "gram" },
            "water":  { "value": 250, "unit": "gram" },
            "author": { "name": "James Hoffmann",
                        "url": "https://www.jameshoffmann.co.uk",
                        "type": "person" },
            "based_on": "https://example.com/ultimate-v60",
            "images": ["https://example.com/v60-brew.jpg", "https://example.com/v60-pour.jpg"],
            "description": "A single-cup V60 in five even pours.",
            "date_published": "2019-03-27" } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let r = try #require(doc.recipes?.first)
        #expect(r.author?.name == "James Hoffmann")
        #expect(r.author?.url == "https://www.jameshoffmann.co.uk")
        #expect(r.author?.type == "person")
        #expect(r.basedOn == "https://example.com/ultimate-v60")
        #expect(r.images == ["https://example.com/v60-brew.jpg", "https://example.com/v60-pour.jpg"])
        #expect(r.description == "A single-cup V60 in five even pours.")
        #expect(r.datePublished == "2019-03-27")
    }

    @Test("unknown top-level/nested fields and a full bean block are ignored (forward-compatible)")
    func forwardCompatibleUnknownFields() throws {
        let json = Data("""
        { "coffeejson": "1.0", "future_top": 1,
          "recipes": [ { "title": "X",
                      "coffee": { "value": 15, "unit": "gram", "note": "ignored" },
                      "water":  { "value": 250, "unit": "gram" },
                      "bean": { "name": "Nano Challa", "roaster": { "name": "Onyx" },
                                "origin": { "type": "single", "items": [ { "country": "ET" } ] },
                                "roaster_notes": ["blueberry", "floral"] },
                      "mystery": { "nested": true } } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let r = try #require(doc.recipes?.first)
        #expect(r.title == "X")
        #expect(r.coffee?.grams == 15)
        #expect(r.water?.grams == 250)
    }
}
