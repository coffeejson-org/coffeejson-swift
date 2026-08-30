# CoffeeJSON

The CoffeeJSON core for Swift: wire DTOs, the codec (encode and decode
semantics, unit canonicalization), the imported-model layer, and the share-link
transport. It has no package dependencies. It uses Foundation plus one system
framework (see Platforms), and it has no app-specific types.

The module name is `CoffeeJSON`.

Spec: the CoffeeJSON v1.0 specification at https://coffeejson.org
(repo: https://github.com/coffeejson-org/coffeejson).

## Platforms

iOS 18 · watchOS 11 · macOS 13. The app-platform floors are high on purpose,
and the reason is maintainer capacity, not API need. Nothing in the code
requires iOS 18. Supporting and testing many OS versions is real, ongoing work,
and this package chooses a small, honestly tested matrix over a broad, nominal
one. If the floor is what blocks your adoption, open an issue: widening it is a
conversation, not a rewrite.

The toolchain floor is `swift-tools-version: 6.0` — Xcode 16 or later.

Apple platforms only: this package does not build on Linux. The share-link
parser reads a compressed payload as well as a plain one, and the decompression
uses Apple's `Compression` framework. Reading both forms is a permanent
contract, so a build with that path removed is not on offer. A build where a
link minted by another implementation silently fails to open is worse than a
platform this package does not claim. That is a position rather than a verdict.
If you want this on the server, say so and we will talk about what that takes.

## Installation

Add the package with Swift Package Manager. In `Package.swift`:

```swift
.package(url: "https://github.com/coffeejson-org/coffeejson-swift.git", from: "1.0.0")
```

Then add the product to your target:

```swift
.product(name: "CoffeeJSON", package: "coffeejson-swift")
```

In Xcode, choose **File > Add Package Dependencies**. Then enter the repository
URL.

This package's version is independent of the `coffeejson` wire version a
document declares; neither number moves the other. `Codec.currentVersion` is
what an emit stamps, and `Codec.supportedMajorVersion` is the major this build
reads.

The package vends a second product, `CoffeeJSONSchemaTesting`. It is for test
targets only, and [The package validates what it emits](#the-package-validates-what-it-emits-and-vends-that-gate)
gives its contract.

## A scanned link, end to end

```swift
import CoffeeJSON

let imported = try CoffeeJSON.ShareLink.importDocument(fromScanned: scannedText)
guard let recipe = imported.recipes.first else { return }

print(recipe.title)                   // "Tetsu Kasuya 4:6"
print(recipe.methodSlug ?? "")        // "pour_over"
print(recipe.coffeeGrams)             // 20.0 — canonical grams, whatever the wire stated
print(recipe.waterGrams ?? 0)         // 300.0
print(recipe.ratio ?? 0)              // 15.0 — derived when the document states none
for step in recipe.pourSteps {
    print(step.atSeconds, step.cumulativeWaterGrams)   // 0.0 60.0 · 45.0 120.0 · …
}
```

`ShareLink.importDocument(from:)` takes a `URL` where a scanner hands you text,
and `shareURL(forEncodedDocument:host:)` goes the other way. Every failure is an
`ImportError`, whose `kind` names it in the format's shared vocabulary — the
same twelve tokens every implementation reports (`not_a_url`,
`unsupported_version`, `empty_document`, …), and `nil` for a validation fault,
which names a field instead.

## What this package models

This package models every field the published 1.0 schema declares, on every
object it defines: `Document` · `Generator` · `Recipe` · `Grind` · `Step` ·
`Bean` · `Origin` · `OriginItem` · `Altitude` · `RestDays` · `Tasting` ·
`PerceivedAxes` · `MeasuredCup` · `Gear` · `Party` · `Filter` · `Addition` ·
`Quantity`. It models each entity's `localizations` with them. One `Party`
covers every credit the schema defines — a recipe's `author`, a bean's
`roaster`, an origin item's `producers` — so a consumer renders all three with
one code path.

Read that list as of the commit you are holding, not as a promise about every
version to come. Nothing is lost in the meantime: an unknown field is ignored on
decode, per the spec's forward-compatibility contract, and a recipe's and a
coffee's verbatim bytes ride a `rawJSON` property (`ImportedRecipe.rawJSON`,
`ImportedBean.rawJSON`), so a consumer can round-trip fields the typed layer
does not model. A tasting has none: nothing re-emits one.

### A dated field is a day, not an instant

`roast_date` and `date_published` project as `CalendarDay` — `year` / `month` /
`day`, and no time. Its own doc comment carries why a `Date` cannot say what a
dated field says.

```swift
bean.roastDate?.iso8601                     // "2026-06-20" — the wire spelling, to re-emit
bean.roastDate?.date(in: .current)          // the reader's own midnight, asked for explicitly
CalendarDay(pickedDate, in: .current)       // the inverse: which day that instant is, `nil` if none
CalendarDay(year: 2026, month: 6, day: 20)  // failable, on the same rule as the wire spelling
```

Either crossing is the consumer's, with the consumer's calendar, and the
calendar is a parameter both ways because it is what decides the answer. A day
the calendar does not have — `2026-02-31`, `2026-13-45` — reads as absent rather
than as the date Foundation would normalize it into.

### A quantity can state a window

`Quantity` carries `value` **or** `min`/`max`, and the window is the author's
number:

- `grams` / `celsius` / `bar` / `milliliters` return `nil` for a window. They
  never invent a midpoint.
- `minGrams` / `maxGrams` (and the `celsius` / `bar` / `milliliters`
  equivalents) read the bounds.
- `midpointGrams` / `midpointCelsius` / `midpointBar` / `midpointMilliliters`
  vend the midpoint on its own, for a consumer that must label it as derived.
- `effectiveGrams` returns the stated value, or the midpoint when there is only
  a window. `effectiveCelsius` / `effectiveBar` / `effectiveMilliliters` are the
  same rule on the other three.

`ImportedRecipe` is a brew model and needs one number, so it uses the midpoint
and records which quantities it derived in `derivedQuantities`. **A surface that
shows a derived number must say so**, or show the window itself from `rawJSON`.

Brew water is the one quantity a publisher can state by volume (`milliliter`),
and no mass⇄volume conversion is defined. So `ImportedRecipe.waterGrams` is
`nil` for a volume-stated recipe; `waterStatedByVolume` says that is what
happened, and `waterMilliliters` carries the author's number.

### A translation lines up with its steps, or it is discarded

`localizations` carries the publisher's own wording in other languages, keyed by
BCP-47 tag — `RecipeLocalization` on a recipe, `BeanLocalization` on a coffee.
Wording only. Per-step wording is **positional**, so read it through
`steps(pairedWith:)` rather than indexing `steps`:

```swift
let recipe = try JSONDecoder().decode(Document.self, from: bytes).recipes?.first
let english = recipe?.localizations?["en"]

english?.steps(pairedWith: recipe?.steps)?[1].instruction   // nil-safe pairing
```

That returns `nil` when the two disagree on length: the whole array is discarded
rather than zipped to the shorter one.

### The format's token sets have a typed view

Every set the schema closes has a type here: `KnownBrewMethod` ·
`KnownStepKind` · `KnownGrindSize` · `KnownFilterMaterial` · `KnownProcess` ·
`KnownRoastLevel` · `KnownBeanForm` · `KnownPreferredExtraction` ·
`KnownOriginType` · `KnownPartyType` · `QuantityBasis`, and one per kind of
measurement for the units: `KnownMassUnit` · `KnownWaterUnit` ·
`KnownTemperatureUnit` · `KnownPressureUnit` · `KnownAltitudeUnit`.
`KnownAdditionType` and `KnownProducerRole` view an **open registry** instead,
so they name the tokens the spec recommends and no more.

```swift
recipe.method.flatMap(KnownBrewMethod.init(rawValue:))   // "pour_over" → .pourOver
bean.process?.map(KnownProcess.init(rawValue:))          // ["anaerobic", "koji_natural"] → [.anaerobic, nil]
```

They are **views, never gates**: `init?(rawValue:)` is the only way to read one,
every wire field stays a free `String` — or a free `[String]` where the format
states a set, so a list maps in one call and an unrecognized member keeps its
place. An unrecognized token round-trips verbatim and reads as `nil` here. `nil`
means *outside this set* and nothing more, never a folded `other`, which would
report a token the producer did not write. Where the spec states a per-field
*fallback*, the consumer applies it at the point of display, over the wire field
itself.

An **absent** field is a different question, and where the format answers it the
answer is vended here rather than left to each reader: `KnownStepKind.whenUnstated`
is `.pour` and `QuantityBasis.whenUnstated` is `.water`, both from the schema's
own `default`. `drying_method`, `certifications` and `varietals` get no view at
all, because the schema closes no set for them.

Each unit set bridges to Foundation — `KnownMassUnit.gram.foundationUnit` is
`UnitMass.grams`. `KnownWaterUnit` bridges to a two-case answer, mass or volume,
because the format defines no conversion between them and `Measurement` would
otherwise return a number for one.

The localized name for a token is yours, and so is every rendered figure: this
package ships no resources, no `MeasurementFormatter` and no locale. The suite
compares each view against the published schema and walks the schema for a
closed set no type here vends, so a transcription slip fails rather than
degrading quietly.

### The decoder reads what the schema defines, and nothing else

A document in a shape the schema rejects fails to decode instead of degrading.
This package is the format's Swift reference implementation, and a decoder more
permissive than its own specification teaches the specification wrong: the
rejected shape keeps circulating because one reader keeps accepting it. That
cost is accepted.

### Carry-raw: edit a subset without rewriting the document

A consumer's typed model is a **projection**, and a projection that re-emits
only its own columns silently rewrites the producer's document: a compound
process becomes one value or none, and several credited parties become one name.
So the recipe and the bean carry their verbatim bytes on decode, and a model
states which wire keys it is authoritative for:

```swift
struct StoredRecipe: RecipeConvertible {
    var title: String
    var grams: Double
    var rawJSON: Data?
    var isEditable: Bool

    var wireRecipe: Recipe { Recipe(title: title, coffee: .grams(grams), water: .grams(250)) }
    var carriedRecipeJSON: Data? { rawJSON }
    // Per instance: a row the user never edited owns nothing and rides its raw.
    var ownedRecipeKeys: Set<Recipe.WireKey> { isEditable ? [.title, .coffee] : [] }
}

let bytes = try Codec.encode(recipes: rows)      // beans: and tastings: too
```

An **owned** key is authoritative from the typed value: present wins, absent
strips, so no stale value leaks. Every other raw key passes through verbatim,
and an *unowned* typed key never overwrites the raw. Ownership is the single
authority. That is the format's fidelity contract — *an edit-and-re-share never
drops a field the editor did not touch*.

`BeanConvertible` is the same three requirements for a coffee. Both collections
default to empty. `generator` is an envelope member you pass to the call rather
than an owned key, because the software that wrote a document names itself once
for the file.

**This call is the export seam**, and `Codec.encode(_:)` — the typed projection
alone, no raw — is the only other way out. For a link, encode and then build:

```swift
let url = try ShareLink.shareURL(forEncodedDocument: bytes, host: host)
```

### How a cup is recorded

A `Tasting` is how one brewed cup turned out: the format's third top-level
collection. `rating`, `perceived`, and `descriptors` are one person's impression
of one occasion. `measured` is what an instrument read. **A consumer must never
present one as the other.** A document of tastings alone is `.emptyDocument`.

`ImportedTasting.extractionYieldPercent` is this package doing the arithmetic
the spec states and asks consumers to do: from the tasting's own weighed yield
when it has one, and from the referenced recipe's target otherwise. It is `nil`
whenever an input is missing, rather than a guess.

Bean↔recipe **association** is resolved per the spec's envelope rule, by
`ImportedDocument.associatedBean(forRecipeAt:)`,
`associatedRecipe(forTastingAt:)` and `associatedBean(forTastingAt:)` — each
one's doc comment states which reference wins and what co-location covers. An
unresolved reference means unlinked, never an error.

`Codec.encode` emits `id` / `bean_ref` / `recipe_ref` in Unicode NFC, on every
collection, because the reference match is byte-exact.

### The package validates what it emits, and vends that gate

Coverage says the typed layer can *read* every key the schema declares. It says
nothing about what the encoder *writes*, and a reference implementation that
cannot answer "does what I emit conform?" is asserting its own correctness.

So the package ships a second library product, **`CoffeeJSONSchemaTesting`**,
and runs every emit path through it: the typed encoder, the re-emit, and a built
share link's payload. It holds a dependency-free draft-2020-12 **subset**
validator — exactly the keywords this schema uses — and a keyword it does not
implement is **an error, never a shrug**, because silently ignoring one is how a
rule enters the format and is enforced by nobody.

**It is for test targets only** — never link it into a shipping target:

```swift
// Package.swift — in the test target, not the library.
.testTarget(name: "MyAppTests", dependencies: [
    .product(name: "CoffeeJSONSchemaTesting", package: "coffeejson-swift"),
])
```

```swift
import CoffeeJSONSchemaTesting

@Test("what this app emits conforms", .enabled(if: SchemaSource.isAvailable))
func emitConforms() throws {
    let validator = SchemaValidator(schema: try #require(SchemaSource.root))
    #expect(validator.validate(try JSONSerialization.jsonObject(with: bytes)).isEmpty)
}

@Test("the validator implements every keyword the schema uses",
      .enabled(if: SchemaSource.isAvailable))
func subsetIsComplete() throws {
    #expect(SchemaValidator.unimplementedKeywords(in: try #require(SchemaSource.root)).isEmpty)
}
```

`SchemaSource` finds the schema in a `coffeejson` checkout beside this package,
or wherever `COFFEEJSON_SPEC_DIR` names — set it wherever the layout is not
that. **The schema is not vendored**, here or in your package, for the reason
`SchemaSource`'s own doc comment gives. Gate each test on
`SchemaSource.isAvailable`, as above, so a clone without a spec checkout
**skips** rather than fails. A bundle that can reach no checkout at all — an
app-platform target in a simulator sandbox — parses its own copy and hands it to
`SchemaValidator(schema:)`; that copy's staleness is then yours to gate.

`SchemaSource.file(at:)` reaches any other file of that checkout on the same
terms, and `SchemaSource.scanVectorsPath` names the transport's shared
scan-vector corpus, which this package's own suite executes. A consumer that
implements its own link intake runs the same corpus against it, and then two
conformant consumers agree on whether a given link imports.

### The schema is the gate on what this package models

A field the published schema declares and this package does not name is skipped
silently on decode, and no test here can fail on it. So the coverage check is
CI's job rather than a reviewer's:

```sh
node scripts/check-schema-coverage.mjs ../coffeejson
```

It walks every wire key the schema defines and looks for it **on the type that
owns it**: a `name` declared by some other type does not count. It reports a
`$def` nobody mapped rather than skipping it.

CI reads the spec at a **pinned commit** — the `ref:` in
`.github/workflows/ci.yml`, one per job. To adopt a newer format, move both to
the spec commit you are adopting in the same commit that carries whatever it
asks of this code; an unpinned spec would instead let an upstream change redden
a tree nobody touched.

Test fixtures and samples name real roasters, recipe authors, producers and farms, alongside
their published pages, as attribution. They follow the format corpus's terms: a
named source that wants a reference corrected or removed can open an issue, and
both are honored.

## Local development

To build against a checkout rather than a release, add a path dependency in
your own `Package.swift`:

```swift
.package(path: "../coffeejson-swift")
```

In Xcode, choose **File > Add Package Dependencies > Add Local**. Then select the
`coffeejson-swift` folder.

## License

Apache-2.0, see [LICENSE](LICENSE). The format itself (spec prose, schema,
fixtures, registries) is CC0 public domain at its own repo. This package's code
carries Apache's standard terms, including the express patent grant.
