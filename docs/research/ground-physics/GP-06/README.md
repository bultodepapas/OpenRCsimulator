# GP-06 — fleet landing-gear and touchdown audit

2026-10-19 · **Status: audit complete; GP-06a–c delivered; stiffness, restitution and wheel-shape decisions open (below).** Owner: physics line. Tools and reproduction: [research/ground-physics/gp06](../../../../research/ground-physics/gp06/README.md). Software evidence only: no RC aircraft was measured.

Scope: every geared catalog airplane — Jensen Ugly Stik 60 and its three glow variants, GP Extra 300S .60, P-51D 1/4, Ventage Jet (SebArt Avanti S) and Turbo Lumber Evolution. The audit asked three questions: do the physics contacts sit where the drawn wheels touch, is the gear geometry sane, and how does each airplane land.

## Method

| Check | Tool | Basis |
| --- | --- | --- |
| Static gear geometry | `geometry_dump.gd` + `geometry_audit.py` | Production loader output; spring equilibrium, point contacts. Full-size guidance quoted for context only (Raymer ch. 11, Currey ch. 3). |
| Visual vs physics contact | `app/tests/test_gear_visual_contacts.gd` | Manifest-bound model as flown; rendered axle node minus profile radius, converted through the manifest datum, against the physics contact. |
| Gear survival | `app/tests/test_gear_reserve_energy.gd`, `reserve_drop.gd` | Former 14 CFR Part 23 (2011 text): §23.473(d) limit descent velocity ≥ 7 ft/s, §23.473(e) lift ≤ 2/3 W through the CG, §23.725 limit drop, §23.727 reserve drop at 1.44× height (1.2× velocity) in which the gear "may not fail". Borrowed full-size convention, not RC data. |
| Touchdown behaviour | `landing_envelope.gd` | Real `FlightSession`, interactive soft-contact policy, idle, field surfaces; sink sweep 0.25–3.5 m/s in flare (1.15 Vs), flat/wheel landing (1.4 Vs) and three-point attitudes; attitude-holding probe pilot. |

Regulation text was read from the GPO 2011 CFR volume (§23.473, §23.725, §23.727).

## Findings and actions

| # | Finding | Evidence | Action |
| --- | --- | --- | --- |
| F1 | **Stik contacts 5 mm below the drawn wheels.** E1 read the model-v3 axle (model y −0.22 m) as 0.22 m below the thrust line; the thrust line is at model y −0.005 m. The rendered wheels floated 5 mm above the ground on all nine Stik-derived files. `test_aircraft_data` compared against the same misread value and passed. | Mains 5.000 mm, nose 4.975 mm (and 0.28 mm in x) against `research/ugly-stik/model-v3/equipment-handoff.json` | **GP-06b** fixed (below). |
| F2 | **Glow Stiks had no wheel profile.** They fell back to the legacy gear law: no rim-speed state, and the renderer skipped compression, spin and steering, so their wheels were drawn 15–18 mm into the ground at rest (static sag minus the F1 float). A fleet test required at least one geared aircraft on the legacy route, which kept the gap invisible. Glow traces could not carry a wheel tail. | `test_aircraft_contact_contract`, `test_trace_metadata` (63 failures once profiles were added) | **GP-06a** fixed (below). |
| F3 | **Collapse thresholds below the reserve drop.** Gear overtravel is a terminal crash. The Extra, P-51 tail wheel, Avanti and Timber collapsed already in the 7 ft/s limit drop; in piloted touchdowns the Extra, Avanti and Timber crashed at 2.5 m/s sink. | Tables below | **GP-06c** fixed (below). |
| F4 | **Gear stiffness is a numerical artifact.** Every spring comes from the E1 rule ω·dt < 0.1 at 240 Hz: 17.5–34.5 mm static sag, 2.7–3.8 Hz heave. The airframe sits about 2 cm below its built geometry and the renderer draws each wheel that far up its leg (Extra: 21 mm of a 35 mm wheel radius; its pant bottom is 24.7 mm above the wheel bottom, so pants reach the ground at 25 mm compression). Large touchdown compressions follow. | Static table | **Open: owner decision D1.** |
| F5 | **Taildragger bounce is unmeasured.** First-bounce restitution of the CG (climb out / sink in): Extra 0.28–0.43, Timber 0.10–0.36, P-51 0.42–0.65, and 1.02 in a near-stall P-51 three-point touchdown at 0.25 m/s, where lift adds energy. Near-stall three-point P-51 touchdowns also drop a wing onto its tip (soft scrape). Mains ahead of the CG pitch the nose up 12–42°/s on touchdown, so the P-51 balloons 0.4–0.7 m after a 1 m/s touchdown under an attitude-holding pilot. The tricycles do not bounce: the mains behind the CG derotate them. This is the expected taildragger mechanism; its size depends on gear damping that no source gives. | Envelope tables | **Open: measurement M1.** |
| F6 | **Point contact at the level-attitude wheel bottom.** In a pitched attitude the round wheel touches r·sinθ farther forward and r(1−cosθ) lower: P-51 at rest (14.6°) 21.6 mm / 2.8 mm, Timber (9.8°) 9.9 / 0.9 mm, Extra (10.9°) 6.6 / 0.6 mm. The drawn wheel sinks by the second figure; the main-gear moment arm changes by up to 14 % (P-51). | Static table | **Open: proposal D2.** |
| F7 | **Glow variants soften their gear.** `research/glow-engines/build_installations.py` multiplies Stik stiffness and damping by 0.8 on every variant, an ω·dt workaround predating SF-05 substeps. The 61FX variant flies at the base Stik's mass, so the same wire gear sags 23.0 mm instead of 18.4 mm. | Static table | **Open: NITRO owner; resolve with D1.** |
| F8 | Geometry follows plans and meshes and was not changed. Outside full-size guidance: Extra and P-51 mains are 29.8° and 33.7° ahead of the CG in the three-point attitude (Raymer 16–25°: tail-heavy, bounce-prone wheel landings); the Timber mains are only 11.6° ahead tail-up, so it noses over at 0.20 g of wheel drag; the Stik carries 27 % on its nose wheel with a 63.5° overturn angle (Currey ≤ 63°), so it tips before it slides in fast taxi turns (known E3 item). Without rudder input the Timber ground-loops and scrapes its stab tip: expected of a taildragger. | Static table, unpiloted runs | Recorded only. |

### GP-06a — glow Stik wheel profiles

`app/data/ground/wheel_profiles.json` gains `stik-glow-55ax-2t`, `stik-glow-61fx-2t` and `stik-glow-fs64v-4t` with the Stik's wheels (same radii, estimated inertia, no brakes). `FlightSession.trace_meta()` keeps the wheel tail after the glow slots; `Trace` validates it like the shaft and turbine routes. `test_glow_trace` adds three negative cases (undeclared tail, shifted index, state without its wheels). The fleet contract now requires every shipped geared aircraft to apply its profile; the legacy route stays covered by its isolated fixture. The Avanti derivation, which records the profile-registry hash, was regenerated.

### GP-06b — Stik contacts on the drawn wheels

Mains `[0.215, ±0.18, −0.2531]`, nose `[−0.136276, 0, −0.249925]` (LE frame) from the model-v3 handoff, in the Stik, the four synthetic electric files and, through `build_installations.py`, the five glow files. The airframe now rests 5 mm lower: propeller clearance 84 → 79 mm, belly 186 → 181 mm. `test_aircraft_data` checks the thrust-line datum. In `test_ground_contact` the nose-only sign fixture moved from 0.30 to 0.29 m altitude (the nose wheel had touched by only 0.9 mm), and the frictionless-drift order check exempts drifts below 0.1 µm (now 4.2·10⁻⁸ m at 240 Hz); E5a uses the same floor. Touchdown, takeoff roll (E3b3), runway start, stiction, friction, landing maneuver and landing-variation tests pass unchanged. The D8b-R2 synthetic polar candidates embed the Stik file and were regenerated (gear lines only).

### GP-06c — reserve-energy gear travel

Rule: each contact's `max_compression` is at least 1.05× its peak compression in the §23.727 reserve drop (2.56 m/s, lift 2/3 W, two attitudes), rounded up to 5 mm. Values are authored through each generator with this provenance:

| Aircraft | Contact | Before → after (m) | Reserve-drop peak (mm) |
| --- | --- | --- | --- |
| Extra 300S | mains / tail | 0.08 → 0.10 / 0.05 → 0.08 | 93 / 73 |
| P-51D | tail | 0.08 → 0.105 | 96 |
| Ventage Jet | mains / nose | 0.08 → 0.105 / 0.06 → 0.085 | 96 / 79 |
| Timber | all (`gear_travel`) | 0.08 → 0.10 | 95 (mains) |

Stik family and P-51 mains already passed (worst 83 %). Only `max_compression` and its source text changed in the four generated files (verified against HEAD). The economics dossier pins were rebound after that bill-of-materials check; catalog, worked examples and Workshop descriptors were regenerated. Forces below the threshold are unchanged, so no trajectory changes unless the old threshold was crossed.

## Measurements

### Static geometry (after GP-06b)

| Aircraft | Rest pitch | Loads mains/third | Sag mains/third (mm) | ζ mains/third | Mains to CG, level / rest | Overturn | Rest clearances | Prop | Strike angles |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Stik 60 | −0.4° | 72.7 / 27.3 % | 18.4 / 17.5 | 0.38 / 0.44 | 20.4° / 20.8° aft | 63.5° | belly 181 mm | 79 mm | tail 18.2° pitch, wingtip 26.0° bank |
| Stik 61FX | −0.3° | 72.8 / 27.2 % | 23.0 / 21.9 | 0.34 / 0.40 | 20.4° aft | 63.1° | belly 177 mm | 75 mm | tail 17.9°, wingtip 25.6° |
| Extra 300S | +10.9° | 86.5 / 13.5 % | 21.0 / 21.0 | 0.26 / 0.47 | 18.9° / 29.8° ahead | 56.2° | tail end 48 mm | 147 / 95 mm tail up | wingtip 16.7° |
| P-51D | +14.6° | 80.0 / 20.0 % | 19.2 / 34.5 | 0.27 / 0.39 | 19.2° / 33.7° ahead | 47.2° | tail end 38 mm | 297 / 161 mm tail up | wingtip 24.9° |
| Ventage Jet | +0.1° | 87.9 / 12.1 % | 21.0 / 21.0 | 0.26 / 0.50 | 23.6° / 23.5° aft | 39.8° | belly 146 mm | — | stab tip 19.4° pitch, wingtip 21.9° |
| Timber | +9.8° | 87.6 / 12.4 % | 21.0 / 21.0 | 0.26 / 0.49 | 11.6° / 21.4° ahead | 62.6° | aft belly 30 mm | 137 / 95 mm tail up | wingtip 26.6° |

ζ uses each contact's real static share, not the loader's m/3 convention. Stall onset α: Stik 12.1°, Extra 13.3°, P-51 11.9°, Ventage 10.3°, Timber 15.1°; every tricycle tail-strike angle exceeds it.

### Visual vs physics wheel bottoms

Before GP-06b: Stik family 5.0 mm (all others ≤ 0.014 mm). After: every aircraft ≤ 0.014 mm (Timber's mesh-measured radius). The guard fails on the pre-fix Stik data (3 failures at 5.000/4.975 mm).

### Reserve-energy drop (peak compression / travel)

| Aircraft | Before, worst limit drop (2.13 m/s) | Before, worst reserve (2.56 m/s) | After, worst reserve |
| --- | --- | --- | --- |
| Stik 60 | 62 % | 72 % | 72 % |
| Stik 61FX | 72 % | 83 % | 83 % |
| Extra 300S | tail 124 % (three-point) | tail 147 % | 93 % |
| P-51D | tail 102 % (three-point) | tail 120 % | 91 % |
| Ventage Jet | nose 111 % (all wheels) | nose 131 % | 93 % |
| Timber | mains 100 % (level) | mains 118 % | 95 % |

Peak ground-reaction load factor in the reserve drops: 4.4–5.5 g.

### Piloted touchdowns (first sink rate that ends the flight)

| Aircraft | Flare before → after | Flat before → after | Three-point before → after | Bounce at 1 m/s (hop height) |
| --- | --- | --- | --- | --- |
| Stik 60 | > 3.5 → > 3.5 m/s | > 3.5 → > 3.5 | — | none |
| Extra 300S | 2.5 → 3.0 | 3.0 → 3.5 | 2.5 (tail) → 3.0 | 57 mm flare, 204 mm wheel landing |
| P-51D | > 3.5 → > 3.5 | > 3.5 → > 3.5 | 3.0 (tail) → > 3.5 | 688 mm flare, 397 mm wheel landing, 528 mm three-point |
| Ventage Jet | 2.5 → 3.5 | 2.5 → 3.5 | — | none |
| Timber | 2.5 → 3.0 | 3.0 → 3.5 | 2.5 → 3.0 | none flare, 130 mm wheel landing, 59 mm three-point |

Every remaining end is a gear-travel collapse at or above 3.0 m/s, beyond the reserve drop. Soft scrapes: P-51 three-point left wingtip and tail end from 1 m/s; Timber aft belly from 2.5 m/s. Raw per-case results are in this directory: `landing-envelope-{before,after}.json` (before = commit `bfc32834`, the last tree without GP-06, run from an app-only worktree), `reserve-drop-{before,after}.json` and `geometry-audit.json`.

## Open decisions and measurements

- **D1 — realistic gear stiffness.** Real RC wire and strap legs with rubber tyres probably sag a few millimetres, not 2 cm (estimate; unmeasured). SF-05 already admits stiffer gear by substepping while a wheel is within reach: 5 mm sag needs 2 substeps, 3 mm needs 3. Cost scales with the substeps near the ground; this VM measured 925 µs/tick for the Extra against the 500 µs budget on the owner's slowest machine. Choosing values needs M1 data; travel would then be re-derived with the GP-06c rule and F7 removed.
- **D2 — round-wheel contact.** Replace the body-fixed point with axle minus radius along the ground normal projected into the wheel plane, as an opt-in law keyed on the profiled radius. Changes every geared aircraft's ground trajectories; needs its own step, refinement and golden review.
- **M1 — owner measurement (Stik).** Static sag under the airplane's weight, then level drops from 10, 20 and 30 cm filmed at 240 fps against a ruler: rebound height gives restitution, the frames give peak compression. That calibrates k, c and travel for the first airplane; the others keep the GP-06c rule until measured.

## Limits

The probe pilot, speeds and start height are authored test choices. The FAR rules are a full-size convention. Software checks do not establish physical realism; pilot acceptance and RC measurements remain open.
