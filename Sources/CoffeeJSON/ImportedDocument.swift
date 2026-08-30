import Foundation

/// A decoded CoffeeJSON document, each collection already validated and
/// normalized. Always-array: a single coffee, recipe or tasting is an array of
/// one.
public struct ImportedDocument: Equatable, Hashable, Sendable {
    public var beans: [ImportedBean]
    public var recipes: [ImportedRecipe]
    /// A document of tastings alone never reaches here — a tasting evaluates
    /// something, so `Codec` rejects it as empty.
    public var tastings: [ImportedTasting]
    /// The software that wrote this document. Informational: nothing here reads
    /// it, and a consumer must not change how it imports because of it.
    public var generator: Generator?

    public init(
        beans: [ImportedBean] = [],
        recipes: [ImportedRecipe] = [],
        tastings: [ImportedTasting] = [],
        generator: Generator? = nil
    ) {
        self.beans = beans
        self.recipes = recipes
        self.tastings = tastings
        self.generator = generator
    }

    /// Co-location association: exactly one bean alongside ≥1 recipe means those
    /// recipes are *for* that bean (bag-to-brew). With several beans the link is
    /// ambiguous (the reserved `beans × recipes` cell), so this is `false` and a
    /// consumer imports the collections unlinked. The per-recipe answer —
    /// which also honors explicit references — is
    /// ``associatedBean(forRecipeAt:)``.
    public var recipesShareSingleBean: Bool { beans.count == 1 && !recipes.isEmpty }

    /// The bean a recipe is associated with, resolved by the spec's one rule
    /// (envelope § Association): an explicit `bean_ref` wins, matched against
    /// bean `id`s **byte-exactly** (case-sensitive); an unresolved reference —
    /// including one to a duplicated id, which makes the document malformed
    /// there — leaves the recipe associated with **no** bean, never an error
    /// and never a fallback to co-location. A recipe without a reference is
    /// associated with the single bean when exactly one is present
    /// (bag-to-brew), else with none.
    public func associatedBean(forRecipeAt index: Int) -> ImportedBean? {
        guard recipes.indices.contains(index) else { return nil }
        if let ref = recipes[index].beanRef { return beans.referenced(by: ref) }
        return beans.count == 1 ? beans[0] : nil
    }

    /// The recipe a tasting was brewed from: the one whose `id` matches its
    /// `recipe_ref` byte-exactly, or `nil`.
    ///
    /// There is **no positional fallback**. Co-location in this format triggers
    /// on a single *bean* and associates a coffee, so a tasting that names no
    /// recipe names none however few the document carries. An unresolved
    /// reference — including one to a duplicated id, which makes the document
    /// malformed there — leaves the tasting unlinked and is never an error.
    public func associatedRecipe(forTastingAt index: Int) -> ImportedRecipe? {
        guard tastings.indices.contains(index) else { return nil }
        return recipes.referenced(by: tastings[index].recipeRef)
    }

    /// The coffee a tasting was brewed with, resolved **independently** of the
    /// recipe it points at.
    ///
    /// The tasting's own `bean_ref` wins — including over the referenced
    /// recipe's, which is not a conflict but "I brewed your recipe with my
    /// coffee", the ordinary case for a recipe somebody else published.
    /// Answering with the recipe's bean there would name a coffee that was never
    /// in the cup. Absent a reference, a single co-located bean associates as it
    /// does for a recipe; with several, none does.
    public func associatedBean(forTastingAt index: Int) -> ImportedBean? {
        guard tastings.indices.contains(index) else { return nil }
        if let ref = tastings[index].beanRef { return beans.referenced(by: ref) }
        return beans.count == 1 ? beans[0] : nil
    }
}
