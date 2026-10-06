# Roadmap investigations: the physics knowledge base

**Status:** research knowledge base, 2026-10-06 (plan review #4). **Serves:** ROADMAP M1 follow-ups (D11), Phase H, M2 (E), M3 (F), M4 (G, EL), M5, and the parallel programs VAL, DATA and PERC. **Read with:** [ROADMAP.md](../../../ROADMAP.md) (plan review #4 at the end), [docs/README.md](../../README.md) (step-ID registry).

Ten documents that do the research in advance for each roadmap phase: theory and equations, implementation options for this repository, Godot notes, reusable tools and data, parameters with their evidence kind, validation tests, pitfalls, proposed steps, and the decisions that would limit later work. ROADMAP keeps the actionable steps; these documents keep the knowledge behind them.

**How to use:**
- Before starting a step, read its document and section.
- If building the step proves the document wrong, fix the document in the same change and record the lesson in LEARNINGS.

## The ten documents

| # | Document | Serves | What a developer must know first |
| --- | --- | --- | --- |
| 01 | [Numerics, architecture and performance](01-numerics-architecture-performance.md) | Phase H, E1b, G2, M5 wind numerics, Gate P | **Integration:** RK4 at 240 Hz remains suitable for the rigid-body kernel, but current P-51 full-session shaft stepping converges at first order because auxiliary rpm is frozen over those stages. H8 should define only the needed continuous, sampled and discrete state semantics, stage time, trace/reset behavior and rollback before wheel anchors or coupled shaft work. **Performance:** use the four-aircraft audit measurements in doc 01 as an exploratory reference; P-51 is materially more expensive. |
| 02 | [Aerodynamics at RC scale](02-aerodynamics-rc-scale.md) | D11, E0a, M5 stall / ground effect / spin, every derive_physics | **Roll gap:** the 2.1× roll time-constant gap against both flight-identified UMN Sticks is mostly roll inertia (×1.62), then Clp (×1.15). **Pitch:** the 1.45× gap is obsolete since D1-R1. **Damping by regime (new defect, re-measured by the lead):** Clp −0.45 → −0.77 and Cmq −13.6 → −4.4 between α 6° and 10°, where an approach flies. **Ground effect:** on its wheels the Stik gets +16 % lift and −34 % induced drag |
| 03 | [Propeller, slipstream and propwash](03-propeller-propwash.md) | E0b, G1, M5 propeller items | **Wash ratio:** q_wash/q∞ = 1 + 8Ct/(πJ²) gives 35.3× at 5 m/s and 1.3× in level cruise (ideal momentum theory, re-computed by the lead). Measured jet decay at the tail gives 12–20×. The optional P-51 shaft, thrust-axis and slipstream implementation is committed and declared in its aircraft data; it remains experimental and does not validate Stik propwash. The Stik's 11×6-to-12×6 extrapolation remains. |
| 04 | [Ground handling, collisions and crashes](04-ground-handling-collisions.md) | E3b–E4, PT2, E5+ (taildraggers, brakes, retracts, terrain, obstacles, launch, damage) | **Stiction:** a stick/slip anchor per contact, switched in `pre_step`. **E3b targets:** 10 m/s after 4.69 m (elevator neutral); full up-elevator lifts the nose at 11.3 m/s after 6.0 m on the runway. **Taildraggers:** diverge when the tailwheel grips less than its share. **Crash rules:** hull points become frictional contacts with per-component impact limits. Never use Godot physics queries in the sim |
| 05 | [Propulsion: glow, gas, electric, turbine](05-propulsion-engines-motors.md) | G1–G5, PT4, EL1–EL6 (electric), AV-05 | P-51 shaft/slipstream and Avanti turbine code are committed. **Missing reaction:** `−dh/dt` still omits rotor-acceleration reaction (0.83 vs 0.05 N·m on the first Stik tick, derived). **Integration:** the optional P-51 shaft is advanced once per tick; the audited full session showed first-order step-halving. H8/G2 should settle the coupled state and stage contract. Windmilling/stopped-propeller evidence and torque-curve validation remain open. |
| 06 | [Radio input, servos and latency](06-radio-input-servos-latency.md) | F1–F11, D6d, UI-10/12, M5 flight aids | **Radio:** sends channel outputs (expo, rates, trims already applied), 8 axes at 11 bits, every 1 ms only with RF off. **Godot:** samples joysticks once per rendered frame. **Latency:** stick-to-photon ≈ 42 ms at 60 Hz, more than a real 2.4 GHz link, so the sim adds no extra RF delay. **Servos:** too fast on small moves. **Trim:** solved trims become a per-aircraft linkage trim |
| 07 | [Atmosphere, wind, turbulence, thermals, slope](07-atmosphere-wind-turbulence.md) | M5-ATM, M5-W (refines [WIND-PLAN](../../WIND-PLAN.md)) | **Density altitude:** 1500 m and 35 °C gives σ 0.78 (stall +13 %, thrust −22 %). **Turbulence:** WIND-PLAN's OU process is already the MIL-HDBK-1797 first-order form. **Sampling:** wind plus its gradient per stage gives correct rotational gusts. **Random numbers:** xoshiro128** is bit-exact in GDScript at ~10 µs/tick. **Treeline:** the field sits in its wake for most wind directions |
| 08 | [Validation and flight testing](08-validation-flight-testing.md) | VAL-1…15, D8b, D10, Gate 2/2-R, EX-09, P51-09 | **D11a is complete:** `research/sensitivity/results.md` contains the repaired D10 sweep with no refused rows and both US120 and 25e comparisons. Current roll-pole gaps are 2.07× (US120) and 2.37× (25e). Owner measurements, logger flights and pilot validation remain future evidence. |
| 09 | [Aircraft data and the geometry-to-physics pipeline](09-aircraft-data-pipeline.md) | DATA-1…16, every aircraft track, P51-11 | **v1 limits:** v1 fits one airplane shape. A component-tree v2 remains conditional on an approved consumer v1 cannot represent cleanly. **Load time:** 110 ms, almost all of it the stall-start bisection. **Pipeline:** two duplicated `derive_physics.py` scripts and no P-51 `--check` in CI. **Mods:** data-only. **Licences:** GPL tools stay outside `app/` |
| 10 | [Audio, perception and presentation](10-audio-perception-presentation.md) | G3a–f, PERC-1…9, Gate 2 readability, VQ-03, UI-08 | **Tones:** firing at rpm/60 and blade passing at blades·rpm/60. **Godot 3D audio:** its Doppler has no travel delay and its distance filter is 20 dB too strong, so we render propagation ourselves. **Audio queue:** the placeholder adds ~186 ms. **Readability:** a 50° camera shows the airplane at 0.63× real size, and auto-zoom erases the approaching/receding cue |

## Where the documents disagree, and the resolution used in ROADMAP

ROADMAP is authoritative for execution order and gates. H8 precedes wheel anchors and new coupled states; load-contributor extraction (H10), aircraft schema v2 (DATA-8), and custom VLM research (D11c) are conditional on a concrete consumer or unresolved question. Gate P uses the 500 µs/tick budget or a documented near-term reserve on the owner’s slowest supported machine; 250 µs is not a migration threshold. The proposals below are reconciled against those policies.

| Topic | Positions | Resolution |
| --- | --- | --- |
| Session integration and the G2 shaft state | 01's original toy comparison favors coupled RK4; the audit separately measured the current full P-51 session and found first-order convergence while its rigid-body kernel remains fourth-order with frozen auxiliaries. 05's linearly implicit split update would retain that coupling error. | Before anchors or further coupled shaft work, H8 defines a minimal typed contract for continuous RK4 state, sampled per-tick state and discrete modes, plus stage time, trace/reset semantics and fault rollback. G2 then integrates coupled rotor speed through the RK stages and verifies end-to-end h/h₂ convergence. Current estimates do not justify an implicit split update; reconsider solver choice only if measured stiffness requires it. |
| Touchdown force jump | 01: Hunt–Crossley damping. 04: ramped damping plus rebound damping | One step, E1b: a force that is continuous at δ = 0 (either law, chosen by the h/h₂ order test) plus rebound damping |
| G1 numbering | 03 and 05 both proposed G1a/G1b | 03's G1a–e (table schema, flags, BEM tool, windmill, normal force) absorb 05's two |
| Aero performance | 02's X-perf-1 duplicates 01's PERF steps | Merged into H4/H5 and Gate P |
| D10 re-run and 25e comparison | 02's X-aero-1 and 08's X-VAL-1/2 | Completed in D11a; generated results have no refused rows and include the 25e comparison. |

## Facts the lead re-checked

- **Physics cost:** the audit measured all four catalog aircraft under concurrent audit load on a shared host (best of three; trimmed / α=15°): Stik 408.1 / 370.3, Extra 447.9 / 457.2, P-51 1,255.8 / 1,186.9, Avanti 411.9 / 404.4 µs/tick. These are exploratory headroom measurements, not a controlled comparison or release certificate; see [audit benchmark evidence](../project-audit-2026-10-06/README.md#verified-lead-findings) and [doc 01](01-numerics-architecture-performance.md). The earlier 501 µs and 505–562 µs single-model figures are dated baseline measurements, not the current all-aircraft reference.
- **Damping by regime:** a probe through `Aero.loads` at 15 m/s gives Clp −0.451 (α 2–6°) → −0.774 (α 10°) and Cmq −13.6 → −4.40, following the local-flow blend weight (0 → 1). This measurement used a 2026-10-06 working-tree snapshot that included then-uncommitted `aero.gd` edits; the Stik uses none of them.
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
- **Other tracks' code:** the initial snapshots predate commit `480cddd`, which landed the P-51 shaft/slipstream and Avanti turbine work. Current statuses and remaining integration/fidelity gaps are reconciled in docs 03 and 05; their dated baseline descriptions are explicitly historical. Line references may drift.
- **Scope:** everything here is research and proposals. No simulation code or data was changed. Proposed steps become real when ROADMAP lists them and their proof passes.
