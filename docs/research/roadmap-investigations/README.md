# Roadmap investigations: the physics knowledge base

**Status:** research knowledge base, 2026-10-06 (plan review #4). **Serves:** ROADMAP M1 follow-ups (D11), Phase H, M2 (E), M3 (F), M4 (G, EL), M5, and the parallel programs VAL, DATA and PERC. **Read with:** [ROADMAP.md](../../../ROADMAP.md) (plan review #4 at the end), [docs/README.md](../../README.md) (step-ID registry).

Ten documents that do the research in advance for each roadmap phase: theory and equations, implementation options for this repository, Godot notes, reusable tools and data, parameters with their evidence kind, validation tests, pitfalls, proposed steps, and the decisions that would limit later work. ROADMAP keeps the actionable steps; these documents keep the knowledge behind them.

**How to use:**
- Before starting a step, read its document and section.
- If building the step proves the document wrong, fix the document in the same change and record the lesson in LEARNINGS.

## The ten documents

| # | Document | Serves | What a developer must know first |
| --- | --- | --- | --- |
| 01 | [Numerics, architecture and performance](01-numerics-architecture-performance.md) | Phase H, E1b, G2, M5 wind numerics, Gate P | **Integration and gear:** RK4 at 240 Hz is right. The gear rule ω·dt < 0.1 is ~27× inside RK4's stability limit; use an eigenvalue rule and contact substeps instead of a faster global tick. **Touchdown:** the damper's force jump at first contact drops RK4 to first order. **Engine rpm:** held across RK4 stages, it becomes a first-order error once rpm depends on airspeed (G2). **Performance:** one load evaluation per tick is redundant, and an allocation-free derivative is 11× faster |
| 02 | [Aerodynamics at RC scale](02-aerodynamics-rc-scale.md) | D11, E0a, M5 stall / ground effect / spin, every derive_physics | **Roll gap:** the 2.1× roll time-constant gap against both flight-identified UMN Sticks is mostly roll inertia (×1.62), then Clp (×1.15). **Pitch:** the 1.45× gap is obsolete since D1-R1. **Damping by regime (new defect, re-measured by the lead):** Clp −0.45 → −0.77 and Cmq −13.6 → −4.4 between α 6° and 10°, where an approach flies. **Ground effect:** on its wheels the Stik gets +16 % lift and −34 % induced drag |
| 03 | [Propeller, slipstream and propwash](03-propeller-propwash.md) | E0b, G1, M5 propeller items | **Wash ratio:** q_wash/q∞ = 1 + 8Ct/(πJ²) gives 35.3× at 5 m/s and 1.3× in level cruise (ideal momentum theory, re-computed by the lead). Measured jet decay at the tail gives 12–20×. **Propeller table:** the Stik's table is an 11×6 at ≤ 6,259 rpm used for a 12×6 at 11,149 rpm, so rpm must become a table dimension. **Small effects:** P-factor and normal force are small on the .60s |
| 04 | [Ground handling, collisions and crashes](04-ground-handling-collisions.md) | E3b–E4, PT2, E5+ (taildraggers, brakes, retracts, terrain, obstacles, launch, damage) | **Stiction:** a stick/slip anchor per contact, switched in `pre_step`. **E3b targets:** 10 m/s after 4.69 m (elevator neutral); full up-elevator lifts the nose at 11.3 m/s after 6.0 m on the runway. **Taildraggers:** diverge when the tailwheel grips less than its share. **Crash rules:** hull points become frictional contacts with per-component impact limits. Never use Godot physics queries in the sim |
| 05 | [Propulsion: glow, gas, electric, turbine](05-propulsion-engines-motors.md) | G1–G5, PT4, EL1–EL6 (electric), AV-05 | **Missing reaction:** the `−dh/dt` reaction delays torque roll on a throttle punch (0.83 vs 0.05 N·m on the first tick). **Dead-stick:** stopped and windmilling props are missing. **Torque curves:** their shape is undocumented and inconsistent between aircraft. **Density:** engine power must scale with σ. **Electric:** the chain is cheap and closed-form (Drela motor, averaged ESC, one-time-constant LiPo) |
| 06 | [Radio input, servos and latency](06-radio-input-servos-latency.md) | F1–F11, D6d, UI-10/12, M5 flight aids | **Radio:** sends channel outputs (expo, rates, trims already applied), 8 axes at 11 bits, every 1 ms only with RF off. **Godot:** samples joysticks once per rendered frame. **Latency:** stick-to-photon ≈ 42 ms at 60 Hz, more than a real 2.4 GHz link, so the sim adds no extra RF delay. **Servos:** too fast on small moves. **Trim:** solved trims become a per-aircraft linkage trim |
| 07 | [Atmosphere, wind, turbulence, thermals, slope](07-atmosphere-wind-turbulence.md) | M5-ATM, M5-W (refines [WIND-PLAN](../../WIND-PLAN.md)) | **Density altitude:** 1500 m and 35 °C gives σ 0.78 (stall +13 %, thrust −22 %). **Turbulence:** WIND-PLAN's OU process is already the MIL-HDBK-1797 first-order form. **Sampling:** wind plus its gradient per stage gives correct rotational gusts. **Random numbers:** xoshiro128** is bit-exact in GDScript at ~10 µs/tick. **Treeline:** the field sits in its wake for most wind directions |
| 08 | [Validation and flight testing](08-validation-flight-testing.md) | VAL-1…15, D8b, D10, Gate 2/2-R, EX-09, P51-09 | **Stale data:** `research/sensitivity/results.md` predates the repair and must be regenerated. **New reference:** Dorobantu 2013 (25e) is readable as a preprint. **Most valuable measurement:** a $10 bifilar swing test for Ixx. **Added air mass:** ≈ 23 % of the sim's Ixx. **Flight-test cards** for a hobbyist, a passive-logger rule, and a dashboard instead of CI failures |
| 09 | [Aircraft data and the geometry-to-physics pipeline](09-aircraft-data-pipeline.md) | DATA-1…16, every aircraft track, P51-11 | **v1 limits:** v1 fits one airplane shape. **v2:** a component tree, ID-keyed, with derivatives as an optional oracle. **Load time:** 110 ms, almost all of it the stall-start bisection. **Pipeline:** two duplicated `derive_physics.py` scripts and no P-51 `--check` in CI. **Mods:** data-only. **Licences:** GPL tools stay outside `app/` |
| 10 | [Audio, perception and presentation](10-audio-perception-presentation.md) | G3a–j, PERC-1…9, Gate 2 readability, VQ-03, UI-08 | **Tones:** firing at rpm/60 and blade passing at blades·rpm/60. **Godot 3D audio:** its Doppler has no travel delay and its distance filter is 20 dB too strong, so we render propagation ourselves. **Audio queue:** the placeholder adds ~186 ms. **Readability:** a 50° camera shows the airplane at 0.63× real size, and auto-zoom erases the approaching/receding cue |

## Where the documents disagree, and the resolution used in ROADMAP

| Topic | Positions | Resolution |
| --- | --- | --- |
| Where engine rpm lives (G2) | 01: integrate rpm in the RK4 state (split error 9.6e-3 vs 6.2e-11 m/s in a toy throttle step). 05: keep it outside RK4 with a linearly implicit update, as insurance for light electric rotors | **Integrate it** (H8 then G2a). The fastest realistic rotor (electric, τ ≈ 30 ms) gives λ·dt ≈ 0.14 at 240 Hz, far inside RK4's limit of 2.78, so the implicit insurance is not needed. Discrete modes (engine state, gear anchors, ESC cut-off) stay in `pre_step` |
| Touchdown force jump | 01: Hunt–Crossley damping. 04: ramped damping plus rebound damping | One step, E1b: a force that is continuous at δ = 0 (either law, chosen by the h/h₂ order test) plus rebound damping |
| G1 numbering | 03 and 05 both proposed G1a/G1b | 03's G1a–e (table schema, flags, BEM tool, windmill, normal force) absorb 05's two |
| Aero performance | 02's X-perf-1 duplicates 01's PERF steps | Merged into H4/H5 and Gate P |
| D10 re-run | 02's X-aero-1 and 08's X-VAL-1/2 | One step, D11a |

## Facts the lead re-checked

- **Physics cost:** `bench_physics.gd` measures **501 µs per tick** on the dev VM against a 500 µs budget. Doc 01 measured 505–562 µs with the other tracks' uncommitted changes.
- **Damping by regime:** a probe through `Aero.loads` at 15 m/s gives Clp −0.451 (α 2–6°) → −0.774 (α 10°) and Cmq −13.6 → −4.40, following the local-flow blend weight (0 → 1). It was measured on the working tree, where other tracks' uncommitted `aero.gd` edits exist; the Stik uses none of them.
- **Propwash ratios:** recomputed from the data file: 35.3× / 8.9× / 4.2× at 5 / 10 / 15 m/s, full throttle.
- **Links:**
  - All relative links resolve, and none point into ignored folders.
  - Of 347 external URLs, 296 answer 200 and 36 refuse robots (403).
  - Four dead links were repaired or labelled.
  - Three hosts timed out (FlightGear git mirror, Lund LUP, SAE Mobilus) and are kept as cited.

## Limits of this research

- **Search budget:** the session's web-search budget (200 searches) ran out partway through. Later sources were fetched directly by URL. Each document marks sources as "fetched" or "search result only".
- **Still unverified:**
  - RC-community static-thrust figures and pilot accounts of taxi and tail authority (03);
  - grass rolling resistance for small RC wheels (04);
  - FrSky Ethos USB behaviour (06);
  - the Phillips–Hunsaker ground-effect formulas (02);
  - RealFlight, aerofly and PicaSim tick rates (01);
  - controlled studies of RC orientation errors (10).
- **Other tracks' code:** the documents were written while other tracks' propulsion work was uncommitted (P-51 shaft balance "P51-06", `app/physics/slipstream.gd` "P51-12", `app/physics/turbine.gd` AV-05). That work was committed in `480cddd` the same evening; where a document says "uncommitted" it means that work. Line references may drift.
- **Scope:** everything here is research and proposals. No simulation code or data was changed. Proposed steps become real when ROADMAP lists them and their proof passes.
