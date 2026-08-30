# Integration patterns for a stateful app

How a consuming app relates its own domain or persistence model to the
CoffeeJSON wire types (`CoffeeJSON.Recipe`, `CoffeeJSON.Bean`, …). This is not
about the wire format itself.

The recommended pattern for a **stateful** Swift app is **Hybrid**: a mapped
working set of native columns, plus the carried raw payload, with on-demand
`CoffeeJSON` accessors. Which columns to project is each app's own call (see
Consequences).

## The constraint

A stateful app persists, queries, and edits, and it holds app-only data the
format has no concept of: brew logs, `createdAt`, bean relations. So a
CoffeeJSON wire type cannot be the app's persisted model.

Direct mapping is the common starting point: SwiftData `@Model` domain types
kept separate from the wire types, hand-mapped both ways in a consumer-side
interop layer. The CoffeeJSON package never references domain types. Direct
mapping has two costs:

- **Mapping tax.** Every new wire field needs hand-mapping at each layer
  between the wire and the model — codec, model, import, export — plus a
  conformance-gate touch when the app emits it.
- **Silent drops.** Anything the app does not explicitly map is lost on import.
  Unknown and future fields do not round-trip.

## The patterns

| # | Pattern | What it is | Round-trips unknown and future fields? | Native query and edit? | Mapping cost | Best fit |
|---|---|---|---|---|---|---|
| 1 | **Direct mapping** | domain `@Model` ⇄ hand-mapped ⇄ wire | ✗ drops unmapped | ✓ | high (per field) | the common starting point |
| 2 | **Pure CoffeeJSON** | the wire type *is* the model | ✓ | ✗ (not a SwiftData `@Model`, no room for app-only data) | none | display-only consumers only |
| 3 | **Embed** | `@Model { id, appFields, coffeejson }`: store the typed payload | ✓ | ✗ (wire fields live in a blob) | low | detail-heavy, small datasets |
| 3b | **On-demand types** | store the raw payload, and **materialize** `CoffeeJSON.Recipe` or `Bean` by decoding it *when a field is read* | ✓ (from the raw) | ✗ on the wire fields | low | the *read half* of Hybrid |
| 4 | **Hybrid** | minimal native columns for the working set **+** the carried raw payload | ✓ | ✓ for the projected set | low (project only what you use) | **stateful apps** |
| 5 | **Codegen / protocol** | direct mapping with the boilerplate generated (a `CoffeeJSONConvertible` protocol or a schema-driven macro) | ✗ still drops unmapped | ✓ | low (via tooling) | complements 1 or 4 |

Why the others lose for a stateful app:

- **Pure (2).** A `Codable` wire struct is not a SwiftData `@Model`, and it has
  nowhere to hang brew logs, timestamps, or edits. It is fine for **stateless,
  display-only** consumers (a viewer, a share preview, a web card).
- **Embed (3).** It buys free fidelity, but the wire fields sit in a blob. You
  cannot query or sort on them at the database level, and edits go through the
  embedded struct. That is awkward for a list-driven, editable app.
- **Codegen (5).** It removes the mapping tax, but on its own it still drops
  unmapped fields. So it is a complement, not a substitute.

## Hybrid with on-demand accessors (4 + 3b)

Pattern 3b is the read mechanism for pattern 4. The model persists:

1. A **minimal set of native columns**: only the fields the app *lists, sorts,
   or edits* (for example title, coffee, water, ratio, `createdAt`, bean).
2. The **raw CoffeeJSON payload**, in one `Data?` column.

Everything else (`notes`, `additions[]`, and every future field) is **never
mapped into a column**. It rides the raw and is read **on demand**, by decoding
into `CoffeeJSON.Recipe` or `CoffeeJSON.Bean` in the detail view. **Export is
the raw, overlaid with the app's edited columns.**

This removes both costs at once, and it keeps the SwiftData-native query, edit,
and list that Pure and Embed sacrifice:

- **Fidelity.** Unknown and future fields round-trip for free, because the raw
  carries them verbatim.
- **Mapping tax.** A field is mapped into a column *only when the app needs to
  query or edit it*. Display-only fields cost nothing.

### How it works

- **Import:** decode the wire document, populate the working-set columns, and
  store the raw bytes.
- **Read (list, query, sort):** native columns.
- **Read (detail, non-projected fields such as notes and additions):** decode
  the raw into `CoffeeJSON.Recipe` on demand.
- **Edit:** update the columns. They are the app's editable surface.
- **Export and share:** one export call. It decodes the raw, overlays the
  current values of the app-editable columns, and encodes. This is the *one*
  consistency point: it preserves the raw's non-mapped fields and reflects the
  app's edits. The package vends that assembly: conform the model to
  `RecipeConvertible` or `BeanConvertible` — typed projection, carried raw,
  owned keys — and call `Codec.encode(beans:recipes:tastings:generator:)`. It
  is sugar over the overlay primitive, so the contract is unchanged. Ownership
  is per instance, so a read-only row and an edited one can be the same type.
  See the README's carry-raw section.
- **An app that adopts carry-raw after it ships** holds records with no raw.
  Those fall back to a document rebuilt from columns, while every new import
  gets full fidelity. Adopt the seam as early as possible: a record imported
  before the seam exists can never get its raw bytes back.

## Consequences

- **Adopting a display-only field gets *smaller*.** Under Hybrid, fields like
  `notes` and `additions[]` need **no `@Model` migration and no codec, interop,
  export, or conformance mapping**. They ride the raw and show on demand. Build
  the carry-raw plumbing **once**. Then a new field costs on-demand display
  only.
- **Adoption is incremental, not a rewrite.** Add an optional raw-payload
  column (Optional, so SwiftData migrates it lightweight), populate it on
  import, and route export through the overlay. Existing mapped columns and
  views stay.
- **Sync discipline.** The raw is the fidelity source. The columns are the
  app's working projection. That export call is the single overlay point that
  keeps them consistent. Do not scatter export logic.
- **A conformance gate still applies** to what the app *emits*. Export
  re-encodes the raw plus the overlay, so the emitted document is whatever the
  raw carried plus the app's edits. The raw is the half no typed layer checked.
  The package validates its own emit paths against the published schema, which
  covers the typed and overlay encoders. It cannot cover the content of a raw
  an app carried in from somewhere else.

## Choosing a pattern

Choose by the consumer's relationship to the data. The pattern is deliberately
**not** one-size-fits-all:

- **Stateful apps** (persist, query, edit, carry app-only data): **Hybrid**.
- **Stateless, display-only consumers** (a viewer, a share preview, a web
  recipe card): **Pure CoffeeJSON** (2) or **Embed** (3). Use the wire types
  directly. No domain model is needed.
- **A mapped working set that grows large and churns**: add **codegen or a
  `CoffeeJSONConvertible` protocol** (5) on top of Hybrid to cut the projection
  boilerplate.

## References

- The neutrality rule: this package never references consumer domain types,
  and consumer policy (range bounds, storage mapping) lives with the consumer
  (`Sources/CoffeeJSON/Codec.swift`, the type's doc comment).
- The export seam that mechanizes this: `RecipeConvertible` / `BeanConvertible`
  and `Codec.encode(beans:recipes:tastings:generator:)`
  (`Sources/CoffeeJSON/Interop/`). The re-emit under it is internal — a model
  states its owned keys and the package does the rest.
