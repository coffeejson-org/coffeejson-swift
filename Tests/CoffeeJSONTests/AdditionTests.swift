import Testing
import Foundation
@testable import CoffeeJSON

@Suite("Addition decode")
struct AdditionTests {
    private func decode(_ json: String) throws -> Addition {
        try JSONDecoder().decode(Addition.self, from: Data(json.utf8))
    }

    @Test("an ice addition decodes with its mass in grams")
    func ice() throws {
        let a = try decode(#"{ "type": "ice", "amount": { "value": 120, "unit": "gram" } }"#)
        #expect(a.type == "ice")
        #expect(a.isIce)
        #expect(a.amountGrams == 120)
    }

    @Test("an addition carries its optional temperature and note")
    func temperatureAndNote() throws {
        let a = try decode(#"""
        { "type": "milk", "amount": { "value": 50, "unit": "gram" },
          "temperature": { "value": 60, "unit": "celsius" }, "note": "oat, steamed" }
        """#)
        #expect(a.temperatureCelsius == 60)
        #expect(a.note == "oat, steamed")
        #expect(a.isIce == false)
    }

    @Test("an addition without a temperature or note omits both on re-emit")
    func omitsAbsentOptionals() throws {
        let a = try decode(#"{ "type": "ice", "amount": { "value": 120, "unit": "gram" } }"#)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(a)) as? [String: Any]
        #expect(json?.keys.sorted() == ["amount", "type"])
    }

    /// `type` is an **open registry**: any non-empty string, with `ice` · `milk`
    /// · `sugar` · `syrup` · `water` · `cream` recommended. A value outside that
    /// set has to survive a round trip — folding one into a catch-all rewrites
    /// another producer's document.
    @Test("a registry value outside the recommended set survives a round trip")
    func unrecognizedTypeRoundTripsVerbatim() throws {
        let a = try decode(#"{ "type": "milk", "amount": { "value": 50, "unit": "gram" } }"#)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(a)) as? [String: Any]
        #expect(json?["type"] as? String == "milk")
    }

    @Test("a recommended registry value decodes as itself, not a catch-all")
    func recommendedTypeDecodes() throws {
        let a = try decode(#"{ "type": "sugar", "amount": { "value": 5, "unit": "gram" } }"#)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(a)) as? [String: Any]
        #expect(json?["type"] as? String == "sugar")
    }

    @Test("an ounce amount converts to canonical grams")
    func ounceAmount() throws {
        let a = try decode(#"{ "type": "ice", "amount": { "value": 1, "unit": "ounce" } }"#)
        #expect(a.amountGrams.map { ($0 - 28.349).magnitude < 0.01 } == true)
    }
}
