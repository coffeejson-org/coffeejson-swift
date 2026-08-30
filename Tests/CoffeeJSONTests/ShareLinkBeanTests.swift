import Testing
import Foundation
@testable import CoffeeJSON

@Suite("ShareLink document round-trip")
struct ShareLinkBeanTests {
    @Test("a bag-to-brew link round-trips a bean and its recipe")
    func bagToBrewRoundTrip() throws {
        let document = Document(
            version: "1.0",
            beans: [Bean(name: "Nano Challa", roaster: Party(name: "Example Roastery"), process: ["washed"])],
            recipes: [Recipe(
                title: "Recommended V60",
                coffee: .grams(15),
                water: .grams(250))])
        let url = try ShareLink.shareURL(for: document, host: "example.com")

        let imported = try ShareLink.importDocument(from: url)
        #expect(imported.beans.count == 1)
        #expect(imported.beans.first?.name == "Nano Challa")
        #expect(imported.beans.first?.roaster?.name == "Example Roastery")
        #expect(imported.beans.first?.process == ["washed"])
        #expect(imported.recipes.count == 1)
        #expect(imported.recipes.first?.title == "Recommended V60")
        #expect(imported.recipesShareSingleBean == true)
    }

    @Test("a bean-only link round-trips just the bean")
    func beanOnlyRoundTrip() throws {
        let document = Document(version: "1.0", beans: [Bean(name: "Solo Coffee")])
        let url = try ShareLink.shareURL(for: document, host: "example.com")

        let imported = try ShareLink.importDocument(from: url)
        #expect(imported.beans.first?.name == "Solo Coffee")
        #expect(imported.recipes.isEmpty)
        #expect(imported.recipesShareSingleBean == false)
    }
}
