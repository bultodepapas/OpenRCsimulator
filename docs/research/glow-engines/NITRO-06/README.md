# NITRO-06: the glow carburettor as a flow restriction

2026-10-19 · **Status: implemented in the shared glow kernel and the six generated installations; software verified. The idle no longer pulls in flight, the level-flight throttle of the four glow catalog aircraft moved from 1–11 % to 20–37 % of the stick, and a quarter-stick step from the trimmed start no longer climbs. The law's three quantities are derived from estimates and one dynamometer figure, not from a measurement of these engines.** Part of the [D6e-R3 power-step investigation](../../flight-dynamics/power-climb-2026-10-19/README.md); owning plan [RC glow engine realism](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md).

## The defect

The glow kernels (`physics/glow/two_stroke.gd`, `four_stroke.gd`) take `admission`, the charge per cycle relative to wide-open breathing. Until this step the installation mapped the throttle to it directly: `admission = idle_admission + (1 − idle_admission)·servo`, a constant per stick position. That makes a closed throttle admit the same 28 % of the cylinder at every engine speed. On the ground, where the propeller holds the engine at 2,800 rpm, that is the idle. In a glide the propeller unloads, the engine speeds up and, at a constant charge per cycle, the delivered air and the power grow with the speed: at 20 m/s the idling MAX-61FX turned 9,169 rpm, made 174 W and pulled 4.7 N, enough to fly the Stik and the Extra level with the throttle closed.

Measured on the flight-test card ([card v5 `power_step`](../../../../research/flight-test/README.md#the-card), hands-off throttle steps from the trimmed start, [D6e-R3](../../flight-dynamics/power-climb-2026-10-19/README.md)):

| Aircraft (glow law) | Level throttle at the start speed | Idle, path angle after 30 s | 25 % stick | 50 % stick |
| --- | ---: | ---: | ---: | ---: |
| Stik MAX-61FX | 1.5 % | −0.6° | +12.2° | +46° |
| Extra 300S MAX-61FX | 1.5 % | −0.5° | +8.0° | +19° |
| Stik MAX-55AX | 10.3 % | −4.2° | +5.3° | +17° |
| Stik FS-64V | 11.0 % | −5.0° | +6.8° | +20° |

A real .60 glow engine at its idle stop in a 15–25 m/s glide runs at about 4,000–6,200 rpm and its 12×6 gives roughly zero to −1.5 N, never the static idle thrust ([research note, section 2](throttle-power-research.md#2-idle-in-a-glide)).

## The law

A carburettor throttle is a flow restriction. Heywood (*Internal Combustion Engine Fundamentals*, 1988, §7.6.2, eqs. 7.26–7.28) gives the air mass flow through the open area A at the pressure ratio r = p_manifold/p_ambient as the isentropic nozzle flow

```text
ṁ = Cd·A·p0/√(R·T0) · Ψ(r),   Ψ(r) = r^(1/γ) · √(2γ/(γ−1) · (1 − r^((γ−1)/γ)))  for r > r_c,
Ψ = Ψ_c = √γ · (2/(γ+1))^((γ+1)/(2(γ−1)))  for r ≤ r_c (choked),   r_c = 0.5283, Ψ_c = 0.6847 (γ = 1.4).
```

The engine draws r·ρ0·V_d·η_b(n)·n/(60·revs) (isothermal manifold; η_b is the profile's delivery ratio or volumetric efficiency; revs is 1 for a two-stroke, 2 for a four-stroke). With x = Q_engine/Q_capacity (Q_capacity = Cd·A_open·Ψ_c·√(R·T0), the choked volumetric capacity of the fully open path) and a = A/A_open, the balance is r·x = a·Ψ(r)/Ψ_c, whose root depends only on y = a/x: r = y when y ≤ r_c (the orifice chokes: mass flow fixed by the opening, charge per cycle ∝ 1/rpm) and the unique root of r = y·g(r) above it. The kernel's admission is r(a, n)/r(1, n): the profile tables already describe wide-open breathing through this carburettor, so the fully open throttle admits exactly 1 at every speed.

The barrel's open area is the lens common to two equal circles offset by u = d/(2R): a(u) = (2/π)(acos u − u√(1 − u²)), moved from the idle stop u_idle (where the lens equals the idle opening) to u = 0 at full throttle along u = u_idle·(1 − servo)^p.

Implementation: [`physics/glow/carburetor.gd`](../../../../app/physics/glow/carburetor.gd) (pure, with [`research/glow-engines/carburetor.py`](../../../../research/glow-engines/carburetor.py) as the independent mirror). The lifecycle's lagged `air_fraction` state is now the barrel opening (target `Carb.opening(servo)` through the unchanged air time constant), and every evaluation derives the admission from the opening and the stage rpm: `lifecycle.gd`, `operating_point.gd` (trim and equilibrium), `flight.gd` (initial state, fuel feed, stopped-crank friction) and the session starter. Telemetry reports both `throttle_opening` and `admission`. The glow law identifier is `glow-mean-cycle-carburettor-v4` and the continuous layout names the slot `throttle opening`; v2/v3 traces stay readable with their own laws.

### The three installation quantities (`openrc-glow-installation v2`)

| Setting | 2T (55AX / 61FX) | 4T (FS-64V) | Derivation |
| --- | ---: | ---: | --- |
| `throttle_effective_area_m2` (Cd·A of the open path) | 2.34e-5 / 2.61e-5 | 9.90e-6 | From the NITRO-05 wide-open venturi depression estimate (6,000 Pa 2T, 4,000 Pa 4T, `fuel_feed.wot_drive_pressure_pa`): r_wot = 1 − Δp/p0 gives y_wot = r/g(r), so x at the rated rpm and the capacity. Equivalent to a 5.5–5.8 mm (2T) or 3.6 mm (4T) fully effective bore. |
| `idle_opening` (area fraction at the idle stop) | 0.0150 | 0.0239 | The former per-cycle idle charge (0.28 2T, 0.35 4T) at the declared 2,800 rpm static idle, through the choked law: a_idle = y(r_idle)·x(2,800 rpm). |
| `throttle_travel_exponent` p | 0.49–0.55 | 0.45 | Calibrated so the static half-stick equilibrium on each installation's propeller sits at 0.81 of the full-throttle static rpm: Menon 2010 (O.S. 46 FX, barrel carburettor, Fig. 7-11, read from the figure) puts a half-open barrel on a matched propeller at 78–84 % of the wide-open rpm ([note, section 1](throttle-power-research.md#1-throttle-position-versus-rpm-and-power)). A linear travel (p = 1) gives 91–93 %. |

[`build_installations.py`](../../../../research/glow-engines/build_installations.py) derives all three and records each derivation in the quantity's `source`; the static balance it solves uses the independent Python cycle oracle, which reproduces the kernels' full-throttle static rpm (10,330; 12,550; 7,785). [`installation_schema.py`](../../../../research/glow-engines/installation_schema.py) writes the v2 schema; `idle_admission` and the v1 schema are gone.

## Results

Static engine speed against the stick (rpm; the full-throttle point is unchanged by construction):

| Stick | 61FX / Extra before → after | 55AX | FS-64V |
| --- | --- | --- | --- |
| 0 | 3,724 → 3,144 | 2,832 → 2,815 | 2,775 → 2,793 |
| 0.25 | 6,602 → 7,388 | 4,782 → 6,195 | 4,294 → 4,862 |
| 0.50 | 9,066 → 10,165 | 6,987 → 8,367 | 5,511 → 6,306 |
| 0.75 | 11,003 → 11,646 | 8,698 → 9,632 | 6,664 → 7,189 |
| 1.00 | 12,550 | 10,330 | 7,785 |

Thrust at 20 m/s, N (shaft power, W):

| Stick | 61FX / Extra | 55AX | FS-64V |
| --- | --- | --- | --- |
| 0 | +4.67 → −1.17 (174 → 18) | +3.21 → −0.54 (112 → 17) | +2.94 → −4.52 (202 → 4) |
| 0.10 | 7.46 → 1.50 (256 → 86) | 4.98 → 1.57 (161 → 69) | 4.85 → −2.51 (258 → 54) |
| 0.25 | 11.71 → 7.13 (390 → 246) | 8.04 → 5.88 (250 → 186) | 7.76 → 1.43 (345 → 160) |
| 0.50 | 19.49 → 19.36 | 14.41 → 15.62 | 12.73 → 9.80 |
| 1.00 | 35.37 | 27.65 | 22.31 |

Idle in flight after the change (rpm / thrust): 61FX 4,489 / +0.97 N at 10 m/s, 5,922 / 0.0 at 15, 7,528 / −1.17 at 20, 9,204 / −2.55 at 25 m/s; the derived real range is 4,000–6,200 rpm and +0.7 to −1.4 N at 15–25 m/s. The thrust is right; the engine speed is 20–30 % high because the installations' blade-element surrogate propeller (pitch 6 in, no camber) reaches zero thrust near J 0.5 where the measured APC Sport reaches it at J 0.75–0.77, so it windmills faster. That is the NITRO-02 propeller surrogate, not this law.

Level-flight throttle at the start speed: 61FX 1.5 % → 20.0 %, Extra 1.5 % → 22.1 %, 55AX 10.3 % → 22.4 %, FS-64V 11.0 % → 36.8 %. The after-change `power_step` flights are in the [D6e-R3 report](../../flight-dynamics/power-climb-2026-10-19/README.md#after-nitro-06).

On the whole flight-test card, flown on the same tree with and without the law ([FT-05 verification](../../flight-test/FT-05/README.md#verification)), the four non-glow aircraft are unchanged to the last bit and the four glow aircraft gain valid tests: their power-off stalls break for the first time (9.3–10.8 m/s), the slowest level trim falls from 18–21 m/s to 10–12 m/s, the idle glide ratio becomes finite (9.0–14.4), and the landings touch down at 11.7–13.6 m/s instead of 19.4–25.0 m/s. Full-throttle values are unchanged by construction.

## Verification

- `test_glow_carburetor.gd`, 58 checks: the nozzle constants recomputed from their definitions; g(r) and r(y) against independent scalar values at 1e-12; the choked identity r = y; the balance r·x = a·g(r) at a mid opening; wide-open admission 1 at every speed; charge ∝ 1/rpm at a small opening; monotone in the opening and in the speed; the lens, its inverse and the travel exponent; rejection of invalid inputs. `research/glow-engines/test_carburetor.py` holds the same values for the Python mirror.
- Glow suites after the change: installation 345, lifecycle 52, equilibrium 196, flight physics 110, session 140, trace 286, prepared 580, stage reuse 2,005 comparisons, fuel feed 38, coupling 65, hub inflow 168, propeller prepared 38, audio 42, two-stroke 50, four-stroke 304, oracle 723, profiles 53, thermal 15, vibration 37, propeller momentum 63 checks, all passing. `test_glow_installation` adds the zero-area and out-of-band exponent rejections.
- Generators: `build_installations.py --check`, `installation_schema.py --check`, the schema, build and line-ending Python tests, `build_descriptors.py --check` (8 descriptors current) and `build_models.py --check` pass. The aircraft JSON files did not change (the installations are separate files).
- The flight-test card flies all four aircraft through the new law; the before/after tables above come from [`part_throttle_probe.gd`](../../../../research/flight-dynamics/power-climb/part_throttle_probe.gd).

## Limits

- The three quantities are derived from estimates (venturi depression, the former idle charge) and from one figure of another engine (O.S. 46 FX). No carburettor of these engines was measured; no in-flight idle rpm of any glow engine was found. The static rpm-against-stick table above is a prediction to compare with a measured curve when one exists.
- The four-stroke shares the two-stroke's half-barrel anchor; its stronger idle brake at 20–30 m/s (−4.5 to −11 N) comes from its 14×6 surrogate propeller, not from the carburettor.
- The travel exponent stands for barrel kinematics and linkage that no drawing gives. It is one number per installation, exposed in the data file.
- The NITRO-02 matched-cycle oracle evidence predates this law; `matched_cycle_oracle.py` now takes command-derived openings and admits through the same Python mirror, but its recorded output was not regenerated.
- Side finding from the literature search for the fuel owners: Glassock (2012) measured 29.3 ml/min at full throttle and 11,000 rpm on a 10 cc O.S. FX with a 12×6, 25–35 % below the NITRO-61FX candidate's 38.8–46 ml/min at similar rpm; the O.S. manual's 12–13 min per 350 cm³ agrees with the measurement.

## Reproduce

Release verification, 2026-10-19: the carburettor's `pow`, `sqrt` and `acos` calls
now use the existing `math3d` wrappers, satisfying the H6 simulation boundary.
Those wrappers call the same built-ins. A native Godot 4.7.2 comparison of 5,005
sampled flow, root, lens, opening and capacity outputs against the pre-routing
source was byte-identical; the checked carburettor suite passed all 58 checks.
This routing change does not alter the physical law.

```sh
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script res://tests/test_glow_carburetor.gd
python3 research/glow-engines/test_carburetor.py
python3 research/glow-engines/build_installations.py --check && python3 research/glow-engines/installation_schema.py --check
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- --out=/tmp/part-throttle.csv --aircraft=stik-glow-61fx-2t,gp-extra-300s-60
python3 research/flight-test/run.py --out /tmp/ft-power --only power_step --aircraft stik-glow-61fx-2t,stik-glow-55ax-2t,stik-glow-fs64v-4t,gp-extra-300s-60
```
