# AS-04: Historical v1 schema and loader compatibility

2026-10-11 · Prefix: AS-

**Status: Passed.** The existing v1 contract suite exercises explicitly migrated v1 payloads even though the live fleet now stores v2 data.

Ran `research/aircraft-data/schema/test_contract.py` with `OPENRC_TEST_GODOT` set to `.tools/Godot_v4.7.2-stable_win64_console.exe` (Godot `4.7.2.stable.official.ed1daf0bf`; SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`). The runner reported **1,873 schema/loader cases, 142 valid controls, and 20 runtime-only checks**. All four Python tests passed in 74.773 seconds, including schema/loader agreement, nonfinite JSON rejection, schema-mutation detection, and CLI diagnostics.

`cases.py` converts each current fleet input through `research/aircraft-standardization/migrate.py:legacy_input` before making the v1 mutations. This keeps the historical permissive assertions meaningful after fleet migration. The catalog's production-v2 format/ID guard is separately enforced in `FlightSession._prepare_aircraft`; this suite intentionally tests legacy parser compatibility, not that catalog guard. No fixture or acceptance assertion needed changes.

The independent AS-01 suite continues to cover strict v2 schema/runtime behavior. The broader `app/test.sh` run was active separately and is not represented by this result.
