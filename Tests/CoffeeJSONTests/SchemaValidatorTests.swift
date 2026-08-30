import Testing
import Foundation
@testable import CoffeeJSON
import CoffeeJSONSchemaTesting

/// Proves the vended ``SchemaValidator`` reproduces the published schema's
/// verdicts.
///
/// Without this the conformance gate would pass vacuously: a validator that
/// accepted everything would satisfy every test written against it.
/// `CoffeeJSONSchemaTesting` is vended for other producers to gate themselves
/// with, so this is the test that says it is worth having. Each case
/// below mirrors a fixture in the format's own corpus, where the canonical
/// harness has already decided the verdict — so agreement here is agreement with
/// a second implementation, not with this package's opinion of itself.
@Suite("JSON Schema validator — canonical agreement")
struct SchemaValidatorTests {
    private func validator() throws -> SchemaValidator {
        SchemaValidator(schema: try #require(SchemaSource.root))
    }

    private func object(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    /// Documents the schema MUST reject — the constraints that keep a minted
    /// document honest: required masses and units, the envelope, the ranges.
    static let rejected: [(String, String)] = [
        ("no collections", #"{"coffeejson":"1.0"}"#),
        ("empty recipes collection", #"{"coffeejson":"1.0","recipes":[]}"#),
        ("recipe missing water (non-espresso)", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"}}]}"#),
        ("recipe missing title", #"{"coffeejson":"1.0","recipes":[{"coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#),
        ("measurement missing unit", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15},"water":{"value":250,"unit":"gram"}}]}"#),
        ("ratio at or below zero", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"ratio":0}]}"#),
        ("non-canonical mass unit", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"ml"},"water":{"value":250,"unit":"gram"}}]}"#),
        ("espresso carrying water", #"{"coffeejson":"1.0","recipes":[{"title":"x","method":"espresso","basis":"yield","coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"},"water":{"value":30,"unit":"gram"}}]}"#),
        ("espresso missing yield", #"{"coffeejson":"1.0","recipes":[{"title":"x","method":"espresso","basis":"yield","coffee":{"value":18,"unit":"gram"}}]}"#),
        ("bad country code", #"{"coffeejson":"1.0","beans":[{"name":"x","origin":{"items":[{"country":"USA"}]}}]}"#),
        ("negative step time", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"steps":[{"at_s":-1}]}]}"#),
        ("version outside major 1", #"{"coffeejson":"2.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#),
        ("bare-string roaster, the pre-party shape", #"{"coffeejson":"1.0","beans":[{"name":"x","roaster":"Some Roastery"}]}"#),
        // Why the validator implements `dependentSchemas`: an unimplemented
        // keyword is silently ignored, so without it this document validates here
        // while the canonical harness rejects it — the gate passing on a document
        // the published schema refuses.
        ("point and window at once", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"min":14,"max":16,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#),
        // The three keywords `localizations` introduced. Before they were
        // implemented all three validated here and were rejected upstream — the
        // same silent-gate failure as above.
        ("localizations with no lang to override",
         #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"localizations":{"en":{"title":"X"}}}]}"#),
        ("a locale key that is not a BCP-47 tag",
         #"{"coffeejson":"1.0","recipes":[{"title":"x","lang":"ja","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"localizations":{"english":{"title":"X"}}}]}"#),
        ("a localization value that is not an object",
         #"{"coffeejson":"1.0","recipes":[{"title":"x","lang":"ja","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"localizations":{"en":"X"}}]}"#),
        // `rating` is the schema's one `integer`: a fractional value is rejected,
        // never widened to a number.
        ("a fractional rating, where the scale is integer",
         #"{"coffeejson":"1.0","recipes":[{"id":"r","title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}],"tastings":[{"recipe_ref":"r","rating":3.5}]}"#),
    ]

    /// Documents the schema MUST accept — so the validator is not merely strict.
    /// Every rejection above needs its counterpart here, or it is satisfiable by
    /// a validator that refuses the whole construct outright.
    static let accepted: [(String, String)] = [
        ("rich pour-over", #"{"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"ratio":16.7,"water_temp":{"value":93,"unit":"celsius"},"grind":{"setting":"22 clicks"},"steps":[{"at_s":0,"to_water":{"value":45,"unit":"gram"}}],"finish_s":210}]}"#),
        ("valid espresso dose:yield", #"{"coffeejson":"1.0","recipes":[{"title":"Shot","method":"espresso","basis":"yield","coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"}}]}"#),
        ("a bilingual recipe, stated correctly",
         #"{"coffeejson":"1.0","recipes":[{"title":"4:6メソッド","lang":"ja","coffee":{"value":20,"unit":"gram"},"water":{"value":300,"unit":"gram"},"localizations":{"en":{"title":"4:6 Method","steps":[{"instruction":"first pour"}]}}}]}"#),
        ("bag-to-brew bean and recipe", #"{"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}],"beans":[{"name":"Guji","roaster":{"name":"R"},"process":["washed"],"roast_agtron":62,"roast_date":"2023-11-14","origin":{"items":[{"country":"ET"}]}}]}"#),
        // The other side of the point-and-window rule: a window with no point is
        // the shape the format added, so `dependentSchemas` must not reject it.
        ("windowed dose, no point", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"min":14,"max":16,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#),
        // An unknown key rides through: the format's forward-compatibility
        // contract, asserted from the validating side.
        ("an unmodelled key is tolerated", #"{"coffeejson":"1.0","recipes":[{"title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"x_future":{"cup_score":88}}]}"#),
        // The other side of the integer rule: a whole number written with a
        // fractional part is an integer, and the harness accepts it.
        ("a whole rating written as 4.0",
         #"{"coffeejson":"1.0","recipes":[{"id":"r","title":"x","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}],"tastings":[{"recipe_ref":"r","rating":4.0}]}"#),
    ]

    @Test("the schema rejects every non-conforming document",
          .enabled(if: SchemaSource.isAvailable), arguments: rejected)
    func rejectsInvalid(_ testCase: (label: String, json: String)) throws {
        let errors = try validator().validate(try object(testCase.json))
        #expect(!errors.isEmpty, "\(testCase.label): expected rejection but validated")
    }

    @Test("a keyword the validator does not implement is an error, not a shrug")
    func unimplementedKeywordIsLoud() throws {
        // The whole point of the subset being safe: a rule this validator cannot
        // enforce must not read as a document that satisfies it.
        let validator = SchemaValidator(schema: [
            "type": "object",
            "properties": ["a": ["type": "string", "unevaluatedProperties": false]],
        ])
        let errors = validator.validate(try object(#"{"a":"x"}"#))
        #expect(errors.contains { $0.contains("unevaluatedProperties") })
    }

    @Test("a list-valued type is enforced, not skipped")
    func listValuedTypeIsEnforced() {
        // The same failure as an unimplemented keyword, one level down: reading
        // `type` only as a string drops the rule when a schema states a list.
        let validator = SchemaValidator(schema: ["type": ["string", "number"]])
        #expect(validator.validate("x").isEmpty)
        #expect(validator.validate(7).isEmpty)
        #expect(!validator.validate([1, 2]).isEmpty)
    }

    @Test("the schema accepts every conforming document",
          .enabled(if: SchemaSource.isAvailable), arguments: accepted)
    func acceptsValid(_ testCase: (label: String, json: String)) throws {
        let errors = try validator().validate(try object(testCase.json))
        #expect(errors.isEmpty, "\(testCase.label): expected valid but got \(errors)")
    }
}
