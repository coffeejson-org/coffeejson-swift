import Testing
import Foundation
@testable import CoffeeJSON

/// `.notADocument` means one thing: the envelope could not be read. A modeled
/// field carrying the wrong type is a fault *in* a document, and reports as
/// ``ImportError/wrongFieldType(field:)`` naming that field.
///
/// The second half of this suite is the load-bearing half. Narrowing an error
/// is only safe if the inputs that genuinely deserve it still get it, so the
/// genuine not-a-document inputs are pinned here rather than left to inference.
@Suite("Wrong field type")
struct WrongFieldTypeTests {
    @Test("a bean's roaster written as a bare string names roaster, not the format")
    func bareStringRoasterNamesTheField() {
        #expect(throws: ImportError.validation(.wrongFieldType(field: "roaster"))) {
            try decodeDocument(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roaster":"Example Roastery"}]}"#)
        }
    }

    @Test("a wrong type deep in a collection names the field, not its index")
    func deepWrongTypeNamesTheLeafField() {
        #expect(throws: ImportError.validation(.wrongFieldType(field: "roast_agtron"))) {
            try decodeDocument(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roast_agtron":"sixty-five"}]}"#)
        }
    }

    private static let validRecipe = #"""
        {"title":"V60","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}
        """#

    @Test("an envelope collection written as a scalar names that collection")
    func wrongTypeOnAnEnvelopeCollection() {
        #expect(throws: ImportError.validation(.wrongFieldType(field: "recipes"))) {
            try decodeDocument(#"{"coffeejson":"1.0","recipes":"nope"}"#)
        }
    }

    // Envelope § Fields: a slot claiming an entity and holding a number is
    // malformed, and an importer rejects the document rather than skipping it.
    // All three collections, because the rule is the envelope's and not one
    // collection's.
    @Test("a collection element that is not an object names the collection",
          arguments: [
            ("recipes", #"{"coffeejson":"1.0","recipes":[17,\#(validRecipe)]}"#),
            ("beans", #"{"coffeejson":"1.0","beans":[17,{"name":"Nano Challa"}]}"#),
            ("tastings", #"{"coffeejson":"1.0","recipes":[\#(validRecipe)],"tastings":[17]}"#),
          ])
    func nonObjectCollectionElementNamesTheCollection(_ collection: String, _ json: String) {
        #expect(throws: ImportError.validation(.wrongFieldType(field: collection))) {
            try decodeDocument(json)
        }
    }

    @Test("the field named is the wire key, so it matches what the document actually says")
    func fieldIsNamedByItsWireKey() {
        #expect(throws: ImportError.validation(.wrongFieldType(field: "water_temp"))) {
            try decodeDocument(#"""
            {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
              "water":{"value":250,"unit":"gram"},"water_temp":"hot"}]}
            """#)
        }
    }

    @Test("JSON with no envelope member is still not a document")
    func noEnvelopeMemberIsStillNotADocument() {
        #expect(throws: ImportError.decode(.notADocument)) {
            try decodeDocument(#"{"beans":[{"name":"Nano Challa"}]}"#)
        }
    }

    // A string is the member's declared type, so the envelope is this format's
    // and the fault is the version it states — not the identity of the document.
    @Test("an envelope member that states no version is unsupported, not undocumented")
    func unparseableVersionIsUnsupported() {
        #expect(throws: ImportError.decode(.unsupportedVersion(documentMajor: nil, supportedMajor: 1))) {
            try decodeDocument(#"{"coffeejson":"banana","beans":[{"name":"Nano Challa"}]}"#)
        }
    }

    @Test("an envelope member that is not a string is still not a document, not a named field")
    func nonStringEnvelopeMemberIsStillNotADocument() {
        // The envelope member is the format's identity rather than a field a
        // document merely got wrong, so it keeps the format-level verdict — the
        // same reading the spec's own reference reader takes.
        #expect(throws: ImportError.decode(.notADocument)) {
            try decodeDocument(#"{"coffeejson":1.0,"beans":[{"name":"Nano Challa"}]}"#)
        }
    }

    @Test("JSON that is not an object at all is still not a document")
    func nonObjectRootIsStillNotADocument() {
        #expect(throws: ImportError.decode(.notADocument)) {
            try decodeDocument("[1,2,3]")
        }
    }

    @Test("a missing required field still reports that field, not a wrong type")
    func missingRequiredFieldIsUnchanged() {
        #expect(throws: ImportError.validation(.missingRequiredField("title"))) {
            try decodeDocument(#"{"coffeejson":"1.0","recipes":[{"coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}]}"#)
        }
    }

    @Test("text that is not JSON at all still reports notJSON")
    func notJSONIsUnchanged() {
        #expect(throws: ImportError.decode(.notJSON)) {
            try decodeDocument("not json at all")
        }
    }
}
