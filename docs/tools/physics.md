# Physics and flight tools

Use these tools to change, measure and compare simulated behavior. A software result is not physical validation. The [shared guide](shared.md) owns the engine, checked runner and suite; the [tool index](README.md) routes other tasks.

## Flight-test battery

The [flight-test card](../../research/flight-test/README.md) exercises fixed-wing session behavior and reports pilot validity and aircraft response. For flight-feel, controls or physics tuning, first preserve an `.orfl` baseline and verify exact replay under the [flight logging workflow](#flight-log-and-replay); the card is complementary evidence, not a replacement for that comparison.

Freeze the baseline source and engine before editing. Use a separate full source checkout for the candidate, starting from the same snapshot, then change one owning source and regenerate its outputs there. Preserve the app, adjacent assets, card/runner files, configuration and identity of both snapshots. A detached checkout at `HEAD` does not include uncommitted changes unless they are deliberately copied into it. Import each app copy before running Godot. The [FT-04 record](../research/flight-test/FT-04/README.md) explains why comparisons on a moving shared tree can attribute unrelated changes to the candidate.

From the frozen baseline checkout, use the same card runner and engine for both flights. Replace the two placeholders and use fresh output paths:

```bash
FT_GODOT="$(app/get-godot.sh)"
FT_AIRCRAFT='replace-with-catalog-id'
FT_CANDIDATE='/absolute/path/to/candidate-checkout'
FT_TESTS=trim_sweep,stall_power_off,vmax,roll_rate
python3 research/flight-test/run.py --godot "$FT_GODOT" --out tmp/ft-base \
  --aircraft "$FT_AIRCRAFT" --only "$FT_TESTS"
python3 research/flight-test/run.py --godot "$FT_GODOT" --out tmp/ft-candidate \
  --aircraft "$FT_AIRCRAFT" --only "$FT_TESTS" --app "$FT_CANDIDATE/app"
python3 research/flight-test/compare.py tmp/ft-base tmp/ft-candidate --out tmp/ft-compare.md
```

Discover aircraft through the card's `--list` command in the [card guide](../../research/flight-test/README.md#standard-workflow), not a copied catalog. Check that the selected test names all appear in `profile.json`: `--only` silently ignores unknown names, including a typo mixed with valid names. Speed-dependent tests need the trim, stall and maximum-speed tests in the same selection. Inspect each test's `valid` result and explain every comparison change; an invalid pilot or an unchanged model prediction is not a realism verdict. Use matching aircraft and test selections, and `--shared-tests` only when intentionally comparing common tests.

The runner records its own checkout's Git identity and the selected aircraft-data hash; `--app` records the candidate path, not a complete candidate checkout identity. Record the candidate commit, dirty paths and relevant generator/data/model hashes separately. Direct session tests use the reference backend by default; they do not prove the application's backend selection or attached observer performance. See the [native selection contract](../../research/native-kernel/README.md#normal-flight-backend-selection).

## Aircraft data and generators

Find the aircraft's owning source and generator in the [ownership registry](../README.md#tracks-plans-and-step-ids) and [aircraft authoring contract](../AIRCRAFT_CONTRACT.md#add-an-aircraft-using-supported-laws). Change source inputs and regenerate; never hand-edit generated aircraft geometry or physics data. Some files combine authored fields with generated sections: for example, [GP-07](../research/ground-physics/GP-07/README.md) owns the Stik's generated hull fields. Follow the owner for the field being changed rather than treating the entire JSON as hand-authored.

Check baseline freshness before changing a generator, follow its dependency order, run its supported `--check`, then load the generated result through the production validator. Refresh affected variants, model manifests, Workshop descriptors and presentation bindings through their own generators. The [Workshop generation sequence](../TOOLS.md#aircraft-workshop) and each aircraft guide own the commands; preserve their byte and line-ending rules. A reproducible generator does not establish that its physical inputs are measured.

## Flight log and replay

The [flight-log manual](../FLIGHT-LOGGING.md) owns recording, export, exact replay, candidate replay and plotting. Preserve the baseline `.orfl`, verify its complete exact replay before making one candidate, and compare the same tick/input tape. Retain markers, source/configuration and solver identities, CSV and reports. Check `complete` and `solver_changed`; a candidate run or recovered prefix is not exact equivalence or physical validation.

For an editor/source recording use the matching engine and backend. A packaged recording must use its matching verified executable for replay/export; see the [package identity rules](../FLIGHT-LOGGING.md#quick-start). The CLI chooses an OS-specific pinned engine unless `--godot` or `GODOT` is supplied.

## Golden flights

Check existing physics goldens with the [checked runner](shared.md#one-godot-script):

```bash
python3 tools/godot/run_checked.py --timeout 300 -- "$(app/get-godot.sh)" \
  --headless --path app --script res://tests/test_golden.gd
```

A physics change may alter recorded trajectories. Re-record with `res://tests/record_golden.gd` only for an intentional, explained change; do not overwrite goldens to conceal an unexplained failure. Keep the baseline and comparison evidence with the owning track.

## Headless trace checks

Use the matching trace validator and supply the requested duration, so a truncated run cannot pass solely on valid rows. Replace `3.0` with the actual requested seconds:

```bash
python3 app/tests/check_trimmed_flight.py tmp/trace.csv --duration 3.0
python3 app/tests/check_wind_trace.py tmp/wind.csv --duration 3.0
python3 app/tests/check_atmosphere_trace.py tmp/atmosphere.csv --duration 3.0
```

For atmosphere v11 standard-column traces, add `--column` only for the calm preset (zero wind, gust and turbulence). Without it, the atmosphere validator uses the custom-atmosphere v6/v10 path. See [launch flags](shared.md#launch-flags), [wind recording](../WIND-PLAN.md#recording-and-evidence) and [trace integrity](../research/trace-integrity/C7-R2/README.md).

## Benches and probes

Run benchmarks on a quiet target host with frozen sources and recorded conditions. A headless session or component probe does not establish complete-application cost or display performance; include accepted-tick observers and actual rendering for those claims. [Performance tools](../../research/performance/README.md) and the [native backend guide](../../research/native-kernel/README.md#normal-flight-backend-selection) own workload and backend selection.

| Task | Tool / limit |
| --- | --- |
| Reference session cost | Run `app/tests/bench_physics.gd` through the [checked runner](shared.md#one-godot-script). It reports best-of-three session timings without product observers, and an unknown `--aircraft` ID silently selects the default; check the ID against the catalog before running it. It is not a Gate P percentile or whole-app benchmark. |
| Other physics and full-app timings | [Session performance tools](../../research/performance/README.md), including complete callback and observer workloads. |
| Parameter sensitivity | `research/sensitivity/sensitivity.gd`; [sensitivity evidence](../research/README.md#flight-model-and-simulation). |
| Part-throttle thrust and neutral points | [Power-climb tools](../../research/flight-dynamics/power-climb/README.md). |
| Modal dashboard | `research/validation/dashboard.py --check`; it recomputes against the current source and engine. A stale or platform-incompatible snapshot is not a physical failure; see [validation tools](../../research/validation/README.md). |
| Workshop experiment runner | [Aircraft Workshop tools](../TOOLS.md#aircraft-workshop) for static, tape and sweep analysis. |

### Spatial wind workload verification and timing

Use `app/tests/bench_spatial_wind.gd` through the checked runner. Its provider-only and full-session workloads answer different questions. Replace the aircraft placeholder and use a fresh output path:

```bash
python3 tools/godot/run_checked.py --timeout 600 -- "$(app/get-godot.sh)" \
  --headless --path app --script res://tests/bench_spatial_wind.gd -- \
  --full-session --verify-only --aircraft=replace-with-catalog-id \
  --case=spatial-v5-gusts-thermals-24 --output=tmp/wind-verify-new.json
```

`--verify-only` exercises workload and query-coverage checks without timing. For timing, omit it and run paired measurements on a controlled host. The report's median/p95 are batch means, not per-tick latency percentiles; headless timing does not qualify the 1080p presentation path. [Workloads, identities and limits](../research/wind-implementation/M5-W05d-R5/README.md).

## Aircraft conformance and unchanged behavior

Capture a baseline before a behavior-preserving edit and write each report to a fresh directory: `conformance.py` overwrites existing output files. Use the same engine, platform and verifier source for the before/after comparison.

```bash
python3 research/aircraft-standardization/conformance.py --godot "$(app/get-godot.sh)" \
  --out tmp/aircraft-contract-before
# Apply the intended edit and regenerate its outputs before collecting the after report.
python3 research/aircraft-standardization/conformance.py --godot "$(app/get-godot.sh)" \
  --out tmp/aircraft-contract-after \
  --baseline tmp/aircraft-contract-before/fleet.json \
  --contact-baseline tmp/aircraft-contract-before/contacts.json
```

In the after `verification.json`, require `ok`, `flight_comparison.complete_fleet`, `flight_comparison.baseline_complete`, both `exact_baseline_match` fields, and no source drift. The verifier checks the declared catalog cases and replay/contact fixtures; equality covers only those runs on that engine and platform. V1 reports are not v2 baselines. `--parse-all` adds the parse pass; `--package` checks exported resources; `--models-only` omits flight/contact evidence. The [aircraft contract](../AIRCRAFT_CONTRACT.md) owns admission and [AS-07/14-R1](../research/aircraft-standardization/AS-06-14/README.md#shared-flight-admission-as-0714-r1-2026-10-26) describes coverage.

## Track verifiers

Use the pinned engine, checked runner for Godot scripts, isolated profiles and fresh output directories. Verification establishes the stated software property, not physical fidelity.

| Area | Entrypoint / authoritative contract |
| --- | --- |
| Aircraft authoring | [Conformance workflow](#aircraft-conformance-and-unchanged-behavior); [aircraft contract](../AIRCRAFT_CONTRACT.md). |
| Natural Random | `python3 research/natural-random/verify.py --godot <engine> --out <fresh-dir>`; [evidence](../research/natural-random/README.md). |
| Glow 2T/4T | `python3 research/glow-engines/verify_integration.py --godot <engine> --out <fresh-dir> --parse-all`; [glow guide](../GLOW-ENGINES.md). |
| Helicopter | `python3 research/helicopter/verify_kernels.py --godot <engine> --out <fresh-dir>`; [session and limits](../HELICOPTER.md). |
| Ground vehicle | [Runtime and experiments](../../research/rc-monster-truck/README.md); [native builder and parity](../../research/rc-monster-truck/native/README.md). |
| Electric coupling | [EL2a-P1](../../research/propulsion/el2a-p1/README.md), [EL2a-P2](../../research/propulsion/el2a-p2/README.md); reference solvers use their pinned Python dependencies. |
| Crash-hull coverage | [GP-07 tools and generator](../../research/ground-physics/gp07/README.md); dump the built model with the checked runner, then run the coverage sweep. |
| Taildragger and nose-over | [E5a](../../research/ground-contact/e5a/README.md), [E5b](../../research/ground-contact/e5b/README.md); mutation runs use disposable copies. |
| Long-circuit sensitivity | [E4b tool](../../research/landing/e4b/README.md), [limits](../research/ground-contact/E4b/README.md); completion does not mean every perturbation passed. |
| Radio calibration | `python3 research/input/d6b-r2/verify.py --out <fresh-dir>`; [contract](../research/radio-input/D6b-R2/README.md). |

The [research index](../research/README.md) maps dated evidence; the [research tool map](../../research/README.md) pairs experiment folders with their reports.
