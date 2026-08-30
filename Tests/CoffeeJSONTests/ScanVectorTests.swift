import Testing
import Foundation
@testable import CoffeeJSON
import CoffeeJSONSchemaTesting

/// The format's shared scan-vector corpus, executed rather than paraphrased.
///
/// The corpus is what makes two conformant consumers agree on whether a given
/// link imports, so a reference implementation runs the same file every other
/// implementation runs — hand-rolled equivalents drift the moment a vector is
/// added. Each rejecting vector states a machine-readable `kind` from the
/// format's own error vocabulary, and that is what this suite keys on: a
/// vector's name is an identifier, while its `kind` is the claim. Absent a spec
/// checkout the suite skips, on ``SchemaSource``'s terms.
@Suite("Shared scan vectors")
struct ScanVectorTests {
    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let input: String
        let expect: String
        let kind: String?
        let document: Document?

        var testDescription: String { name }
    }

    private struct Corpus: Decodable {
        let vectors: [Vector]
    }

    static let vectors: [Vector] = {
        guard let url = SchemaSource.file(at: SchemaSource.scanVectorsPath),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONDecoder().decode(Corpus.self, from: data) else { return [] }
        return corpus.vectors
    }()

    @Test("the corpus is present and non-empty", .enabled(if: SchemaSource.isAvailable))
    func corpusLoads() {
        #expect(!Self.vectors.isEmpty)
    }

    @Test("every vector reaches the outcome it states",
          .enabled(if: !vectors.isEmpty), arguments: vectors)
    func vectorHoldsItsOutcome(_ vector: Vector) throws {
        switch vector.expect {
        case "document":
            let imported = try ShareLink.importDocument(fromScanned: vector.input)
            let stated = try #require(vector.document)
            #expect(imported.recipes.map(\.title) == (stated.recipes ?? []).map { $0.title ?? "" })
            #expect(imported.beans.map { $0.name ?? "" } == (stated.beans ?? []).map { $0.name ?? "" })
        case "reject":
            let kind = try #require(vector.kind, "\(vector.name) rejects under no stated kind")
            let thrown = #expect(throws: ImportError.self) {
                try ShareLink.importDocument(fromScanned: vector.input)
            }
            let error = try #require(thrown)
            #expect(error.kind?.rawValue == kind,
                    "\(vector.name) rejects as \(error), not \(kind)")
        default:
            // A new `expect` kind is a change to the corpus's contract, and
            // silently passing one would hide it.
            Issue.record("\(vector.name) states the unknown outcome \(vector.expect)")
        }
    }

    @Test("the vocabulary names every kind the corpus states, and reports the ones it does not",
          .enabled(if: !vectors.isEmpty))
    func vocabularyMatchesTheCorpus() {
        let vended = Set(ImportError.Kind.allCases.map(\.rawValue))
        let exercised = Set(Self.vectors.filter { $0.expect == "reject" }.compactMap(\.kind))
        #expect(exercised.subtracting(vended).isEmpty)
        // The other direction is not a failure: the corpus decides which kinds it
        // exercises, and a kind it drops must be visible rather than quietly
        // untested here.
        let untested = vended.subtracting(exercised).sorted()
        withKnownIssue("the corpus need not exercise every kind the vocabulary names",
                       isIntermittent: true) {
            #expect(untested.isEmpty, "no vector exercises \(untested.joined(separator: ", "))")
        }
    }

    @Test("the corpus carries both payload forms, so neither branch rots untested",
          .enabled(if: !vectors.isEmpty))
    func bothPayloadFormsAreExercised() {
        let firstBytes = Self.vectors.compactMap { vector -> UInt8? in
            guard let url = URL(string: vector.input) else { return nil }
            return ShareLink.payloadBytes(from: url)?.first
        }
        #expect(firstBytes.contains(0x7B))
        #expect(firstBytes.contains { $0 != 0x7B && $0 & 0x0F == 8 })
    }
}

/// The failure kind a consumer reads off an ``ImportError`` — the corpus's own
/// token, so a Swift consumer and any other implementation say the same word.
@Suite("Import error kinds")
struct ImportErrorKindTests {
    @Test("a transport or decode fault names its kind")
    func faultsNameTheirKind() {
        #expect(ImportError.decode(.notADocument).kind == .notADocument)
        #expect(ImportError.decode(.unsupportedVersion(documentMajor: 2, supportedMajor: 1)).kind
                    == .unsupportedVersion)
        // A kind names a case, never its payload.
        #expect(ImportError.transport(.notHTTP(scheme: "javascript")).kind == .notHTTP)
    }

    @Test("a fault the corpus does not name states no kind")
    func unnamedFaultsStateNoKind() {
        #expect(ImportError.validation(.missingRequiredField("title")).kind == nil)
        #expect(ImportError.transport(.invalidLink).kind == nil)
    }
}
