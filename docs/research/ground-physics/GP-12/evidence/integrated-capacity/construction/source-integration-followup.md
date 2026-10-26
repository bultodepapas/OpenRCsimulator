# Remaining source integration dependency

Root source audit, 2026-10-26. No implementation in this note.

The shared integrated-capacity operator deliberately rejects the legacy `capture`
mapping. `AircraftGroundElectric._evaluate` appends a shaft-bearing row after the
instantaneously loaded legacy wheel rows and emits `capture.impulse_row` in that
layout. The new packet instead retains unloaded wheel rows and hardware brake rows,
so those ordinals are not interchangeable. An electric owner cannot simply attach
the new packet to the old electric sample and enable the new law.

Next source integration must bind the shaft-bearing independent row and its stable
identity to the same finite mobility solve. Preserve existing electric result bytes
when the new opt-in is absent. Validate the explicit capacity-row capture mapping,
stable rotor identity and row topology before any shared Step publication; do not
guess the mapping from the old ordinal, change tolerances or add a shaft projector.
Test zero-RPM startup, source-off rundown, finite capture with simultaneous loaded
wheel braking, malformed/stale row mappings, checkpoint continuation and rejected
tick rollback. The current packet guard and raw-QP membership checks stay decisive.

After that, finite-battery boundaries must locate using complete duration-dependent
contact steps. Existing `ElectricBatteryStep` nests the older `ElectricStop` path;
it cannot be called around/inside the new Step as a second free-flight integrator.
Reuse its documented root tolerances and `EventBracket.propose` only after explicit
admission for the composed path. Trial charge/RPM continuations remain trial-only.
`AircraftGroundBattery.supervise_endpoint` runs once per accepted outer tick, never
for predictors, error-gate comparisons, root trials or contact pieces. Accepted
segment work/receipts/events accumulate once; rejected trial work stays computational
diagnostics. No charge clamp substitutes for event localization. Stock Session and
Workshop admission remain separate final gates.
