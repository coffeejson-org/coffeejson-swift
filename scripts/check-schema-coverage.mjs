#!/usr/bin/env node
// Fields the schema declares that a reference implementation cannot read. JSON
// decoding skips keys a type does not name, so a field can land in the schema
// and reach no reader with every test green. This walks `$defs` (where `grind`
// and `step` live) and matches PER TYPE — a global text match would pass
// `originItem.name` because `Party` declares a `name`. A coverage check, not a
// conformance check: it proves a key is named on the right type, not mapped.
// Pure functions over injected sources, so the harness can prove the check
// catches seeded drift.

// A schema $def, and the type that reads it in each stack. Measurement defs
// share one type on purpose. A $def missing here is REPORTED, not skipped, so
// a new one must be mapped deliberately.
export const OWNER = {
  document:             { ts: ["CoffeeJSONDocument"], swift: ["Document"] },
  // The TypeScript type is `DocumentGenerator`, not `Generator`: the short name
  // shadows TypeScript's own `Generator<T, TReturn, TNext>`. The wire member is
  // still `generator`, so the type name and the member name do not match, and
  // both names are listed.
  "document.generator": { ts: ["DocumentGenerator", "Generator"], swift: ["Generator"] },
  "bean.rest_days":     { ts: ["Bean"],               swift: ["RestDays"] },
  recipe:               { ts: ["Recipe"],             swift: ["Recipe"] },
  bean:                 { ts: ["Bean"],               swift: ["Bean"] },
  tasting:              { ts: ["Tasting"],            swift: ["Tasting"] },
  "tasting.perceived":  { ts: ["PerceivedAxes"],      swift: ["PerceivedAxes"] },
  "tasting.measured":   { ts: ["MeasuredCup"],        swift: ["MeasuredCup"] },
  step:                 { ts: ["Step"],               swift: ["Step"] },
  grind:                { ts: ["Grind"],              swift: ["Grind"] },
  gear:                 { ts: ["GearRef"],            swift: ["Gear"] },
  filter:               { ts: ["Filter"],             swift: ["Filter"] },
  addition:             { ts: ["Addition"],           swift: ["Addition"] },
  party:                { ts: ["Party"],              swift: ["Party"] },
  origin:               { ts: ["Bean"],               swift: ["Origin"] },
  originItem:           { ts: ["Bean"],               swift: ["OriginItem"] },
  altitude:             { ts: ["Bean"],               swift: ["Altitude", "Quantity"] },
  massMeasurement:      { ts: ["Measurement"],        swift: ["Quantity"] },
  waterMeasurement:     { ts: ["Measurement"],        swift: ["Quantity"] },
  tempMeasurement:      { ts: ["Measurement"],        swift: ["Quantity"] },
  pressureMeasurement:  { ts: ["Measurement"],        swift: ["Quantity"] },
  recipeLocalization:   { ts: ["RecipeLocalization"], swift: ["RecipeLocalization"] },
  beanLocalization:     { ts: ["BeanLocalization"],   swift: ["BeanLocalization"] },
  stepLocalization:     { ts: ["StepLocalization"],   swift: ["StepLocalization"] },
};

/** Every wire key the schema declares, as `<owning $def>.<key>`. */
export function wireKeys(schema) {
  const keys = new Set();
  const walk = (node, owner) => {
    if (!node || typeof node !== "object") return;
    if (node.properties)
      for (const k of Object.keys(node.properties)) {
        keys.add(`${owner}.${k}`);
        // An inline object declares its own scope. Without this, `generator`'s
        // members read as members of the document and `rest_days`' as members
        // of the bean, so the check looks for them on the wrong type.
        const sub = node.properties[k];
        const nested = sub && typeof sub === "object" && (sub.properties || sub.items?.properties);
        walk(sub, nested ? `${owner}.${k}` : owner);
      }
    if (node.items) walk(node.items, owner);
    // Conditional branches are walked too: a key that appears only inside a
    // `then` is still a key an implementation must read.
    for (const kw of ["allOf", "anyOf", "oneOf"]) if (node[kw]) node[kw].forEach((n) => walk(n, owner));
    for (const kw of ["if", "then", "else"]) if (node[kw]) walk(node[kw], owner);
    if (node.$defs) for (const k of Object.keys(node.$defs)) walk(node.$defs[k], k);
  };
  walk(schema, "document");
  return keys;
}

/** The body of a named type, brace-matched from its declaration. Nested braces
 *  belong to the body — an inline object literal in a TS interface is part of
 *  the type that declares it, which is how `Bean.origin.items[]` is reached. */
function body(source, re) {
  const m = re.exec(source);
  if (!m) return null;
  const open = source.indexOf("{", m.index);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}" && --depth === 0) return source.slice(open, i + 1);
  }
  return null;
}

const camel = (k) => k.replace(/_([a-z])/g, (_, c) => c.toUpperCase());

const READS = {
  ts: (source, name, key) => {
    const b = body(source, new RegExp(`export (?:interface|type) ${name}\\b`));
    return !!b && new RegExp(`(^|[\\s{;])${key}\\??\\s*:`, "m").test(b);
  },
  // `public` is load-bearing, not decoration: every wire property is public
  // and no local binding is, so a `let name` inside a custom `init(from:)`
  // cannot count as the type declaring `name`.
  swift: (source, name, key) => {
    const b = body(source, new RegExp(`(?:struct|enum|final class) ${name}\\b`));
    return !!b && (b.includes(`"${key}"`) || new RegExp(`\\bpublic (?:var|let) ${camel(key)}\\b`).test(b));
  },
};

/**
 * @param schema   parsed docs/schema/coffeejson-1.0.schema.json
 * @param sources  { ts?: string, swift?: string } — concatenated source text
 *                 per stack. A stack absent here is not checked, so a repo that
 *                 holds only one implementation checks only that one.
 * @returns [{ label, error }] — error null on pass
 */
export function coverageFindings(schema, sources) {
  const findings = [];
  const stacks = Object.keys(READS).filter((s) => typeof sources[s] === "string");
  const gaps = Object.fromEntries(stacks.map((s) => [s, []]));
  const unmapped = [];

  for (const key of [...wireKeys(schema)].sort()) {
    const cut = key.lastIndexOf(".");
    const [def, bare] = [key.slice(0, cut), key.slice(cut + 1)];
    const owner = OWNER[def];
    if (!owner) {
      unmapped.push(key);
      continue;
    }
    for (const stack of stacks)
      if (!owner[stack].some((name) => READS[stack](sources[stack], name, bare))) gaps[stack].push(key);
  }

  for (const stack of stacks)
    findings.push({
      label: `${stack} names every schema key`,
      error: gaps[stack].length ? `${gaps[stack].length} unnamed: ${gaps[stack].join(", ")}` : null,
    });
  findings.push({
    label: "every $def is mapped to a type",
    error: unmapped.length ? `unmapped $def(s): ${unmapped.join(", ")}` : null,
  });
  return findings;
}

// ── CLI ──────────────────────────────────────────────────────────────────────
//
//   node scripts/check-schema-coverage.mjs [path-to-the-spec-repo]
//
// Exit 0 = this package names every key the schema declares · 1 = a gap · 2 =
// could not run. The schema is not vendored here on purpose: a copy is a copy,
// and a stale one would let this check pass against a format that has moved on.
// The spec repo is public (github.com/coffeejson-org/coffeejson) — clone it
// beside this one, or let CI check it out.
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const here = fileURLToPath(new URL("..", import.meta.url));
  const specRepo = process.argv[2] ?? join(here, "..", "coffeejson");
  const schemaPath = join(specRepo, "docs/schema/coffeejson-1.0.schema.json");
  const sourcesDir = join(here, "Sources/CoffeeJSON");

  for (const [label, path] of [["schema", schemaPath], ["swift sources", sourcesDir]])
    if (!existsSync(path)) {
      console.error(`no ${label} at ${path} — pass the spec repo's path as an argument`);
      process.exit(2);
    }

  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  const swift = readdirSync(sourcesDir, { recursive: true })
    .filter((f) => String(f).endsWith(".swift"))
    .map((f) => readFileSync(join(sourcesDir, String(f)), "utf8"))
    .join("\n");

  const findings = coverageFindings(schema, { swift });
  console.log(`schema wire keys: ${wireKeys(schema).size}`);
  for (const { label, error } of findings) console.log(error ? `FAIL ${label} — ${error}` : `ok   ${label}`);

  // A green run has to be provable, not assumed: an undeclared key is skipped
  // silently by every decoder here, so nothing else in this package can fail on
  // one. If the seeded gap does not register, the check is not checking.
  const ghosted = structuredClone(schema);
  ghosted.$defs.tasting.properties.ghost_key = { type: "string" };
  if (!coverageFindings(ghosted, { swift }).some((f) => f.error?.includes("tasting.ghost_key"))) {
    console.error("FAIL probe — a seeded schema key nobody names produced no finding");
    process.exit(1);
  }
  console.log("ok   probe: a schema key no type names is caught");

  process.exit(findings.some((f) => f.error) ? 1 : 0);
}
