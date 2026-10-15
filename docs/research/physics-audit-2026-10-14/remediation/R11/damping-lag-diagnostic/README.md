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

The machine-readable generator is [`research/aero/d11g/derive_rate_derivatives.gd`](../../../../../../research/aero/d11g/derive_rate_derivatives.gd); the leaf-only writer/checker is [`research/aero/d11g/apply_rate_derivatives.py`](../../../../../../research/aero/d11g/apply_rate_derivatives.py). Report v4 fingerprints the target input after excluding exactly the six output leaves and uses a deterministic recursive inventory of all 94 `app/physics/**/*.gd` files, plus `app/data/ground/wheel_profiles.json`, `app/project.godot`, and the generator. The wheel-profile resource is read by `AircraftData.load_file`; the project setting supplies its tick-rate validation. This conservative scope includes `mass_inventory.gd` and `effective_mass.gd` and does not rely on a partial preload list. Two runs produced byte-identical v4 reports, and the checker rejects a forged stale hash for `mass_inventory.gd`; the updater also rejects stale non-output inputs and boolean values. Derivative values and the normalized input fingerprint are unchanged. A replay from the preserved original Stik JSON produced a byte-identical result to the updated live base (`bdcf4d64…f723`). [`d11g-repair/identity-final-v2.json`](d11g-repair/identity-final-v2.json) retains the earlier report receipt, [`d11g-repair/identity-final-v3.json`](d11g-repair/identity-final-v3.json) binds the prior yaw-test revision, and [`d11g-repair/identity-final-v4.json`](d11g-repair/identity-final-v4.json) binds the current v4 generator/replay, exact generated leaves, yaw-test result, and matched-comparison artifacts.

With updated data, the focused `test_damping_regimes.gd` passes 20/20 and `test_downwash_lag.gd` passes 22/22; their captured outputs are in [`d11g-repair`](d11g-repair/). These are software consistency checks, not physical validation, and downstream flight/golden qualification remains separate.

### Yaw-damping verification and the independent D11f comparison

The current [`test_yaw_damping.gd`](../../../../../../app/tests/test_yaw_damping.gd) has 17 checks: 16 pass and the original whole-range 7% fin-plus-wing-profile comparison remains an ordinary failing assertion. Its worst deviation is 7.75% at α=11°. The α=0 local check, fin-rate/Cnβ checks, attached-domain checks and independent chain-rule checks pass. The chain-rule calculation includes fin and wing profile, induced and lift-projection terms; it matches production central differences over α=0–11° with maximum absolute Cnr errors 6.496e−6 at h=0.05 and 1.506e−6 at h=0.0125, with every fourfold refinement reducing error. The actual ±h strip angles are checked to remain attached, and asymmetric strip-CL0 or induced-map fixtures are rejected. See [`d11g-repair/test_yaw_damping-R02-open-gate-v5.log`](d11g-repair/test_yaw_damping-R02-open-gate-v5.log). This derivative agreement verifies implementation consistency only; it does not clear the 7% gate or validate the force law physically.

The independent wing comparison is recorded in [`d11g-repair/yaw_r02_vs_kj_comparison-v4.json`](d11g-repair/yaw_r02_vs_kj_comparison-v4.json), generated by [`d11g-repair/yaw_r02_vs_kj_comparison.py`](d11g-repair/yaw_r02_vs_kj_comparison.py) from a read-only production input export. The unchanged [`research/aero/d11f/wing_yaw_damping.py`](../../../../../../research/aero/d11f/wing_yaw_damping.py) solves a rate-dependent generalized Weissinger circulation model and evaluates Kutta–Joukowski loads with trailing-leg downwash. Its original zero-camber run at α=11° gives wing CL 0.790394, profile Cnr −0.0140648, circulation/downwash contribution +0.0002584, and total wing Cnr −0.0138064; at α=4° it gives −0.0140306. The current R02 reproduction matches the production GDScript wing Cnr at the seven sampled α values to a maximum absolute difference of 6.9e−11. At α=11° it gives wing CL mean 0.909009 and wing Cnr −0.0054262 (profile −0.0138088, induced drag −0.0020214, chord-axis lift projection +0.0104040), a +0.0083802 residual toward less damping relative to D11f. At α=4° the wing-only residual is +0.0021905. These are wing-only values and must not be confused with the full-aircraft test, whose α=11°, h=.05 derivative is −0.1217572 and whose independent attached-law derivative is −0.1217507.

The comparison matches AR≈5, six equal-area strips, section slope 6.08175/rad, CD0=0.0434, speed 15 m/s, density 1.225 kg/m³, neutral controls, and central difference h=.05 rad/s. It remains intentionally diagnostic rather than like-for-like physical validation. The static operator recovered from production `E` agrees with D11f's kernel to a maximum absolute error of 1.45e−7. D11f starts with zero strip CL0; its fixed-incidence matched variant reproduces production CL0 at α=0, then gives Cnr −0.0134806 at α=11°—only +0.0003258 relative to original D11f, so the CL0 match alone does not close the residual. D11f uses the exact positive-axial `W/u_i` incidence source and a rate-dependent `u_j/u_i` induced operator. It forms circulation as `Γ_i=0.5 u_i c CL_i` and uses Kutta–Joukowski force with trailing-leg downwash; its profile term is `0.5ρ(u_i²+W²)cΔy CD0` in the D11f x direction. R02 instead uses `atan2` section angles with a fixed `E` map, weights off-diagonal angle donors by normalized section speed, and applies the whole-aircraft `k=0.0814934`, `CL_minD=0.23` drag parabola per strip. Its axial profile-force term scales with `Vp_i·u_i`, while its chord-axis lift projection scales with `Vp_i CL_i W`; the D11f comparison uses `u_i` in circulation and `W−w_down` in the Kutta–Joukowski axial force. Thus matched-CL comparisons still differ in their force closures, in addition to their drag conventions.

Selected α=11° variants show where the comparison is sensitive without identifying a validated correction:

| Diagnostic variant | Wing Cnr |
| --- | ---: |
| Current fixed-E R02 law with donor-speed weighting | −0.0054262 |
| Same R02 law with off-diagonal donor weighting disabled | −0.0067018 |
| Fixed-E dimensional source `g=u·CL`, exact `W+u·α₀` RHS, R02 force closure | −0.0098863 |
| Rate-dependent `uⱼ/uᵢ` operator with geometric-angle RHS, R02 force closure | −0.0097058 |
| D11f Kutta–Joukowski force closure using current fixed-E R02 CL | −0.0119062 |
| D11f Kutta–Joukowski closure with CL0-matched incidence | −0.0134806 |

These rows change distinct parts of the model and are not interchangeable predictions. At this point the donor weights range 0.995853–1.0; removing them changes Cnr by −0.0012756 but leaves a material residual. A current-law x-only profile-drag variant is −0.0054238, only 2.4e−6 from the current result, so profile-drag axis projection alone does not explain the discrepancy. The D11f force closure on the same current CL changes the result materially, while the exact-`W/u` and rate-dependent-operator variants also change the local circulation law. The remaining issue is open: a matched comparison must resolve strip camber, geometric-angle versus `W/u` incidence, the induced operator, local versus whole-aircraft polar use, and force/downwash accounting before any physical conclusion or law change.

The preserved R00 control and older R02 failure logs remain historical evidence. Raw reference and input data are [`d11g-repair/yaw_d11f_reference_probe.py`](d11g-repair/yaw_d11f_reference_probe.py), [`d11g-repair/yaw_d11f_reference_probe.log`](d11g-repair/yaw_d11f_reference_probe.log), [`d11g-repair/yaw_r02_input_export-v1.json`](d11g-repair/yaw_r02_input_export-v1.json), and [`d11g-repair/yaw_current_strip_state_probe-retry2.log`](d11g-repair/yaw_current_strip_state_probe-retry2.log). The D11f result is an independent model comparison, not measurements or physical truth. The [NASA TM-2016-219349 abstract](https://ntrs.nasa.gov/citations/20170000682) describes discrete-horseshoe derivative calculations within unseparated inviscid incompressible flow and reports low-angle comparisons; that scope context does not validate either simulator model.

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
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/research/aero/d11g/derive_rate_derivatives.gd -- --json --check --report-file C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/current-law-report-v4.json
python research/aero/d11g/apply_rate_derivatives.py --report C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/current-law-report-v4.json --check
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_damping_regimes.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_downwash_lag.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_yaw_damping.gd
.\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/gradient_stripping_probe.gd
```

The first four commands reproduce the current-law derivation, source identity check, and two focused passing tests. `test_yaw_damping.gd` intentionally exits nonzero because its original whole-range 7% comparison remains an open gate; the retained run is [`d11g-repair/test_yaw_damping-R02-open-gate-v5.log`](d11g-repair/test_yaw_damping-R02-open-gate-v5.log). The final command preserves the read-only fixture diagnosis. The retained D11f comparison can be reproduced with `python docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/yaw_d11f_reference_probe.py`; the current local strip summary uses `Godot --headless --path app --audio-driver Dummy --script <absolute path to d11g-repair/yaw_current_strip_state_probe.gd>`. The R00 yaw control used the immutable app copy as --path; its captured output is retained under d11g-repair. These are software comparisons and model-to-model evidence, not wind-tunnel, flight, or model-validation results.

