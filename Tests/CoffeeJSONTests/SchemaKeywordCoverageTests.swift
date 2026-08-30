import Testing
import Foundation
import CoffeeJSONSchemaTesting

/// The gate's blind spot, made loud.
///
/// ``SchemaValidator`` implements a *subset* of JSON Schema. It reports a
/// keyword it does not implement wherever a document reaches one, but a document
/// only reaches the branches it exercises: a rule stated in a branch nothing
/// tests would go unenforced with nothing anywhere red.
///
/// So this walks the whole schema. It is the check `CoffeeJSONSchemaTesting`
/// asks every consumer's test target to run, run here first.
@Suite("Schema keyword coverage")
struct SchemaKeywordCoverageTests {
    @Test("the published schema uses no keyword the validator does not implement",
          .enabled(if: SchemaSource.isAvailable))
    func everyKeywordIsUnderstood() throws {
        let schema = try #require(SchemaSource.root)
        let unknown = SchemaValidator.unimplementedKeywords(in: schema)
        #expect(
            unknown.isEmpty,
            """
            The schema uses \(unknown.joined(separator: ", ")), which \
            SchemaValidator does not implement — so the conformance gate is not \
            enforcing it. Implement the keyword, or add it to \
            understoodKeywords once you have satisfied yourself it asserts \
            nothing.
            """,
        )
    }

    @Test("the walk reads keywords in schema position and field names as data")
    func walkDistinguishesPositions() {
        // `type` appears twice here: once as a keyword, once as the name of a
        // field the format defines. A walk that cannot tell them apart reports
        // no unknowns for the wrong reason, and this suite would pass forever.
        #expect(SchemaValidator.unimplementedKeywords(in: [
            "type": "object",
            "properties": ["type": ["pattern": "^x$"]],
        ]).isEmpty)
    }

    @Test("an unimplemented keyword in schema position is caught")
    func unknownKeywordIsCaught() {
        #expect(SchemaValidator.unimplementedKeywords(
            in: ["properties": ["a": ["unevaluatedProperties": false]]]) == ["unevaluatedProperties"])
    }
}
