# FPV battery and power improvement — 2026-11-16

**DR-05/10/16/17/18/21; experimental implementation.** This change adds delayed battery sag and recovery, replaces unlimited pack regeneration with an explicitly identified dissipative braking policy, and admits hover against the loaded four-motor bus. It addresses **A06** and **A08** from the [audit](../audit-2026-11-16/README.md) and the battery/negative-drag subset of **A09**. Full prepared-document physical-schema parity remains open.

The source baseline is `a92598fd5c69bde3b9e4edcd5267a0be2e3ba91a`, whose production FPV code is unchanged from the original audit baseline. The implementation branch is `fix/fpv-battery-power-2026-11-16`. No hardware measurements or native pilot qualification are implied by these software results.

## What changes in flight

- A throttle burst causes an immediate resistance drop and then a slower polarization drop. After the burst, the immediate part recovers while polarization relaxes over simulated time. Charge does not return during voltage recovery.
- The controller's static motor map sees the sampled OCV minus the existing polarization drop. The four-motor bus still solves instantaneous load sag at every integration stage; no wall-clock smoothing or arbitrary motor lag is added.
- Braking keeps signed mean motor torque and may supply other motors and auxiliaries. Surplus generation becomes explicitly accounted effective motor-path resistive loss. The selected policy never charges the pack.
- Restoring an overcharged pack, negative energy/heat, or invalid polarization refuses the checkpoint before replacing the current flight. The retired `damped` setting receives an explicit admission error.
- The loader and prepared-data session path now reject electrically impossible hover, inadequate individual motor duty, and unsupported fast RC configurations. A refusal preserves the accepted session.

A same-tape chart can be generated from the privately retained simulation CSVs by [analyze.py](analyze.py). The lower instantaneous resistance intentionally increases the initial burst voltage/current relative to the old all-instantaneous estimate. This is a consequence of the chosen exploratory split, not a measured improvement in the real aircraft's performance.

## Battery model and parameters

The new pack is a constant-parameter one-RC Thevenin equivalent. Current is positive during discharge:

```text
SOC       = Q / Qmax
Vsource   = OCV(SOC) - vp
Vbus      = Vsource - R0 * Ipack
Q_dot     = -Ipack
vp_dot    = (R1 * Ipack - vp) / tau
pack_heat = R0 * Ipack^2 + vp^2 / R1
RC_energy = 0.5 * (tau / R1) * vp^2
```

The differential energy identity is `OCV*Ipack = Vbus*Ipack + pack_heat + d(RC_energy)/dt`. The RC state continues to decay and dissipate after depletion disconnects pack current. Disarming still leaves the modeled auxiliary load connected while charge is positive, so a connected disarmed pack need not recover fully to OCV. Missing RC fields, or a zero/zero pair, select the purely resistive limit and require `vp=0`.

| Source parameter | New value | Provenance and interpretation |
| --- | ---: | --- |
| Cells / nominal capacity | 6S / 1.3 Ah | Existing estimates; full charge is 4,680 C |
| `resistance` / normalized `resistance_ohm` | 0.020 Ω | Estimated instantaneous R0 |
| `polarization_resistance` / `polarization_resistance_ohm` | 0.010 Ω | New estimated delayed R1 |
| `polarization_time` / `polarization_time_s` | 1.0 s | New estimated relaxation time |
| Auxiliary current | 0.6 A | Existing estimated FC/VTX/receiver load |
| SOC/OCV curve | Existing generic curve | Estimated resting voltage, not a selected pack measurement |

R0 + R1 preserves the previous 0.030 Ω estimate at steady DC. The original resistance had no identified measurement timescale; neither the split nor the one-second time constant is fitted to a real racing pack. The source-owned [sources.json](../../../../research/drone-racing/openrc-fpv5-x1/sources.json) and [derive.py](../../../../research/drone-racing/openrc-fpv5-x1/derive.py) generate the shipped JSON.

Battery domains are shared by raw and prepared admission: finite capacity, cell count, nonnegative resistances and auxiliary load, ordered SOC/OCV points spanning 0–1, bounded per-cell voltage, and a valid RC parameter pair. `tau >= 0.02 s` is only a scalar floor. An additional frozen-shaft screen requires:

```text
h * |lambda_RC| = [1 + 4 R1 u_max^2 / (Rm + 4 R0 u_max^2)] / (240 tau) <= 1
```

This is a conservative screen of the added RC pole, **not** a stability proof for the complete coupled motor/body/charge Jacobian. The stock proxy is approximately 0.00495. A counterexample with R0=0, R1=1 Ω, tau=0.02 s can pass steady hover while giving approximately 6.48, so it is refused. A point just inside the limit is retained as a positive test.

## Braking policy and energy accounting

`damped_nonregenerative` is a new experimental averaged policy, not a claim about installed BLHeli firmware. The alternative `none` remains the existing one-quadrant/coasting policy. The old unbounded `damped` setting is refused by the raw reader, prepared session admission and direct plant construction.

Ordinary signed motor current is `(d*Vbus - E)/Rm`. When aggregate bus demand is nonnegative, the shared resistive bus is solved normally. When the unconstrained bus would charge the pack, the solver instead finds a coherent switching allocation with `Ipack=0` and `Vbus=OCV-vp`:

1. At that voltage, compute positive bus demand D, including auxiliaries, and generated current G from negative motor contributions.
2. Use `alpha=D/G` of each generating motor's bridge power to supply the other loads.
3. Preserve the generating motor's mean current and torque. Model the remaining fraction by an active-short/coast mixture; its extra resistive loss is `(1-alpha)*(-d*Vbus*I)`.
4. Compute equivalent RMS current from total effective resistive loss. Squaring the mean current alone would omit switching-current variance and fail the energy balance.

The fitted Rm already lumps motor, ESC and wiring resistance. It is reused in the conceptual switching states. Therefore `p_motor_resistive_w` and `i_motor_rms` describe the equivalent path; they do not identify physical winding temperature or three-phase RMS current. `p_brake_loss_w` is a diagnostic subset already included in that resistive loss. There is no added external dump resistor or unaccounted energy sink.

The scalar coast assumption is admitted only when the generating back-EMF does not exceed bus voltage. An out-of-domain state is refused instead of inventing zero-current coast despite possible diode rectification. Disabled motor paths retain the previous ideal-isolation assumption. Real phase inductance, commutation, current limits and thermal protection remain unmodeled.

Near-zero demand uses the same grouped current totals for branch selection and allocation, avoiding a reproduced binary64 cancellation refusal. The selected branches have `Ipack>=0` at every valid stage; consequently, Q cannot increase from an admitted initial value under the RK4 weights. Accepted/restored states enforce the strict upper bound `Q<=Qmax`. The existing lower-charge endpoint depletion policy and its small permitted negative endpoint overshoot remain; this change does not introduce sub-tick depletion event localization.

## Loaded hover admission

Hover thrusts are recomputed from mass and rotor geometry, independently of cached derived diagnostics. For each rotor, the check computes speed, regularized shaft-friction current, required motor voltage and duty. With `Rp=R0+R1`, the settled bus obeys:

```text
Vbus^2 - (OCV - Rp*Iaux)*Vbus + Rp*sum(U_motor*I_motor) = 0
```

The check selects the high-voltage root, requires positive power margin, verifies every motor's idle/max duty and speed limit, and reconstructs bus/current/shaft-torque residuals. It runs at full charge and the first listed SOC knot strictly above 0.1 (0.2 for the stock curve). A normalized wrench solve avoids an underflowing dimensional yaw pivot. This is a frozen-SOC operating-point screen, not a guarantee of sustained controller hover or endurance.

The old single-motor OCV maximum-thrust diagnostics retain their meaning. New tests independently reject a 10 Ω pack, a pack that fails only at low charge, excess auxiliary demand, polarization resistance that removes hover margin, and a 0.210 duty ceiling that passed the former OCV check but falls below the loaded requirement of approximately 0.210518.

## State, telemetry and replay

The electric law is `multirotor-controlled-el-coupled-v2`; the layout is `openrc-multirotor-controlled-el-v2`. Indices 0–7 retain their positions; index 8 adds polarization voltage. The pack identity is `multirotor-pack-one-rc-v1` and the braking bus identity is `multirotor-damped-nonregenerative-bus-v1`. Laboratory state remains unchanged.

Telemetry adds OCV, polarization voltage/energy, terminal power, total pack heat and braking-loss diagnostics. Existing battery voltage/current/SOC displays consume the revised values. The separate existing `consumed_mah` reference-to-document-initial-SOC issue is **not** repaired here; comparisons use remaining charge directly.

Production restore and exact replay rules are not weakened. Old eight-state recordings do not become exact new-law replays, and unknown mid-flight polarization is not invented. The research-only [compare.gd](compare.gd) accepts an old baseline only at a complete, disarmed, rested tick-zero checkpoint whose existing arrays and physical configuration match the fresh candidate byte for byte; the new polarization state starts at zero. It then feeds the preserved pilot tape, records explicit candidate deltas, and separately verifies the new recording exactly under the new solver. The nested candidate comparison always reports `exact=false` and `solver_changed=true`.

## Results and verification

Before editing any solver source, three baseline recordings each completed 1,418 ticks and passed exact replay. The candidate uses all three identical pilot tapes, starting at 100%, 50% and 20% charge. All candidate flights complete without a fault or crash, and each new recording passes its own exact replay. Both sets retain the terminal reason `power maneuver complete`; a complete container alone is not treated as successful flight.

| Initial charge | Minimum bus V, old → new | Peak pack A, old → new | Minimum pack A, old → new | Maximum delayed loss, new | Final position difference |
| --- | --- | --- | --- | --- | --- |
| 100% | 18.385 → 19.973 | 226.074 → 254.962 | −34.246 → 0 | 0.472 V | 2.044 m |
| 50% | 16.835 → 18.287 | 206.418 → 232.828 | −32.605 → 0 | 0.418 V | 2.015 m |
| 20% | 16.395 → 17.809 | 200.871 → 226.578 | −32.087 → 0 | 0.403 V | 1.978 m |

These are short power-stress maneuvers, not a competitive racing benchmark or an endurance estimate. Higher initial power follows from the exploratory R0/R1 split. The new full-charge run consumes 129.198 C versus 123.615 C before, reflecting the changed load response and no-charge braking policy; voltage recovery is not replenished capacity.

Key independent checks include:

- A real plant run with a one-second 10 A pulse: `vp=0.0632120559 V`, with terminal energy, resistor heat and stored RC energy closing the 240 J chemical-energy integral. On disconnection, the state decays to `0.0232544158 V` after a further second without drawing charge.
- Four braking motors at 24 V with 16 V back-EMF, duty 0.5, Rm=0.1 Ω and 0.5 A auxiliaries: −40 A mean current per motor, zero pack current, 637 W effective resistive loss per motor and 12 W auxiliaries. The 2,560 W mechanical release is fully accounted.
- An independent exponential shaft solution and integrated kinetic-to-loss balance converge at 60/120/240 Hz; the 240 Hz energy error is about `2.59e-10 J` in that synthetic oracle.
- The existing throttle-chop control gate remains: at 50 ms, braking reduces the sampled shaft to approximately 1,242 rad/s versus 2,320 rad/s with coasting; roll authority after eight ticks remains above its original threshold.
- The original product air-start route at full and 99.9% charge accepts arm/punch/chop without charge increase or a fault. Checkpoint mutations include a one-ULP overcharge, invalid polarization, negative energy/heat and the legacy layout.
- The stock response passes the existing timestep/sample-rate checks. A complete three-lap race finishes and replays all **16,372 accepted ticks** exactly, including the race suffixes and final lap times.

**12 targeted suites: 524 checks, zero failures.** [validation.json](validation.json) records each final checked-suite verdict, test-script digest and source identity. The groups cover battery/braking and loaded admission (177 checks including the controlled plant), data (86), sessions/flight logs (98), racing (57), numerical/contact checks (28), and OSD behavior (78). The retained evidence is Linux headless software verification. Native controls, visible 1080p acceptance, thermal behavior and real flight handling remain unqualified; required hosted CI is a separate gate. The local repository-wide large-file check cannot complete because four existing allowlisted assets are present in the baseline tree but are not materialized in this checkout; its policy is unchanged by this work. Every added artifact is below 0.5 MB. The exact paths and check result are recorded in `validation.json`; no unrelated asset policy was changed.

## Reproduction and retained evidence

The public branch retains the [baseline](evidence/baseline/summary.json) and [candidate](evidence/candidate/summary.json) aggregate summaries, and the portable verdicts in `validation.json`. The full recording package, including the original `.orfl` files, CSVs, pilot tapes, markers, accepted states, checksum manifest and plot, is retained privately. Its manifest pins original and compressed file digests, the baseline commit, and the exact Godot 4.8 beta2 engine hash. Original recording and CSV bytes in that package are gzip-compressed without host-path metadata; the raw files and their checksum manifest are not published on this branch. Routine engine logs also remain outside the public evidence.

After extracting the private package so its `evidence` directory is at `tmp/fpv-power-private/evidence`, run from the repository root. The unpack destination must be fresh:

```sh
python3 research/drone-racing/openrc-fpv5-x1/derive.py --check
python3 docs/research/drone-racing/power-2026-11-16/analyze.py --evidence-dir tmp/fpv-power-private/evidence --unpack tmp/fpv-power-replay
python3 docs/research/drone-racing/power-2026-11-16/analyze.py --evidence-dir tmp/fpv-power-private/evidence --plot tmp/fpv-power-replay/comparison.png
```

Use a fresh output directory for the following candidate comparison:

```sh
OPENRC_FPV_BASELINE_DIR="$PWD/tmp/fpv-power-replay/baseline" \
OPENRC_FPV_POWER_DIR="$PWD/tmp/fpv-power-replay/new-candidate" \
python3 tools/godot/run_checked.py --label fpv-power-comparison --timeout 240 \
  --out-dir tmp/fpv-power-replay/checks --require-text 'power maneuvers: 3 cases, 0 failed' -- \
  .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app --audio-driver Dummy \
  --script "$PWD/docs/research/drone-racing/power-2026-11-16/compare.gd"
```

To recreate the original baseline, use a separate checkout at the pinned baseline commit, the same pinned engine and the comparison script in recording mode (`OPENRC_FPV_BASELINE_DIR` unset). Exact replay is only claimed for matching source/configuration, engine and platform. New timestamps change container hashes even when accepted state/tape bytes match.

## Sources and remaining physical work

1. [Suti, Di Rito and Mattei, 2022, Thevenin models for Li-Po UAV packs](https://www.mdpi.com/1996-1073/15/23/9249). Supports the equivalent-circuit model family and pulse/rest identification. Its 6S 1850 mAh pack and test regime do not supply parameters for this estimated 1300 mAh racing pack.
2. [Texas Instruments, active short circuit technology](https://www.ti.com/document-viewer/lit/html/SSZTDA3/GUID-4A4EC389-64F0-4F31-9DAF-438F56ECF2C6). Supports the dissipative principle and the diode-rectification/current/thermal caveats. It does not validate this averaged allocation or an FPV ESC implementation.
3. [BLHeli_32 operation manual](https://raw.githubusercontent.com/bitdump/BLHeli/master/BLHeli_32%20ARM/BLHeli_32%20manual%20ARM%20Rev32.x.pdf). Describes regenerative damped-light operation. The new explicitly named non-regenerative law must not be presented as firmware equivalence.

Bounded regeneration remains a future alternative once charge acceptance, upper-bound event handling and overvoltage behavior are defined. A pack-current or charge clamp by itself is rejected because it breaks energy accounting; removing braking entirely fails the retained early-chop control gate. A fully identified multi-RC/thermal model would require more measured parameters than are currently available.

Next physical qualification needs synchronized pack voltage/current and rotor-speed data for pulse, rest and braking tests across SOC and temperature; identification of R0/R1/tau and effective braking losses; and held-out flight comparisons. Cell imbalance, temperature-dependent resistance/capacity, aging, ESC current/thermal limits, undervoltage supervision and sub-tick terminal events remain explicit follow-up work.
