import Testing
import Foundation
@testable import CoffeeJSON

// The suite's four ways into a document from a JSON literal. One definition
// each, so a change to the entry points is a change in one place.

func decodeDocument(_ json: String) throws -> ImportedDocument {
    try Codec.decodeDocument(Data(json.utf8))
}

func decodeRecipe(_ json: String) throws -> ImportedRecipe {
    try #require(try Codec.decodeDocument(Data(json.utf8)).recipes.first)
}

func decodeBean(_ json: String) throws -> ImportedBean {
    try #require(try Codec.decodeDocument(Data(json.utf8)).beans.first)
}

/// The wire DTO, undecoded by ``Codec`` — the structural layer alone.
func decodeWireDocument(_ json: String) throws -> Document {
    try JSONDecoder().decode(Document.self, from: Data(json.utf8))
}
