import Foundation

/// Wire DTO → `Imported*` projection: the format's *semantics* half, as against
/// the envelope reading in `Codec.swift`. Unit canonicalization, required-field
/// enforcement, window midpointing and step mapping live here.
extension Codec {
    static func importedRecipe(from wire: Recipe) throws -> ImportedRecipe {
        let title = (wire.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ImportError.validation(.missingRequiredField("title")) }

        // Required, in canonical grams; an unrecognized unit reads as absent, and
        // representable-range bounds are a *consumer* policy. A stated window
        // midpoints and records that in `derivedQuantities` — refusing the recipe
        // would lose a document the format carries perfectly well.
        var derived: DerivedQuantities = []
        guard let coffeeGrams = wire.coffee?.effectiveGrams else {
            throw ImportError.validation(.missingRequiredField("coffee"))
        }
        derived.insert(.coffee, ifWindow: wire.coffee)

        // Which of water and yield is required depends on basis, which is
        // authoritative and defaults to `water`. An unrecognized value never
        // fails on the value itself: the effective basis derives from the
        // quantities present, the spec's derive rule, so a newer-major or
        // malformed sender degrades to what its data supports instead of a
        // spurious missing-water error. The order is the spec's, because a
        // water-basis recipe MAY state a yield too and a bare which-is-present
        // test would read one as a shot: water or ratio first, then yield.
        let basis: QuantityBasis
        if let raw = wire.basis {
            basis = QuantityBasis(rawValue: raw)
                ?? ((wire.water == nil && wire.ratio == nil && wire.yield != nil) ? .yield : .water)
        } else {
            basis = .whenUnstated
        }

        // The yield reads the same way whatever the basis; only whether it is
        // required differs, which the yield-basis branch below states.
        let statedYield = wire.yield?.effectiveGrams
        derived.insert(.yield, ifWindow: wire.yield)

        let waterGrams: Double?
        let yieldGrams: Double?
        let ratio: Double?
        let waterStatedByVolume: Bool
        let waterMilliliters: Double?
        var waterFromRatio = false
        if basis == .yield {
            guard let y = statedYield else { throw ImportError.validation(.missingRequiredField("yield")) }
            yieldGrams = y
            waterGrams = nil                        // a shot states no brew water
            ratio = coffeeGrams > 0 ? y / coffeeGrams : wire.ratio
            waterStatedByVolume = false
            waterMilliliters = nil
        } else if let water = wire.water, water.hasMagnitude {
            // Brew water is the one quantity a publisher may state by volume, and
            // no mass<->volume conversion is defined, because water's density
            // moves with temperature. A volume-stated recipe therefore has no
            // water *mass* to brew by: `waterGrams` and `ratio` are `nil`,
            // `waterStatedByVolume` says which absence this is, and the stated
            // volume is surfaced as `waterMilliliters`. Absent rather than zero,
            // because zero is a quantity a person could pour and this is the
            // absence of one — and the recipe still imports.
            let w = water.effectiveGrams
            derived.insert(.water, ifWindow: water)
            waterGrams = w                         // nil exactly when volume-stated
            waterStatedByVolume = (w == nil)
            waterMilliliters = waterStatedByVolume ? water.effectiveMilliliters : nil
            yieldGrams = statedYield                // a water-basis doc may still carry a measured yield
            ratio = (coffeeGrams > 0 && w != nil) ? w! / coffeeGrams : wire.ratio
        } else if let stated = wire.ratio, stated.isFinite, stated > 0 {
            // Of `water` and `ratio` a recipe needs one, not both: the dose is
            // required either way, so each fixes the other, and only a recipe
            // carrying neither is invalid. Stated water wins where both appear
            // (the branch above) — it is what the publisher measured, where a
            // ratio is what they intended.
            //
            // The arithmetic invents nothing: 20 g at 1:15 is exactly 300 g. A
            // windowed dose is the one place a midpoint enters, and scaling by a
            // constant carries it through, so `.water` says a midpoint is in it
            // while `.ratio` stays clear — the ratio was stated, not computed.
            waterFromRatio = true
            waterGrams = coffeeGrams * stated
            // Not the plain rule: a windowed DOSE scaled by a stated ratio puts
            // the dose's midpoint into the water, so the flag reads `coffee`.
            if wire.coffee?.isWindow == true { derived.insert(.water) }
            waterStatedByVolume = false
            waterMilliliters = nil
            yieldGrams = statedYield
            ratio = stated
        } else {
            // Neither a usable water nor a ratio that states a proportion: a
            // zero, a negative or an unreadable one fixes nothing. This is the
            // recipe the schema calls invalid.
            throw ImportError.validation(.missingRequiredField("water"))
        }

        derived.insert(.waterTemperature, ifWindow: wire.waterTemp)
        derived.insert(.pressure, ifWindow: wire.pressure)

        let (pours, readOnly, derivedPour) = pourSteps(from: wire.steps)
        if derivedPour { derived.insert(.steps) }
        // A ratio computed from midpointed operands is itself derived.
        if basis == .yield {
            if coffeeGrams > 0, wire.yield?.isWindow == true || wire.coffee?.isWindow == true {
                derived.insert(.ratio)
            }
        } else if !waterFromRatio, let water = waterGrams, water > 0,
                  wire.water?.isWindow == true || wire.coffee?.isWindow == true {
            // Not when the water came from the ratio: there the ratio is the
            // author's stated number, and no arithmetic of ours produced it.
            derived.insert(.ratio)
        }

        return ImportedRecipe(
            id: wire.id,
            title: title,
            coffeeGrams: coffeeGrams,
            waterGrams: waterGrams,
            ratio: ratio,
            waterStatedByVolume: waterStatedByVolume,
            waterMilliliters: waterMilliliters,
            waterTemperatureCelsius: wire.waterTemp?.effectiveCelsius,
            derivedQuantities: derived,
            basket: wire.basket,
            filter: wire.filter,
            grindDescription: grindDescription(wire.grind),
            grindSize: wire.grind?.size,
            pourSteps: pours,
            finishSeconds: wire.finishSeconds,
            methodSlug: wire.method,
            brewerLabel: gearLabel(wire.brewer),
            micronsApprox: wire.grind?.micronsApprox,
            readOnlySteps: readOnly,
            yieldGrams: yieldGrams,
            pressureBar: wire.pressure?.effectiveBar,
            preinfusionSeconds: wire.preinfusionSeconds,
            basis: basis,
            notes: wire.notes,
            additions: wire.additions ?? [],
            author: wire.author.flatMap(importedParty(from:)),
            basedOn: wire.basedOn,
            images: wire.images ?? [],
            description: wire.description,
            datePublished: wire.datePublished.flatMap(CalendarDay.init(iso8601:)),
            beanRef: wire.beanRef,
            recommended: wire.recommended ?? false)
    }

    /// Split the wire steps into timed pours and a read-only list. A step becomes
    /// a timed pour when it carries both `at_s` and a usable `to_water` —
    /// scheduled on its **data, not its `kind`**, so any water-bearing kind (a
    /// timed `bloom`, say) is coached rather than dropped. A windowed `to_water`
    /// schedules on the midpoint and reports it through `derivedPour`.
    ///
    /// A step with no schedulable pair is **surfaced, never dropped** — the
    /// spec's own espresso example is `{"kind": "tamp"}`, and an unmodeled step
    /// is displayed rather than an error. Only a step that states nothing at all
    /// is dropped. Array order is preserved throughout.
    ///
    /// `to_water` is carried through as **cumulative grams, exactly as sent**;
    /// rescaling to a consumer's storage model is the consumer's job.
    private static func pourSteps(
        from steps: [Step]?
    ) -> (pours: [ImportedPourStep], readOnly: [ImportedReadOnlyStep], derivedPour: Bool) {
        guard let steps else { return ([], [], false) }
        var pours: [ImportedPourStep] = []
        var readOnly: [ImportedReadOnlyStep] = []
        var derivedPour = false
        for step in steps {
            if let at = step.atSeconds, let cumulativeGrams = step.toWater?.effectiveGrams {
                if step.toWater?.isWindow == true { derivedPour = true }
                pours.append(ImportedPourStep(
                    atSeconds: at, cumulativeWaterGrams: cumulativeGrams,
                    label: step.label, instruction: nonEmpty(step.instruction),
                    kind: step.kind,
                    actionDurationSeconds: step.actionDurationSeconds))
            } else {
                let carried = ImportedReadOnlyStep(
                    kind: step.kind,
                    atSeconds: step.atSeconds,
                    actionDurationSeconds: step.actionDurationSeconds,
                    instruction: nonEmpty(step.instruction),
                    label: nonEmpty(step.label))
                if carried.statesSomething { readOnly.append(carried) }
            }
        }
        return (pours, readOnly, derivedPour)
    }

    /// Trimmed human text, or `nil` when the document stated only whitespace: a
    /// blank string states nothing, and `title` is trimmed on the same rule.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The explicit `label`, else `brand`+`model`, else nil. Never fails on an
    /// unrecognized `id`.
    private static func gearLabel(_ gear: Gear?) -> String? {
        guard let gear else { return nil }
        if let label = gear.label, !label.isEmpty { return label }
        let brandModel = [gear.brand, gear.model].compactMap { $0 }.joined(separator: " ")
        return brandModel.isEmpty ? nil : brandModel
    }

    /// The sender's grind composed into one display string, e.g. "Comandante
    /// C40, 22 clicks (~700µm)". Grinder scales are not portable, so this is
    /// shown faithfully and never converted.
    private static func grindDescription(_ grind: Grind?) -> String? {
        guard let grind else { return nil }
        var parts: [String] = []
        if let gear = gearLabel(grind.grinder) { parts.append(gear) }
        if let setting = grind.setting?.trimmingCharacters(in: .whitespacesAndNewlines),
           !setting.isEmpty {
            parts.append(setting)
        }
        var text = parts.joined(separator: ", ")
        if let microns = grind.micronsApprox {
            let approx = "~\(Int(microns.rounded()))µm"
            text = text.isEmpty ? approx : "\(text) (\(approx))"
        }
        return text.isEmpty ? nil : text
    }

    /// Project one wire tasting, deriving extraction yield where the three
    /// inputs exist. `recipes` is the already-imported collection, needed only
    /// for the dose and the fallback beverage mass.
    static func importedTasting(
        from wire: Tasting, recipes: [ImportedRecipe]
    ) -> ImportedTasting {
        let measuredYieldGrams = wire.measured?.yield?.grams
        var imported = ImportedTasting(
            id: wire.id,
            recipeRef: wire.recipeRef,
            beanRef: wire.beanRef,
            rating: wire.rating,
            perceivedExtraction: wire.perceived?.extraction,
            perceivedStrength: wire.perceived?.strength,
            descriptors: wire.descriptors ?? [],
            note: wire.note,
            lang: wire.lang,
            tds: wire.measured?.tds,
            measuredYieldGrams: measuredYieldGrams
        )
        imported.extractionYieldPercent = extractionYieldPercent(
            tds: wire.measured?.tds,
            measuredYieldGrams: measuredYieldGrams,
            recipe: recipes.referenced(by: wire.recipeRef))
        return imported
    }

    /// `(beverage mass × TDS %) ÷ dose`, in percent — the derivation the spec
    /// states and declines to store, so one quantity never has two homes that can
    /// disagree. The beverage mass is the tasting's own measured yield when it
    /// has one and the recipe's otherwise; the dose is the recipe's. `nil` on any
    /// missing or non-positive input.
    private static func extractionYieldPercent(
        tds: Double?, measuredYieldGrams: Double?, recipe: ImportedRecipe?
    ) -> Double? {
        guard let tds, tds > 0, let recipe, recipe.coffeeGrams > 0 else { return nil }
        guard let beverageGrams = measuredYieldGrams ?? recipe.yieldGrams, beverageGrams > 0
        else { return nil }
        let percent = (beverageGrams * tds) / recipe.coffeeGrams
        return percent.isFinite && percent > 0 ? percent : nil
    }

    /// Map a wire bean to a normalized `ImportedBean`: altitudes → meters,
    /// `roast_date` → ``CalendarDay``; everything else passed through
    /// (forward-compat).
    static func importedBean(from wire: Bean) -> ImportedBean {
        ImportedBean(
            id: wire.id,
            name: wire.name,
            roaster: wire.roaster.flatMap(importedParty(from:)),
            url: wire.url,
            images: wire.images ?? [],
            origin: importedOrigin(from: wire.origin),
            process: wire.process ?? [],
            dryingMethod: wire.dryingMethod,
            varietals: wire.varietals ?? [],
            roastLevel: wire.roastLevel,
            roastAgtron: wire.roastAgtron,
            restDays: wire.restDays,
            roastDate: wire.roastDate.flatMap(CalendarDay.init(iso8601:)),
            productionRoaster: wire.productionRoaster,
            decaf: wire.decaf,
            form: wire.form,
            preferredExtraction: wire.preferredExtraction,
            certifications: wire.certifications ?? [],
            roasterNotes: wire.roasterNotes ?? [],
            description: wire.description,
            lang: wire.lang)
    }

    /// A party without a non-empty `name` projects as `nil`, and the call site
    /// decides what that means: absent where the format credits one party (an
    /// `author`, a `roaster`), dropped where it credits a list (`producers`).
    /// Attribution metadata never fails an import either way. The name is
    /// trimmed, like `title`.
    private static func importedParty(from wire: Party) -> ImportedParty? {
        guard let name = wire.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return ImportedParty(name: name, url: wire.url, type: wire.type, role: wire.role)
    }

    private static func importedOrigin(from wire: Origin?) -> ImportedOrigin? {
        guard let wire else { return nil }
        return ImportedOrigin(
            type: wire.type,
            items: (wire.items ?? []).map(importedOriginItem(from:)))
    }

    private static func importedOriginItem(from wire: OriginItem) -> ImportedOriginItem {
        ImportedOriginItem(
            name: wire.name,
            country: wire.country,
            region: wire.region,
            producers: (wire.producers ?? []).compactMap(importedParty(from:)),
            altitude: importedAltitude(from: wire.altitude),
            process: wire.process ?? [],
            varietals: wire.varietals ?? [],
            harvestTime: wire.harvestTime,
            percentage: wire.percentage)
    }

    /// Canonical meters. An absent or unrecognized unit, or an all-empty band,
    /// reads as absent — the rule measurements follow.
    private static func importedAltitude(from wire: Altitude?) -> ImportedAltitude? {
        guard let wire, let unit = wire.unit.flatMap(KnownAltitudeUnit.init(rawValue:)) else {
            return nil
        }
        func meters(_ value: Double) -> Double {
            Measurement(value: value, unit: unit.foundationUnit).converted(to: .meters).value
        }
        let altitude = ImportedAltitude(
            valueMeters: wire.value.map(meters),
            minMeters: wire.min.map(meters),
            maxMeters: wire.max.map(meters))
        guard altitude.valueMeters != nil || altitude.minMeters != nil || altitude.maxMeters != nil else {
            return nil
        }
        return altitude
    }
}
