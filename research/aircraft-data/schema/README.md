# Aircraft structural preflight

**Status:** DATA-4a/b compatibility tooling plus AS-01 v2 dispatch; the Godot loader remains the flight authority.

The current fleet uses the [v2 contract](../../../AIRCRAFT_CONTRACT.md) and [v2 schema](../../../app/data/schema/openrc-aircraft-v2.schema.json). `check.py` selects v1 or v2 from each file’s declared format; unknown versions fail. The [v1 schema](../../../app/data/schema/openrc-aircraft-v1.schema.json) remains for historical experiments and supplies the reviewed numeric constraints used by the v2 generator. Both support editor association without adding `$schema` to aircraft files.

Run from the repository root (Python 3.12 tested):

```sh
python3 -m venv /tmp/openrc-schema-venv
/tmp/openrc-schema-venv/bin/python -m pip install -r research/aircraft-data/schema/requirements.txt
/tmp/openrc-schema-venv/bin/python research/aircraft-data/schema/check.py
/tmp/openrc-schema-venv/bin/python research/aircraft-data/schema/test_contract.py
/tmp/openrc-schema-venv/bin/python research/aircraft-data/schema/check_mutations.py
/tmp/openrc-schema-venv/bin/python research/aircraft-standardization/test_schema_v2.py --godot "$(app/get-godot.sh)"
```

On distributions without `venv` support, install their Python venv package first. All validator dependencies are pinned; they are development dependencies, not simulator dependencies. CI runs these commands before the generator checks and `app/test.sh`.

`check.py [file.json ...]` defaults to all eight catalog/electric files. It reports JSON-pointer paths and exits nonzero for invalid structure, unreadable/malformed JSON or numbers outside finite float64 range. It does not rewrite inputs. V2 rejects unknown keys and null modules. Only the explicit v1 branch retains ignored metadata and its historical optional/null behavior.

`test_contract.py` explicitly adapts current source files to v1, then independently mutates fixture data and calls the production `AircraftData.load_file()` in a single headless Godot process. It checks positive variants as well as refusals, checks the complete response sequence, and fails on engine errors. DATA-4b adds manually specified numeric endpoints and outside values, all 32 combinations of shaft/axis/normal-force/P-factor/slipstream presence, eight turbine option combinations, and transport/swirl restrictions. It also runs the eight schema mutations, including an overstrict endpoint, through the existing CI entry point. The existing E0b3b smooth-wake geometry supplies an additional synthetic opt-in fixture; its settings are test inputs, not calibration. Set `OPENRC_TEST_GODOT` to override the pinned engine and `OPENRC_SCHEMA_REPORT=/absolute/path/report.json` to retain case outcomes and source hashes.

Schema success does **not** prove physical validity. The loader still checks mass/CG consistency, inertia, area/planform relations, force/moment consistency, ordered tables, profile integrals, support geometry, and contact stability at the configured timestep. Eleven explicit counterexamples pin that distinction. The corpus is bounded: it does not exhaust every numeric boundary, metadata spelling, optional-feature combination or future loader change. In particular, coupled geometry/envelope bounds and contact-stability thresholds need dedicated fixtures; DATA-4's remaining mutation-equivalence coverage stays open.

When the loader gains a field, update the schema and add positive/negative fixtures together. Keep the schema manually reviewed against code; deriving it from the fleet alone would confuse observed values with permitted values.

References: [JSON Schema validation vocabulary](https://json-schema.org/draft/2020-12/json-schema-validation), [Python validator API](https://python-jsonschema.readthedocs.io/en/stable/validate/). Verification evidence: [DATA-4a](../../../docs/research/aircraft-validation/DATA-4a/README.md), [DATA-4b](../../../docs/research/aircraft-validation/DATA-4b/README.md).
