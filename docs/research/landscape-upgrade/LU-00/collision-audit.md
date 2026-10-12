# LU-00 — Collision integration audit

Date: **2026-10-11**. **Status: research complete; implementation proceeds under LU-05.**

## Current contact boundary

`FlightSession._physics_process()` currently checks the committed aircraft state for hull points at or below the flat NED ground plane, then checks landing-gear travel limits. `ImpactSnapshot.hull_contact()` records the first penetrating hull point in data order; `HullCrossing.reconstruct()` estimates a crossing only after the ground detector has already fired. Neither is a scenery solver, and an obstacle entered and exited between tick boundaries is missed. `Simulation.stepped` fires synchronously after `previous`, `state` and `tick` are committed, so it is the narrow hook for a per-tick obstacle query that also covers direct `sim.step()` callers.

The state is float64 packed data: N/E/down position, body-FRD velocity, body-to-NED quaternion, and body angular rates. Aircraft hull points are local body coordinates. Scenery placement and field-light inputs use N/E metres and degree headings. Trees are positioned relative to `field.pilot`; scenery placements and light fixtures are already in field coordinates. Render-space `Vector3`/`Transform3D` data must not enter the simulation query.

## Existing field inventory

The default field defines 1,680 deterministic tree positions (480 near and 1,200 far). Each visual card has a deterministic species and 12–25 m height from `Treeline.identity()`. The field loader normalizes these positions but refuses `collides=true`.

`SceneryLoader` normalizes placement groups. The default layout has open-sided pit shelters, a pavilion and other buildings, 11 cars, vehicles and four parked RC aircraft (Stik, Extra, P-51D and Avanti). Placement coordinates and dimensions are already normalized, and the prefab/model catalogs provide metric bounding sizes. The scenery loader currently requires all groups to be visual-only. A pit shelter is explicitly a roof sheet with posts and open sides; treating its catalog envelope as a solid box would create false collisions through empty space.

`FieldLights` normalizes two 8 m floods, one lower flood and several stake rows. Flood positions provide N/E plus fixture height; stake rows provide N/E points and a height. These objects are rendered in a separate world path and currently have no simulation contacts.

## Recommended collision world and query

Compose an immutable, scalar-only obstacle inventory once from the validated field, normalized scenery and normalized lights. Keep the builder in `app/scenery/collision_world.gd`; keep all 64-bit motion, sweep and contact math in `app/sim/scenery_collision.gd`. A deterministic 32 m spatial grid is suitable for the 1,680 trees and local props. Stable IDs must be assigned before bin insertion, with earliest time of impact selected before a stable-ID/probe-index tie break.

Use small explicit proxies: tree trunk plus a bounded crown envelope; oriented boxes for ordinary buildings, cars/vehicles and each parked aircraft; capsules or thin boxes for lamp poles/stakes; and explicit post and roof proxies for the open pit shelters. The visual tree cards and several placement dimensions are estimates, so proxies describe a gameplay contact envelope, not surveyed geometry or source-backed structural properties. Exclude distant visual ridges unless a matching terrain sampler is added.

Sweep each float64 aircraft hull probe across `sim.previous` to `sim.state` on the committed tick. Use analytic segment tests for the static proxy primitives and subdivide the shortest-path attitude change with a documented geometric error bound. Return a typed event compatible with the current crash snapshot boundary: detected state/tick, crossing fraction and pose, body probe, point velocity, surface normal, stable obstacle ID/kind, response class, and effective-mass impact energy estimate. Do not feed Godot physics nodes or renderer coordinates into flight dynamics. Hard contacts can use the existing terminal crash/presentation path; no deformation or aircraft strength limit is currently supported.

## Reset and checkpoint constraints

`FlightSession.set_field()` stores a detached normalized field copy and builds ground surfaces. The new world should be injected separately after field/scenery/light normalization, before the session is added to the scene. Include the world's stable identity in the checkpoint configuration fingerprint so a checkpoint cannot replay against a different obstacle inventory. The initial implementation should keep obstacle proxies immutable and avoid persistent damage state; otherwise breakage and nonfatal contacts would need to be serialized and replayed. `reset()` must clear any contact latch/event while retaining the configured world. Tests should verify rejected checkpoint restores do not alter the running state.

## Required verification

- Segment passes through a thin obstacle while both endpoint samples are clear; a nearby miss stays clear.
- Translation and a large attitude change cross tree trunk/crown, building, open-shelter post/roof, car, flood/stake lamp and every parked-aircraft proxy.
- Stable earliest-hit selection under overlapping/tied proxies and repeated runs.
- Checkpoint identity rejects a changed world before changing simulation state; replay produces the same event; reset clears it and does not create a start contact.
- The ordinary flight path without an injected collision world retains existing trace, ground-contact and crash behavior.
- Measure the query separately from the 240 Hz physics tick against the LU-05 100 μs p95 target on the stated host; this is a software budget, not physical validation.

Limits: tree canopy dimensions, obstacle envelopes and object-specific response thresholds lack independent impact calibration. Reports may expose kinematics and energy estimates, but must not claim validated severity, breakage, or flexible-structure behavior.
