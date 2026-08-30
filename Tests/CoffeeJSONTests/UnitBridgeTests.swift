import Testing
import Foundation
@testable import CoffeeJSON

/// The format's unit tokens against Foundation's units.
///
/// The mapping is vended because every consumer rendering a quantity in a
/// reader's own units needs it, and a hand-rolled copy is a place for `ounce` to
/// become `UnitMass.pounds` in one app and nowhere else. These check each token
/// lands on the unit it names — and that this package's own canonical
/// conversions come out of the same mapping.
@Suite("Foundation unit bridge")
struct UnitBridgeTests {
    @Test("every mass token names its Foundation unit")
    func massTokens() {
        #expect(KnownMassUnit.gram.foundationUnit == .grams)
        #expect(KnownMassUnit.ounce.foundationUnit == .ounces)
    }

    @Test("every temperature token names its Foundation unit")
    func temperatureTokens() {
        #expect(KnownTemperatureUnit.celsius.foundationUnit == .celsius)
        #expect(KnownTemperatureUnit.fahrenheit.foundationUnit == .fahrenheit)
    }

    @Test("every pressure token names its Foundation unit")
    func pressureTokens() {
        #expect(KnownPressureUnit.bar.foundationUnit == .bars)
    }

    @Test("every altitude token names its Foundation unit")
    func altitudeTokens() {
        #expect(KnownAltitudeUnit.meter.foundationUnit == .meters)
        #expect(KnownAltitudeUnit.foot.foundationUnit == .feet)
    }

    @Test("a water token names its unit and its dimension, which are two answers")
    func waterTokensCarryTheirDimension() {
        // The dimension is part of the answer because the format defines no
        // conversion between the two: a caller has to see which it holds.
        #expect(KnownWaterUnit.gram.foundationUnit == .mass(.grams))
        #expect(KnownWaterUnit.ounce.foundationUnit == .mass(.ounces))
        #expect(KnownWaterUnit.milliliter.foundationUnit == .volume(.milliliters))
    }

    @Test("a non-canonical unit converts through the bridge")
    func conversionsReadThroughTheBridge() throws {
        let ounces = try #require(Quantity(value: 1, unit: "ounce").grams)
        #expect(abs(ounces - Measurement(value: 1, unit: UnitMass.ounces)
            .converted(to: .grams).value) < 1e-9)
        let boiling = try #require(Quantity(value: 212, unit: "fahrenheit").celsius)
        #expect(abs(boiling - 100) < 1e-9)
    }

    @Test("a canonical unit comes back exactly as the author stated it")
    func canonicalUnitsAreUntouched() {
        // Not a rounding quibble: a round trip through the dimension's base unit
        // can hand back a figure the author did not write.
        #expect(Quantity(value: 18, unit: "gram").grams == 18)
        #expect(Quantity(value: 93.5, unit: "celsius").celsius == 93.5)
        #expect(Quantity(value: 9, unit: "bar").bar == 9)
        #expect(Quantity(value: 250, unit: "milliliter").milliliters == 250)
    }

    @Test("a quantity reads in its own dimension and no other")
    func dimensionsDoNotCross() {
        // Foundation would happily convert milliliters to grams through base
        // units and return a number. The format defines no such conversion, so
        // neither does this.
        #expect(Quantity(value: 250, unit: "milliliter").grams == nil)
        #expect(Quantity(value: 250, unit: "gram").milliliters == nil)
        #expect(Quantity(value: 250, unit: "gram").celsius == nil)
        #expect(Quantity(value: 94, unit: "celsius").grams == nil)
    }

    @Test("a unit outside the set converts to nothing at all")
    func unknownUnitsConvertToNothing() {
        #expect(Quantity(value: 250, unit: "liter").milliliters == nil)
        #expect(Quantity(value: 18, unit: "g").grams == nil)
        #expect(Quantity(value: 9, unit: "psi").bar == nil)
    }
}
