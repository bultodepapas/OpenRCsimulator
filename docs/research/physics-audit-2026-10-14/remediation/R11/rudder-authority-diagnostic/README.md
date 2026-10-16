# R11 rudder recovery gate diagnostic

## Prerelease status — 2026-10-16

The release owner explicitly deferred this physical acceptance item for `v0.1.2-rc.1`. `app/test.sh` supplies `--allow-known-stik-rudder-recovery` to this test; direct invocation remains strict. Only the right-first reference 240 Hz recovery bound is deferred. The required recovery sample must exist and be finite; missing and NaN sample probes fail with zero pending results. No coefficient, equation or acceptance threshold changed. A pending result is not a pass and does not establish physical validation.

The hardened reporting checks produce [27 checks, one failure in strict mode](prerelease-20261016/review-rudder-strict.log) and [27 checks, one pending and zero failures in prerelease mode](prerelease-20261016/review-rudder-pending.log) on native Godot 4.7.2. Unrelated-failure probes still exit 1 with the flag enabled. The diagnosis below is retained as the physical basis; its original requirement to resolve the gate still applies to physical acceptance.

The frozen-07 failure is a repeatable software-acceptance regression caused by the regenerated Jensen Ugly Stik `Cnr` value. The reference case still completes without a fault and passes the peak sideslip and peak yaw-rate screens; only the 3.0 s yaw-rate recovery screen fails. This result does not establish a physical handling defect: the 15°/s recovery limit is explicitly an estimated engineering screen, not a measurement or validated aircraft limit.

## Reproduction and cause

The test’s default scenario is `jensen-das-ugly-stik-60`. Its 15 m/s, 3 s level doublet commands full right rudder from 0.5–1.0 s, full left from 1.0–1.5 s, then neutral. It samples body yaw rate `r` at 3.0 s, 1.5 s after release. The frozen log records `r = −15.13°/s` at 240 Hz and `−15.20°/s` at 480 Hz; the 0.075°/s refinement difference is within the test’s 0.5°/s final-rate tolerance. The other peak screens pass (`βpk = 20.39°` against 25° and `|r|pk = 92.58°/s` against 120°/s), and the full frozen test reports 26 checks with this one failure.

The frozen-07 materialization receipt records the pre-overlay Stik JSON hash `5fe8ece9…e1ee9b6` and regenerated file hash `bdcf4d64…1950f723`. Comparing the preserved pre-regeneration JSON with the current file shows exactly six changed leaves: `value` and `source` for `Cmq`, `CLq`, and `Cnr`. The runtime `aero.gd` is byte-identical in the frozen candidate and the overlay. The three rate derivatives changed from `Cmq = −7.944`, `CLq = 1.977`, `Cnr = −0.1354` to `−8.009`, `2.003`, `−0.1335`. In particular, the new `Cnr` is 1.40% less negative, so it supplies slightly less yaw-rate damping in this model. Both generations are model-derived; the current source provenance explicitly says “not measured or physically validated.”

The read-only probe [rudder_data_matrix.gd](../../../../../../research/physics-audit-2026-10-14/remediation/R11/rudder-authority-diagnostic/rudder_data_matrix.gd) ran against the exact frozen-07 Linux app and pinned Godot binary. For each case it set only those three numeric rate coefficients in memory, ran the test’s same `Maneuvers.all().rudder_doublet` through `FlightSession` and `Maneuvers.fly`, and recorded the 3 s sample. No application, aircraft-data, test, or snapshot source file was changed. The complete raw output is [rudder-data-matrix-frozen-07-linux-01.log](../../../../../../research/physics-audit-2026-10-14/remediation/R11/rudder-authority-diagnostic/rudder-data-matrix-frozen-07-linux-01.log), with the source and result identities in [matrix-receipt.json](../../../../../../research/physics-audit-2026-10-14/remediation/R11/rudder-authority-diagnostic/matrix-receipt.json).

| Frozen-07 data values | 240 Hz `r@3 s` | 480 Hz `r@3 s` |
| --- | ---: | ---: |
| Preserved pre-regeneration values | −14.709714°/s | −14.785031°/s |
| Regenerated values | −15.125273°/s | −15.200616°/s |
| Difference, regenerated minus previous | −0.415559°/s | −0.415585°/s |

At 240 Hz the preserved values clear the screen by 0.2903°/s, while the regenerated values exceed it by 0.1253°/s. A split matrix attributes essentially the whole change to `Cnr`: keeping new `Cmq`/`CLq` with old `Cnr` shifts `r@3 s` by only +0.000078°/s from the all-old case; keeping old `Cmq`/`CLq` with new `Cnr` shifts it by −0.415614°/s. The corresponding 480 Hz shifts are +0.000092°/s and −0.415655°/s. This isolates the test crossing to the data update under the same frozen runtime; it does not show that either derivative set is physically more accurate.

The `Cnr` damping change is distinct from `Cndr`, the rudder-control derivative. The default reference call does not request the test’s separate in-memory legacy-`Cndr` override. `Cndr` itself is unchanged by the D11g regeneration. The mirrored left-first case also passes the recovery screen in the frozen log.

## Interpretation and limits

The data regeneration causes a genuine regression against this checked-in software acceptance screen. The screen’s physical authority remains unqualified: the test header calls it an estimate and says it is not flight data, while the regenerated derivatives are model outputs rather than measurements. Therefore the failure should remain an ordinary visible failure; this evidence does not justify changing the bound, reverting the derivation, or claiming a real-aircraft safety issue. Clearing the screen needs independent handling data or a documented acceptance basis.

The relevant implementation and test definitions are `app/tests/test_rudder_authority.gd` (screen and exact sampling), `app/sim/maneuvers.gd` (doublet), `app/sim/scenarios.gd` (default Stik), `app/physics/aero.gd` (current coefficient law), and the old/current `app/data/aircraft/jensen_ugly_stik_60.json` values. The test explicitly labels all three reference-doublet limits as estimated screens, not flight data.
