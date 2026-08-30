import Testing
import Foundation
@testable import CoffeeJSON

@Suite("CoffeeJSON bean decode")
struct BeanTests {
    @Test("a full bean document decodes every modeled field")
    func fullBean() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ {
            "name": "Nano Challa",
            "roaster": { "name": "Example Roastery",
                         "url": "https://example-roastery.com",
                         "type": "organization" },
            "url": "https://example.com/coffees/nano-challa",
            "images": ["https://example.com/coffees/nano-challa/bag.jpg"],
            "origin": {
              "type": "single",
              "items": [
                { "country": "ET", "region": "Guji", "producers": [{ "name": "Nano Challa cooperative", "role": "cooperative" }], "varietals": ["heirloom"],
                  "altitude": { "min": 1900, "max": 2100, "unit": "meter" },
                  "harvest_time": "Oct–Dec 2025" }
              ]
            },
            "process": ["washed"],
            "drying_method": "raised_bed",
            "varietals": ["heirloom"],
            "roast_level": "medium_light",
            "roast_agtron": 65,
            "roast_date": "2026-06-20",
            "decaf": false,
            "form": "bean",
            "certifications": ["organic", "fair_trade"],
            "roaster_notes": ["blueberry", "dark chocolate", "floral"],
            "description": "A washed heirloom lot from the Nano Challa cooperative."
          } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let bean = try #require(doc.beans?.first)
        #expect(bean.name == "Nano Challa")
        #expect(bean.roaster?.name == "Example Roastery")
        #expect(bean.roaster?.url == "https://example-roastery.com")
        #expect(bean.roaster?.type == "organization")
        #expect(bean.url == "https://example.com/coffees/nano-challa")
        #expect(bean.images == ["https://example.com/coffees/nano-challa/bag.jpg"])
        #expect(bean.description == "A washed heirloom lot from the Nano Challa cooperative.")
        #expect(bean.process == ["washed"])
        #expect(bean.dryingMethod == "raised_bed")
        #expect(bean.varietals == ["heirloom"])
        #expect(bean.roastLevel == "medium_light")
        #expect(bean.roastAgtron == 65)
        #expect(bean.roastDate == "2026-06-20")
        #expect(bean.decaf == false)
        #expect(bean.form == "bean")
        #expect(bean.certifications == ["organic", "fair_trade"])
        #expect(bean.roasterNotes == ["blueberry", "dark chocolate", "floral"])

        let origin = try #require(bean.origin)
        #expect(origin.type == "single")
        let item = try #require(origin.items?.first)
        #expect(item.country == "ET")
        #expect(item.region == "Guji")
        #expect(item.producers?.count == 1)
        #expect(item.producers?.first?.name == "Nano Challa cooperative")
        #expect(item.producers?.first?.role == "cooperative")
        #expect(item.varietals == ["heirloom"])
        #expect(item.altitude?.min == 1900)
        #expect(item.altitude?.max == 2100)
        #expect(item.altitude?.unit == "meter")
        #expect(item.harvestTime == "Oct–Dec 2025")
        #expect(doc.beans?.count == 1)
    }

    @Test("a bean and a recipe coexist in one document")
    func beanAndRecipeCoexist() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "Bag", "roaster": { "name": "Roastery" } } ],
          "recipes": [ { "title": "Recommended V60",
                      "coffee": { "value": 15, "unit": "gram" },
                      "water":  { "value": 250, "unit": "gram" } } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        #expect(doc.beans?.first?.name == "Bag")
        #expect(doc.recipes?.first?.title == "Recommended V60")
    }

    @Test("a bare-string roaster fails to decode — a roaster is a party object")
    func bareStringRoasterRejected() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "Bag", "roaster": "Example Roastery" } ] }
        """.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Document.self, from: json)
        }
    }

    @Test("a beans array decodes as a catalog")
    func beansCatalog() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "One" }, { "name": "Two", "decaf": true } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let beans = try #require(doc.beans)
        #expect(beans.count == 2)
        #expect(beans[0].name == "One")
        #expect(beans[1].decaf == true)
        #expect(doc.recipes == nil)
    }

    @Test("a blend origin decodes multiple items with altitude and percentage")
    func blendOrigin() throws {
        let json = Data("""
        { "coffeejson": "1.0",
          "beans": [ { "name": "House Blend",
            "origin": { "type": "blend", "items": [
              { "country": "BR", "percentage": 70, "altitude": { "value": 1100, "unit": "meter" } },
              { "country": "ET", "percentage": 30 }
            ] } } ] }
        """.utf8)
        let doc = try JSONDecoder().decode(Document.self, from: json)
        let origin = try #require(doc.beans?.first?.origin)
        #expect(origin.type == "blend")
        #expect(origin.items?.count == 2)
        #expect(origin.items?[0].altitude?.value == 1100)
        #expect(origin.items?[0].percentage == 70)
        #expect(origin.items?[1].country == "ET")
        #expect(origin.items?[1].percentage == 30)
    }
}
