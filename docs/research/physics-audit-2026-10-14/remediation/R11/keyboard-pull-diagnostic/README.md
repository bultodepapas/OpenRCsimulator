# R11 keyboard over-pull regression

2026-10-14. The canonical Linux diagnostic remainder failed the old AV-17-R1 requirement that a two-second keyboard pull from a 45 m/s, −45° dive reach a maximum strip stall weight above 0.9. The run completed without a simulation fault, reached the existing diagnostic stall onset, and peaked at 0.77234. This is a changed response under the corrected aerodynamic law, not evidence of stall immunity or a measured aircraft envelope.

## Reproduction and distinction

The unchanged [AV-17 helper](../../../../../../app/tests/avanti_pullup_base.gd) applies commands through the actual session sampler. Its normal keyboard pitch takes one second to reach the endpoint. Each run lasts four seconds; reported maxima cover that full interval. The diagnostic [runner](../../../../../../research/physics-audit-2026-10-14/remediation/run_keyboard_pull_diagnostic.py) records source/data hashes before execution and rejects source drift or engine errors. All retained diagnostic runs completed with no such errors or drift.

| Source / rate | Hold | Peak body α | Peak strip stall weight | First weight ≥0.5 | First weight >0.9 |
| --- | ---: | ---: | ---: | ---: | ---: |
| R00 baseline, 240 Hz | 2 s | 40.87° | 1.00000 | see raw record | not instrumented |
| Corrected, 240 Hz | 2 s | 15.0704° | 0.77234 | 0.81250 s | absent |
| Corrected, 480 Hz | 2 s | 15.0706° | 0.77231 | 0.81042 s | absent |
| Corrected, 240 Hz | 3 s | 18.6992° | 0.97877 | 0.81250 s | 2.475 s |
| Corrected, 480 Hz | 3 s | 18.6996° | 0.97877 | 0.81042 s | 2.475 s |

Holding four seconds at 240 Hz also reaches 0.97877, with peak α 18.709°. The three-second fixture therefore includes approximately two seconds at the full normal-profile command, and reaches deep model separation during the commanded pull. The test does not accept a threshold reached only after release. `stall_weight` is a modeled strip blend, not a measured percentage of wing area or a physical stall calibration.

The baseline and corrected copies had identical keyboard command code and scenario helper before instrumentation. The aircraft data differ only by the separately documented analytic high-angle polar rounding. Repeating the corrected two-second case with the original R00 aircraft bytes in a disposable physical copy produces the same reported response; this rules out that data regeneration as the explanation for the failure. It does not isolate each term of R02 from the other source changes. See [override receipt](data-override.json), [original-data control](candidate-original-data-240/cases.json), [all metrics](summary.json), and the independent [R02 law evidence](../../R01-R02/README.md).

## Regression change

The [patch](test.patch) retains the two-second maneuver and explicitly checks onset ≥0.5 before release. It adds a three-second maneuver using the original **>0.9** criterion, and records the first threshold-crossing time so a post-release peak cannot satisfy it. All existing tap/recovery, input shaping, malformed data, normal/full profile, reset and physical key routing checks remain. No production physics, aircraft parameter, input filter, tolerance or golden flight was changed for this repair.

The focused Windows regression passes **39 checks, 0 failed** in a separate physical source copy: [log](patched-test-240/probe.log), [source identity](patched-test-240/identity.json). The new event timing is independently rerun at [240 Hz](event-times-240/cases.json) and [480 Hz](event-times-480/cases.json). The historical baseline, exploratory two/three/four-second runs and their identities remain alongside these records. Linux focused and canonical integration remain the enclosing R11 gate.
