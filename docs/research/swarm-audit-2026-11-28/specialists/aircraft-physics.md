# Aircraft physics review

Reviewed OpenRC Simulator main at `71306784a250d634854f0c8bab3a927cc46a61b8`. The scope covered fixed-wing strip forces and moments, the delayed tail wake, table-driven propulsion, the Phoenix power-package conversion and calculations on the reference flight path. The checks below test properties of the software laws. Aircraft-specific stall curves, propeller maps outside their measured intervals and pilot handling still need independent measurements.

## A custom conventional tail can turn a wake lag into exponential growth

**Medium severity for custom raw-aircraft files.** At `app/physics/aircraft_data.gd:989` the wake travels from the wing quarter chord to the horizontal tail. The loader derives its length in metres as `tail_x − 0.25 × wing_area / wing_span`. The horizontal position passes a per-component range check at line 2618. Lines 2652–2655 validate the optional downwash gradient and lines 2660–2663 enforce the aft position of the vertical fin. The horizontal tail has no corresponding positive transport-length check. The law applies to conventional aircraft with the gradient and associated local wing model. This finding concerns directly loaded aircraft JSON. Workshop package construction separately rejects nonpositive conventional tail arms; the Workshop flow is not the demonstrated exposure.

For a frozen wing wake and positive airspeed, the residual of a causal first-order lag must decay as `exp(−dt V/L)`. At positive time and speed, a negative length instead amplifies the residual each tick. The GDScript update is at `app/sim/flight_session.gd:6575–6576`. The native source uses the same expression after checking only finiteness at `research/native-kernel/src/nk_pre_step.hpp:323,332`. The linear mode analysis also divides by this length at `app/physics/flight_modes.gd:41–44`. The input and lag are equivalent-lift velocity in m/s, computed as the equal-area mean of strip plane speed times CL at `app/physics/aero.gd:890–894,962`.

The only input change in the reproduction sets the Stik’s horizontal pressure-centre x coordinate to 0.0 m in its leading-edge frame. The unchanged record has x = 0.8409 m. No coefficient, gradient, timestep or solver changes. The separate stock scan covered all 16 direct fixed-wing files carrying this gradient. Every transport length was positive, spanning 0.607242 to 1.422995 m.

The pinned Godot 4.8-beta2 reference backend accepted and trimmed both files at 15 m/s. At fixed state the measured tick multiplier was 0.921519450716 for stock (L = 0.764700033 m) and 2.270977434949 for the custom case (L = −0.076199967 m), matching the analytical factors. A 0.300 m/s lag residual became 0.156012 m/s and 212.238324 m/s, respectively, after eight calls.

A separate run started at the normal settled trim and applied +0.25 normalized elevator with no auxiliary-state perturbation. The stock lag minus wing source was −0.200423 m/s at tick 16 and −0.599317 m/s at tick 40. The custom residual reached −527.808 m/s at tick 16 (66.7 ms) and −1.24889309542 × 10¹¹ m/s at tick 40 (166.7 ms), while the custom wing source remained 7.282678 m/s. Both committed all 40 ticks with no simulation fault. These are internal lag values, not aircraft or local airflow speeds. Native source equivalence was inspected. The engine result here is GDScript reference only.

**Remediation.** Validate that the derived length is strictly positive before publishing a model with this wake law. Return a field-specific error for a horizontal pressure centre at or ahead of the model’s shedding station. Keep the existing arithmetic unchanged for positive lengths. Include negative and exactly zero lengths and a healthy stock control in loader and session tests. Supporting a deliberately forward horizontal surface would require an appropriate wake interaction for that geometry. The gradient-free layout is outside the demonstrated defect. No matching finding was located in the consolidated ledger, the fixed-wing review, or the public scope of A36/PR 17.

## Existing propulsion findings rechecked

| Finding | Current baseline evidence | Classification |
|---|---|---|
| Phoenix static figure of merit | `app/workshop/creator/phoenix/physics.gd:736–742` scales CP using a merit larger than the correct one by π/2. `app/tests/test_creator_phoenix_readers.gd:1023–1024` shares the formula. At unity coefficient/advance-ratio scaling, the donor’s static CT = 0.113 and CP = 0.0471 give true merit 0.643483. The importer gets 1.010780 and multiplies the entire CP map by 1.263475 against its 0.8 design cap. | A36 F6. Draft PR 17 contains a correction and an independent dimensional power test. The reviewed main still has the old equation. This affects those Phoenix-derived packages on which the erroneous cap trips. |
| External electric CT/CP tables can prescribe excess thrust work | At J = 0.501 the stock Turbo Lumber’s CT = 0.0731 and CP = 0.0536. Change only CP to 0.0200, within the scalar admission bounds at `app/physics/aircraft_data.gd:1332–1354`. At 6000 rpm, D = 0.2794 m, ρ = 1.225 kg/m³ and axial U = 13.99794 m/s, the production law at `app/physics/propulsion.gd:659–665` gives 76.3877 W of thrust work and 41.7156 W shaft demand. The stock shaft demand is 111.7977 W. | A36 R6-G01 notes this admission opportunity and a separate ordinary-trim witness. This is a synthetic input hardening case. The calculation here is a single shaft-aligned operating point. |

For static operation the ideal induced power is `T × sqrt(T / (2ρA))`. With `A = πD²/4`, `T = CT ρ n² D⁴` and `P = CP ρ n³ D⁵`, the ratio is `sqrt(2/π) × CT^(3/2) / CP`. For forward shaft-aligned flight, the dimensional power balance reduces to `CP − J CT ≥ 0`. The exact interval screen split each pair of tables at the union of their knots and tested both endpoints and every interior stationary point of the resulting quadratic. All **ten** direct records using the tabulated propulsion law passed throughout the shared authored J range: six catalog base files and four synthetic fixtures, representing seven distinct table pairs. The smallest margin was 0.00409308 on the F4U, at interior J = 0.974567. Some records share tables. The screen excluded extrapolation, turbine/rotorcraft records and glow installations whose runtime loads use the blade-element law.

Sources for the dimensional relationships and previous audit are [Georgia Tech actuator-disk model](https://www.sankar.gatech.edu/sites/default/files/Actuator_Disk_Model.pdf), [Dantsker, Selig and Mancuso, AIAA 2017-3745](https://m-selig.ae.illinois.edu/pubs/DantskerSeligMancuso-2017-AIAA-Paper-2017-3745.pdf) and [OpenRC Simulator PR 17](https://github.com/bultodepapas/OpenRCsimulator/pull/17).

## GDScript computes an unused three-dimensional strip speed

At `app/physics/aero.gd:489,493,572`, each strip computes its lateral velocity and the three-dimensional velocity norm. Only optional debug rows read that norm, at lines 574–579 and 636–643. Production calls at lines 982–985 and 995 pass a null diagnostics array. The reference local-load path consequently executes six diagnostic square roots per conventional six-strip evaluation. The native stage at `research/native-kernel/src/nk_aero.hpp:856–860` already avoids them.

A candidate patch could guard the diagnostic-only norm behind `strip_diagnostics != null` and compute lateral velocity there, retaining the existing spatial offset arithmetic and the existing zero-plane and nonzero-plane diagnostic outputs. Keep the distinct plane-speed square root used by the actual force law. The applicable workload includes local stall and flap combinations and excludes attached clean global-only evaluations. The A33 companion distance/sqrt candidate and A2 wing-flow reuse both concern different expressions. This is a source count. Reward depends on whole-flight A/B measurements, identical force/moment and diagnostic bytes, and replay with the real release build. The separate polar-overwrite candidate for Extra/Avanti is tracked by the native engineering review.

## Reproduction

From the repository root, use the [audit reproduction guide](../../../../research/swarm-audit-2026-11-28/README.md) and its checked runner:

```bash
python3 research/swarm-audit-2026-11-28/probes/coefficient_energy.py .
python3 research/swarm-audit-2026-11-28/run_probes.py --godot .tools/Godot_v4.8-beta2_linux.x86_64 --case downwash
```

The downwash probe loads its temporary raw file through the production API and removes it after the measurements. Its final assertions require the isolated recurrence and both forty-tick maneuvers. The script prints `DOWNWASH_TRANSPORT`; the compact checked receipt and raw output are in the audit evidence directory.
