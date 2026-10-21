# EX-14: Extra 300S realism pass against the weighed build and owner reports

2026-10-20 · EX-14a/c/d/e, with shared steps NITRO-61FX-R1 and D10-R3 · **Status: delivered as software; the aircraft stays experimental.** Owner: [Extra aircraft guide](../../../EXTRA-300-PLAN.md).

Goal: make the GPMA0236 Extra 300S .60 fly like the real RC model. The targets come from the only magazine flight report of this kit, from five named owners on its build thread, and from comparable 60-size Extras. Each change below is a mechanism with its own source. None is a gain tuned to pass a maneuver. Software verification here does not establish physical validation (EX-09).

## Sources

The [manifest](sources.json) lists 32 local files (`references/extra-300/`, gitignored) with URL and sha256, plus links and dead ends.

- **RCM product review**, April 2000, Jack J. Joseph (3-page scan). The prototype ran an O.S. .61FX with a 12 oz tank and weighed "124 Oz. (7 Lbs., 12 Oz.)" ready to fly (24 oz/sq ft). In the taxi tests "at 1/3 throttle, the tail lifted off the ground". It flew "loops, Immelmanns, hammerheads, Cuban-8s, rolls", and "the only criticism … was that more rudder was needed for the knife-edges". A "stable flying airplane".
- **RC Universe thread 1062376**, "Great Planes Extra 300 .60 Build/Mods" (2003–05), posts 1–250 recovered from the Wayback Machine. These are owner reports on Saito 100–1.20 and .91 four-strokes, several with enlarged rudders:
  - Built weights 7.6–8.4 lb.
  - Knife-edge "takes full power and full rudder deflection" with the stock rudder, and pitches toward the belly (3–6 % up-elevator mixes). One owner reports 13 % opposite-aileron mixes.
  - Stalls "very very mild … mushes forward"; owners report reluctant spin entries.
  - "Comes in pretty hot"; it "floated way long".
  - High-rate rolls "~1.5 rolls per second" on enlarged ailerons; low-rate rolls "pretty slow".
  - Snaps crisp at high rate.
  - "Inverted takes just a touch of down."
- **Comparable models** (context, not acceptance data):
  - GP Extra 300S .40 (RCM&E 1998);
  - Goldberg Extra 300 (Model Builder and RCSA 1992);
  - Lanier Extra 300L (MA 2003);
  - GP Extra 300SP and Aeroworks Extra 300 (RCU);
  - PAU, DPM, League and Superior Extras (MA).
- **Method references, already local:**
  - Selig AIAA 2010-7635/7938 and 2014: the component model, the propwash wash factor and the fuselage side lift.
  - Letko & Williams NACA TN 3551: fuselage side force by cross-section.
  - Polhamus NASA TR R-29: crossflow drag of rounded rectangles.
  - Ragheb & Selig 2013: measured spins of the 35 % Extra 260.

No source gives a measured speed, roll rate, knife-edge mix or spin rate for a 60-size Extra. The targets are qualitative bands.

## Findings in the previous model (FT-05 and this session's baseline)

- **Knife-edge.** It could not knife-edge: it sank 35 m/s with full rudder. The local aerodynamic model, which takes all loads from β 15°, had the fin's side force only (CY −0.065 at β 20°). The oracle gave −0.168, and 0.111 is needed at 0.8 Vmax.
- **Overspeed fault.** A full-throttle dive faulted the simulation at 19,992 rpm, past the MAX-61FX profile's 20,000 rpm support.
- **No propwash.** The glow installation refused the propwash, P-factor and propeller normal force that the P-51 has. As a result there was no stall-turn pivot, and the rudder-free takeoff swung right, while the manual says to expect a left swing.
- **Mass.** The dry mass was 3.273 kg, below every weighed build.
- **Ground effect.** None.

## Changes

| Step | Change | Owner / files |
| --- | --- | --- |
| [NITRO-61FX-R1](../../glow-engines/NITRO-61FX/README.md#2026-10-20--dive-support-nitro-61fx-r1) | Two inferred windmill knots (24,000 / 32,000 rpm, no indicated work) keep a full-throttle dive inside the profile; every knot ≤ 20,000 rpm byte-identical | NITRO: `build_profiles.py`, `os_max_61fx_candidate.json`, `test_glow_dive_support.gd` |
| EX-14a | Dry mass = RCM's weighed 124 oz (3.515 kg; loaded 3.820 kg). One unaccounted-build-mass closure (0.384 kg, solved 32 mm ahead of the wing LE) replaces the 0.142 kg virtual nose ballast and keeps the manual's 4⅛ in balance. 1-g stall 10.66 → 11.02 m/s; static margin 16.5 → 16.2 % MAC; Jxx/Jyy/Jzz 0.169/0.314/0.457 kg·m² | Extra generator |
| EX-14c | The Glow shaft composes with the quasi-static tail slipstream (Selig wash factor, swirl, Ribner sidewash), McCormick propeller normal force and P-factor. The stage hands the wake its own hub thrust and torque; the smooth and transported wakes stay refused (the Glow layout has no wash states). The Extra derives the tables from its Glow propeller surrogate (σ 0.071) and four tail pieces from its geometry, including the rudder below the fuselage top line, behind the tail post | Shared: `slipstream.gd` (new `stage_loads`), `dynamics.gd`, `glow/flight.gd`, `glow/installation.gd`; Extra generator |
| D10-R3 / EX-14d | Opt-in `aero.surfaces.body_cy_beta` and `body_crossflow_area`: the fuselage side force in the local law at the ARP. It is Allen–Perkins in form: a slender-body term ½ρ·S·CYβ_B·u·v plus crossflow drag −½ρ·η·c_d·S_side·√(v²+w²)·v, not faded. With `body_cy_beta` the loader requires the oracle's `CYb` = fin + body. Extra values: CYβ_B −0.124/rad (its DATCOM body term; Letko × K_i gives −0.116), η 0.65, c_d 1.4, S_side 0.172 m² | Shared: `aero.gd`, `aircraft_data.gd`, v1/v2 schema, contract, [AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md); Extra generator; `test_body_side_force.gd` |
| EX-14e | Ground effect (shared M5-GE-1 law) with constants fitted to an image-method VLM of the Extra's wing and tail. The VLM reuses the P-51 P51-20 solver unchanged: induced c 17.2, e 1.21 (rms 0.006); tail c 19.2, e 1.33 (rms 0.013). The low wing sits at x 0.133 on its wheels | `research/extra-300/ex14/ground_effect_vlm.py` → `vlm_ground_effect.json`; Extra generator; CI check |

Regenerated through their pipelines:
- Workshop descriptor;
- fuel mass-balance report (only the Extra's entries moved);
- v2 schema and parameter register;
- crash-economics costing identity. The rebind also absorbs the economy catalog's pre-existing staleness from the UI-34b–d `aircraft_catalog.gd` change; its unit tests pass.

## Verification

- **New and updated tests.**
  - `test_glow_dive_support.gd`: 10 checks. With the old profile on a disposable copy, 6 of 10 fail.
  - `test_body_side_force.gd`: 11 checks. The formula holds to 5×10⁻¹⁷ q·S over 84 states. The local side force at β 2° is within 2.3 % of the oracle (the fin alone fell 30 % short). The loader rule refuses a 1×10⁻⁶ error in CYb.
  - `test_glow_installation.gd`: 362 checks; new contract cases refuse unvalidated or stateful modules and accept the Extra's.
  - `test_extra_installation.gd`: 17 checks; its independent wrench oracle now includes the crossflow terms.
  - `test_trace_metadata.gd`: 372 checks.
  - `test_ground_effect.gd`: 51 checks; the no-module control moved to the Timber.
- **Unchanged tests.** These pass with no edit:
  - `test_extra_handling.gd` (13 checks) and `test_extra_runway.gd` (18 checks);
  - 17 glow and fuel programs;
  - the slipstream suite (scalar 20,001 comparisons, segmented parity 381, sidewash, transport, swirl);
  - aero, regime consistency, wing polar, modes, golden flights (4), rudder authority, yaw damping, law properties, contract (3,029 checks);
  - the Python schema contract.
- **Generator checks.** Every `--check` in the [cascade](#reproduce) passes, including the P-51's VLM.
- **Cost.** `bench_physics.gd` on the shared VM, best of 3 × 2,400 ticks. The VM is about 6× slower than the owner's workstation, which measured 390–455 µs in EX-06.
  - Before: 2,510–2,733 µs/tick. After: 3,340–3,445 µs/tick (+25–35 %).
  - Removing only the slipstream gives 2,771, so the mass, side force and ground effect cost is within noise. The single-centroid swirl would save about half of the wash cost, but P51-26 measured it off by up to ×2.15, so the segmented quadrature stays.
  - Same VM, for context: P-51 3,582 and 61FX Stik 6,371 µs/tick.
  - `test_extra_handling` and `test_extra_runway` got measured 120 s timeouts in `app/test.sh`: 66 s and 46 s on the quiet VM, against 53 s and 41 s before.
- **Fleet-wide sweep.** 65 programs that fly or load every catalog aircraft (Workshop, economy, crash, UI aircraft/runway, trim, wind, turbulence, natural random flight, half-power start, pilot trim, golden, modes) all pass on the final tree. `test_engine_audio` once failed its wall-clock queue check at load 6; it passes on this tree and on the baseline (146/146) when the machine is quiet.

## Probes (read-only, baseline vs this change on frozen copies)

The baseline snapshot is HEAD `e251b374` with this session's EX/NITRO files reverted to `0605d1e8`. The candidate is the working tree.

**Taxi, ⅓ throttle, elevator neutral, rudder holding heading** ([taxi_tail_probe.gd](../../../../research/extra-300/ex14/taxi_tail_probe.gd)). RCM: "at 1/3 throttle, the tail lifted off the ground".

| Throttle | Tail unloads (baseline → EX-14) | Peak heading rudder | Worst heading error |
| --- | --- | --- | --- |
| 0.25 | 3.63 s / 8.85 m/s → 3.41 s / 7.82 m/s | 0.064 → 0.043 | 1.7° → 1.0° |
| 0.33 | 2.82 s / 8.75 m/s → 2.55 s / 7.18 m/s | 0.096 → 0.035 | 2.5° → 0.8° |
| 0.50 | 2.12 s / 7.98 m/s → 1.98 s / 6.61 m/s | 0.174 → 0.025 | 4.2° → 0.5° |

Both versions lift the tail at ⅓ throttle, so the RCM sentence does not discriminate. The wash raises it 15–18 % earlier and makes the rudder a ground-steering control, as on a real taildragger.

**Hammerhead, flown as an RC pilot does** ([hammerhead_probe.gd](../../../../research/extra-300/ex14/hammerhead_probe.gd)): full-throttle pull to vertical, the up-line held at ⅓ throttle, full rudder at the kick speed, ailerons against the roll rate, elevator against the pitch rate.

| Kick | Direction | Baseline | EX-14 |
| --- | --- | --- | --- |
| 6 m/s | right | no pivot in 6 s, wing-over sweeping 45 spans | **pivot 1.25 s, 2.0 spans, 3° roll, nose round by yaw** |
| 6 m/s | left | flop by pitch, 2.3 s, 86° roll | pivot 4.7 s, 295° torque roll |
| 8 m/s | right | no pivot, 34 spans | **pivot 1.58 s, 3.2 spans, 3° roll** |
| 8 m/s | left | 2.95 s, 6.7 spans, 76° roll | no pivot, 75° roll |

The Extra now hammerheads to the right. The left kick loses to torque roll at 1–3 m/s, where the ailerons have no authority. The wing in the wake, whose swirl offsets part of the torque roll (Selig: about 40 %), is not modelled. At ½ throttle neither version decelerates on the up-line; see the propulsion finding below.

## Flight-test battery (card v5, frozen baseline vs candidate)

Both runs used the same frozen runner copy and the same Godot build, on the shared VM. The Extra flew 40 tests in each. Retained here:
- [side-by-side summary](ft/summary-extra.md);
- the comparator output, [compare-extra.md](ft/compare-extra.md): 626 changes, as expected when the mass changes;
- both profiles (`ft/baseline`, `ft/candidate`).

The candidate data file differs from the committed one only in the closure row's name, restored afterwards so crash economics still excludes it. Its physics are identical.

| Metric | Baseline | EX-14 | Real-model reference |
| --- | --- | --- | --- |
| Mass (kg) | 3.58 | 3.82 | RCM 3.52 dry + 0.30 fuel |
| Power-off stall (m/s), wing drop | 10.79, left (−78° in 1 s) | 11.11, left (−77°) | "very very mild … mushes" (open finding 2) |
| Max level speed (m/s) at rpm | 41.0 at 18,290 | 41.0 at 18,283 | see open finding 1 |
| Best full-throttle climb (m/s) | 17.9 | 16.8 | |
| Full-aileron roll at 22 / 32.8 m/s (°/s) | 305 / 406 | 306 / 406 | high rate ~1–1.5 rolls/s |
| Knife-edge, full rudder, full throttle: sink (m/s) / β | −35.4 / 20.7° (not valid) | **−8.4 / 20.9°** (valid) | holds only at full rudder + power |
| Slow roll (right): height change / peak rudder | −7.4 m / 0.77 | −1.2 m / 0.92 | |
| Four-point roll: worst over-rotation | 1.6° | 0.6° | |
| Rudder-free takeoff, heading change in 3 s | **+8.8° (right)** | **−9.6° (left)** | manual: expect a left turn |
| Takeoff: lift-off (Vs) / ground roll / peak rudder | 1.46 / 14.1 m / 0.17 | 1.40 / 14.3 m / 0.06 | |
| Landing: touchdown speed / sink / rollout | 13.6 m/s / 0.48 / 96 m | 14.0 m/s / 0.42 / 102 m | floats long, comes in hot |
| Snap roll: autorotation short of 360° (right / left) | 37° / 108° | 67° / 131° | crisp (open finding 4) |
| Stall turn, card technique (idle up-line) | no pivot | no pivot | see the hammerhead probe |
| Spin (right): s per turn / recovery turns | 1.11 / 0.27 | 1.23 / 0.24 | Froude-scaled Extra 260: ~1 s/turn |
| Hands-off 30 s: heading / height change | 417° / −102.5 m | 394° / −80.7 m | |
| Valid tests | 38 / 40 | 40 / 40 | |

The snap stops further short in EX-14. Each mechanism was removed in turn on a disposable copy (same card prerequisites, `snap_roll` only; autorotation short of 360°, right / left):

| Variant | Right | Left |
| --- | --- | --- |
| Before EX-14 | 37° | 108° |
| Mass only (EX-14a) | 40° | 105° |
| EX-14 without the side force | 47° | 106° |
| EX-14 without the wash | 73° | 137° |
| EX-14 without ground effect | identical to full | identical to full |
| Full EX-14 | 67° | 131° |

The fuselage crossflow term (D10-R3) causes it. A snap is flown at α ≈ 27°, where √(v²+w²) gives the body about 2.2× its level-flight side-force slope. That is inside Letko & Williams' measured high-α growth for square and deep bodies (about 6× at α 28–32°). The term resists the sideslip build-up that feeds an autorotation the post-stall strips already under-predict. The sourced term is kept; the snap belongs to the separation-dynamics step (D8b-R2d-v3), and the regression is recorded here rather than tuned away. The 61FX Stik pair below isolates NITRO-61FX-R1.

**61FX Stik, full card at zero tolerance: 0 changes** ([compare-stik-61fx.md](ft/compare-stik-61fx.md)). The other glow airframe on the changed profile, `dynamics.gd`, `slipstream.gd` and Glow paths is bit-identical; none of its card flights passes 20,000 rpm. Its regression dive in `test_glow_dive_support.gd` does pass 20,000 rpm, and it faulted before R1.

## Open findings (ranked)

1. **The propulsion looks too strong at high rpm and at half throttle.** This is NITRO with the Extra installation.
   - Level Vmax 41 m/s needs 18,290 rpm, above O.S.'s 17,000 rpm practical limit and APC's 15,833 rpm limit.
   - A 12×6 cannot exceed its pitch speed by much: 15,833 rpm × 6 in is 40 m/s.
   - At ½ throttle the up-line does not decay, so thrust is close to weight. Owners say even a Saito 100 lacks solid hover power, and a .61FX was clearly weaker than a .91 four-stroke.
   - The installation predicts 12,550 rpm static against the 10,400 (Pitts muffler) to 12,000 rpm reported.
   - The prototype ran a Pitts muffler, and the profile carries catalog power with no installed loss.
   - Needed: tach and thrust readings of a 61FX + APC 12×6 with the Pitts muffler, and torque beyond 16,000 rpm.
2. **The stall drops a wing; the real airplane mushes.**
   - The battery's power-off stall banks 78° in the first second, and a held stall enters a spin.
   - Owners: "very very mild … mushes forward", with reluctant spin entries.
   - This is the shared post-stall polar ([D8b-R2](../../flight-robustness/D8b-R2/analog/)), awaiting that owner's decision. The Extra's symmetric, untwisted taper-0.5 wing gets the legacy table.
3. **Knife-edge is close but not sustained.**
   - With full rudder the model holds β ≈ τ·δr ≈ 21°. At full power it sinks 5–10 m/s at 40 m/s; owners hold altitude only at full rudder and power.
   - Missing pieces:
     - the fuselage yaw moment (the slender-body part acts forward and is destabilizing, the crossflow part 0.2 m aft and is stabilizing; they roughly cancel near 25°);
     - gear, wheel-pant and canopy side area;
     - knife-edge pitch toward the belly, which owners mix out with 3–6 % up.
4. **Left hammerhead torque roll and snap rolls.**
   - Left hammerheads torque-roll at the top.
   - Snaps still stop short (FT-05: 37° and 108°); owners call them crisp. This is the post-stall separation dynamics, D8b-R2d-v3.
5. **Ground and landing remain unmeasured.** Rolling resistance, tyre and spring values are borrowed, and no measured flare exists.

## Reproduce

```bash
python3 research/glow-engines/build_profiles.py --check
python3 research/extra-300/ex14/ground_effect_vlm.py --check
python3 research/extra-300/ex05/derive_physics.py --check
python3 research/aircraft-editor/build_descriptors.py --check
python3 -I research/fuel-systems/mass_balance_report.py --check research/fuel-systems/mass_balance_current.json --fail-on-drift
python3 research/crash-economics/build_catalog.py --check && python3 research/crash-economics/build_runtime.py --check
G="$(app/get-godot.sh)"
for t in glow_dive_support body_side_force extra_installation extra_handling extra_runway glow_installation ground_effect trace_metadata; do
  "$G" --headless --path app --audio-driver Dummy --script res://tests/test_$t.gd; done
"$G" --headless --path <app copy> --audio-driver Dummy --script "$PWD/research/extra-300/ex14/taxi_tail_probe.gd"
"$G" --headless --path <app copy> --audio-driver Dummy --script "$PWD/research/extra-300/ex14/hammerhead_probe.gd" -- --throttle=0.35 --kick=6
python3 research/flight-test/run.py --out <new dir> --aircraft gp-extra-300s-60 --app <app copy>
```
