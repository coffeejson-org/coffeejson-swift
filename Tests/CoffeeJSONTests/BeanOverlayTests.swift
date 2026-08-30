import Testing
import Foundation
@testable import CoffeeJSON

/// Carry-raw for the other entity the format defines. A consumer's bean model is
/// a projection; without this seam, importing a roaster's bag and re-sharing it
/// emits a document that says less than the one that arrived — and, where the
/// projection flattens several credited parties into one string, a document that
/// is wrong.
@Suite("CoffeeJSON bean overlay re-emit")
struct BeanOverlayTests {
    private func beanObjects(_ data: Data) throws -> [[String: Any]] {
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["beans"] as? [[String: Any]])
    }

    private func firstBeanObject(_ data: Data) throws -> [String: Any] {
        try #require(try beanObjects(data).first)
    }

    private func document(_ beans: Bean...) -> Document {
        Document(version: Codec.currentVersion, beans: beans)
    }

    @Test("an owned key takes the typed value; every non-owned raw key passes through verbatim")
    func ownedWinsAndNonOwnedPassesThrough() throws {
        // The raw is a roaster's bag: a compound process, two credited parties,
        // a rest window, and a field no consumer models yet.
        let raw = Data(#"""
        {"name":"STALE","roaster":{"name":"PHILOCOFFEA"},"process":["anaerobic","honey"],
         "rest_days":{"min":14},
         "origin":{"type":"single","items":[{"country":"CO",
           "producers":[{"name":"Franco Lopez","role":"producer"},{"name":"La Mina","role":"farm"}]}]},
         "x_future":{"cup_score":88}}
        """#.utf8)
        let overlay = BeanOverlay(raw: raw, ownedKeys: [.name])
        let bean = try firstBeanObject(Codec.encode(
            document(Bean(name: "La Mina")), beanOverlays: [overlay]))

        #expect(bean["name"] as? String == "La Mina")                              // owned → typed wins
        #expect(bean["process"] as? [String] == ["anaerobic", "honey"])            // unmodelled set survives
        #expect((bean["rest_days"] as? [String: Any])?["min"] as? Double == 14)    // unmodelled field survives
        #expect((bean["x_future"] as? [String: Any])?["cup_score"] as? Double == 88) // future key survives
    }

    @Test("both credited parties survive a re-share — the fusing a projection would do never reaches the wire")
    func severalProducersSurvive() throws {
        // This is the defect the seam exists for: a consumer holding one display
        // string would re-emit `[{name: "Tesfaye Bekele, Suke Quto Coffee Farms"}]`.
        let raw = Data(#"""
        {"name":"Ethiopia Suke","roaster":{"name":"Linea Caffe"},
         "origin":{"type":"single","items":[{"country":"ET","region":"Oromia","producers":[
           {"name":"Tesfaye Bekele","role":"producer","type":"person"},
           {"name":"Suke Quto Coffee Farms","role":"cooperative"}]}]}}
        """#.utf8)
        let overlay = BeanOverlay(raw: raw, ownedKeys: [.name, .roaster])
        let bean = try firstBeanObject(Codec.encode(
            document(Bean(name: "Ethiopia Suke", roaster: Party(name: "Linea Caffe"))),
            beanOverlays: [overlay]))

        let items = try #require((bean["origin"] as? [String: Any])?["items"] as? [[String: Any]])
        let producers = try #require(items[0]["producers"] as? [[String: Any]])
        #expect(producers.count == 2)
        #expect(producers[0]["name"] as? String == "Tesfaye Bekele")
        #expect(producers[1]["role"] as? String == "cooperative")
    }

    @Test("an owned key absent from the typed bean is stripped, so no stale value leaks")
    func ownedButAbsentStripsStaleValue() throws {
        let raw = Data(#"{"name":"x","roaster":{"name":"R"},"description":"OLD PROSE"}"#.utf8)
        // The typed bean owns `description` but carries none.
        let overlay = BeanOverlay(raw: raw, ownedKeys: [.name, .description])
        let bean = try firstBeanObject(Codec.encode(
            document(Bean(name: "x")), beanOverlays: [overlay]))

        #expect(bean["description"] == nil)
    }

    @Test("an unowned key present in the typed bean never clobbers the raw — ownership is the only authority")
    func unownedTypedKeyIsIgnored() throws {
        let raw = Data(#"{"name":"RAW NAME","roaster":{"name":"R"},"process":["washed"]}"#.utf8)
        // The typed bean carries a process, but does not own the key.
        let overlay = BeanOverlay(raw: raw, ownedKeys: [.name])
        let bean = try firstBeanObject(Codec.encode(
            document(Bean(name: "TYPED NAME", process: ["natural"])), beanOverlays: [overlay]))

        #expect(bean["name"] as? String == "TYPED NAME")           // owned
        #expect(bean["process"] as? [String] == ["washed"])        // unowned → raw wins
    }

    @Test("a nil overlay, a non-object raw, and a short array each fall back to the typed bytes")
    func lenientEdges() throws {
        let typedOnly = try firstBeanObject(Codec.encode(
            document(Bean(name: "A")), beanOverlays: [nil]))
        #expect(typedOnly["name"] as? String == "A")

        let notAnObject = try firstBeanObject(Codec.encode(
            document(Bean(name: "B")),
            beanOverlays: [BeanOverlay(raw: Data("[1,2,3]".utf8), ownedKeys: [.name])]))
        #expect(notAnObject["name"] as? String == "B")

        // Two beans, one overlay: the tail stays typed.
        let beans = try beanObjects(Codec.encode(
            document(Bean(name: "C"), Bean(name: "D")),
            beanOverlays: [BeanOverlay(raw: Data(#"{"name":"raw-c","form":"bean"}"#.utf8), ownedKeys: [.name])]))
        #expect(beans[0]["form"] as? String == "bean")   // overlaid
        #expect(beans[1]["name"] as? String == "D")      // typed
        #expect(beans[1]["form"] == nil)
    }

    @Test("recipe and bean overlays apply in the same encode without interfering")
    func bothEntitiesOverlayTogether() throws {
        let doc = Document(
            version: Codec.currentVersion,
            beans: [Bean(name: "Bag")],
            recipes: [Recipe(title: "Brew", coffee: .grams(15), water: .grams(250))])
        let data = try Codec.encode(
            doc,
            recipeOverlays: [RecipeOverlay(
                raw: Data(#"{"title":"raw","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},"filter":{"material":"paper"}}"#.utf8),
                ownedKeys: [.title])],
            beanOverlays: [BeanOverlay(
                raw: Data(#"{"name":"raw","rest_days":{"min":14}}"#.utf8),
                ownedKeys: [.name])])

        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recipe = try #require((root["recipes"] as? [[String: Any]])?.first)
        let bean = try #require((root["beans"] as? [[String: Any]])?.first)

        #expect(recipe["title"] as? String == "Brew")
        #expect((recipe["filter"] as? [String: Any])?["material"] as? String == "paper")
        #expect(bean["name"] as? String == "Bag")
        #expect((bean["rest_days"] as? [String: Any])?["min"] as? Double == 14)
    }

    // The bean↔recipe reference matches on bytes, so `Codec.encode` emits `id`
    // and `bean_ref` in NFC. The overlay path copies only *owned* keys onto the
    // carried raw, so an unowned linking key would ride out in its producer's
    // form — one side NFC, the other decomposed, and a document that arrived
    // linked leaves unlinked with nothing thrown.

    /// "café" with a decomposed é (e + combining acute): canonically equal to the
    /// precomposed form, so `String ==` cannot tell them apart, but byte-different
    /// — which is the whole reason the emit side pins NFC.
    private static let decomposedRef = "cafe\u{0301}"

    @Test("an unowned bean_ref is re-emitted in NFC, so a re-share still links")
    func unownedBeanRefIsNormalizedOnReemit() throws {
        let decomposed = Self.decomposedRef
        let precomposed = decomposed.precomposedStringWithCanonicalMapping
        #expect(!Array(decomposed.utf8).elementsEqual(Array(precomposed.utf8))) // the probe is real

        // The recipe overlay does NOT own `bean_ref`, and `beanOverlays` is left
        // at its default — so the bean takes the typed, normalizing path while
        // the recipe's reference rides the raw. That is the default configuration.
        let raw = Data(#"""
        {"title":"raw","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"},
         "bean_ref":"\#(decomposed)"}
        """#.utf8)
        let document = Document(
            version: Codec.currentVersion,
            beans: [Bean(id: decomposed, name: "Café lot")],
            recipes: [Recipe(title: "V60", coffee: .grams(15), water: .grams(250), beanRef: decomposed)])
        let data = try Codec.encode(
            document,
            recipeOverlays: [RecipeOverlay(raw: raw, ownedKeys: [.title, .coffee, .water])])

        let round = try Codec.decodeDocument(data)
        #expect(Array(try #require(round.beans[0].id).utf8).elementsEqual(Array(precomposed.utf8)))
        #expect(Array(try #require(round.recipes[0].beanRef).utf8).elementsEqual(Array(precomposed.utf8)))
        #expect(round.associatedBean(forRecipeAt: 0)?.name == "Café lot")
    }

    @Test("an unowned bean id is re-emitted in NFC too — the mirrored break")
    func unownedBeanIdIsNormalizedOnReemit() throws {
        let decomposed = Self.decomposedRef
        let precomposed = decomposed.precomposedStringWithCanonicalMapping

        // The other direction: the recipe overlay owns `bean_ref` (so the typed,
        // normalized value crosses over) while the bean overlay does not own
        // `id` (so the raw's decomposed id rides through).
        let recipeRaw = Data(#"""
        {"title":"raw","coffee":{"value":15,"unit":"gram"},"water":{"value":250,"unit":"gram"}}
        """#.utf8)
        let beanRaw = Data(#"{"id":"\#(decomposed)","name":"Café lot","rest_days":{"min":14}}"#.utf8)
        let document = Document(
            version: Codec.currentVersion,
            beans: [Bean(id: decomposed, name: "Café lot")],
            recipes: [Recipe(title: "V60", coffee: .grams(15), water: .grams(250), beanRef: decomposed)])
        let data = try Codec.encode(
            document,
            recipeOverlays: [RecipeOverlay(raw: recipeRaw, ownedKeys: [.title, .coffee, .water, .beanRef])],
            beanOverlays: [BeanOverlay(raw: beanRaw, ownedKeys: [.name])])

        let round = try Codec.decodeDocument(data)
        #expect(Array(try #require(round.beans[0].id).utf8).elementsEqual(Array(precomposed.utf8)))
        #expect(Array(try #require(round.recipes[0].beanRef).utf8).elementsEqual(Array(precomposed.utf8)))
        #expect(round.associatedBean(forRecipeAt: 0)?.name == "Café lot")
        // The unowned raw key still rides through untouched — normalization is
        // not license to rewrite anything else.
        let bean = try firstBeanObject(data)
        #expect((bean["rest_days"] as? [String: Any])?["min"] as? Double == 14)
    }

    @Test("a decoded bean carries its verbatim bytes, ready to become an overlay")
    func decodeCapturesRawBytes() throws {
        let json = #"""
        {"coffeejson":"1.0","beans":[
          {"name":"First","roaster":{"name":"R"},"url":"https://x.test","process":["washed"],"x_future":1},
          {"name":"Second","roaster":{"name":"R"},"url":"https://y.test"}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        #expect(imported.beans.count == 2)

        let raw = try #require(imported.beans[0].rawJSON)
        let object = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(object["name"] as? String == "First")
        #expect(object["x_future"] as? Double == 1)

        // Each bean gets its own slice, not the document's.
        let second = try #require(imported.beans[1].rawJSON)
        let secondObject = try #require(try JSONSerialization.jsonObject(with: second) as? [String: Any])
        #expect(secondObject["name"] as? String == "Second")
    }

    @Test("import then re-share round-trips a bag losslessly through a subset projection")
    func importEditReshareKeepsWhatItDidNotModel() throws {
        // The whole point, end to end: decode a roaster's bag, edit only the
        // name, re-share, and every field the consumer never modelled is intact.
        let json = #"""
        {"coffeejson":"1.0","beans":[{"name":"La Mina","roaster":{"name":"PHILOCOFFEA"},
          "url":"https://philocoffea.com","process":["anaerobic","honey"],"rest_days":{"min":14},
          "origin":{"type":"single","items":[{"country":"CO","varietals":["Caturra"],
            "producers":[{"name":"Franco Lopez","role":"producer"}]}]}}]}
        """#
        let imported = try Codec.decodeDocument(Data(json.utf8))
        let raw = try #require(imported.beans[0].rawJSON)

        // A consumer that models only name + roaster, and renames the coffee.
        let edited = Document(
            version: Codec.currentVersion,
            beans: [Bean(name: "My La Mina", roaster: Party(name: "PHILOCOFFEA"))])
        let out = try Codec.encode(
            edited, beanOverlays: [BeanOverlay(raw: raw, ownedKeys: [.name, .roaster])])

        let back = try JSONDecoder().decode(Document.self, from: out)
        let bean = try #require(back.beans?.first)
        #expect(bean.name == "My La Mina")                      // the edit landed
        #expect(bean.process == ["anaerobic", "honey"])          // never modelled, never lost
        #expect(bean.restDays?.min == 14)
        #expect(bean.origin?.items?.first?.varietals == ["Caturra"])
        #expect(bean.origin?.items?.first?.producers?.first?.role == "producer")
    }
}
