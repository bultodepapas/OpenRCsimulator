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
