# HELI-06b: Passive local airframe loads

**Date:** 2026-10-13. **Scope:** standalone fuselage, vertical-fin, and horizontal-tail loads with caller-supplied local wake velocities. The equations define a passive numerical extension; they do not qualify an aircraft or close the rotor wake.

## Source audit and selected signs

Gavrilets, Mettler, and Feron, [“Dynamic Model for a Miniature Aerobatic Helicopter”](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), §§4.3–4.5, printed pp. 14–16, is the reference. The rendered pages are the cited source pages, not simulator output. The rigid-body equations on p. 4 put gravity in positive `ẇ`; the main-rotor force equation on p. 12 gives upward thrust as `Zmr = −T`; the air-relative velocity definitions on p. 6 subtract wind. Together these establish the paper’s forward/right/down force convention.

Several printed signs conflict with the stated conventions. Section 4.3’s initial low-speed and flat-plate `Xfus`/`Yfus` expressions have positive velocity terms despite describing drag that opposes motion; its final approximation gives negative terms. The same final approximation uses `wa + Vimr` for fuselage vertical speed, while tail-wake Eqs. 37 and 39 subtract `Kλ Vimr`. Section 4.5 Eq. 40 gives `Zht` the same sign as `wht`; with `+z` down, that makes its vertical force point with local vehicle-relative flow. This report records the equations as printed and treats all passive signs below as an explicit extension, not a claim about an erratum or an exact transcription. Gavrilets Eq. 35 already opposes fin side velocity. NASA’s [NDARC theory](https://ntrs.nasa.gov/api/citations/20160012474/downloads/20160012474.pdf) independently defines component velocity relative to air using body translation, `ω × r`, and subtracted air-interference velocities, then resolves aerodynamic drag opposite the velocity.

For each center of pressure, the caller supplies a wake-air velocity increment `v_wake` in body FRD. The local vehicle velocity relative to that air is

```text
vrel = vCG,air + ω × r − vwake
```

The selected forces are

```text
Ffus,i = −0.5 ρ Sfus,i vrel,i |vrel|
Fvf,y* = −0.5 ρ Svf (avf √(vrel,x² + vrel,z²) + |vrel,y|) vrel,y
Fht,z* = −0.5 ρ Sht (aht |vrel,x| + |vrel,z|) vrel,z
```

The vertical-fin force is capped at `0.5 ρ Svf |vrel|²`; the horizontal-tail force is capped at `0.5 ρ Sht (vrel,x² + vrel,z²)`. Each cap preserves its ideal force sign. Other surface-force axes are zero in this damping-only law. All component moments use `r × F`. Consequently each component satisfies `F · vrel ≤ 0`. Its power on the body may be positive when a supplied wake transfers energy: `Pbody = Prel + Pwake`, with `Prel = F · vrel` and `Pwake = F · vwake`.

Here `body_air_power_w` means work relative to the ambient air reference: `Σ F · (vCG,air + ω × r)`. It equals `Ftotal · vCG,air + Mtotal · ω`. Actual world-frame body power also includes `Ftotal · vambient`; this kernel cannot infer that term because ambient/ground velocity is not an input. Relative-flow passivity does not imply that aircraft world-frame kinetic energy always decreases in wind.

## Reference and evidence

[`airframe.py`](../../../../research/helicopter/reference/airframe.py) requires all nine parameters and all five input vectors. `prepare` returns a flat read-only mapping with detached tuples; it has no aircraft defaults. Wake velocities are explicit and are not inferred from main- or tail-rotor states. The result includes component and total six-axis loads, local relative velocities, cap diagnostics, and relative/body/wake power.

[`airframe_oracle.json`](../../../../research/helicopter/reference/airframe_oracle.json) uses a numerical test fixture, not an aircraft profile. Its independent generator covers rest, three-axis drag, yaw and pitch damping, force caps, backward flow, full point-rate kinematics, and wake-to-body power transfer. Run from the repository root:

```powershell
python research/helicopter/reference/test_airframe.py
python research/helicopter/reference/make_airframe_oracle.py --check
```

These checks establish implementation consistency and the stated passivity properties only. No airframe flight data or physical validation is claimed.

## Native kernel and verification

[`airframe.gd`](../../../../app/physics/rotorcraft/airframe.gd) returns a flat immutable 18-field context with detached scalar arms/areas; all runtime vectors and loads use packed float64. Python retains immutable tuples in its read-only mapping. Both interfaces refuse writable context copies, missing/extra parameters, negative areas/slopes, nonpositive density and nonfinite values. Python raises `ValueError`; native evaluation returns `{ok:false}`. The native compact option omits component diagnostics while preserving identical total load bytes and work values.

The native suite passes 1,799 checks with the ten independent oracle cases, a strict full-output schema check, constructed drag/cap/download anchors, pitch/yaw damping, sign reflection, displaced three-axis CPs, 45 flow/wake samples and force-versus-wrench work identity. Zero flow requires no angle or speed division. Overflow in translation, wake or rate×arm products is refused. Four disposable defects are detected: reversed wake subtraction, reversed pitch point velocity, a horizontal force that injects relative-flow energy, and a tail cap incorrectly including lateral flow.

```powershell
$AirframeOracle = (Resolve-Path research/helicopter/reference/airframe_oracle.json).Path
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_airframe.gd -- --oracle="$AirframeOracle"
```

The native test fixture uses the X-Cell drag areas and tail dimensions as explicit numerical inputs at ρ=1.225 kg/m³. The horizontal-tail CP's test height is zero because Table 1 does not give that height; it is not a measured datum. The oracle uses a separate numerical profile and off-axis points. Neither profile is authored aircraft data.

## Joint aerodynamic stage

[`aerodynamic_stage.gd`](../../../../app/physics/rotorcraft/aerodynamic_stage.gd) evaluates main-hub point velocity, main disc/inflow, tail rotor and all three airframe pieces from the same `[a1,b1,vi]` stage. Shaft speed is prescribed. Its named `openrc-xcell-shaft-airframe-wake-v1` approximation supplies downward main-vi air motion to the fuselage, the tail source's `Kλ vi` to both tail surfaces, and explicit `ε vi,tr` lateral wake to the fin. The exposure fraction is required and bounded in [0,1]; no aircraft default is hidden. Tail compact output now includes the already-computed wake factor; no tail load arithmetic changed.

The wrapper refuses inconsistent density, main radius, or fin area between blockage and fin loading. It computes all loads once and adds each component once, retaining the aerodynamic shaft moments already supplied by the rotor kernels. It stores no previous-stage flow/load cache and mutates no input state. Main-hub velocity uses the full CP cross product; the tail retains its documented source approximation.

The 47-check stand verifies load composition, compact/full byte parity, stage-vi effects on thrust and download, main-hub p/q point flow, same-stage tail-wake delivery, missing/mismatched context refusal and residual main wake after rotor stop. A 16-state workspace passes through the existing RK4 core at h, h/2 and h/4 while its 13 body entries remain clamped. Main vi settles to the independently derived unsaturated hover quadratic; flap targets and fuselage download also settle. This is a component stand, not complete hover trim or free-body flight.

Full body/drive/momentum/control coupling, spatial wake convection, TPP-aligned/inverted wake qualification, automatic Johnson seam localization and session integration remain open. Aerodynamic relative-work diagnostics do not close the entire rotor/airframe wake energy budget.

## HELI-09d joint-stage cost

[`bench_aerodynamic_stage.gd`](../../../../research/helicopter/bench_aerodynamic_stage.gd), Windows Ryzen 9 5900X, official Godot 4.7.2, 2026-10-13: 20 warmed batches of 500 compact evaluations per fixture.

| Joint fixture | Median batch mean (µs/call) | p95 batch mean (µs/call) |
| --- | ---: | ---: |
| Hover | 106.73 | 129.64 |
| Forward | 103.49 | 113.77 |
| VRS crossflow | 125.18 | 145.51 |
| Windmill | 103.25 | 119.14 |

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/helicopter/bench_aerodynamic_stage.gd
```

This diagnostic exceeds the proposed 37 µs full-evaluation gate even before drive, body, controllers and seam localization. It does not measure individual-tick p95 or the H15 acceptance host. HELI-09 remains open: profile the complete evolving path and redesign validated-context/payload evaluation before flight integration; do not simplify the source laws or remove input guards to pass a timing number.
