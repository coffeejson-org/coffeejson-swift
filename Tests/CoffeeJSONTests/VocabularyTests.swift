import Foundation
import Testing
@testable import CoffeeJSON
import CoffeeJSONSchemaTesting

extension SchemaSource {
    /// The `enum` member at a key path, or `nil` when the path names no closed
    /// set — which is itself worth asserting, since a `Known*` view over an
    /// open-ended field would assert a set the format does not define.
    static func enumTokens(_ path: [String]) -> [String]? {
        var node: Any? = root
        for key in path {
            node = (node as? [String: Any])?[key]
        }
        return (node as? [String: Any])?["enum"] as? [String]
    }

    /// The `default` member at a key path, or `nil` when the schema declares
    /// none there.
    static func defaultToken(_ path: [String]) -> String? {
        var node: Any? = root
        for key in path {
            node = (node as? [String: Any])?[key]
        }
        return (node as? [String: Any])?["default"] as? String
    }

    /// Every path in the schema that declares a `default` — found rather than
    /// listed, for the reason ``enumPaths()`` gives.
    static func defaultPaths() -> [[String]] {
        var found: [[String]] = []
        func walk(_ node: Any, _ path: [String]) {
            guard let object = node as? [String: Any] else { return }
            if object["default"] is String { found.append(path) }
            for (key, child) in object {
                walk(child, path + [key])
            }
        }
        walk(root ?? [:], [])
        return found
    }

    /// Every path in the schema that carries an `enum` — the format's closed
    /// sets, found rather than listed, so one added upstream shows up here
    /// instead of waiting for someone to remember it.
    static func enumPaths() -> [[String]] {
        var found: [[String]] = []
        func walk(_ node: Any, _ path: [String]) {
            guard let object = node as? [String: Any] else { return }
            if object["enum"] is [String] { found.append(path) }
            for (key, child) in object {
                walk(child, path + [key])
            }
        }
        walk(root ?? [:], [])
        return found
    }

    /// The bare-token array a registry file lists under its one data key, or
    /// `nil` when the checkout has no such file or the file names entries
    /// (`gear.json`, `varietals.json`, `implementations.json`) rather than
    /// bare tokens — a registry of entries carries no `Known*` view and is
    /// outside this gate.
    static func registryTokens(at path: String) -> [String]? {
        guard let file = file(at: path),
              let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root.values.compactMap { $0 as? [String] }.first
    }

    /// Every `.json` file directly under the spec checkout's `registries/`,
    /// by its path within the checkout — found rather than listed, so a
    /// registry added upstream shows up here too.
    static func registryPaths() -> [String]? {
        guard let directory = file(at: "registries") else { return nil }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .map { "registries/\($0.lastPathComponent)" }
    }
}

/// Every default the schema declares, paired with the constant that vends it.
/// A default the format states is the format's answer, so a reader applying its
/// own would be reading a different recipe than the one that was published.
private let vendedDefaults: [(path: [String], token: String)] = [
    (["$defs", "step", "properties", "kind"], KnownStepKind.whenUnstated.rawValue),
    (["$defs", "recipe", "properties", "basis"], QuantityBasis.whenUnstated.rawValue),
]

/// Every closed set the schema declares, paired with the type that vends it.
/// The pairing is the gate: a set with no type fails ``everyClosedSetIsVended``,
/// and a type whose members drift from the schema fails ``vendedSetsMatchTheSchema``.
private let vendedVocabularies: [(path: [String], tokens: [String])] = [
    (["$defs", "method"], KnownBrewMethod.allCases.map(\.rawValue)),
    (["$defs", "step", "properties", "kind"], KnownStepKind.allCases.map(\.rawValue)),
    (["$defs", "grind", "properties", "size"], KnownGrindSize.allCases.map(\.rawValue)),
    (["$defs", "filter", "properties", "material"], KnownFilterMaterial.allCases.map(\.rawValue)),
    (["$defs", "process"], KnownProcess.allCases.map(\.rawValue)),
    (["$defs", "bean", "properties", "roast_level"], KnownRoastLevel.allCases.map(\.rawValue)),
    (["$defs", "bean", "properties", "form"], KnownBeanForm.allCases.map(\.rawValue)),
    (["$defs", "bean", "properties", "preferred_extraction"], KnownPreferredExtraction.allCases.map(\.rawValue)),
    (["$defs", "origin", "properties", "type"], KnownOriginType.allCases.map(\.rawValue)),
    (["$defs", "party", "properties", "type"], KnownPartyType.allCases.map(\.rawValue)),
    (["$defs", "recipe", "properties", "basis"], QuantityBasis.allCases.map(\.rawValue)),
    (["$defs", "massMeasurement", "properties", "unit"], KnownMassUnit.allCases.map(\.rawValue)),
    (["$defs", "waterMeasurement", "properties", "unit"], KnownWaterUnit.allCases.map(\.rawValue)),
    (["$defs", "tempMeasurement", "properties", "unit"], KnownTemperatureUnit.allCases.map(\.rawValue)),
    (["$defs", "pressureMeasurement", "properties", "unit"], KnownPressureUnit.allCases.map(\.rawValue)),
    (["$defs", "altitude", "properties", "unit"], KnownAltitudeUnit.allCases.map(\.rawValue)),
]

/// The two open registries the spec ships as a flat, recommended-token list,
/// paired with the view that reads it. Unlike ``vendedVocabularies``, the
/// wire value is never checked against this set — the registry is a
/// recommendation, not a gate — but the set of tokens the view names and the
/// set the registry lists must still agree, and ``everyTokenRegistryIsVended``
/// below is what a third such registry would fail.
private let vendedRegistries: [(path: String, tokens: [String])] = [
    ("registries/addition-types.json", KnownAdditionType.allCases.map(\.rawValue)),
    ("registries/producer-roles.json", KnownProducerRole.allCases.map(\.rawValue)),
]

@Suite("Closed vocabularies")
struct VocabularyTests {
    @Test("every typed view reads a token outside its set as nil, and folds nothing")
    func unknownTokensReadAsNil() {
        #expect(KnownBrewMethod(rawValue: "percolator") == nil)
        #expect(KnownStepKind(rawValue: "swirl") == nil)
        #expect(KnownGrindSize(rawValue: "turkish") == nil)
        #expect(KnownFilterMaterial(rawValue: "nylon") == nil)
        #expect(KnownProcess(rawValue: "koji_natural") == nil)
        #expect(KnownAdditionType(rawValue: "kombucha") == nil)
        #expect(KnownProducerRole(rawValue: "importer") == nil)
        #expect(KnownRoastLevel(rawValue: "medium_light") == nil)   // the transposition
        #expect(KnownBeanForm(rawValue: "sachet") == nil)
        #expect(KnownPreferredExtraction(rawValue: "moka") == nil)
        #expect(KnownOriginType(rawValue: "microlot") == nil)
        #expect(KnownPartyType(rawValue: "cooperative") == nil)
        #expect(QuantityBasis(rawValue: "strength") == nil)
    }

    @Test("a unit outside its measurement's set reads as nil, display symbols included")
    func unknownUnitsReadAsNil() {
        #expect(KnownMassUnit(rawValue: "g") == nil)
        #expect(KnownTemperatureUnit(rawValue: "°C") == nil)
        #expect(KnownWaterUnit(rawValue: "liter") == nil)
        #expect(KnownPressureUnit(rawValue: "psi") == nil)
        #expect(KnownAltitudeUnit(rawValue: "masl") == nil)
        // A view is per measurement kind, because which units a field admits is
        // part of what the field means: only water may be stated by volume.
        #expect(KnownMassUnit(rawValue: "milliliter") == nil)
        #expect(KnownWaterUnit(rawValue: "milliliter") == .milliliter)
    }

    @Test("an unrecognized unit is treated as absent, and the quantity converts nothing")
    func unknownUnitConvertsNothing() {
        #expect(Quantity(value: 18, unit: "g").grams == nil)
        #expect(Quantity(value: 93, unit: "°C").celsius == nil)
        #expect(Quantity(value: 18, unit: "gram").grams == 18)
    }

    @Test("`other` is a token a producer writes, and reads back as itself")
    func otherIsAToken() {
        #expect(KnownBrewMethod(rawValue: "other") == .other)
        #expect(KnownStepKind(rawValue: "other") == .other)
        #expect(KnownFilterMaterial(rawValue: "other") == .other)
        #expect(KnownProcess(rawValue: "other") == .other)
        #expect(KnownBeanForm(rawValue: "other") == .other)
    }

    @Test("a field reads through its view in one step, and an absent field states nothing")
    func fieldsReadThroughTheirView() {
        #expect(Recipe(method: "pour_over").method.flatMap(KnownBrewMethod.init(rawValue:)) == .pourOver)
        #expect(Bean(roastLevel: "light_medium").roastLevel.flatMap(KnownRoastLevel.init(rawValue:)) == .lightMedium)
        #expect(Bean(form: "drip_bag").form.flatMap(KnownBeanForm.init(rawValue:)) == .dripBag)
        #expect(Grind(size: "medium_coarse").size.flatMap(KnownGrindSize.init(rawValue:)) == .mediumCoarse)
        #expect(Recipe().method.flatMap(KnownBrewMethod.init(rawValue:)) == nil)
        #expect(Grind(setting: "22 clicks").size.flatMap(KnownGrindSize.init(rawValue:)) == nil)
    }

    @Test("an unrecognized token stays on the wire, whatever the view says")
    func theWireKeepsTheProducersWord() {
        #expect(Recipe(method: "percolator").method == "percolator")
        #expect(Step(kind: "swirl").kind == "swirl")
        #expect(Bean(process: ["koji_natural"]).process == ["koji_natural"])
    }

    @Test("every vended set holds exactly the tokens the schema declares", .enabled(if: SchemaSource.isAvailable))
    func vendedSetsMatchTheSchema() throws {
        for (path, tokens) in vendedVocabularies {
            let name = path.joined(separator: "/")
            let schema = try #require(SchemaSource.enumTokens(path), "\(name) declares no closed set")
            #expect(Set(tokens) == Set(schema), "\(name)")
            #expect(tokens.count == schema.count, "\(name)")
        }
    }

    @Test("the schema declares no closed set this package leaves unvended", .enabled(if: SchemaSource.isAvailable))
    func everyClosedSetIsVended() {
        let declared = Set(SchemaSource.enumPaths().map { $0.joined(separator: "/") })
        let vended = Set(vendedVocabularies.map { $0.path.joined(separator: "/") })
        #expect(declared == vended)
    }

    @Test("every default the schema declares is vended, and is the schema's value", .enabled(if: SchemaSource.isAvailable))
    func vendedDefaultsMatchTheSchema() throws {
        for (path, token) in vendedDefaults {
            let name = path.joined(separator: "/")
            let schema = try #require(SchemaSource.defaultToken(path), "\(name) declares no default")
            #expect(token == schema, "\(name)")
        }
    }

    @Test("the schema declares no default this package leaves unvended", .enabled(if: SchemaSource.isAvailable))
    func everyDefaultIsVended() {
        let declared = Set(SchemaSource.defaultPaths().map { $0.joined(separator: "/") })
        let vended = Set(vendedDefaults.map { $0.path.joined(separator: "/") })
        #expect(declared == vended)
    }

    @Test("every open-registry view holds exactly the tokens its registry lists", .enabled(if: SchemaSource.isAvailable))
    func vendedRegistriesMatchTheirFile() throws {
        for (path, tokens) in vendedRegistries {
            let registry = try #require(SchemaSource.registryTokens(at: path), "\(path) declares no flat token list")
            #expect(Set(tokens) == Set(registry), "\(path)")
            #expect(tokens.count == registry.count, "\(path)")
        }
    }

    @Test("the spec ships no flat-token registry this package leaves unvended", .enabled(if: SchemaSource.isAvailable))
    func everyTokenRegistryIsVended() throws {
        let paths = try #require(SchemaSource.registryPaths(), "no registries/ directory in the spec checkout")
        let flatRegistries = Set(paths.filter { SchemaSource.registryTokens(at: $0) != nil })
        let vended = Set(vendedRegistries.map(\.path))
        #expect(flatRegistries == vended)
    }

    @Test("an absent kind reads as the format's default, and stays distinguishable")
    func absentKindTakesTheFormatDefault() {
        #expect(KnownStepKind.whenUnstated == .pour)
        // The default applies to an absent field, never to an unrecognized
        // token: the wire field keeps both apart, and so does this.
        #expect(Step().kind == nil)
        #expect(Step(kind: "swirl").kind.flatMap(KnownStepKind.init(rawValue:)) == nil)
        #expect(Step(kind: "pour").kind.flatMap(KnownStepKind.init(rawValue:)) == .pour)
    }

    @Test("an absent basis reads as the format's default, and an unrecognized one derives")
    func absentBasisTakesTheFormatDefault() throws {
        #expect(QuantityBasis.whenUnstated == .water)
        let stated = try Codec.decodeDocument(Data(#"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
          "water":{"value":250,"unit":"gram"}}]}
        """#.utf8))
        #expect(stated.recipes.first?.basis == .whenUnstated)
        // An unrecognized basis is the other rule: derive it from the quantities
        // the recipe states, because a new basis changes which one is required.
        let unknown = try Codec.decodeDocument(Data(#"""
        {"coffeejson":"1.0","recipes":[{"title":"Shot","basis":"strength",
          "coffee":{"value":18,"unit":"gram"},"yield":{"value":36,"unit":"gram"}}]}
        """#.utf8))
        #expect(unknown.recipes.first?.basis == .yield)
    }

    @Test("the roast levels read light to dark, and the grind sizes fine to coarse", .enabled(if: SchemaSource.isAvailable))
    func scalesAreDeclaredInOrder() throws {
        // Declaration order is the scale, not the alphabet, so `allCases` reads
        // as a consumer would build a picker.
        let roast = try #require(
            SchemaSource.enumTokens(["$defs", "bean", "properties", "roast_level"]))
        #expect(KnownRoastLevel.allCases.map(\.rawValue) == roast)
        let grind = try #require(SchemaSource.enumTokens(["$defs", "grind", "properties", "size"]))
        #expect(KnownGrindSize.allCases.map(\.rawValue) == grind)
    }

    @Test("a stated process reads back, including the two-word tokens")
    func statedProcessReadsBack() {
        #expect(KnownProcess(rawValue: "washed") == .washed)
        #expect(KnownProcess(rawValue: "pulped_natural") == .pulpedNatural)
        #expect(KnownProcess(rawValue: "wet_hulled") == .wetHulled)
        #expect(KnownProcess(rawValue: "carbonic_maceration") == .carbonicMaceration)
    }

    @Test("a coffee's whole list reads through one map, and an unknown member keeps its place")
    func processListReadsThroughOneMap() {
        let bean = Bean(process: ["anaerobic", "honey", "koji_natural"])
        #expect(bean.process?.map(KnownProcess.init(rawValue:)) == [.anaerobic, .honey, nil])
        #expect(bean.process?.last == "koji_natural")
    }

    @Test("the open-ended fields have no closed set, so none is asserted here", .enabled(if: SchemaSource.isAvailable))
    func openEndedFieldsStayOpen() throws {
        // A `Known*` view over any of these would assert a set the format does
        // not define, and would drop a producer's value on the floor.
        for field in ["drying_method", "certifications", "varietals"] {
            #expect(SchemaSource.enumTokens(["$defs", "bean", "properties", field]) == nil)
        }
    }

    @Test("the rule reaches a projected step, whose kind is carried in the same shape")
    func kindRuleReachesAProjection() throws {
        let imported = try Codec.decodeDocument(Data(#"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
          "water":{"value":250,"unit":"gram"},
          "steps":[{"kind":"tamp"},{"at_s":0,"to_water":{"value":50,"unit":"gram"}}]}]}
        """#.utf8))
        let recipe = try #require(imported.recipes.first)
        #expect(recipe.readOnlySteps.first?.kind.flatMap(KnownStepKind.init(rawValue:)) == .tamp)
        // The pour states no kind, and the projection carries that absence.
        #expect(recipe.pourSteps.first?.kind == nil)
    }
}
