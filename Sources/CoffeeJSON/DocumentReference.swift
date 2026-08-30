import Foundation

/// Something a document-scoped reference can name. The format gives `beans`,
/// `recipes` and `tastings` each an optional `id`, and every reference between
/// them resolves by the same rule.
protocol DocumentScopedIdentifiable {
    var id: String? { get }
}

extension ImportedBean: DocumentScopedIdentifiable {}
extension ImportedRecipe: DocumentScopedIdentifiable {}
extension ImportedTasting: DocumentScopedIdentifiable {}

extension Collection where Element: DocumentScopedIdentifiable {
    /// The one element `ref` names, or `nil`.
    ///
    /// Byte-exact on the UTF-8 view, deliberately NOT Swift's `==`: String
    /// equality is canonical-equivalence, which would link two normalization
    /// forms the spec says do not match. (Emit-side NFC makes honest producers
    /// converge; the read side stays exact.)
    ///
    /// Exactly one match resolves. A duplicated id makes the document malformed
    /// there, so it resolves to none rather than a guess — an unlinked entity is
    /// honest where a picked winner is not.
    func referenced(by ref: String?) -> Element? {
        guard let ref else { return nil }
        var found: Element?
        for element in self where element.id?.utf8.elementsEqual(ref.utf8) == true {
            if found != nil { return nil }
            found = element
        }
        return found
    }
}
