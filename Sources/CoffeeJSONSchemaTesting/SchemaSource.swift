import Foundation

/// Where a test target finds the published CoffeeJSON spec — its schema, and
/// the fixture corpora that ship beside it.
///
/// **The spec is deliberately not vendored** — not in this package, and not in
/// yours. A pinned copy is a second place for the format to drift, and a stale
/// one lets a conformance gate pass against a format that has moved on; that
/// failure is silent, which is the worst way for a gate to fail. So the files
/// are read from a checkout of the spec repo, and a test that cannot find one
/// **skips rather than fails**, so a single-repo clone still runs its suite.
///
/// Two places are looked at, in order:
///
/// 1. `COFFEEJSON_SPEC_DIR` — the spec checkout's root, from the environment.
///    This is the answer wherever the layout is not the default: CI, a build
///    server, a package resolved into `.build/checkouts`.
/// 2. A `coffeejson` checkout **beside this package's own**, the layout a
///    developer working on both already has.
///
/// A test target asserts on ``isAvailable`` through `.enabled(if:)` rather than
/// at runtime, so an absent checkout reports as a skip in the run output.
public enum SchemaSource {
    /// The schema file, or `nil` when neither location holds one.
    public static let url: URL? = file(at: schemaPath)

    /// Any file of the spec checkout, by its path within the repo, or `nil` when
    /// neither location holds one — a fixture corpus is found the same way the
    /// schema is, so a conformance test never hard-codes a second answer.
    public static func file(at path: String) -> URL? {
        let file = specDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The spec checkout's root, from the environment or from beside this
    /// package. Whether it holds anything is ``file(at:)``'s question.
    private static let specDirectory: URL = {
        let sibling = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CoffeeJSONSchemaTesting
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // <this package>
            .deletingLastPathComponent()   // beside it
            .appendingPathComponent("coffeejson")
        return ProcessInfo.processInfo.environment["COFFEEJSON_SPEC_DIR"]
            .map { URL(fileURLWithPath: $0) } ?? sibling
    }()

    /// The schema's path within a spec checkout.
    public static let schemaPath = "docs/schema/coffeejson-1.0.schema.json"

    /// The shared scan-vector corpus's path within a spec checkout.
    public static let scanVectorsPath = "fixtures/transport/scan-vectors.json"

    /// Whether a schema can be read — gate every test that needs one on this.
    public static var isAvailable: Bool { root != nil }

    /// The parsed schema, ready for ``SchemaValidator/init(schema:)``.
    public static var root: [String: Any]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
