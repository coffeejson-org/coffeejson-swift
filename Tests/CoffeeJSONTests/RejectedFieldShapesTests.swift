import Testing
import Foundation
@testable import CoffeeJSON

/// The decoder reads the shapes the published schema defines, and only those.
///
/// This package is the format's Swift **reference implementation**, and it is
/// the first thing an implementer reads. A decoder more permissive than its own
/// specification teaches that specification wrong: the shape the schema rejects
/// goes on circulating because one reader keeps accepting it, and the next
/// implementer copies the reader, not the schema.
///
/// The cost is accepted: a document in a shape the schema rejects fails to
/// decode rather than degrading. No build can mint one, because a reader that
/// cannot import a shape cannot re-emit it either.
@Suite("Rejected field shapes")
struct RejectedFieldShapesTests {
    @Test("a bean's process written as a bare string does not decode")
    func beanProcessAsString() {
        #expect(throws: DecodingError.self) {
            try decodeWireDocument(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","process":"washed"}]}"#)
        }
    }

    @Test("an origin item's process written as a bare string does not decode")
    func originItemProcessAsString() {
        #expect(throws: DecodingError.self) {
            try decodeWireDocument(#"{"coffeejson":"1.0","beans":[{"name":"Blend","origin":{"items":[{"country":"ET","process":"natural"}]}}]}"#)
        }
    }

    // Through the codec the same failure arrives in this package's own
    // vocabulary rather than as a Foundation error — the contract every other
    // wrong-typed field already keeps.
    @Test("the codec names the field rather than leaking a DecodingError")
    func throughTheCodec() {
        #expect(throws: ImportError.validation(.wrongFieldType(field: "process"))) {
            try Codec.decodeDocument(Data(#"{"coffeejson":"1.0","beans":[{"name":"N","process":"washed"}]}"#.utf8))
        }
    }

    // A singular `producer` is an unknown key: ignored on decode like any
    // other, so the document still imports, and credits nobody, because the
    // schema's shape credited nobody. Silently dropping a name is the
    // forward-compatibility contract working as specified, not a fallback.
    @Test("a singular producer key is ignored, and the document still imports")
    func singularProducerIsUnknown() throws {
        let item = try #require(try decodeWireDocument(
            #"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","origin":{"items":[{"country":"ET","producer":"Ato Ayana"}]}}]}"#
        ).beans?.first?.origin?.items?.first)
        #expect(item.producers == nil)
        #expect(item.country == "ET")
    }

    @Test("the shapes the schema does define still decode")
    func currentShapes() throws {
        let bean = try #require(try decodeWireDocument(#"""
        {"coffeejson":"1.0","beans":[{"name":"Nano Challa","process":["anaerobic","honey"],
          "origin":{"items":[{"country":"ET","process":["natural"],
            "producers":[{"name":"Ato Ayana","role":"producer"}]}]}}]}
        """#).beans?.first)
        #expect(bean.process == ["anaerobic", "honey"])
        let item = try #require(bean.origin?.items?.first)
        #expect(item.process == ["natural"])
        #expect(item.producers?.map(\.name) == ["Ato Ayana"])
    }

    @Test("a process that is neither a string nor a list is still a decode failure")
    func processWrongTypeEntirely() {
        #expect(throws: DecodingError.self) {
            try decodeWireDocument(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","process":42}]}"#)
        }
    }
}
