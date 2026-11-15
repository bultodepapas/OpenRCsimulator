# Verification scope, reproducibility and limits

## Identity and execution boundary

The audited application is commit `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`. All application source and data remained identical to that baseline. The candidate change is in the research flight-card harness, tests and documentation; campaign `run.json` files identify the baseline and relevant dirty harness paths. They do not claim that the whole audit worktree was clean. The [source identity record](evidence/source-identity.json) retains the baseline application tree, engine digest, candidate harness/probe hashes and application-diff result. The commit containing this report identifies the published candidate.

The engine was the official pinned Linux x86-64 `4.8.beta2.official.cafc17a19`, not the separately installed system Godot. Its executable SHA-512 was:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

This workspace was not enrolled in the project's test pool (`tools/testqueue/testctl.py pool hosts` found no pool configuration). Numerical work used the existing checked runner locally, headless, with isolated `XDG_DATA_HOME` profiles. The checked runner judges engine diagnostics as well as exit status and required completion text. Tests and campaigns ran concurrently where independent; their wall times are not performance measurements. No native Mac package, GPU, physical transmitter or real aircraft was used. No `.orfl` baseline was re-recorded or golden updated.

## Accepted focused software checks

Every row below has a complete retained checked report with process exit 0 and no runner-detected engine errors/warnings. Some logs print `aircraft data warning:` provenance/plausibility text that is not a Godot warning diagnostic; those messages remain in the logs and are not erased by the clean checked verdict.

| Check | Observed result | Retained receipt under `evidence/checks/` |
| --- | --- | --- |
| Aerodynamic baseline | 23 checks, 0 failed | [aero-baseline-6rciyesa](evidence/checks/aero-baseline-6rciyesa/) |
| Aircraft data | 88 checks, 0 failed | [test_aircraft_data-1fqob_0a](evidence/checks/test_aircraft_data-1fqob_0a/) |
| Stall solver | 571 checks, 0 failed | [test_stall_solver-nzb_8jyj](evidence/checks/test_stall_solver-nzb_8jyj/) |
| Mass inventory | 65 checks, 0 failed | [test_mass_inventory-q3fwdhg5](evidence/checks/test_mass_inventory-q3fwdhg5/) |
| Raw-axis history | 9,252 checks, 0 failed | [test_rc_axis_history-kof73h64](evidence/checks/test_rc_axis_history-kof73h64/) |
| Calibration | 49 checks, 0 failed | [test_rc_calibration-v3sehegu](evidence/checks/test_rc_calibration-v3sehegu/) |
| Propeller table continuity | 49 checks, 0 failed | [test_propeller_table_continuity-restored-assets-g8iq1ivl](evidence/checks/test_propeller_table_continuity-restored-assets-g8iq1ivl/) |
| Aero flow/local loads | 25,000 H4 and 25,001 H12 byte-exact comparisons, 0 failed | [test_aero_flow-restored-assets-snovvyp4](evidence/checks/test_aero_flow-restored-assets-snovvyp4/) |
| Electric session | 98 checks, 0 failed | [test_electric_session-restored-assets-ue7jeiok](evidence/checks/test_electric_session-restored-assets-ue7jeiok/) |
| Basic golden trajectories | Four flights of 600/720/720/1,200 ticks, 0 failed | [test_golden-restored-assets-bqrn94jg](evidence/checks/test_golden-restored-assets-bqrn94jg/) |
| Electric Stik installation | 32 checks, 0 failed, including the test's exact one-second pack checkpoint replay | [stik-electric-installation-twsblcd4](evidence/checks/stik-electric-installation-twsblcd4/) |
| Rates/input shaping | 86 checks, 0 failed, including exact 120-tick replay across rate switches | [test_rates-correct-path-i14v2qwd](evidence/checks/test_rates-correct-path-i14v2qwd/) |
| Sampled servos | 6 checks, 0 failed | [test_servo-correct-path-b70zsz65](evidence/checks/test_servo-correct-path-b70zsz65/) |
| Injected input reproductions | Five checks, 0 failed; confirms existing edge cases, not repaired input behavior | [controls report](evidence/controls-report.json), [values](evidence/controls-probe.json) |
| Prescribed-state physics probe | Required `AUDIT_PROBE_COMPLETE`, structured production-law values | [physics report](evidence/physics-report.json), [values](evidence/physics-probe.json) |
| Candidate flight-card parse | Clean parser result | [flight-card-parse-oepictc9](evidence/checks/flight-card-parse-oepictc9/) |

The golden check uses numerical tolerances (largest printed position difference about 7.1×10⁻¹⁵ m); it is **not** a full exact `.orfl` replay. The rates and electric installation tests do contain their own narrowly scoped exact replays. These separate claims must not be combined into “all replays/native/physics qualified.” Existing passing tests intentionally permit several documented estimates/limitations; passing them does not invalidate the audit findings.

## Card campaigns

| Campaign | Actual source/mode | Requested roster and outcome | Evidence |
| --- | --- | --- | --- |
| All eleven technical fixed-wing aircraft | Catalog main data; electric Stik, Turbo Lumber and MoonRunner therefore use ideal supply | `trim_sweep,aero_sweep,modes`; 3/3 valid each, all identities/rosters match, all exits 0/no script errors | [run](evidence/fleet-static/run.json), [summary](evidence/fleet-static/summary.md) and individual profiles/logs |
| Four-aircraft dynamics | Basic Stik, ideal Electric 6S, 61FX, Extra | Eight named cases below; 8/8 valid each, all identities/rosters match, all exits 0/no script errors | [run](evidence/dynamic/run.json), [summary](evidence/dynamic/summary.md) |
| Electric finite pack | Explicit `app/data/aircraft/battery/stik_electric_6s_pack.json` override; modeled full initial pack | Same eight cases; 8/8 valid, matching aircraft identity and file hash | [run](evidence/electric-pack/run.json), [summary](evidence/electric-pack/summary.md) |

This is 73 requested result entries across sixteen campaign aircraft/configuration runs, including repeated trim work. It is not 73 independent physical experiments, eleven complete forty-case flight cards, or a complete game regression. `valid` is the case's own test-pilot/result criterion. Missing modes, fallback speeds, control saturation and derived orientation thresholds have the limitations explained in [fleet comparison](fleet-comparison.md).

Equivalent reproduction commands from the repository root are:

```bash
python research/flight-test/run.py \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64 \
  --out tmp/ugly-audit-fleet-static --aircraft all \
  --only trim_sweep,aero_sweep,modes --jobs 3 --timeout 600

python research/flight-test/run.py \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64 \
  --out tmp/ugly-audit-dynamic \
  --aircraft jensen-das-ugly-stik-60,stik-electric-6s,stik-glow-61fx-2t,gp-extra-300s-60 \
  --only trim_sweep,stall_power_off,vmax,roll_rate,pitch_pull,throttle_response,hands_off,power_step \
  --jobs 2 --timeout 900

python research/flight-test/run.py \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64 \
  --out tmp/ugly-audit-electric-pack --aircraft stik-electric-6s \
  --data app/data/aircraft/battery/stik_electric_6s_pack.json \
  --only trim_sweep,stall_power_off,vmax,roll_rate,pitch_pull,throttle_response,hands_off,power_step \
  --jobs 1 --timeout 900
```

Set an isolated `XDG_DATA_HOME` when reproducing in an interactive development installation. Use a clean new output directory; the wrapper enforces its existing overwrite boundary. Follow the current test-pool requirements on enrolled machines. Godot's `--script` should be an absolute path or a correct `res://` path after `--path app`; an `app/tests/...` relative script path incorrectly becomes `res://app/tests/...`.

Individual profiles/logs and manifests are retained in full. The 85 raw dynamic CSV files total approximately 11.9 MB and are not all committed; their SHA-256 values, row counts and unmodified selected rows around cited observations are in [trace-observations.json](evidence/trace-observations.json). The [extractor and probe instructions](../../../research/ugly-stik-audit-2026-11-15/README.md) reproduce them. CSV cadence is 20 Hz while event detection runs at 240 Hz; a closest exported row is not necessarily the exact event sample. Raw source values remain strings to preserve their recorded precision.

## Runner repair verification

The [pre-fix Python output](evidence/runner-before.txt) records four failures and seven errors from the expanded regression suite against the old runner. In particular, empty/incomplete requested cards returned success in mocked-child scenarios. The [final output](evidence/runner-final.txt) records all fourteen test methods passing after the repair. Mocks isolate wrapper behavior; they do not substitute for the actual card runs above.

An unchanged copy of baseline `flight_test.gd`, placed beside its original relative dependencies, was executed on the pinned engine after the required numerical assets were restored:

- `--only=not_a_test` produced a **clean exit 0 with no engine errors and an empty `results` object**. Its clean checked verdict measures process/log cleanliness only and confirms the missing-selection defect. [Original comparison receipt](evidence/original-comparison.json), [empty profile](evidence/baseline-invalid/profile.json).
- Baseline `trim_sweep,aero_sweep,modes` produced a profile exactly equal to the candidate's basic-Stik profile after recursively removing only `wall_s`. Source IDs, values, notes, order and metadata remained equal. [Baseline profile](evidence/baseline-comparison/profile.json).
- Independent source comparison found all forty old `(name, callable-expression)` pairs identical and in the same order in the new registry. See [independent review](independent-review.md).

Four malformed direct candidate selections (unknown, mixed unknown, empty, duplicate) each exit 2 with the expected diagnostic and create no output directory. [Expected rejection receipt](evidence/direct-rejections.json). A generic checked runner marks these nonzero/error runs unsuccessful by design; that is not a failed regression expectation. The wrapper unit tests and independent disposable sentinel also verify invalid aircraft paths cannot overwrite an outside file. `--aircraft all` necessarily runs discovery before validating its returned names; those names are checked before per-aircraft writes/jobs, not before the discovery call itself.

## Failed or limited attempts retained

All checked reports/logs, including unsuccessful attempts, are indexed in [checked-runs.json](evidence/checked-runs.json). None of the following is silently relabeled a pass:

1. **Incomplete sparse-checkout dependencies:** early numerical session/golden/flow attempts logged 118 engine diagnostics even when numerical assertions printed passing output. Required exact baseline blobs were restored and the relevant numerical checks rerun cleanly. The original failures identify this audit environment and dependency coupling, not a shipped missing-asset defect.
2. **Editor import diagnostics:** checked import attempts exited 0 but reported two “parent and popup a dialog” engine errors. They were rejected as clean gates. Subsequent standalone numerical tests were independently checked. Asset import progress alone does not override an error verdict.
3. **Three initial rates/servo/stock commands used an incorrect relative script path:** all failed before executing their test. Correct absolute paths produced the accepted rates/servo runs above. The mistakes are retained as invocation errors, not product findings.
4. **Stock-selection UI test:** its first correct-path attempt timed out with 182 errors in missing visual-resource preloads. After restoring 32 exact baseline resources and importing them, a later run printed zero logical assertion failures and exited 0, but the checked runner rejected **351 errors and five warnings**. Further textures/models and all sixteen tracked shader-include files were absent from this sparse checkout; dummy-renderer shader tokenizer and cleanup errors also appeared. Source triage cannot separate missing includes from other preprocessing/renderer behavior. This UI gate remains unqualified; a complete resource checkout/import and an appropriate renderer are needed. The source-route audit and numerical catalog discovery remain valid within their stated scopes. See the [supplemental controls report](controls-feel-and-performance.md) and [actual failed receipt](evidence/checks/test_stik_stock_selection-restored-ui-assets-28ccjfd8/report.json).
5. **An earlier zero-result baseline demonstration was contaminated by missing assets:** it is not used as a clean false-success reproduction. The later clean baseline experiment above supplies that evidence.

No attempt here qualifies full rendered presentation, physical device latency/incidence, real-aircraft forces or handling, all forty flight-card maneuvers, long-duration depletion/thermal behavior, native backend parity/performance, the entire test suite or every vehicle. Existing historical investigations are identified as history rather than represented as rerun results. The delivered repair is bounded by the actually verified wrapper/card behavior; the [findings register](findings-register.md) and [research plan](research-sources-and-validation.md) define remaining runtime and physical work.

Final publication checks found no missing local Markdown targets in the dossier/probe instructions and no tracked application changes. Source/authored-document whitespace checks pass. The full diff's whitespace notices are confined to preserved engine logs (emitted trailing spaces and a final blank line); those raw bytes are retained so their recorded hashes remain valid.
