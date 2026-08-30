import Testing
import Foundation
@testable import CoffeeJSON

@Suite("CoffeeJSON decodeDocument")
struct DecodeDocumentTests {

    @Test("a bean-only document yields one normalized bean and no recipes")
    func beanOnly() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ {
            "name": "Nano Challa",
            "roaster": { "name": "Example Roastery",
                         "url": "https://example-roastery.com",
                         "type": "organization" },
            "images": ["https://example.com/nano-challa/bag.jpg"],
            "description": "A washed heirloom lot.",
            "origin": { "type": "single", "items": [
              { "country": "ET", "region": "Guji",
                "altitude": { "min": 1900, "max": 2100, "unit": "meter" } } ] },
            "process": ["washed"], "varietals": ["heirloom"],
            "roast_level": "medium_light", "roast_agtron": 65,
            "roast_date": "2026-06-20", "decaf": false, "form": "bean",
            "roaster_notes": ["blueberry", "floral"] } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        #expect(doc.recipes.isEmpty)
        #expect(doc.beans.count == 1)
        #expect(doc.recipesShareSingleBean == false)
        let bean = doc.beans[0]
        #expect(bean.name == "Nano Challa")
        #expect(bean.roaster == ImportedParty(
            name: "Example Roastery", url: "https://example-roastery.com", type: "organization"))
        #expect(bean.images == ["https://example.com/nano-challa/bag.jpg"])
        #expect(bean.description == "A washed heirloom lot.")
        #expect(bean.process == ["washed"])
        #expect(bean.varietals == ["heirloom"])
        #expect(bean.roastLevel == "medium_light")
        #expect(bean.roastAgtron == 65)
        #expect(bean.roastDate == CalendarDay(year: 2026, month: 6, day: 20))
        #expect(bean.decaf == false)
        #expect(bean.form == "bean")
        #expect(bean.roasterNotes == ["blueberry", "floral"])
        let item = try #require(bean.origin?.items.first)
        #expect(item.country == "ET")
        #expect(item.altitude?.minMeters == 1900)
        #expect(item.altitude?.maxMeters == 2100)
    }

    @Test("bag-to-brew: one bean + one recipe associate by co-location")
    func bagToBrew() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "Bag", "roaster": { "name": "Roastery" } } ],
          "recipes": [ { "title": "Recommended", "coffee": { "value": 15, "unit": "gram" },
                      "water": { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        #expect(doc.beans.count == 1)
        #expect(doc.recipes.count == 1)
        #expect(doc.recipesShareSingleBean == true)
        #expect(doc.recipes[0].title == "Recommended")
    }

    @Test("a recipe-only document yields no beans and does not associate")
    func recipeOnly() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Solo", "coffee": { "value": 18, "unit": "gram" },
                      "water": { "value": 300, "unit": "gram" } } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        #expect(doc.beans.isEmpty)
        #expect(doc.recipes.count == 1)
        #expect(doc.recipesShareSingleBean == false)
    }

    @Test("reserved beans+recipes: both collections import, no link, no error")
    func beansAndRecipesReserved() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "One" }, { "name": "Two" } ],
          "recipes": [ { "title": "R", "coffee": { "value": 15, "unit": "gram" },
                         "water": { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        #expect(doc.beans.count == 2)
        #expect(doc.recipes.count == 1)
        #expect(doc.recipesShareSingleBean == false)   // multiple beans → no co-location
    }

    @Test("a bean's absent images and description project empty / nil")
    func absentBeanImagesAndDescription() throws {
        let json = Data("""
        { "coffeejson": "1.0", "beans": [ { "name": "Plain Bag" } ] }
        """.utf8)
        let bean = try #require(try Codec.decodeDocument(json).beans.first)
        #expect(bean.images.isEmpty)
        #expect(bean.description == nil)
    }

    @Test("a roaster party without a usable name projects as absent, never failing the import")
    func namelessRoasterProjectsAbsent() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "No name", "roaster": { "url": "https://example-roastery.com" } },
                     { "name": "Empty name", "roaster": { "name": "" } } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        #expect(doc.beans.count == 2)
        #expect(doc.beans[0].roaster == nil)
        #expect(doc.beans[1].roaster == nil)
    }

    @Test("altitude in feet converts to canonical meters")
    func altitudeFeet() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "High",
            "origin": { "items": [ { "country": "GT",
              "altitude": { "value": 5000, "unit": "foot" } } ] } } ] }
        """.utf8)
        let doc = try Codec.decodeDocument(json)
        let meters = try #require(doc.beans.first?.origin?.items.first?.altitude?.valueMeters)
        #expect(abs(meters - 1524) < 0.5)   // 5000 ft × 0.3048
    }

    @Test("a recipe's notes and ice addition are projected onto ImportedRecipe")
    func notesAndAdditions() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ {
            "title": "Iced 4:6", "coffee": { "value": 20, "unit": "gram" },
            "water": { "value": 150, "unit": "gram" },
            "notes": "Brew straight onto the ice.",
            "additions": [ { "type": "ice", "amount": { "value": 80, "unit": "gram" } } ] } ] }
        """.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        #expect(recipe.notes == "Brew straight onto the ice.")
        #expect(recipe.additions.count == 1)
        #expect(recipe.additions.first?.type == "ice")
        #expect(recipe.additions.first?.isIce == true)
        #expect(recipe.additions.first?.amountGrams == 80)
    }

    @Test("a recipe with neither notes nor additions projects nil / empty")
    func noNotesOrAdditions() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Plain", "coffee": { "value": 15, "unit": "gram" },
                         "water": { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        #expect(recipe.notes == nil)
        #expect(recipe.additions.isEmpty)
    }

    @Test("author, based_on, images, description, date_published project onto ImportedRecipe")
    func attributionProjects() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Ultimate V60",
            "coffee": { "value": 15, "unit": "gram" },
            "water":  { "value": 250, "unit": "gram" },
            "author": { "name": "James Hoffmann", "url": "https://www.jameshoffmann.co.uk", "type": "person" },
            "based_on": "https://example.com/ultimate-v60",
            "images": ["https://example.com/v60-brew.jpg"],
            "description": "A single-cup V60 in five even pours.",
            "date_published": "2019-03-27" } ] }
        """.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        #expect(recipe.author == ImportedParty(
            name: "James Hoffmann", url: "https://www.jameshoffmann.co.uk", type: "person"))
        #expect(recipe.basedOn == "https://example.com/ultimate-v60")
        #expect(recipe.images == ["https://example.com/v60-brew.jpg"])
        #expect(recipe.description == "A single-cup V60 in five even pours.")
        #expect(recipe.datePublished == CalendarDay(year: 2019, month: 3, day: 27))
    }

    @Test("absent or empty attribution fields project nil / empty — an empty images array reads as absent")
    func absentAttributionProjectsEmpty() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Plain", "coffee": { "value": 15, "unit": "gram" },
                         "water": { "value": 250, "unit": "gram" }, "images": [] },
                       { "title": "Bare", "coffee": { "value": 15, "unit": "gram" },
                         "water": { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let recipes = try Codec.decodeDocument(json).recipes
        #expect(recipes.count == 2)
        for recipe in recipes {
            #expect(recipe.author == nil)
            #expect(recipe.basedOn == nil)
            #expect(recipe.images.isEmpty)
            #expect(recipe.description == nil)
            #expect(recipe.datePublished == nil)
        }
    }

    @Test("a nameless author projects as absent, never failing the import")
    func namelessAuthorProjectsAbsent() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Anon", "coffee": { "value": 15, "unit": "gram" },
                         "water": { "value": 250, "unit": "gram" },
                         "author": { "url": "https://example.com" } } ] }
        """.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        #expect(recipe.author == nil)
    }

    @Test("rawJSON preserves a field the wire type does not model (basket)")
    func rawJSONCarriesUnmodeledField() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "Espresso", "method": "espresso", "basis": "yield",
            "coffee": { "value": 18, "unit": "gram" }, "yield": { "value": 36, "unit": "gram" },
            "basket": { "id": "vst-18g" } } ] }
        """.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        let raw = try #require(recipe.rawJSON)
        let obj = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(obj["basket"] != nil)                 // survived even though Recipe has no `basket`
        #expect((obj["title"] as? String) == "Espresso")
    }

    @Test("importedRecipe(from:Data) reads a single recipe object into the projection")
    func importedRecipeFromData() throws {
        let json = Data(#"""
        { "title": "One", "coffee": { "value": 18, "unit": "gram" }, "yield": { "value": 36, "unit": "gram" },
          "basis": "yield", "notes": "hi", "pressure": { "value": 9, "unit": "bar" } }
        """#.utf8)
        let imported = try Codec.importedRecipe(from: json)
        #expect(imported.notes == "hi")
        #expect(imported.pressureBar == 9)
        #expect(imported.yieldGrams == 36)
        #expect(imported.rawJSON == json)
    }

    // `decodeDocument` catches `DecodingError` and maps it onto named cases.
    // The two single-object readers never got the same treatment, so a stored
    // payload that failed to parse surfaced as a raw Foundation error — which a
    // caller matching on `ImportError` cannot see at all.

    @Test("importedRecipe(from:) reports non-JSON in this package's vocabulary")
    func importedRecipeFromDataRejectsNonJSON() {
        #expect(throws: ImportError.decode(.notJSON)) {
            try Codec.importedRecipe(from: Data("not json".utf8))
        }
    }

    @Test("importedRecipe(from:) names a wrong-typed field rather than leaking a DecodingError")
    func importedRecipeFromDataNamesWrongFieldType() {
        let json = Data(#"""
        {"title":"V60","coffee":{"value":15,"unit":"gram"},
         "water":{"value":250,"unit":"gram"},"water_temp":"hot"}
        """#.utf8)
        #expect(throws: ImportError.validation(.wrongFieldType(field: "water_temp"))) {
            try Codec.importedRecipe(from: json)
        }
    }

    @Test("importedBean(from:) reports non-JSON in this package's vocabulary")
    func importedBeanFromDataRejectsNonJSON() {
        #expect(throws: ImportError.decode(.notJSON)) {
            try Codec.importedBean(from: Data("not json".utf8))
        }
    }

    @Test("importedBean(from:) names a wrong-typed field rather than leaking a DecodingError")
    func importedBeanFromDataNamesWrongFieldType() {
        let json = Data(#"{"name":"Nano Challa","roast_agtron":"sixty-five"}"#.utf8)
        #expect(throws: ImportError.validation(.wrongFieldType(field: "roast_agtron"))) {
            try Codec.importedBean(from: json)
        }
    }

    @Test("importedRecipe(from:) separates a UTF-8 fault from a syntax fault, as the envelope reader does")
    func importedRecipeFromDataRejectsNonUTF8() {
        // 0xFF is not a legal UTF-8 byte in any position.
        #expect(throws: ImportError.decode(.notUTF8)) {
            try Codec.importedRecipe(from: Data([0xFF, 0xFE, 0x7B]))
        }
    }

    // The failure is not "a bad date is rejected" but "a bad date reads as a
    // *different* date": `Calendar.date(from:)` normalizes month 13 into the
    // next year, and `split` drops the empty subsequence a leading sign leaves.

    @Test(
        "a roast date that is not a real yyyy-MM-dd calendar date reads as absent",
        arguments: ["2026-13-45", "2026-02-31", "2026-00-00", "-2026-01-01", "2026-1-1", "not-a-date-here"])
    func invalidRoastDateProjectsNil(raw: String) throws {
        let json = Data(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roast_date":"\#(raw)"}]}"#.utf8)
        let bean = try #require(try Codec.decodeDocument(json).beans.first)
        #expect(bean.roastDate == nil)
    }

    @Test("a real leap day still parses — the guard against an over-eager fix")
    func leapDayRoastDateParses() throws {
        let json = Data(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roast_date":"2028-02-29"}]}"#.utf8)
        let bean = try #require(try Codec.decodeDocument(json).beans.first)
        #expect(bean.roastDate == CalendarDay(year: 2028, month: 2, day: 29))
    }

    @Test("a recipe's malformed date_published reads as absent too — the other call site")
    func invalidDatePublishedProjectsNil() throws {
        let json = Data(#"""
        { "coffeejson": "1.0",
          "recipes": [ { "title": "V60", "coffee": { "value": 15, "unit": "gram" },
            "water": { "value": 250, "unit": "gram" }, "date_published": "2019-13-40" } ] }
        """#.utf8)
        let recipe = try #require(try Codec.decodeDocument(json).recipes.first)
        #expect(recipe.datePublished == nil)
    }
}
