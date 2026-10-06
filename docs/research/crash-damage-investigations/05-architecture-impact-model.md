# 05 — Architecture and impact model for this repository

**Status:** design research, 2026-10-06 (CR-00). **Serves:** [CRASH-DAMAGE-PLAN](../../CRASH-DAMAGE-PLAN.md) (all CR- steps), ROADMAP E3d, E6c, E7b, G4b. **Read with:** [04 ground handling](../roadmap-investigations/04-ground-handling-collisions.md) §6 (crash vs scrape), [01 numerics](../roadmap-investigations/01-numerics-architecture-performance.md) (budget, state layout), documents 01–04 of this folder. **Evidence:** [`research/crash-damage/cr-00/`](../../../research/crash-damage/cr-00/) (effective-mass experiment, reproducible).

This document turns the research into one design that fits the code as it is on 2026-10-06. It is a proposal: each part becomes real only when its CR step passes its proof.

## Summary

1. **Today a crash is a frozen frame.** Any `crash_hull` point at or below the ground (or a gear leg past its travel) pauses the simulation for 1.5 s, freezes the picture with the airplane half inside the ground, cuts the engine buzz mid-sample (`stream_paused`), prints speed and sink, and resets. Nothing knows *which* point hit, how hard, or on what surface.
2. **Three layers, one boundary.** The deterministic simulation decides *what happened* (impact events, which parts break, how the airplane flies afterwards). The presentation layer shows it (sound, particles, debris, wreck, camera, replay). Presentation never writes back into the simulation.
3. **The simulation owns the airplane while it is an airplane.** After a structural crash the wreck is handed to Godot physics (visual only, not deterministic), starting from a post-impact state that the simulation computes deterministically.
4. **Location and direction matter through rigid-body physics, not tuning.** The energy that the struck part must absorb is ½·m_eff·v_n², with m_eff = 1/(1/m + (r×n)ᵀI⁻¹(r×n)). From our own data: a wingtip struck vertically engages **5–7 %** of the airplane's mass on all four aircraft. A spinner struck in level attitude engages 30–40 %. A vertical nose-in engages 100 %. The rest of the energy stays in the airplane as rotation: the cartwheel.
5. **One pure resolver, two feeders.** `structure.resolve(event, structure, durability)` maps an impact to broken joints with an energy budget. The simulation feeds it the first contact; the wreck's Godot contacts feed it the secondary hits. One rule set means one table of thresholds to validate.
6. **Part loss reuses the mass inventory.** Each structural section lists the inventory items it carries. Removing a section recomputes mass, CG and inertia with the loader's own `inertia_about` (D1-R1: one inventory for CG and inertia). The velocity field stays continuous, so the remaining airplane keeps v_newCG = v + ω × Δcg and the same ω.
7. **Damage feeds back into the flight through existing seams:** wing and tail loads are already local elements (D9-R1), and D11d adds strips. Engine states come with G2d and AV-05b, gear contacts are a list (E1), and mass-property updates arrive with G4b. Damage adds no per-tick cost while nothing is damaged.
8. **Determinism is kept for free.** Damage changes happen only in `pre_step`, as discrete events (like E3b's anchors). A replay from the same inputs recomputes the same events. Goldens stay bit-identical while no impact occurs.
9. **The physics budget is idle after a structural crash** (the simulation stops), so the wreck and debris can spend it. Flying damaged keeps debris to a handful of pieces.

## What exists and what each CR phase reuses

| Existing piece | Where | Reused for |
| --- | --- | --- |
| Crash hull: 8–14 points per aircraft, with provenance | `crash_hull` in `app/data/aircraft/*.json`; `touches_ground()` in [flight_session.gd](../../../app/sim/flight_session.gd) | Impact points (CR-01 names them; E3d1 turns them into typed contacts) |
| Gear contacts with travel limits (E1), tyre friction (E2) | [ground_contact.gd](../../../app/physics/ground_contact.gd) | Gear failure by force or travel; landing-gear damage |
| Surface lookup per contact (E3a) | [ground_surfaces.gd](../../../app/physics/ground_surfaces.gd), `app/data/ground/surface_friction.json` | Surface id in each impact event (sound, particles, compliance) |
| Mass inventory → mass, CG, inertia (D1-R1) | `inertia_about()` in [aircraft_data.gd](../../../app/physics/aircraft_data.gd) | Section masses, debris masses, mass properties after part loss |
| Local wing and tail loads (D9-R1), strips (D11d) | [aero.gd](../../../app/physics/aero.gd) | Lift loss from a lost tip, stab or control surface |
| `pre_step` discrete updates, `aux` state | [simulation.gd](../../../app/sim/simulation.gd) | Damage flags switched once per tick; H8 later adds named extras |
| Deterministic 240 Hz replay, trace v3, goldens | [trace.gd](../../../app/sim/trace.gd), `tests/golden/` | Crash replay; trace event rows; "no impact, no change" proof |
| Turbine spool model (AV-05a) | [turbine.gd](../../../app/physics/turbine.gd) | Spool-down after a crash, its whine and its duration |
| Engine buzz (placeholder) | [engine_sound.gd](../../../app/render/engine_sound.gd) | Engine death after a prop strike instead of a freeze |
| Section-like node groups: `airplane`, `propeller`, `*_hinge`, `gear` | `app/aircraft/*_model.gd`, [airplane.gd](../../../app/render/airplane.gd) | Visual sections (CR-05 adds a `sections` map to every build) |
| Particle research (GPU particles in Compatibility, clocks, captures) | [SMOKE-PLAN](../../SMOKE-PLAN.md), [smoke-investigations](../smoke-investigations/README.md) | Dust, debris, smoke and fire share SM-00's backend decisions |
| Sound snapshot and own propagation (proposed) | ROADMAP G3a, G3d; [10 audio](../roadmap-investigations/10-audio-perception-presentation.md) | Impact sounds read events, never the scene |

## What limits the design today

| Limit | Consequence | Resolved by |
| --- | --- | --- |
| No forces at hull points: any touch must end the flight | Scrapes, belly slides and "damaged but rolling" are impossible | ROADMAP E3d1 (frictional hull contacts) |
| Contacts are soft (k from ω·dt < 0.1): a 15 m/s nose-in would penetrate ≈ 0.6 m before stopping (√(2E/k) with E ≈ 325 J, k ≈ 1,660 N/m) | The simulation cannot resolve a high-energy crash with springs | A structural crash ends the flight and hands the wreck to Godot physics (CR-04) |
| Crash detection runs at tick end; a point can be up to v·dt = 0.125 m (30 m/s) below ground | Wrong point order when two points hit in one tick; a buried picture | Sub-tick crossing fraction per point (CR-01) |
| `crash_hull` is an unnamed list | No component in messages, sounds or damage | Labels in CR-01, kept as the component ids of E3d1's typed contacts |
| `aux` is a fixed array [rpm, servo×3] | No room for damage flags | Session-side damage configuration first (recomputed on replay); H8 named extras later |
| Physics at ≈ 501 µs of its 500 µs budget per tick | No new per-tick cost in flight | Event-only work; zero cost without damage (Phase H buys headroom) |
| Godot physics is 32-bit and frame-synchronised | It must never decide the flight | Used only for the wreck and debris after the handoff |
| gl_compatibility renderer, a VM with no GPU | Some particle and decal features may be missing; GPU cost is unmeasured here | Doc [02](02-godot-destruction-techniques.md); frame times on the owner's machine |

## Three layers

```
 simulation (float64, 240 Hz, deterministic)            presentation (render frames, may be nondeterministic)
 ───────────────────────────────────────────            ─────────────────────────────────────────────────────
 contacts → impact events → structure.resolve()  ──►    crash presenter: sound, dust, marks, camera rules
          → damage config (pre_step)                     debris bodies (Godot physics, visual only)
          → loads/mass/engine/gear reflect damage        wreck handoff after a structural crash
          → trace event rows                             replay viewer, crash report (UI)
                     ▲                                               │
                     └──── never: presentation never writes back ────┘
```

- **Event channel:** `FlightSession` emits `impact(event)` and `damaged(change)`, and appends the same data to the trace as event rows. Presentation subscribes. Tests read the events without any scene.
- **Paths:** simulation-side code lives in `app/physics/impact.gd` and `app/physics/structure.gd` and is owned by the physics line. Presentation lives in `app/render/crash/` and is owned by the crash track. The crash report goes in `app/ui/`, coordinated with the menu track. Sounds go in `app/assets/audio/crash/` with a `sources.json`.

## The impact event

Computed once per tick for every hull point that crossed the ground during the tick (depth `d = down_CG + R₃·r`, with `d_prev < 0 ≤ d_now`):

| Field | Definition | Unit |
| --- | --- | --- |
| `tick`, `fraction` | Crossing fraction f = −d_prev/(d_now − d_prev) inside the tick; events are ordered by tick + f | —, 0…1 |
| `component` | The hull point's label (`wing_tip_left`, `spinner`, `fin_top`, …) | id |
| `point` | Contact position at the crossing (state interpolated at f) | m, NED |
| `v_point` | v_CG + ω × r, in NED | m/s |
| `v_n`, `v_t` | Normal (into the ground) and tangential parts of `v_point` against the ground normal n̂ (flat: up; later the L12 terrain normal) | m/s |
| `m_eff` | 1/(1/m + (r×n̂)ᵀ I⁻¹ (r×n̂)) | kg |
| `e_normal` | ½·m_eff·v_n²: the energy the struck part must absorb in a plastic impact | J |
| `e_total` | ½·m·v² + ½·ωᵀIω, the airplane's whole kinetic energy | J |
| `attitude` | Bank, pitch, flight-path angle, α, β at the crossing | deg |
| `surface` | Surface id under the point (E3a); later terrain or obstacle id (E6b/E6c) | id |
| `engine` | rpm, running state, throttle | rpm, —, 0…1 |

**Worked numbers** (from [`results.txt`](../../../research/crash-damage/cr-00/results.txt), m_eff in kg, wings-level / vertical nose-in):

| Aircraft (mass) | Wing tip | Spinner/nose | Tail end | Belly or canopy |
| --- | --- | --- | --- | --- |
| Ugly Stik (2.89 kg) | 0.19 / 0.64 | 1.15 / 2.89 | 0.43 / 2.88 | belly 2.89 / 2.83 |
| Extra 300S (3.36 kg) | 0.23 / 0.57 | 1.08 / 3.34 | 0.32 / 3.34 | canopy 1.80 / 2.69 |
| P-51D 1/4 (21.5 kg) | 1.58 / 3.90 | 6.60 / 21.2 | 2.34 / 21.1 | scoop 15.9 / 18.6 |
| Avanti S (11.8 kg) | 0.59 / 2.37 | nose 1.30 / 11.8 | 2.28 / 11.7 | belly 9.20 / 10.9 |

Read: a Stik wingtip touching at 3 m/s vertical has e_normal = ½·0.19·9 ≈ **0.9 J**, a scrape. The same airplane flown vertically into the ground at 15 m/s puts ½·2.89·225 ≈ **325 J** into the nose. A P-51 wingtip at 3 m/s gives 7 J and its nose-in at 25 m/s gives ≈ 6.6 kJ. Same rule, very different outcomes, decided by where and how it hits.

**Not proven by this experiment:** real impacts are not single plastic point events (contacts last milliseconds, structures crush, friction acts). m_eff is the right *ranking*. Absolute thresholds need doc [03](03-rc-construction-crash-physics.md) numbers and the owner's judgement.

## Outcome classes

| Class | Meaning | The simulation… | Available from |
| --- | --- | --- | --- |
| **C0 contact** | Touch without damage (wheel, slow tip, belly at walking pace) | continues; contact forces act | E3d1 |
| **C1 scrape** | Cosmetic: a mark, a scuff sound, dust | continues | E3d1 + CR-02 |
| **C2 damaged, flying** | A part breaks or detaches; the airplane can still fly or roll (prop, gear leg, wingtip, canopy, control surface, cowl) | continues with a changed model; the lost part becomes debris | E3d1, E3d2, CR-08…CR-11 |
| **C3 structural crash** | The airframe stops being an airplane (wing off, fuselage broken, firewall gone) | stops; computes the post-impact state; hands the wreck to presentation | CR-01 (as today's crash), CR-04 |
| **C4 destroyed** | Energy far above the structure: many fragments, fuel effects when the airplane carries fuel | stops as C3; resolver marks every section above its limit | CR-07, CR-13 |

Before E3d1 every ground touch is C3 or C4, as today. The resolver still reports the class it *would* give ("scrape"), so its rules can be tested before the simulation can act on them.

**The five target situations** (the plan's acceptance set; numbers are illustrative, Stik):

| Situation | Typical event | Expected outcome |
| --- | --- | --- |
| Minor wingtip strike on landing | tip, v_n ≈ 1–2 m/s, m_eff 0.19 kg → < 0.5 J | C0/C1: scrape, rocks back, flies on |
| Landing-gear failure | gear force > max_force (E1: 67 N per Stik main) | C2: leg breaks off, belly slides, prop strike if the nose drops |
| Hard landing | belly or gear, v_n 2.5–4 m/s, m_eff ≈ m → 9–23 J | C2: gear gone, prop broken, airframe intact |
| Medium crash (tip stall at 10 m) | tip first at v_n ≈ 8 m/s → 6 J, then the cartwheel brings spinner and wing root | C3: wing panel off, prop broken, fuselage intact |
| High-energy turbine-jet impact | Avanti nose-in at 40 m/s, m_eff ≈ m → ≈ 9.4 kJ | C4: shell shatters, wing panels off, turbine stopped by the ECU, kerosene fire only if a tank ruptured and fuel remains |

## Structure data (proposal, optional section of `openrc-aircraft v1`)

```json
"structure": {
  "sections": [
    { "id": "wing_left", "parent": "fuselage_center", "material": "balsa_built_up",
      "inventory": ["wing incl. ailerons"], "inventory_share": 0.5,
      "hull_points": ["wing_tip_left_le", "wing_tip_left_te"],
      "joint": { "position": {"value": [0.15, -0.05, 0.05], "unit": "m", "kind": "estimated", "source": "…"},
                 "absorb_energy": {"value": 12, "unit": "J", "kind": "estimated", "source": "doc 03 …"},
                 "mode": "wing_bolts_shear" } }
  ],
  "surface_factor": { "runway": 1.0, "mown": 1.3, "rough": 1.5 }
}
```

- `id`s are the component ids that DATA-8's v2 component tree adopts, so nothing is renamed later.
- `inventory` names reuse the existing inventory item names. The loader refuses an item claimed twice or an unknown name. Generated aircraft (Extra, P-51, Avanti) get this section from their generators, never by hand.
- `absorb_energy` is the energy a joint or section takes before it fails. Each value carries a kind; nearly all start as `estimated`. Doc [03](03-rc-construction-crash-physics.md) supplies the ranges, and the owner's judgement is the first validation.
- `surface_factor` (estimated) scales the absorbed energy: soft ground lengthens the stopping distance and lowers the peak force. It is a single number per surface, replaceable by measurement.
- A **durability multiplier** (a setting: realistic 1.0, forgiving > 1) scales every `absorb_energy` and is written in the trace header. It never changes the data file.

## The resolver (pure, deterministic)

```
resolve(event, structure, durability) -> { class, broken: [section ids], absorbed_J, impulse }
  E  = event.e_normal
  s  = section owning event.component
  while s:
      cap = s.joint.absorb_energy · durability · surface_factor[event.surface]
      if E <= cap: absorb E; stop                  # C0/C1/C2 depending on s and E/cap
      break s; E -= cap; s = s.parent              # the load path carries the rest inward
  class = C3 if a "primary" section broke (wing root, fuselage) else C2; C4 if E_left > k·e_total
```

- **Post-impact state (deterministic):** a normal impulse J_n = (1 + e)·m_eff·v_n at the point (e ≈ 0.1, estimated), plus a friction impulse limited by μ·J_n. Then Δv = J/m and Δω = I⁻¹(r × J) for the remaining body. This is the state that the wreck handoff starts from, so the first tumble is decided by the simulation.
- **Detached sections** keep the rigid-body velocity at their own CG (v + ω × r_s) and their own share of ω. The struck section also takes its share of the impulse.
- **Secondary impacts** (wreck and debris, Godot physics) call the same resolver with an event built from Godot's contact impulse: e_normal ≈ J²/(2·m_eff). The rules are the same, but this path is presentation only.
- **In-flight structural failure** (over-g wing fold, flutter) is a later step. It uses the same sections with a load-factor limit per joint, never a separate system.

## Damage back into the flight (C2)

| Damage | Simulation change | Mechanism |
| --- | --- | --- |
| Prop broken | Thrust factor → 0 (or a fraction for one lost blade), rpm free to rise (G2) or stop (prop strike at low rpm) | E3d2 event; propulsion factor; G2d engine states |
| Gear leg gone | Contact removed from the gear list; the belly hull point takes the load | E1 list, E3d1 hull contacts |
| Wing tip or outer panel lost | Outer strips removed; mass, CG and inertia recomputed from the inventory share | D11d strips; `inertia_about` |
| Stab half, elevator or rudder lost | Its local surface removed or its deflection frozen or free | D9-R1 local tail elements |
| Canopy, hatch or cowl lost | ΔCD0 (estimated) and a small mass change | aero drag term; inventory |
| Servo or linkage failure | The surface floats at 0 or sticks at its last position | servo stage in `pre_step` |
| Engine stopped | No thrust or torque; windmill drag after G1d | `engine_running`; G2d |

Rules:
- A change is applied in `pre_step` at the tick after the event. The state is re-referenced to the new CG (p += R·Δcg, v += ω × Δcg, ω unchanged), and the trim and the goldens are untouched while nothing is damaged.
- Damage lives in a session-side configuration until H8. A replay recomputes it from the same inputs, and the trace records the event rows for analysis.

## The wreck handoff (C3/C4)

1. The simulation stops at the event tick and publishes the post-impact state (position, attitude, v, ω), the broken sections and their velocities.
2. Presentation turns a hidden copy of the airplane, built at flight start, into one Godot body per remaining group of attached sections (`RigidBody3D` in GodotPhysics3D, mass and inertia from the inventory, box shapes, CCD on), plus one body per detached section ([02](02-godot-destruction-techniques.md)). Each body gets `linear_velocity = v + ω × r` and `angular_velocity = ω`.
3. Ground: a static plane or the L12 heightmap collider; trees: L14 capsules as static colliders. The wreck slides, bounces and settles. Secondary contacts can break more joints through the same resolver.
4. Pieces stay where they fall until restart (like a real field), up to a body budget; the oldest small pieces sleep and freeze first.
5. The engine sound dies with the rpm (glow: a stutter to silence; turbine: spool-down from its schedule). A proper stop replaces today's `stream_paused` freeze.

## Determinism and tests

| Rule | Proof |
| --- | --- |
| No impact → no change | Goldens and `--trace` rows byte-identical after every CR step |
| Events are pure functions of (state, previous state, data) | Hand-computed events for set states (tip, nose-in, belly, knife-edge), crossing fraction exact for a linear descent |
| m_eff and e_normal | Unit test against `research/crash-damage/cr-00/results.txt` to 1e-9 |
| Resolver | The five-situation table as a scenario test: distinct classes; mutations (ignore direction; use total mass instead of m_eff; skip the cascade) each fail one row |
| Damage feedback | A lost-tip roll moment equals the strip removal in `linearize.gd` (ROADMAP E7b); mass properties after loss equal the inventory without that item to 1e-12 |
| Presentation | Captures at fixed simulation times after a scripted crash (`capture.sh`); presentation clocks owned as in SM-02; frame times on the owner's machine |

## Performance budget (proposal, measured at each step)

| Item | Budget | Note |
| --- | --- | --- |
| Per-tick impact check in flight | ≤ 5 µs/tick | Same loop as today's `touches_ground` plus a sign test; the event is computed only on a crossing |
| Resolver | ≤ 1 ms per event | Runs on events only |
| Damage in the loads | 0 µs without damage | A per-strip factor that is exactly 1.0 must not add work: skip when undamaged |
| Wreck and debris bodies | ≤ 24 active bodies, ≤ 2 ms/frame physics on the owner's machine | Godot physics also ticks at 240 Hz: 3–5 µs per active body per tick on the VM ([02](02-godot-destruction-techniques.md)); the simulation is stopped after C3, so its budget is free |
| Particles per crash | ≤ 2 emitters active, shared with smoke | SM-00 decides the backend |
| Audio | ≤ 8 crash voices, ≤ 2 MB of compressed samples per material set | Doc [04](04-audio-presentation-feel.md) |

## Open questions for the owner

1. Default durability: realistic (1.0) or forgiving? (Plan review #4, decision 10.)
2. Is a prop strike at idle a crash, or "engine stopped, keep rolling"?
3. After a structural crash: automatic restart after the wreck settles (today: 1.5 s), or wait for a key with the crash report and replay?
4. Fire on turbine crashes: on by default when the physics says so, or opt-in?
5. Do wreck pieces stay until restart (realistic field) or fade?
