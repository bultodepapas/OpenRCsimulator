# DATA-4a — offline aircraft structural contract

**Status:** verification in progress. Scope: schema, offline preflight, loader comparison and CI; no runtime or aircraft-data changes.

## Contract

The JSON Schema 2020-12 preflight covers the current v1 fleet and opt-in smooth-wake structure: provenance, exact units, dimensions, per-field ranges, and glow/shaft/turbine alternatives. Unknown metadata stays allowed. Cross-field physical consistency remains with `AircraftData.load_file()`.

The test corpus is independent of the schema: it walks representative quantity paths in the four real files and a synthetic smooth-wake fixture, then changes one field at a time. It also exercises optional/null/empty cases, branch restrictions, malformed containers, and three physically inconsistent but structurally valid inputs. A single production-loader process must return every case in order without engine errors. This is software verification, not evidence of aerodynamic fidelity.

## Verification

- All four fleet files pass the preflight; malformed input produces a nonzero CLI exit with a field path.
- **1,469 schema/loader cases pass**, including **24 valid controls**, the synthetic smooth-wake branch, and **three runtime-only counterexamples**. Reproduced in a fresh checkout: [case outcomes and input hashes](agreement.json), [test log](contract.log).
- Three in-memory schema mutations are detected: dropping the unit requirement, scalar type, and vector width. [Mutation outcomes](mutations.json); rerun `research/aircraft-data/schema/check_mutations.py`.
- CI syntax passes `actionlint`. Godot parses the offline probe; the project linter reports zero errors and the same 12 warnings before/after.
- Full isolated `app/test.sh`: pending final completion. The shared-tree baseline passed all 132 sections, but concurrent edits make the isolated run the release evidence.

## Findings

- A schema inferred from sample files would require `aero.conventions`, although the loader defaults an absent object to `{}`. A positive omission case caught the first schema version's overrestriction.
- Godot's source trimming accepts NBSP and EM SPACE but rejects ASCII control-only source strings. A Unicode `\S` expression would silently narrow the runtime contract. Explicit ASCII bounds and live loader cases preserve existing behavior.
- Optional fields differ: gear permits null or an empty object; steering, breakaway factor and horizontal downwash permit null; other present blocks still require complete quantities. Preserve these cases explicitly.
- The standalone reader rejects NaN, infinities and float64 overflow, including integer-shaped overflow. Schema validity alone cannot guarantee a finite runtime number.

## Reproduction and limits

See [tool commands and maintenance rules](../../../../research/aircraft-data/schema/README.md). The validator dependency set is pinned. The schema follows the [2020-12 validation vocabulary](https://json-schema.org/draft/2020-12/json-schema-validation) and uses the [Python validator API](https://python-jsonschema.readthedocs.io/en/stable/validate/).

The bounded corpus does not establish equivalence for every possible malformed input or feature combination. DATA-4 remains open for expanded coverage. Existing geometry, mass-property and flight-model calibration gaps are unchanged.
