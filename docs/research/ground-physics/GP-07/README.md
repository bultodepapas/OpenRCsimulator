# GP-07 — Ugly Stik airframe contacts: drawn-model hull, surface friction, runway strip

2026-10-25 · **Status: GP-07a–d delivered (software evidence); ploughing, static friction and field measurements open.** Owner: physics line (owner request: make the Stik's contact points, scrapes, crashes and runway friction realistic). Tools: [research/ground-physics/gp07](../../../../research/ground-physics/gp07/README.md). Sources: [sources.json](sources.json). No RC airframe was measured; every coefficient below is a proxy or an estimate.

## Findings

| # | Finding | Evidence |
| --- | --- | --- |
| F1 | **The Stik's crash hull did not match its drawn model.** Eight points read from the plan in 2026-10 had drifted from the model (US-V09…V18): over 6000 attitudes the drawing sank up to **104 mm** into flat ground before any hull point or wheel touched (54 % of attitudes over 10 mm, 22 % over 50 mm): wing-tip leading and trailing edges, the tail skid and ventral fin, the elevator tips, the side-mounted engine. The fin-top point stood **89 mm above the drawn fin**, so an inverted Stik rested on a phantom fin; the wing-tip points sat 20 mm below the drawn tips (2.9° drawn dihedral), so a banked tip touch stopped short of the drawing. | GP-07a sweep (`hull_coverage.py`) |
| F2 | **One friction coefficient for every surface.** Soft hull contacts (E3d1) used μ 0.4 on the runway strip, mown field and uncut grass alike. | `hull_contact.gd` |
| F3 | **Crash presentation treated the runway as pavement.** The field's `runway` is a mown grass strip for physics and rendering ([DECISIONS 2026-10-06](../../../DECISIONS.md)), but the crash code gave it asphalt friction 0.55, rebound 0.18 and transfer 0.95, no turf thrown, a hard thud, sparks from a sliding engine and a grey asphalt scuff, where most landings and crashes happen. | `severity.gd`, `effects.gd`, `crash_audio.gd`, `airframe_scuffs.gd` |
| F4 | **Fixed 0.2 m/s friction regularization.** A lightly loaded resting point crept under small side forces; a hard wing-tip impact (about 90 N on 0.19 kg of effective mass) reached a linear friction rate of λ·dt ≈ 4 when its slip crossed zero, beyond RK4's real-axis limit (2.78), so friction chattered within the band. | rate analysis below |
| F5 | **Restitution is within the evidence.** As integrated (RK4, onset ramp, non-pulling clamp) a contact rebounds with e ≈ 0.22 (wing tip) to 0.44 (near the CG) at 1–8 m/s, and up to 0.72 for 0.1 m/s touches; not the 0.05 the linear formula suggests for ζ 0.7. Proxies: hard light part on firm short turf 0.47 at 1 m/s, 0.41 at 3 m/s; crushing airframe 0.05–0.25. **Not changed.** | `restitution_probe.py` |

## GP-07b — crash hull from the drawn model

`derive_stik_hull.py` reads the built visual model's convex hulls and takes each named feature as the drawn point furthest along a stated direction inside a named part. It mirrors left/right features, skips a feature within 20 mm of an earlier one and drops features strictly inside the hull of the others. The wheels do not count for that pruning, because scenery collisions (posts, fences, trees) test the hull alone. Over 6000 attitudes it refuses a hull that lets the drawn airframe sink more than 12 mm into flat ground (hull and wheels) or 15 mm into a flat obstacle face (hull alone), or that puts more than 5 points within the 4 mm damping onset of one contact plane (each point's damper is sized on its own effective mass, so a bunch multiplies the damping rate: 5 × 0.35 per tick against RK4's 2.78). Propeller blades are left out: the disc is the E3d2 strike test. Hull points are drawn points, so none floats (0.1 mm rounding).

| | 2026-10 plan estimate | GP-07b |
| --- | --- | --- |
| Hull points | 8 | 26 |
| Worst sink of the drawn airframe into the ground | 104 mm (wing tip LE) | 9.5 mm (elevator TE, 66° tail-down) |
| Worst sink into a flat obstacle face (hull alone) | — | 10.7 mm (propeller hub) |
| Attitudes sinking over 10 mm / 50 mm | 54 % / 22 % | 0 % / 0 % (airframe); 1.5 % only at the nose wheel |
| Worst hull point above the drawing | 89 mm (fin top) | 0.1 mm |

Points (LE frame `[x_aft, y_right, z_up]` in the [Stik data](../../../../app/data/aircraft/jensen_ugly_stik_60.json)): per wing tip the bottom crest (`probe_wing_*_tip`, the legacy id), leading edge, top crest and its front, outer edge and aileron trailing-edge tip; per side the elevator tip; fin top and rudder top trailing edge; rudder trailing edge and its bottom (`probe_tail_end`); the **tail skid** (−0.087 m); the fuselage bottom corners at the firewall; the engine top, front, front bottom and **cylinder head** (side-mounted O.S. 61, 78 mm right of the centreline); the propeller nut. On flat ground the wheels always touch before the fuselage bottom (205 mm below it; the gear crashes past 120 mm of travel), but the firewall corners stay for obstacles. The belly and tail-post features fall inside the line from those corners to the tail skid; the leading-edge shoulders sit within 20 mm of the leading edge. Points on the aileron, elevator and rudder sit at neutral; a deflected trailing edge moves 1–5 cm off them (rudder most). Point contacts cannot catch a narrow post or rail between points (the wing span between root and tip, the fuselage between corners and skid); that needs edge contacts.

Contract: hull label `engine` added (an exposed engine point off the centreline; crash presentation already groups and releases engines). Economics: every Stik hull id opens the airframe inspection and spinner/engine points also the engine, now read from the data (`build_runtime.stik_contact_components`). Regenerated: 5 glow and 4 synthetic Stiks (hull fields only), economy catalog and worked examples (source hashes), 4 workshop descriptors (hashes), 5 d8b-r2 research candidates (hull fields only).

Behaviour: an over-rotation on the mains beyond 13.3° (about 11° with 25 mm of gear compression) scrapes the tail skid. On the soft (interactive) route it is a scrape and the flight continues; on the legacy scripted route any hull contact is a crash (D9d), as for any point. An inverted Stik rests on its drawn fin and wing-tip tops. The 3 mm round-wheel rim and the 15 mm nose-wheel rim at a 50° nose-down attitude remain GP-06 D2.

## GP-07c — airframe friction per surface, load-scaled regularization

[`surface_friction.json`](../../../../app/data/ground/surface_friction.json) gains `airframe_friction`, the kinetic friction of an airframe point (not a tyre) per surface; `GroundSurfaces.build_airframe` makes a separate flat table (the tyre table's layout, used by wheels, helicopters and vehicles, is unchanged); `HullContact` reads μ under each point. No source measures film, painted wood or nylon on natural grass:

| Surface | μ | Range | Anchor | Transfer |
| --- | ---: | --- | --- | --- |
| Runway (mown strip) | 0.40 | 0.35–0.50 | Steel tubes towed on a short natural-grass pitch 0.45 ± 0.01 (Linthorne & Cooper 2013); golf ball sliding on a green 0.25–0.40 (Penner 2002) | proxy, fair |
| Mown field, helipad | 0.45 | 0.40–0.60 | Same rig; authors estimate about 0.6 on uneven grass | proxy |
| Rough (uncut) | 0.55 | 0.45–0.8 | No data; stems add drag | estimate |
| Without a field (fixtures, lake banks) | 0.40 | — | Hard dry soil 0.36 (NASA TM-81347) | proxy |

Light loads grip more on grass (Cenek 2005), so the upper half of each band is defensible. Wet grass would scale by about 0.75–0.9; the simulator has no wet ground yet.

Regularization: friction is linear below `v_reg = max(0.01 m/s, n·μ·F/(m_min·120 s⁻¹))`, with m_min the point's smallest effective mass (the same mass that sizes its spring) and n the number of hull points touching. Each point's linear rate on its own mass stays below 120/n s⁻¹ and the sum over the body, Σ (m_i/M)·120/n, below 120 s⁻¹ (λ·dt = 0.5 at 240 Hz, the wheels' bound), however hard the impact and however many points slide. Measured on the real loads: friction alone at most 62 s⁻¹ (179 s⁻¹ without the shared n), all contact damping and friction together λ·dt ≤ 0.98 in the tested poses. A wing tip resting alone with 5 N holds within 0.083 m/s instead of 0.2 m/s. The contact law identity is now `soft-hull-spring-friction-v2`; soft checkpoints and traces hash the airframe table, legacy ones are unchanged. Stiffness, damping, the terminal rule and the depth backstop are unchanged. These laws apply to every aircraft with soft contacts; the friction values describe the surface, not the airframe, but only the Stik was examined here.

Flight logs: the header records the airframe table and replay restores it (`flight_log_cli.gd prepare_replay`; the research comparison scripts that copy a header's surfaces do the same). Setting the session's `airframe_surfaces` re-prepares the hull contact, so a replay, a field change or a failed field change never leaves the physics on another table than the configuration hash. Soft logs recorded before GP-07 are refused by the contact-law identity (v1 → v2), as for any contact-law change.

## GP-07d — the runway strip is turf in crash presentation

The runway strip now matches the mown field for impact transfer (0.82) and wreck rebound (0.06), slides with the physics table's μ (runway 0.40, mown and grass aliases 0.45, rough 0.55; a test keeps them equal), throws turf, sounds like grass and leaves a grass stain with a little soil. Paving keeps its values under `asphalt`/`concrete`; a paved runway would be a new surface type with its own factors. Focused tests that used `runway` as their paving case now say `asphalt`.

## Verification

- [`test_airframe_contacts.gd`](../../../../app/tests/test_airframe_contacts.gd), **46 checks**:
  - drawn-model coverage oracle in Godot, independent of the generator (2000 attitudes, worst 9.5 mm; every hull point within 0.06 mm of a drawn point);
  - μ per surface: friction/normal exactly 0.40 on the strip and 0.55 in the rough; on a synthetic field with four distinct values a wing tip over the mown or pad band feels 0.47 or 0.52 while the CG sits on a 0.31 strip (catches a lookup at the CG or with north and east swapped);
  - rates on the real loads by central differences: friction alone ≤ 120 s⁻¹ on the whole mass, and the largest eigenvalue of all contact damping and friction ≤ 2.5 per tick, over tip-edge, inverted, nose-in, tail-down and leading-edge poses at 2, 6 and 20 mm;
  - presentation/physics table agreement and identity (legacy hash unchanged, soft hash includes the table);
  - real-tick scenarios: a 16° over-rotation at 12 m/s first touches `probe_tail_skid` and continues; an inverted 1 cm drop settles on fin and wing-tip tops with the drawn fin top 2.3 mm into the turf; a 120-tick soft scrape on the field is logged and replays exactly from its header.
- [Mutations](../../../../research/ground-physics/gp07/mutations.log): plan-estimate hull, one μ everywhere, lookup at the CG, north/east swapped, fixed, load-blind, whole-mass or unshared regularization, table not installed or not re-prepared, missing from or leaking into a configuration hash, log header or replay without the table, presentation runway friction/rebound/dust/sound.
- Updated focused tests pass: crash hull labels (257), contact contract (1372), ground contact (23), soft contacts (36), crash audio, presentation ladder (46), proportional, severity, wreck surface; unchanged ones pass: physical identity contacts, hull crossing, contact session and policy, dynamic-mass contacts, lake collision, ground-stage queries, crash effects, wreck, energy, integration, soft-contact feedback, cause, snapshot, breakup. Economics `test_runtime_data` 30/30. Generators `--check`: Stik hull, glow installations, synthetic relabel, schema, economics runtime and catalog, workshop descriptors, d8b-r2 candidates.
- Full suite (2026-10-25, dev VM; `app/test.sh` is fail-fast, so the parts were run separately and every failure was rerun on a clean HEAD copy):
  - Units: 692 of 709 pass. The 17 failures fail identically at HEAD: the AI companion suites (the profile pins a changed `pilot.gd`; GP-07 adds the solver pin to `test_companions_profiles`), field shadow masks, staged-session validation bytes, lake bake source stamp, landscape vegetation, retractable-gear input (engine abort), Settings and modal layout, aircraft-flow and quit UI.
  - Offline generators and integration: all pass (H7 golden branch signatures and one-ulp sensitivity, C7-R1 trace acceptance, model contracts, d8b-r2, pull-up, weather) except checks that fail identically at HEAD: the L7-R1 woodland recipe, the H6 bare `pow` in `mass_inventory.gd`, and the frame-aligned FPS-independence checks of M5-W04a turbulence, M5-ATM atmosphere, G2a/G2b shaft and the fixed-step app run ("a frame ended at tick 120, past the scheduled tick 119").
- AI companions ([A/B report](companion-ab.json), `companion_ab.py`): the 9 retained tapes replayed with the accepted solver and the pre-GP-07 Stik data against this tree. The 6 player tapes are identical. The 3 AI tapes are identical on every row except the last, where the companion meets the ground at 29 m/s and 7.5 m/s sink: the contact geometry this step changes. `qualification.json` names an accepted revision (`73086db4`) that is not in this repository, so `rebind.py` cannot run here; HEAD reproduces the accepted solver identity and served as the base. Re-pinning the profile (solver, aircraft data, and the pre-existing `pilot.gd` controller pin) is the AI track's qualification decision.

## Open

- **Ploughing (dig-in).** Soil-cutting proxies give F ≈ (q_s + C·ρ·v²)·w·d with q_s 0.1–0.5 MPa (Anderson 2018) and an embedded depth from turf stiffness 12–140 kN/m for a 10–20 mm contact; the equivalent extra μ spans 0.01–0.8. Too wide to calibrate; the penalty depth (a numerical choice) must not be read as turf penetration. A wing-tip drag test on the owner's field would bound it.
- **Static friction.** μ_s/μ_k 1.1–1.3 is unverified for grass; a tilt test on the owner's field (breakaway and sliding angle of a wing on the turf) settles it in minutes.
- **Gear collapse.** Gear overtravel stays terminal; a bent strap that lets the belly reach the ground needs persistent gear state (CR-11–15) and brings back the dropped belly features.
- **Fleet.** The other airplanes' hulls come from their own generators and were not changed. A first sweep (`hull_coverage.py --exclude propeller --exclude blade`, 6000 attitudes; informational: retractable gear is dumped in its build pose, which inflates float figures) finds the same class of gap:

  | Airplane | Hull points | Worst sink of the drawing | Over 10 mm | Worst parts |
  | --- | ---: | ---: | ---: | --- |
  | GP Extra 300S | 10 | 24 mm | 2 % | fuselage and rudder top, inverted |
  | P-51D | 14 | 61 mm | 8 % | cowl band and spinner, inverted nose-down |
  | Ventage Jet | 13 | 88 mm | 17 % | fuselage core tail-down, canopy inverted |
  | Turbo Lumber | 17 | 95 mm | 27 % | fixed wing panels on a wing tip |
  | F4U Corsair | 14 | 155 mm | 51 % | fuselage core and cowl |

  Each would take a named-feature list in its own generator, as `derive_stik_hull.py` does for the Stik.
