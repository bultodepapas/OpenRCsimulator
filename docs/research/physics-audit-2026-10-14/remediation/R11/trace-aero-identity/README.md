# R11 exported trace identity check

## Current-law metadata

The frozen-07 Linux executable completes its normal three-second trimmed-flight route, but the export checker rejects its declared R02 aerodynamic identity. The checker admitted only the historical global/local identities. This is a metadata compatibility omission, not a failed flight or a reason to rename the runtime law.

`app/tests/check_trimmed_flight.py` now additionally admits the exact string `section-plane-source-weighted-wake-velocity-v2 with bounded attached oracle`. All existing numeric, duration, finite-state, aircraft-byte-identity and metadata checks remain in place. Unknown or incomplete law strings still fail; no prefix matching or tolerance change was introduced. Frozen-07 remains unchanged, and this correction is a separately identified input to the derived package candidate.

The [process-level verification](verification.json) uses the retained [compiled Linux trace](../next-candidate/materialized-20261015-07-01/linux-exported-main-smoke-01.csv), with 721 samples for ticks 0–720, and verifies its exact Stik JSON hash. The [previous checker](previous-check_trimmed_flight.py) fails only on `aero_model`; the updated checker passes with all samples finite, 30 m altitude and 15 m/s final speed. Two disposable trace mutations—an unknown v99 law and a missing bounded-oracle suffix—both fail as processes with the metadata diagnostic. The original trace is unchanged.

The prior Windows checker SHA-256 is `369432c6c0d16f00295547a7e32f626fa815dc95e2fbde782aac4ce3c49fbc5e`; normalizing its CRLF bytes to LF reproduces frozen-07's exact `55c6d0f6a9ddf088c60de1050b964250f0af39ea36d1268574319273d9a69295`. The updated Windows checker SHA-256 is `bcaa40377bda39fc8e8e7a2be6753fc41441bf2901b0ca60d8c5feb11c203d81`. Commands, input hashes, exits and stdout/stderr are retained in the verification JSON. The existing broader trace-acceptance suite is qualified separately; these four process checks do not stand in for the whole application suite.

## Jet wheel-metadata negative control

The frozen trace-acceptance suite also exposes an independent stale mutation: `test_continuous_turbine_metadata_rejects_mixed_sampling` sets `wheel_profile_status` to `applied`, which is already the valid value in the Jet's integrated retractable-gear trace. The [actual-trace review](wheel-mutation-review-01.json) uses the retained frozen-07 Jet CSV and confirms that the baseline and this unchanged metadata both pass. Changing the value to `not-applied` fails with `wheel profile is not applied`.

The test now uses that invalid value and asserts that every proposed mutation differs from the valid trace before expecting rejection. The production wheel-metadata checker is unchanged; no accepted schema, numeric limit or physical behavior is relaxed. The [previous test](previous-test_trace_acceptance.py) and [source identity](test-source-before.json) retain the failed fixture. The repaired test SHA-256 is `77a9dab563051458cdbfad029e6b453dd2e583a55ee2bae05a7ed0064a1aea93`. This pure metadata review does not replace the separately recorded runtime test.

The [Linux supplemental run](../next-candidate/materialized-20261015-07-01/updated-checker-supplement-01/) keeps the frozen app and frozen test module, redirecting only the imported checker and checker subprocess path: 16 of 17 tests pass, with precisely this unchanged-value mutation remaining. The repaired live mutation test then passes separately against the frozen app. The two shaft-CLI tests previously rejected for `aero_model` also pass with the same checker redirect; their other eight tests had already passed in the original diagnostic tail. These scoped results do not claim a rerun of the canonical full suite.
