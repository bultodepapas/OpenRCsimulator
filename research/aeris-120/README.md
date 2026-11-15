# AERIS-120 research kit

**A120-00 · 2026-11-15.** Offline reference arithmetic, external-data inspection and acquisition preparation for a 120 cc gasoline 3D aerobat. [Active plan](../../docs/plans/aeris-120-3d-gas.md) · [Evidence](../../docs/research/aeris-120/README.md) · [Developer briefs](../../docs/research/aeris-120/development-briefs.md).

This is not the aircraft-data generator. No `app/` file is written and no model is imported. External published measurements are identified separately from illustrative arithmetic; no new hardware acquisition or flight was performed. A120-01…12 implementation remains pending.

## Reproduce the reference study

Python 3.10+ standard library, from the repository root:

```sh
python3 research/aeris-120/test_reference_study.py
python3 research/aeris-120/reference_study.py --check

# After an intentional reviewed input/calculator change:
python3 research/aeris-120/reference_study.py --write
```

With no option the calculator prints the report. `--write` replaces only [reference-study.json](reference-study.json); `--check` recomputes and compares it without writing. [reference-inputs.json](reference-inputs.json) owns all scalar inputs and scenarios. The report retains exact input/calculator SHA-256, input provenance, units in field names, group-specific assumptions, `physical_acceptance: false` and `aircraft_data_export: false`. It has no network or Godot dependency and is not a new CI gate.

The shipped prop inputs use the S06 manufacturer-**simulated** static coefficients at 5,000 RPM and its **estimated** prop inertia. Airframe dimensions are prior design inputs; masses, atmosphere, speeds, body rates and delays are illustrative scenarios. Editing a number requires revisiting its provenance: source strings and `--check` do not authenticate an external source. The calculator does not certify a changed RPM/prop as a manufacturer point or a permitted operating condition.

| Group | Equations | Boundary |
| --- | --- | --- |
| Geometry and flow | `c_ref=S/b`, `AR=b²/S`, `Re=V*c_ref/nu`, `q=0.5*rho*V²`, `p_hat=p*b/(2V)`, `q_hat=q_pitch*c_ref/(2V)` | Reference chord is not MAC; supplied speed is not a uniform installed wash; reduced rates are null at V=0 |
| Static prop point | `n=RPM/60`, `Omega=2*pi*n`, `T=Ct*rho*n²*D⁴`, `P=Cp*rho*n³*D⁵`, `Q=P/Omega` | Ct/Cp at the supplied input point; no engine torque map or forward-flight performance interpolation |
| Ideal static flow | `A=pi*D²/4`, `vi=sqrt(T/(2*rho*A))`, `V_far=2vi`, `R_far=R/sqrt(2)`, `P_ideal=T*vi` | Steady ideal open-flow disk, no swirl/profile losses; no wing/tail velocity or transport prediction [S28] |
| Rotor contribution | `H=I_prop*Omega`, `E_spin=I_prop*Omega²/2`, `M_gyro=H*omega_perpendicular` | Prop-only contribution, specified perpendicular body rate, not net aircraft moment or installed inertia |
| Mass scenario | `T/(mg)`, `RPM_balance=RPM_ref*sqrt(mg/T_ref)` | Constant-Ct algebra across RPM, without a validated range or engine equilibrium; not hover qualification |
| Pure delay | `phase_deg=-360*f*delay_seconds` | Isolated linear delay; no measured radio/display/servo bandwidth or latency budget |

The focused checks use independently simple numerical cases, dimensional scaling, zero-speed/delay behavior and invalid-input rejection. An in-memory **synthetic** round-trip through the existing static-prop reducer checks coefficient/ideal-power consistency; it writes no measurement file. Snapshot agreement establishes repeatability, not independent physical accuracy. Full float precision in the JSON is computational detail, not a measurement precision claim.

## External transient benchmark

[transient-source.json](transient-source.json) pins the S36 Zenodo v1.0.0 dataset, attribution, **CC BY 4.0** terms, two original filenames/URLs/byte counts, published MD5 and locally verified SHA-256. [transient_benchmark.py](transient_benchmark.py) reads only those exact bytes, checks source-array definitions and selects six existing samples near 4,000 RPM. [transient-benchmark.json](transient-benchmark.json) retains selected row indices/values, source identity and interpretation limits. This is an adapted numerical selection from the credited dataset; originals are not redistributed here. The related article and its pitch-label inconsistency remain S35.

For the interpretation/table see [the evidence report](../../docs/research/aeris-120/evidence-update-2026-11-15.md#small-propeller-transient-benchmark). This fixture is an independent external small-propeller research comparison, not a matching AERIS measurement. The selector does not execute the source's example code, load the large PIV archives, perform a new fit, or write aircraft coefficients.

Optional reproduction uses Python 3.12 with [pinned NumPy/h5py dependencies](transient-requirements.txt); the scalar study above needs neither. Choose a fresh external source/environment directory. The script itself never downloads anything:

```sh
aeris_bench_dir="$(mktemp -d)"
python3 -m venv "$aeris_bench_dir/venv"
"$aeris_bench_dir/venv/bin/python" -m pip install -r research/aeris-120/transient-requirements.txt
mkdir "$aeris_bench_dir/source"
curl --fail --location 'https://zenodo.org/records/23083730/files/README.md?download=1' --output "$aeris_bench_dir/source/README.md"
curl --fail --location 'https://zenodo.org/records/23083730/files/data_thrust.h5?download=1' --output "$aeris_bench_dir/source/data_thrust.h5"
"$aeris_bench_dir/venv/bin/python" research/aeris-120/transient_benchmark.py --source-dir "$aeris_bench_dir/source" --check
```

Without `--check` it prints the result; `--write` intentionally regenerates only `transient-benchmark.json`. Retain the source directory for later reproduction. A missing/wrong source fails before any output is published. The stored identity includes the selector, manifest and dependency versions, so an intentional version change needs a reviewed new receipt.

Array paths are `/<pitch>/St/T_fit_coeffs` and `/<pitch>/<Up|Do>/{t,n,T,CT,Delta_CT,Unc_Delta_CT}`. The selector checks shapes, time order/spacing, finite core observations, source normalization and all stored deviations against the author's steady fit. Missing uncertainty elsewhere in a trace is permitted by the source; each selected row requires a finite nonnegative value. The output retains each row's processed mean RPM instead of relabeling all as exactly 4,000 RPM. The authors already cubic-spline interpolated RPM onto the thrust time base; this selector performs no additional interpolation.

The 10 kHz arrays contain processed ensemble means; 30 Hz forward/backward filtering is noncausal. Source `CT` has a different normalization from conventional prop tables, and `Delta_CT` is a relative difference from a fitted steady baseline. Row times are not a latency measurement. The reported expanded uncertainty is per deviation; shared-baseline covariance is unavailable. Individual trials and a held-out repetition set are absent from this file. Those limitations prevent using the benchmark as an unqualified transient-law or DA120 acceptance test.

## Acquisition map

Use the existing tools unchanged where their stated assumptions fit. Copy their documented input structure into a **new** campaign beside the original observations; replace every invented reading, source and uncertainty before declaring measured evidence. No example is pre-filled for AERIS.

| Need / owning A120 step | Existing tool and input contract | AERIS-specific preparation / limit |
| --- | --- | --- |
| Mass and horizontal CG, 01 | [VAL-5a weighing](../validation/weighing/README.md) | Separate dry/full/empty identities; level body axes rather than weighing in taildragger rest attitude. Reducer x is forward; aircraft authoring x is aft. Convert with the declared origin/sign; no vertical CG result. |
| Inertia, 01/03 | [VAL-6a swing test](../validation/inertia/README.md) | Axis, fixture/tare, amplitude/decay and configuration; compare reference rig and repeated offsets. In-air added-inertia limits remain. Prop-plus-spinner and effective engine inertia are distinct acquisitions. |
| Static thrust/RPM/torque, 03 | [VAL-7a static prop](../validation/static-prop/README.md) | Exact engine/exhaust/prop/atmosphere; stabilized repeated points, net tared loads. Leave torque null if unavailable; no Cp/power inference from thrust alone. Positive static operation only. |
| RPM transients, 03 | [VAL-7b/c RPM step](../validation/rpm-step/README.md) | One step per record, identified steady windows, common clock, actual butterfly angle in parallel records, up/down repeats and held-out conditions. Diagnostic apparent lag includes the whole chain. |
| Whole-roll timing, 05/09 | [VAL-8b roll video](../validation/roll-video/README.md) | Actual original cadence, signed complete phase events and visible orientation. Mean completed-roll rate is not instantaneous body rate, roll damping or an aerodynamic derivative. |
| Ground path, 07/09 | [VAL-8a ground video](../validation/ground-video/README.md) | Surveyed ground reference and valid projection; contact geometry/fuel/surface/wind recorded. A raised aircraft point does not remain on the calibration plane. |
| Coupled ground reactions, 04/07 | [E0b7 field observations](../propwash/e0b7/README.md) | Taxi/takeoff channels can be useful. Its **nose-wheel** unloading card is not a taildragger-tail-load card; never rename tail load into `nose_load`. A new measurement type needs the shared owner's extension. These observations cannot identify a wing/tail wake field. |
| Physical stick to displayed marker, 06/11 | [F6a protocol](../../docs/research/radio-input/F6a/README.md), [F6b reducer](../radio-latency/README.md) | Actual radio/USB or adapter route, common-view physical threshold and displayed patch, verified acquisition cadence; record scanout/exposure effects. It does not measure servo or aircraft response. |
| Inflow literature benchmark, 04 | [S24 Glasgow source/README](../../docs/research/aeris-120/evidence-update-2026-11-15.md#5-data-reuse-and-remaining-evidence) | Optional future ingestion of licensed upstream-plane data, within its J/yaw/Re envelope. Preserve source total-freestream J versus axial J, and each case's blade pitch. Full archive not inspected; not a target-aircraft wake map. |

No existing reducer in this table supplies loaded-servo identification, full-angle air data, direct installed wake vectors or a complete engine torque map. Preserve those raw observations and define their measurement model with the owning track before adding a reducer. A successful CLI run cannot make an unsuitable experiment valid.

## Common campaign record

Before collection, freeze configuration, proposed task windows, observation definitions, expected regimes, uncertainty method, tolerances and calibration/held-out trial assignments. Preserve all attempts, including interruptions and missing channels. Keep a complete original recording in one partition; neighboring excerpts are not independent holdout data. Record shared-day, instrument and environmental correlations.

For every input channel, retain units/frame/datum, physical reference point, sensor range, calibration, raw sampling cadence, filtering, clock alignment and validity/saturation flags. Record actual surface angles separately from receiver commands, RPM separately from throttle, and air-relative velocity separately from GPS motion. Treat unavailable values as missing evidence, not zero.

Use [pilot-evaluation.template.md](pilot-evaluation.template.md) for task-based pilot records alongside the existing A120-C cards. Future simulator work uses the established [flight logging workflow](../../docs/FLIGHT-LOGGING.md); `.orfl` replay is not a physical measurement or a new radio-latency test.

## Uncertainty and evidence retention

VAL weighing/inertia/static-prop use standard uncertainty `u`; RPM-step uncertainty has its own optional independence model. E0b7 uses absolute error `bound`; F6 uses observation intervals and cadence bounds. These are different mathematical objects. Do not convert them by renaming a field or treating every repeated sample as independent. Shared clock/gain/filter errors can survive averaging. Follow each reducer's contract and preserve incomplete uncertainty budgets. [S27 in the source register]

Keep lightweight summaries, sources, hashes, procedures and regeneration commands in Git. Preserve original videos, instrument streams and external archives in the project's evidence location with retrievable references; no unnecessary raw media or the 1 GB Glasgow archive belongs in this change. Separate physical observations, derived results, simulator predictions and synthetic software fixtures in filenames and manifests.

### Verification of this kit

Eight focused arithmetic/domain checks and the deterministic snapshot check pass on Python 3.12.14. The external selector verifies both source files and all six transient-array definitions; its six-row snapshot reproduces with NumPy 2.3.5 and h5py 3.15.1. A deliberately corrupted same-size source is rejected before output, preserving the stored result. All 60 added local links/anchors resolve, and the staged whitespace check passes. Independent technical review corrected source-point attribution after edited inputs, relative-wind/gradient wording, zero-thrust/nonzero-torque wake coverage, advance-ratio convention and author-preprocessed RPM wording; no material findings remain in the reviewed candidate. No Godot session, target radio, physical bench, aircraft flight or performance campaign ran. Source labels remain declarations, and no implementation or aircraft-promotion gate is closed.
