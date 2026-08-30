import Testing
import Foundation
@testable import CoffeeJSON

/// The wire `{value, unit}` shape. Conversion and the closed unit sets are
/// ``UnitBridgeTests``' and ``VocabularyTests``' ground.
@Suite("CoffeeJSON Quantity")
struct QuantityTests {
    @Test("canonical gram identifier passes through unchanged")
    func gramCanonical() {
        #expect(Quantity(value: 250, unit: "gram").grams == 250)
    }

    @Test("decodes from the wire {value, unit} shape")
    func decodesFromWire() throws {
        let json = Data(#"{ "value": 15, "unit": "gram" }"#.utf8)
        let m = try JSONDecoder().decode(Quantity.self, from: json)
        #expect(m.value == 15)
        #expect(m.unit == "gram")
    }
}
