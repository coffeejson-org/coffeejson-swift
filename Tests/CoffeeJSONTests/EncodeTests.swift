import Testing
import Foundation
@testable import CoffeeJSON

/// The produce (encode) half of the pure codec: building a wire document,
/// serializing it with canonical unit ids, and packing it into a share link.
/// The decode half is exercised by `CodecTests`; here we lean on it
/// only to prove a round-trip.
@Suite("CoffeeJSON encode")
struct EncodeTests {
    private func document(
        title: String = "Café V60",
        coffee: Double = 15,
        water: Double = 250,
        temp: Double? = 92,
        steps: [Step]? = [
            Step(atSeconds: 0, toWater: .grams(45)),
            Step(atSeconds: 40, toWater: .grams(250)),
        ],
        finish: Double? = 150
    ) -> Document {
        Document(
            version: Codec.currentVersion,
            recipes: [Recipe(
                title: title,
                coffee: .grams(coffee),
                water: .grams(water),
                ratio: water / coffee,
                waterTemp: temp.map(Quantity.celsius),
                steps: steps,
                finishSeconds: finish)],
            generator: Generator(name: "ExampleApp", version: "1.2"))
    }

    @Test("encode → decode preserves every modeled field")
    func roundTrip() throws {
        let data = try Codec.encode(document())
        let imported = try #require(try Codec.decodeDocument(data).recipes.first)

        #expect(imported.title == "Café V60")
        #expect(imported.coffeeGrams == 15)
        #expect(imported.waterGrams == 250)
        #expect(abs(try #require(imported.ratio) - 250.0 / 15.0) < 0.0001)
        #expect(imported.waterTemperatureCelsius == 92)
        #expect(imported.pourSteps.count == 2)
        #expect(imported.pourSteps.last?.cumulativeWaterGrams == 250)
        #expect(imported.finishSeconds == 150)
    }

    @Test("the generator round-trips on the document, not on a recipe")
    func generatorRoundTrip() throws {
        let data = try Codec.encode(document())
        let json = String(decoding: data, as: UTF8.self)
        // On the envelope, so it is a sibling of `recipes`, and stated once.
        #expect(json.contains(#""generator":{"#))
        #expect(json.components(separatedBy: #""name":"ExampleApp""#).count == 2)

        let imported = try Codec.decodeDocument(data)
        #expect(imported.generator?.name == "ExampleApp")
        #expect(imported.generator?.version == "1.2")
    }

    @Test("the wire carries canonical unit ids — gram/celsius, never symbols")
    func canonicalUnitIdentifiers() throws {
        let json = String(decoding: try Codec.encode(document()), as: UTF8.self)
        #expect(json.contains(#""unit":"gram""#))
        #expect(json.contains(#""unit":"celsius""#))
        #expect(!json.contains(#""unit":"g""#))
        #expect(!json.contains("°C"))
    }

    @Test("nil fields are omitted, not emitted as null")
    func omitsNils() throws {
        let minimal = Document(
            version: Codec.currentVersion,
            recipes: [Recipe(title: "x", coffee: .grams(15), water: .grams(250))])
        let json = String(decoding: try Codec.encode(minimal), as: UTF8.self)
        #expect(!json.contains("water_temp"))
        #expect(!json.contains("grind"))
        #expect(!json.contains("steps"))
        #expect(!json.contains("method"))
        #expect(!json.contains("null"))
    }

    @Test("the version is stamped under the `coffeejson` envelope key")
    func stampsVersionKey() throws {
        let json = String(decoding: try Codec.encode(document()), as: UTF8.self)
        #expect(json.contains(#""coffeejson":"1.0""#))
    }

    /// A quantity carrying a value JSON cannot write. Reachable from public API:
    /// `Quantity.value` is a plain `Double` with no validation, by design.
    private var nonFiniteDocument: Document {
        Document(
            version: Codec.currentVersion,
            recipes: [Recipe(
                title: "Impossible",
                coffee: Quantity(value: .infinity, unit: "gram"),
                water: .grams(250))])
    }

    @Test("a value JSON cannot write is reported in this package's vocabulary, not Foundation's")
    func nonFiniteValueIsAnImportError() {
        // `JSONEncoder` throws `EncodingError.invalidValue` for a non-finite
        // Double. A caller matching on `ImportError` could not see it.
        #expect(throws: ImportError.validation(.nonRepresentableValue(field: "value"))) {
            try Codec.encode(nonFiniteDocument)
        }
    }

    @Test("shareURL propagates that as an ImportError too — the transport leaks nothing either")
    func shareURLDoesNotLeakEncodingError() {
        #expect(throws: ImportError.validation(.nonRepresentableValue(field: "value"))) {
            try ShareLink.shareURL(for: nonFiniteDocument, host: "example.com")
        }
    }

    @Test("a non-ASCII (ja / pt-BR) title survives encode → decode intact")
    func nonASCIITitleSurvives() throws {
        for title in ["浅煎りエチオピア", "Café da manhã ☕️"] {
            let data = try Codec.encode(document(title: title))
            #expect(try #require(try Codec.decodeDocument(data).recipes.first).title == title)
        }
    }
}

@Suite("ShareLink build")
struct ShareLinkBuildTests {
    private let document = Document(
        version: Codec.currentVersion,
        recipes: [Recipe(
            title: "Rich", coffee: .grams(18), water: .grams(300),
            waterTemp: .celsius(92),
            steps: [Step(atSeconds: 0, toWater: .grams(50)),
                    Step(atSeconds: 45, toWater: .grams(300))],
            finishSeconds: 140)])

    @Test("builds an https /r?d= link with a padding-free base64url payload")
    func httpsQueryLink() throws {
        let url = try ShareLink.shareURL(for: document, host: "example.com")
        // The payload rides in the `d` query item — messaging linkifiers drop a
        // trailing #fragment but keep the query (LINE/Messages/Slack/WhatsApp).
        #expect(url.absoluteString.hasPrefix("https://example.com/r?d="))

        let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "d" }?.value
        #expect(d?.isEmpty == false)
        // base64url, unpadded: none of `+`, `/`, `=`.
        #expect(d?.contains("+") == false)
        #expect(d?.contains("/") == false)
        #expect(d?.contains("=") == false)
    }

    @Test("a built link round-trips back through the parser")
    func roundTrip() throws {
        let url = try ShareLink.shareURL(for: document, host: "example.com")
        let back = try #require(try ShareLink.importDocument(from: url).recipes.first)
        #expect(back.title == "Rich")
        #expect(back.coffeeGrams == 18)
        #expect(back.waterTemperatureCelsius == 92)
        #expect(back.pourSteps.count == 2)
        #expect(back.finishSeconds == 140)
    }

    @Test("builds a custom-scheme link (myapp://import?d=…) that round-trips")
    func customSchemeLink() throws {
        let url = try ShareLink.shareURL(
            for: document, scheme: "myapp", host: "import", path: "")
        #expect(url.absoluteString.hasPrefix("myapp://import?d="))
        // Same `d` query payload, so the parser round-trips it like the https form.
        #expect(try #require(try ShareLink.importDocument(from: url).recipes.first).title == "Rich")
    }

    @Test("an oversized payload is rejected before a URL is built")
    func rejectsOversized() {
        let huge = Document(
            version: Codec.currentVersion,
            recipes: [Recipe(
                title: String(repeating: "x", count: 10_000),
                coffee: .grams(15), water: .grams(250))])
        #expect(throws: ImportError.transport(.tooLarge)) {
            try ShareLink.shareURL(for: huge, host: "example.com")
        }
    }
}
