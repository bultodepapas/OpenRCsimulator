# R11 damping and lag failure diagnosis

This note records the D11g rate-derivative repair and the downwash-lag fixture diagnosis from `linux-gd-remainder-after-contact-contract.log`. It does not change runtime aerodynamics, test bounds, or retained Linux evidence. The current D11g aircraft data now reflects the current R02 law; later catalog/golden requalification is tracked separately by the R11 integration owner.

## D11g rate-derivative pin

`test_damping_regimes.gd` keeps its original broad local-versus-oracle derivative sweep inside ±15% and its `DERIVED_TOL = 0.005` exact-trim contract. The checked-in rates had been derived with the R00 local law, while the current R02 section-plane and dimensional-wake law produces slightly different local derivatives.

The original Stik coefficient bytes are preserved in [`d11g-repair/before`](d11g-repair/before), and [`d11g-repair/before-identity.json`](d11g-repair/before-identity.json) records all 16 input hashes. I re-ran the derivation against current R02 code at the same 15 m/s trimmed condition, with neutral controls, settled dimensional wake, and a 0.05 rad/s central difference. The reproduced values are:

| Coefficient at 15 m/s trim (α = 4.184°) | Old value about CG | Current-law result about CG | New ARP value |
| --- | ---: | ---: | ---: |
| Cmq | −7.7410 | −7.8033 | −8.009 |
| CLq | 1.9770 | 2.0034 | 2.003 |
| Cnr | −0.1318 | −0.1299 | −0.1335 |

The change was limited to the `value` and `source` leaves for `Cmq`, `CLq`, and `Cnr` in the Jensen Stik plus its five generated Glow aircraft variants. Four Workshop descriptors were updated only to point at the new base hashes; all five Glow installation profiles stayed byte-identical. [`d11g-repair/leaf-diff.json`](d11g-repair/leaf-diff.json) is the exact leaf receipt. No incidence, geometry, other coefficients, runtime, test bounds, or goldens were changed by this repair.

The machine-readable generator is [`research/aero/d11g/derive_rate_derivatives.gd`](../../../../../../research/aero/d11g/derive_rate_derivatives.gd); the leaf-only writer/checker is [`research/aero/d11g/apply_rate_derivatives.py`](../../../../../../research/aero/d11g/apply_rate_derivatives.py). The v2 report records a normalized input fingerprint excluding exactly the six output leaves and hashes the solver/generator sources. The checker rejects stale source hashes, stale non-output inputs, booleans passed as numbers, and reports without the identity scheme. A replay from the preserved original Stik JSON produced a byte-identical result to the updated live base (`bdcf4d64…f723`). [`d11g-repair/identity-final-v2.json`](d11g-repair/identity-final-v2.json) records the report, before/diff receipts, sources, and raw outputs; supplemental [`d11g-repair/identity-final-v3.json`](d11g-repair/identity-final-v3.json) binds the revised yaw test and this note.

With updated data, the focused `test_damping_regimes.gd` passes 20/20 and `test_downwash_lag.gd` passes 22/22; their captured outputs are in [`d11g-repair`](d11g-repair/). These are software consistency checks, not physical validation, and downstream flight/golden qualification remains separate.

### Yaw-damping invariant scope

The revised analytic test also rejects the preserved R00 force law as expected: maximum full-law Cnr discrepancy is 0.005003, with no engine errors. The current R02 test passes 8/8. This negative control shows the new assertion tracks the projected R02 law rather than a re-pinned value.

The old `test_yaw_damping.gd` compares local Cnr over α=0–11° to the α=0 fin-plus-profile estimate. That estimate omits the current law's attached-wing induced-drag derivative, induced-source weighting, and chord-axis lift projection. An independent chain-rule probe in [`d11g-repair/yaw_analytic_derivative.gd`](d11g-repair/yaw_analytic_derivative.gd) separates those terms and checks the result against central differences of current production `_local_loads`.

At α=0°, the full current local result is −0.133098 versus the fin-plus-wing-profile estimate −0.131983 (0.84% difference). At α=11°, the independent full-law derivative is −0.121751: fin lift −0.115752 plus fin profile drag −0.000579, wing profile drag −0.013809, induced drag −0.002032, and chord-axis lift projection +0.010420. Thus the original 7% whole-range assertion reports a model-definition mismatch at α=11° (about 7.75%), not a demonstrated force-law defect. The preserved R00 control passed 4/4; the old R02 test failed only that approximate whole-range sum. The revised test retains the α=0 estimate and fin/Cnβ checks, then compares the complete attached-law derivative over α=0–11° against an independent chain-rule derivation. It passes 8/8 without widening bounds; maximum absolute Cnr errors are 6.496e−6 at h=0.05 and 1.506e−6 at h=0.0125, with every fourfold step refinement reducing error. See [`d11g-repair/test_yaw_damping-analytic-v2-clean.log`](d11g-repair/test_yaw_damping-analytic-v2-clean.log). These derivative checks establish software consistency, not physical damping calibration.

## P-51 stripped-gradient case

`test_downwash_lag.gd` originally removed only `aero.surfaces.horizontal.downwash_gradient` for each aircraft, then expected the modified candidate to validate and apply. The P-51 candidate still contained its authored `aero.ground_effect`. The current loader requires the derived horizontal `free_slope` for that ground-effect law; `free_slope` is derived only when `downwash_gradient` is present. The candidate was therefore invalid before lag allocation was tested.

The read-only probe used the same catalog raw files and operations as the test. GP Extra and Avanti validate and apply after their gradient is removed and end with `downwash_index() == -1`. P-51 returns the exact loader error:

```text
aero.ground_effect: requires aero.surfaces.horizontal.downwash_gradient (the free tail law whose downwash it reduces)
```

Its `_apply()` returns false and the existing active P-51 session remains on its original lag index (13). The failed assertion is therefore a fixture/schema incompatibility, not evidence that a valid no-gradient P-51 allocates a lag entry. Keep the loader contract. If P-51 must cover the no-lag branch, use a clearly synthetic candidate that also removes the dependent ground-effect law, or make the P-51 branch explicitly assert this combination is rejected; the existing GP Extra and Avanti cases already cover valid no-gradient models.

The current fixture now first asserts this invalid combination is rejected without changing the active lag allocation, then also removes the dependent optional ground-effect law from the in-memory candidate before asserting a valid no-gradient/no-lag apply. The updated test passes 22/22, including the 2,000/2,000 settled-lag identity comparisons, plunge-theory check, 240/480 Hz refinement, and checkpoint replay. The diagnostic source and raw output remain [`gradient_stripping_probe.gd`](gradient_stripping_probe.gd) and [`gradient-stripping-probe-windows.log`](gradient-stripping-probe-windows.log).

## Reproduction

From the repository root in PowerShell:

```powershell
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/aero/d11g/derive_rate_derivatives.gd -- --json
python research/aero/d11g/apply_rate_derivatives.py --report C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/current-law-report-v2.json --check
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_damping_regimes.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_downwash_lag.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_yaw_damping.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/gradient_stripping_probe.gd
```

The first five commands reproduce the current-law derivation, identity check, and focused tests. The final command preserves the read-only fixture diagnosis. The R00 yaw control used the immutable app copy as --path; its captured output is retained under d11g-repair. This evidence is a software comparison, not a wind-tunnel, flight, or model-validation result.

