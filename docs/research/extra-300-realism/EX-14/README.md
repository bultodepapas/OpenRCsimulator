# EX-14: Extra 300S realism pass against the weighed build and owner reports

2026-10-20/21 · EX-14a/c/d/e/f/g/h, with shared steps NITRO-61FX-R1/R2 and D10-R3 · **Status: delivered as software; the aircraft stays experimental.** Owner: [Extra aircraft guide](../../../EXTRA-300-PLAN.md).

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
  - EX-14h, all already local: Sheldahl & Klimas SAND80-2114 (NACA 0012/0015 section data at Re 3.6·10⁵, to 180°), NASA FASER static lift and forced-oscillation roll damping (D8b-R2d digitizations), Selig AIAA 2010-7635 and Dantsker & Selig AIAA 2015-2568 (instrumented high-α flight), all in `references/rc-aero-data/` ([registry](../../flight-dynamics/rc-aero-data-sources.md)); the kit manual's flying notes (p. 46) and its plan's full-size rib 2D (`references/extra-300/gp-extra-300s-60/`).

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
| [EX-14f](#ex-14f--propeller-section-camber) | Optional cambered-section zero-lift angle in the Glow propeller surrogate, fitted to measured APC Sport 11×6 data and adopted by the Extra's installation | NITRO: `glow/propeller.gd`, `glow/installation.gd`, installation schema, Python mirrors, `fit_section.py`, `build_installations.py`; `test_glow_propeller_camber.gd` |
| [EX-14g](#ex-14g--installed-engine) | The Extra's installation uses the muffler-installed MAX-61FX (NITRO-61FX-R2, Gierke-anchored back-pressure law) with the carburettor sized on the bare engine | NITRO: `build_profiles.py` (`INSTALLED`), `os_max_61fx_installed_candidate.json`, `build_installations.py`, `installation_schema.py`; tests: `test_profiles.py` and the binding pins |
| [EX-14h](#ex-14h--post-stall-wing-polar) | The Extra's wing gets the D8b-R2d tabulated post-stall polar (v2 method, full spanwise progression) fitted to NASA FASER's measured lift retention and stall-onset roll damping, replacing the legacy blend's 14–18° roll instability | `research/extra-300/ex14/fit_wing_polar.gd` → `wing_polar_fit.json`; Extra generator; `test_extra_post_stall.gd`; `test.sh` check |

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
- **After EX-14f (2026-10-21)**, 37 programs that fly the Extra (sweep on `03ed5759`):
  - `test_glow_dive_support`: the Extra's dive now peaks below 20,000 rpm. The test keeps the R1 assertion (> 20,000) for the 61FX Stik, and checks the Extra's overspeed past 17,000 rpm.
  - `test_trim_integrity`: fixed by the trim-solver repair below.
  - `test_workshop_integration` ("frozen cosmetics and a single smoke budget", default Stik) fails identically with every EX-14f app file and the trim repair reverted on a disposable copy, so it is not caused by this work. It passed in the 2026-10-20 sweep and follows the upstream smoke checkpoint `e04b2e6d`; its owner should look.
  - Everything else passes.
- **After EX-14g (2026-10-21).**
  - 18 glow and Extra programs pass (glow profiles, installation 362 checks, oracle, prepared, stage reuse, session, trace, dive support, trim integrity 731, fuel properties incl. the new profile).
  - 30 fleet-wide programs that fly or load the Extra pass (half-power start, trim throttle, pilot trim, runway fleet, natural random flight, wind, turbulence, atmosphere, crash, golden, modes, checkpoint, trace metadata, UI runway/aircraft, Workshop, contract).
  - Every generator `--check` passes, and the glow Python suites (`test_profiles.py`, `test_build_installations.py`, `test_installation_schema.py`, `test_installation_line_endings.py`, `test_cycle_oracle.py`, …) are green.
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

## EX-14f — propeller section camber

**Diagnosis.** The Glow propeller is a 12-annulus blade-element surrogate with a symmetric section, `cl = a·sin(2α)/2`. Measured against the UIUC APC Sport 11×6 (already the Stik's tables), it differs in two ways:
- It reaches zero thrust at the geometric pitch ratio (J 0.50 on a 12×6). The real props keep thrust to about 1.4× it: measured 0.77 (11×6), APC's computed 12×6 0.68.
- It absorbs only 81 % of the real static power, which implies a static figure of merit of 0.88.

So at speed the engine had to over-rev to make any thrust: level Vmax at 18,283 rpm, above the O.S. 17,000 and APC 15,833 rpm limits. At the APC 12×6's own figures that point needs 2.65 kW, against a 1.4 kW rating. On the ground it over-revved too: 12,550 rpm and 56 N (T/W 1.5), so the airplane hung on its prop at half throttle.

**Law (shared, opt-in).**
- `propeller.zero_lift_angle_rad` (−0.3…0) shifts lift and the flat-plate blend to the angle from the zero-lift line, α − α₀. Absent or 0 is byte-identical.
- It runs through `propeller.gd`, the installation validator and JSON schema, and the Python mirrors (`calibration_report.py`, `cycle_oracle.py`).
- [test_glow_propeller_camber.gd](../../../../app/tests/test_glow_propeller_camber.gd) has 10 checks: byte identity, refusals, zero-thrust J, the actuator-disk bound over 30 points, and the runtime equal to the Python mirror (0 relative error). All 17 glow programs pass unchanged.

**Fit.** [fit_section.py](../../../../research/glow-engines/fit_section.py) writes [section_fits.json](../../../../research/glow-engines/section_fits.json) and is checked by `--check`. It fits c/D and α₀ to the measured 11×6 knots in the repository: **c/D 0.0507, α₀ −5.86°**, normalized RMS 0.038, against 0.547 for the best symmetric section.
- The static figure of merit becomes 0.56.
- On the 12×6 the shaft power stays ≥ 33.9 % above the ideal actuator-disk power (NITRO-02 asks ≥ 5 %).
- The Extra's 12×6 takes it by c/D transfer: chord 15.5 mm, α₀ −0.102 rad.
- Cross-check against APC's own 12×6 Sport file, corrected by APC's measured bias on the 11×6/11×7 ([sources](propeller-sources.json)): Ct within ±5 % at J 0.4–0.6, static Ct 11 % low, Cp 6–13 % high.

**Independent corroboration: phugoid damping.** The battery's linear modes hold rpm fixed, so they see only the prop's thrust–speed slope. With the symmetric section that slope was steep (thrust collapsing toward J 0.5), and the cambered section lowers the phugoid damping at every speed:

| Speed | A (symmetric) | B and D (cambered) |
| --- | --- | --- |
| 1.3 Vs | 0.211 | 0.135 |
| Start speed | 0.451 | 0.292 |

The classical estimate 1/(√2·L/D) gives 0.06–0.10 for these glide ratios. The 2026-10-20 [trim-practice comparison](../../flight-dynamics/power-climb-2026-10-19/trim-practice-comparison.md) attributes the fleet's higher damping to propeller thrust falling with speed. The fit did not target the phugoid, so the move toward the estimate is a side effect, not a calibration.

**Engine side: A / B / C on the same tests.** B was production from `0f71655a` until [EX-14g](#ex-14g--installed-engine) adopted C's design as D. C uses an evidence-only installed-engine hypothesis. Its indicated-efficiency factor puts brake torque on Gierke's 0.679 N·m at 13,000 rpm and near Glassock's 11,000 rpm point, falling past the peak (0.59 at 16,000 rpm). C is not in the repository.

| | A: symmetric prop, catalog engine (EX-14) | **B: cambered prop, catalog engine (production)** | C: cambered prop, installed hypothesis | Anchor |
| --- | --- | --- | --- | --- |
| Static (cambered 12×6 balance) | 12,550 rpm, 56.1 N | 11,284 rpm, 38.7 N | 10,245 rpm, 31.9 N | 10,400 (Pitts) – 11,500 rpm; Glassock rig 10,791 rpm, 41.6 N |
| Level Vmax at rpm | 41.0 m/s at 18,283 | 47.0 m/s at 15,539 | **40.8 m/s at 13,524** | no measurement; estimated 41–42 m/s at 13,700–14,800 rpm with a Gierke-anchored engine |
| Full throttle at 22 m/s | 17,925 rpm | 14,290 rpm | 12,684 rpm | |
| Best full-throttle climb (m/s) | 15.4 / 15.8 / 16.8 | 9.7 / 11.0 / 12.3 | 7.5 / 8.6 / 9.1 | .61FX clearly weaker than a .91 four-stroke |
| Takeoff ground roll / lift-off time | 14.3 m / 3.1 s | 19.1 m / 3.7 s | 23.3 m / 4.2 s | |
| Height after 30 s at 50 % throttle (hands off) | +209 m | +177 m | +140 m | |
| Rudder-free takeoff swing | −9.6° | −9.9° | −9.1° | left (manual) |

B is more realistic than A on ground rpm, static thrust, hover, in-flight rpm (and engine pitch) and climb. Its top speed is about 15 % high. C is consistent with every anchor, but it rests on a secondhand dyno figure and a hypothesized fall-off. The NITRO dossier reserved that choice for the profile owner, so it is not adopted. Adopting C means:
- a muffler-installed MAX-61FX profile variant generated by `build_profiles.py` for the Extra's installation (the Stik's 61FX keeps the catalog profile);
- one tach reading to replace the hypothesis.

**Full card on production B** (frozen copy of `03ed5759` with the economy rebind; 40/40 valid; [A vs B summary](ft/summary-extra-b.md), profile in `ft/production-b`):

| Metric | A (EX-14) | B (EX-14f) |
| --- | --- | --- |
| Max level speed | 41.0 m/s | 47.0 m/s |
| Best full-throttle climb | 16.8 m/s | 12.3 m/s |
| Knife-edge, full rudder and power: sink / β | −8.4 m/s / 20.9° | **−5.9 m/s** / 20.8° |
| Lift-off / ground roll | 15.6 m/s (1.40 Vs) / 14 m | 15.2 m/s (1.37 Vs) / 18 m |
| Hands-off at 25 % / 50 % throttle: path after 30 s | 1.4° / 18.2° | 2.2° / 12.3° |
| Loop height / Immelmann gain | 51 m / 49 m | 56 m / 54 m |
| Snap: autorotation short (right) | 67° | 84° |
| Landing touchdown / sink / rollout | 14.0 m/s / 0.42 / 102 m | 14.0 m/s / 0.40 / 106 m |

The cambered prop keeps thrust at the knife-edge advance ratio (J 0.45–0.55), so the knife-edge gets closer to sustained. The snap metric moves again with every change; it stays the post-stall item (open finding 4).

**Trim-solver repair found while verifying EX-14f.** With the cambered prop, `test_trim_integrity` caught a refused bounded glow trim that reported throttle 1.1×10⁻¹⁶ instead of exactly 0. The line search in `app/physics/trim.gd` had two defects:
- **Rounding:** a step scaled to a throttle bound lands at x + ((b − x)/dx)·dx, which is not b. It now snaps to the bound.
- **Logic:** the residual update and the step acceptance sat outside the "residual decreased" branch. A non-decreasing candidate replaced the residual while the old iterate was kept, and the step was never halved, contrary to its own refusal message.

The repair moves those four lines inside the branch. Evidence:
- Fleet fingerprints (`fingerprint_vehicles.gd`, 24 vehicles including the glow variants and cut cases) are byte-identical with and without the repair: no production trim takes the defective branch.
- `test_trim_integrity` passes 731 checks, against one failure without the repair. Its new invariant check ("a refusal reports its own iterate's residual") passes on both trees; it guards the logic defect but did not catch it here.
- `test_pilot_trim` (118), `test_trim_throttle` (45), `test_half_power_start` (62), `test_trim_density` (35) and `test_glow_equilibrium` (196) pass.

## EX-14g — installed engine

The owner delegated the C decision ("continue like a senior developer expert"). The Extra's installation now pairs the EX-14f cambered prop with the muffler-installed MAX-61FX of [NITRO-61FX-R2](../../glow-engines/NITRO-61FX/README.md#2026-10-21--muffler-installed-variant-nitro-61fx-r2): the bare candidate's delivery × (1 − k·(rpm/13,000)²), with k = 0.209 solved from Gierke's 1.24 hp at 13,000 rpm. The carburettor stays sized on the bare engine. The Stik keeps the bare candidate.

Targets fixed before flying, and results (full card on a frozen copy, 40/40 valid; [B vs D summary](ft/summary-extra-d.md), profile `ft/production-d`):

| Target | Result | Verdict |
| --- | --- | --- |
| Static rpm on the 12×6 within 10,400 (Pitts) – 11,500 (stock) | 10,288 rpm, 32.1 N (T/W 0.86 full tank) | 1 % below the band; the prototype ran the restrictive Pitts, and the transferred fit over-absorbs 6–13 % |
| Level Vmax 38–43 m/s at 12,000–14,500 rpm | **41.2 m/s at 13,662 rpm** | met |
| No hover at half throttle | half-stick static 21.1 N (T/W 0.56) | met |
| Mixed-throttle endurance ≥ 10 min on 355 ml (O.S.: 12–13 min on 350 cc) | 75 %: 13.1 min, 50 %: 18.7, full: 11.2 (B: 10.6 / 14.9 / 8.9) | met; slightly long, because the part-throttle derate is overstated |
| Knife-edge no worse than B beyond noise | −13.6 m/s sink at full rudder and power (B −5.9, A −8.4) | **not met** |

Other changes from B to D:
- Best climb 12.3 → 9.2 m/s.
- Takeoff roll 18 → 22 m. The rudder-free swing is still left (−13.2°).
- Loop height 56 → 49 m; the Immelmann's speed over the top falls from 2.48 to 1.94 Vs.
- Power-on stall 9.6 → 10.0 m/s.
- The taxi tail still lifts at ⅓ throttle (4.0 s, 7.7 m/s).
- The hammerhead to the right still pivots in 1.65 s within 1.9 spans.

**The knife-edge miss is real.** In this model knife-edge leans on thrust·sinβ and the wash on the rudder, and B's better figure rode on catalog power the installed engine does not have. The sources agree on direction but not size. RCM's .61FX review asks for more rudder, and the owners who held altitude ran Saito 100–1.20 four-strokes. So a .61FX Extra that cannot hold knife-edge on the stock rudder is the reported behaviour, but no source gives the sink rate. Remaining physics are finding 3: the fuselage yaw split, gear and pant side area, and belly pitch.

## EX-14h — post-stall wing polar

**The gap.** The power-off stall banked 76° in its first second and a held stall entered a spin. The real airplane:
- Owners (RCU 1062376): "Stalls were very very mild...it sort of mushes forward while loosing a bit of altitude. Center the elevator and its flying again"; "Wingtips didnt drop and the nose really didnt drop either"; "points off on spin entries as it will not drop a wing".
- Manual: "For smooth flying and normal maneuvers, use the low rate settings... High rate elevator may be required for crisp snap rolls and spins."

**Cause.** The legacy blend separates every strip at one angle onto the flat plate.
- On the Extra the [bench](ft/ex14h/bench.md) gives roll damping Clp +0.79 / +0.99 / +0.84 / +0.48 at 15 / 16 / 17 / 18°.
- NASA FASER (Ultra Stick 120, the Extra's Reynolds class) measures −0.45 to 13.5° and −0.31 at 17.5° ([D8b-R2d](../../flight-robustness/D8b-R2/analog/README.md)).
- [`stall_probe.gd`](../../../../research/extra-300/ex14/stall_probe.gd) flies the owners' test: idle, altitude held until the stick reaches its stop, the stop held 5 s, on the manual's low and high rates. On low rate the stop reaches α 16.9°, inside that window, and the wing is already 52° down.

**Section.** The kit plan draws rib 2D at full size in its CG drawing; the printed 4⅛ in measures 4.13 in at 300 dpi.
- The rib is 1.89 in thick on a 14.7 in local chord: t/c 12.9 %, with its leading edge on a NACA 0013 within 0.01 in. This confirms the generator's 13 % estimate.
- At Re 3.6·10⁵ (SAND80-2114, Tables 2–3, checked against the page images) the two neighbouring sections stall differently:
  - NACA 0012 collapses from CL 0.98 to 0.28 within 3°.
  - NACA 0015 falls gradually, from 0.96 at 11° to 0.48 at 18°.

**Candidates.** Bench, [probe](ft/ex14h/probe/) and card subsets; the full card for production and the adopted polar.

| Wing law | Clp at 15–18° | Low-rate stop held, wings kept level | Power-off stall: bank in 1 s | Upright spin | Snap: short of 360° (R / L) |
| --- | --- | --- | --- | --- | --- |
| Legacy blend (before) | +0.79…+0.48 | spin entry | −76° | spin, 1.21 s/turn | 84° / 123° |
| Sandia 13 % (0012/0015 rows, Avanti AV-17-R2 policy) | +0.08…+1.04 | – | – | – | – |
| Sandia NACA 0015 (same policy) | −0.02…+0.05 | spin entry | – | – | – |
| **FASER-fitted v2 (adopted)** | +0.01…−0.24 | wing drop over 2.5 s | +14° | spin, 1.85 s/turn | 69° / 0° |
| Adopted + separated centre of pressure (experiment) | as adopted | **mush** | +9° | **none** (skidding spiral) | 33° / 0° |
| Legacy + separated centre of pressure (experiment) | as legacy | spin entry | −75° | spin, 1.07 s/turn | 35° / 80° |

The 2-D section data cannot give the mush. Their post-stall slope is neutral (0015) or violently unstable (0012) at the onset; only FASER's measured three-dimensional damping is stable there.

**Adopted.** [`fit_wing_polar.gd`](../../../../research/extra-300/ex14/fit_wing_polar.gd) runs D8b-R2d's [`make_v2.gd`](../../../../research/flight-robustness/d8b-r2/analog/make_v2.gd) recipe on the Extra's calibrated attached line; only the aircraft differs.
- Fitted knots: 1.00 / 0.86 / 0.86 / 0.82 of the strip peak at 18 / 24 / 30 / 36°.
- RMS errors: 0.059 retention, 0.255 onset Clp.
- The generator embeds `wing_polar_fit.json` unrounded: its `q()` rounding to 6 decimals breaks the loader's 1e-9 attached-line join.
- The shipped rows equal the flown candidate's. The flown file differs only by a 1-ulp JSON round trip of `Cldr`.

Full card against production on the same commit 3bfdc64f ([compare](ft/ex14h/compare.md), [production](ft/ex14h/production/summary.md), [candidate](ft/ex14h/candidate/summary.md)):

| | Production | EX-14h |
| --- | --- | --- |
| Power-off stall: speed, bank in the first second | 11.11 m/s, −76° | 11.05 m/s, +14° |
| Stall held 5 s, controls neutral: rotation in the last 2 s, height lost | 408°/s spin, 82 m | 138°/s spin, 64 m |
| Skidded stall (right): roll-off in 1 s | 52° into the rudder | 28° toward the held aileron |
| Spin (right): s per turn, sink, recovery turns | 1.21, 21.4 m/s, 0.24 | 1.85, 19.9 m/s, 0.12 |
| Snap (right / left): short of 360° | 84° / 123° | 69° / 0° |
| Attached flight: landing, take-off, loop, rolls, go-around | – | within 1–5 % |

**Not adopted: the separated centre of pressure.** The strip model keeps a stalled strip's force at the quarter chord, but measured sections move it aft.
- SAND80-2114 Fig. 30 (NACA 0015, Re 3.6·10⁵): Cm,c/4 ≈ −0.06 at 20°, −0.10 at 30°, −0.17 at 45°, −0.4 at 90°.
- Selig's full-envelope RC model applies the section moment at the quarter chord, "driven largely by drag acting on the 50% chord location".
- Experiment: a disposable-copy law ([patch](ft/ex14h/cp-shift-experiment.patch)) moving the centre of pressure aft by 0.25·|α|/90°·(1 − attached fraction) reproduces those values.
- With the adopted polar it flies the owners' stall on the manual's low rate. With the wings held level: bank ≤ 6.5°, nose drop 4.9°, sink 1–3 m/s, 9.6 m lost in 5 s, flying again once the elevator is centred. On high rate a wing still drops, as owners warn ("too much elevator will stall the plane").
- But it stops the card's upright spin.

The model's spin is an accelerating spiral dive in every variant: α 18–23°, sideslip about 20°, airspeed 13 → 23 m/s over 6 s ([spin state](ft/ex14h/spin-state.md)). The Extra 260 spins steadily at α ≈ 34° and 12–13 m/s at this wing loading. The centre-of-pressure moment exposes that gap; it does not cause it.

The full-up stop is not too stiff in pitch. Dantsker & Selig's instrumented Sukhoi holds α 18–22° with 20° of up elevator in an unpowered descending harrier; the model's stop is 21.5°. The law therefore waits for spin physics with rotation and separation dynamics (D10-R4, D8b-R2d-v3).

**Verification.**
- Generator chain: `derive_physics.py --check`, `fit_wing_polar.gd --check` (refits on the data without its polar: idempotent), descriptors, mass-balance report, crash-economics catalog and runtime. The costing dossier was rebound after review: EX-14h changes only `aero.wing_polar`.
- `test_extra_post_stall.gd` (new, 7 checks): the declared rows are the fitter's; Clp at 16 / 17 / 18° is −0.16 / −0.21 / −0.24, against legacy +0.99 / +0.84 / +0.48; CL at 20° keeps the peak, where legacy falls to 0.54.
- 56 programs that load the Extra or its polar. All pass except:
  - `test_engine_audio`: fails only under 6-way load; 146/146 alone.
  - `test_workshop_integration`: the smoke-budget failure, already present before EX-14f.
  - `test_workshop_reuse`: 8 profile-copy failures, identical at the pre-change commit `1a00c874~1`. Both are upstream workshop issues.
- The full suite was not run.

**Limits.**
- FASER is an analog airframe (rectangular high wing); the negative branch is the unmeasured fixture recipe.
- Hands-off on low rate the wing still rolls off slowly. Near α 20° a small steady moment (idle torque, the cruise rudder trim) acts on near-neutral damping.
- The spin turns slower than the Extra 260 band (Ωb/2V 0.13–0.15 against 0.20).
- Software verification only.

## Open findings (ranked)

1. **Installed engine power rests on a secondhand dyno figure.** EX-14g adopts it, with one Glassock rig check.
   - The back pressure is a wide-open function of rpm, so the part-throttle derate and endurance are slightly overstated.
   - The Pitts muffler's own loss is not quantified.
   - Needed: a tach and thrust reading of the airplane's own 61FX on the 12×6, static and on a full-throttle level pass, with the muffler noted. One reading would replace k and confirm the prop fit.
2. **The stall is milder but does not yet mush, and the spin is a spiral dive.**
   - EX-14h removes the violent wing drop (+14° in the first second, against −76°), but a held low-rate stall still rolls off over 2.5 s.
   - The measured separated centre of pressure gives the owners' mush and crisper snaps. It stops the card's upright spin, because the model's spin is an accelerating spiral at α 18–23° rather than the Extra 260's steady α ≈ 34°.
   - Next: spin physics with rotation and separation dynamics (D10-R4, D8b-R2d-v3), then the centre-of-pressure law ([EX-14h](#ex-14h--post-stall-wing-polar)).
3. **Knife-edge is close but not sustained.**
   - With full rudder the model holds β ≈ τ·δr ≈ 21°. With the installed engine (EX-14g) it sinks 13.6 m/s at full rudder and power (5.9 with catalog power); owners hold altitude only at full rudder and power, and RCM asks for more rudder on the .61FX.
   - Missing pieces:
     - the fuselage yaw moment (the slender-body part acts forward and is destabilizing, the crossflow part 0.2 m aft and is stabilizing; they roughly cancel near 25°);
     - gear, wheel-pant and canopy side area;
     - knife-edge pitch toward the belly, which owners mix out with 3–6 % up.
4. **Left hammerhead torque roll and snap rolls.**
   - Left hammerheads lose the pivot at the top: 119–135° of roll and 134° of pitch rotation in the probe. Missing wing swirl does not explain it: on this low wing the wake covers only 1.8 cm of exposed root per side near static (about 140 cm², against about 500 cm² per stab half). The pitch points to gyroscopic precession of the clockwise prop turning the left yaw rate into pitch, with little elevator authority near zero airspeed. Real hammerheads are asymmetric for the same reason, and pilots compensate with timing and elevator, so the probe's simple pilot is part of the result.
   - Snaps stop short of 360° by 69° (right) and complete to the left (EX-14h); owners call them crisp. The separated centre of pressure brings the right snap to 33° short (EX-14h).
5. **Ground and landing remain unmeasured.** Rolling resistance, tyre and spring values are borrowed, and no measured flare exists.

## Reproduce

```bash
python3 research/glow-engines/build_profiles.py --check
python3 research/glow-engines/fit_section.py --check && python3 research/glow-engines/build_installations.py --check
python3 research/extra-300/ex14/ground_effect_vlm.py --check
"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/extra-300/ex14/fit_wing_polar.gd" -- --check
python3 research/extra-300/ex05/derive_physics.py --check
python3 research/aircraft-editor/build_descriptors.py --check
python3 -I research/fuel-systems/mass_balance_report.py --check research/fuel-systems/mass_balance_current.json --fail-on-drift
python3 research/crash-economics/build_catalog.py --check && python3 research/crash-economics/build_runtime.py --check
G="$(app/get-godot.sh)"
for t in glow_dive_support body_side_force extra_installation extra_handling extra_runway extra_post_stall wing_polar glow_installation ground_effect trace_metadata; do
  "$G" --headless --path app --audio-driver Dummy --script res://tests/test_$t.gd; done
"$G" --headless --path <app copy> --audio-driver Dummy --script "$PWD/research/extra-300/ex14/taxi_tail_probe.gd"
"$G" --headless --path <app copy> --audio-driver Dummy --script "$PWD/research/extra-300/ex14/hammerhead_probe.gd" -- --throttle=0.35 --kick=6
"$G" --headless --path app --audio-driver Dummy --script "$PWD/research/extra-300/ex14/stall_probe.gd" [-- --data=<abs candidate json>]
"$G" --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd" -- res://data/aircraft/gp_extra_300s_60.json
python3 -I research/extra-300/ex14/sandia_polar.py <legacy Extra json> 0.15 <out json>   # rejected Sandia candidate
python3 research/flight-test/run.py --out <new dir> --aircraft gp-extra-300s-60 --app <app copy>
```
