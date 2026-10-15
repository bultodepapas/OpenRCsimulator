# R01: restore the legacy aero oracle lane

This note records the test-only R01 repair before any production aero edits. The frozen H12 oracle predates optional `envelope.wing_polar`, so the legacy comparison now explicitly erases that known option from both copied inputs. The enabled-polar suites remain separate and unchanged.

## Reproduction

Run from `C:\DEVELOPMENT\OpenRCsimulator` with Godot 4.7.2:

```powershell
$godotPath = 'C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe'
& $godotPath --headless --path tmp/physics-audit-baseline-2026-10-14/app --audio-driver Dummy --script res://tests/test_aero_flow.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_aero_flow.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_wing_polar.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_wing_polar_session.gd
```

The first command used the unmodified app snapshot captured in [R00](../R00/baseline-identity.json). It reproduced H4 at 20,000/20,000 and H12 at 18,445/20,001: 1,556 H12 comparisons failed on the Avanti's enabled polar, while the pre-polar oracle ignored it. The raw failure output is [test_aero_flow-prepatch.log](test_aero_flow-prepatch.log).

After adding the explicit projection, the unchanged production aero code passed H4 at 20,000/20,000 and H12 at 20,001/20,001, including 14,553 stalled and 4,000 zero-flow samples. The existing analytic section-moment check also passed. See [test_aero_flow-r01.log](test_aero_flow-r01.log).

The optional-polar regression suites remained green: 111 checks in `test_wing_polar.gd` and 8 in `test_wing_polar_session.gd`. Their fixture is synthetic; those results establish that the optional polar implementation and session path remain enabled, not Avanti-specific coefficient validity. Logs: [test_wing_polar-r01.log](test_wing_polar-r01.log) and [test_wing_polar_session-r01.log](test_wing_polar_session-r01.log).

## Identity at the R01 check

The pre-patch snapshot's `app/tests/test_aero_flow.gd` SHA-256 was `E319854355B32AE76B068FBCD22D5CCAD79E76C9FC45943484ACB92A1CBB78D1`. The R01 version is `5B923E932A2B72553837E95F69D24ECF4A31EC5332F951AA8852C903D8C54545`. The frozen reference SHA-256 is `D80E056F9897653330C8B6A716CC847FA9EA1089FE2E696EDA5A2411582395E0`.

Production `app/physics/aero.gd` (`CF034742D69332061EB9414CCD57F7D0B6CB6E1C2F17CC5AE39E70FE26655539`) and `app/physics/slipstream.gd` (`9F14A283D8D9529375374228FFCC93C650B4A924FA498DF14034FE3FDC00EDD8`) matched the R00 snapshot during these checks. This is software regression evidence only; it says nothing about physical validation.

## R02 compatibility and continuity regressions

R02 changes the force map outside attached, planar, forward flow. The legacy lanes therefore assert exact parity only in their stated unchanged domains; corrected-domain behavior has independent invariants in `test_aero_continuity.gd`. The pre-split, deliberately broad legacy comparisons are retained in [test_aero_flow-r02-pre-split.log](test_aero_flow-r02-pre-split.log) to show why the domains were separated.

`test_aero_flow.gd` passes 20,000 H4 selector comparisons over its seeded randomized rate set: expected weight is the maximum of the frozen selector and an independent test implementation of R02's angular rate-flow guard. H12 passes 20,000 byte-exact loads comparisons for attached, planar, forward flow with zero rates; the optional polar and induced-map inputs remain explicitly excluded from this frozen legacy lane, and their enabled behavior is tested separately. The comparator's one-ULP rejection and Timber section-moment analytic sum also pass. Raw output: [test_aero_flow-r02.log](test_aero_flow-r02.log).

The new Cartesian suite passes 64 checks across both Jensen Stik and Avanti: finite force/moment and wake limits approaching spanwise zero flow, a mixed stagnant/loaded strip case, passive section and tail identities, free-versus-washed increments, and a production Avanti polar assertion. Its boundary probes use ε/V = 10⁻⁶; worst reported wake differences were 1.977×10⁻⁶ m/s for the Stik and 8.9×10⁻⁸ m/s for the Avanti. These are code-contract checks, not experimental validation. See [test_aero_continuity-r02.log](test_aero_continuity-r02.log).

The dimensional lag and ground/wash consumers are covered by three migrated suites:

- `test_downwash_lag.gd`: 20 checks pass. The held state is an equal-area wing lift-velocity proxy in m/s, including byte-exact settled identity, first-order response, Jet's declared no-lag path, and the analytic derivative of `atan2(g·U_L, V_t)`. The plunge estimate is −3.413 at 240 Hz and −3.484 at 480 Hz, versus the analytic −3.551; the oracle/local comparison remains within 3%. See [test_downwash_lag-r02.log](test_downwash_lag-r02.log).
- `test_ground_effect.gd`: 50 checks pass, including dimensional free/ground wake initialization (6.10528 / 6.32738 m/s for the checked start), the explicit ground-aware tail selector, and unchanged far-field loads. See [test_ground_effect-r02-rerun.log](test_ground_effect-r02-rerun.log). An earlier launch log recorded transient parse errors in another concurrently edited file; the successful rerun is the result to use.
- `test_slipstream_downwash.gd`: 15 checks pass across 300 held-source/rate/stall cases, with 900 immersed wash pieces and the session feeding the held m/s source to both aero and wash. See [test_slipstream_downwash-r02.log](test_slipstream_downwash-r02.log).

Reproduce the final checks from the repository root with Godot 4.7.2:

```powershell
$godotPath = 'C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe'
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_aero_flow.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_aero_continuity.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_downwash_lag.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_ground_effect.gd
& $godotPath --headless --path app --audio-driver Dummy --script res://tests/test_slipstream_downwash.gd
```

R02 source identities at this verification point: `aero.gd` `FED08E735494B6D2597F639CCA118D84C978F75828811F0D09968BFC67A85BE5`; `slipstream.gd` `BB810E8E9E93B1B89AD1750CD4DB507EB7FE66FAD070A5CCE51DFD0DCE58AB06`; `flight_session.gd` `19D19408C6C2A75B6AD99E6A87D413774E20C9B8C525D3C8514C87EBF4C65DDF`. These hashes identify the observed working tree, which also contains unrelated concurrent work. Test identities: H4/H12 `test_aero_flow.gd` `7DB6AB897EE5C6BC7E95081EE59A863C5E5322D5C3CB2ECB99E3FD67E783D45D`; `test_aero_continuity.gd` `14EB4E1801C231E78993D0BAB28191DE681F4E4ABD1B7183D6EFCADD67B92F46`; `test_downwash_lag.gd` `B58745042E618322BA58CDE1994EBE3B087FB3E4428AEA6B998FCB5F209EE655`; `test_ground_effect.gd` `B59939972DAF77B209AB74F3BE315E1FD84B311275B069A7F381A043E2D7AA2B`; `test_slipstream_downwash.gd` `8345C4B64F4644768C0C284CD83DB4C9258FBB664F2C97235563F88F19115F66`.
