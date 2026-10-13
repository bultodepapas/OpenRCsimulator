# CR-09d1 — Wreck section masses from the aircraft inventory

2026-10-13 · **Status:** implemented; presentation physics. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §8 rank 2. Surface friction (CR-09d2) and convex shapes (CR-09d3) remain.

## Problem

Wreck sections took fixed mass shares (core 42 %, each wing 15 %, engine 8 %…) whatever the airplane carried. With those shares, the intact Stik wreck's centre of mass sat **231.5 mm** from the airplane's real CG, so the wreck tumbled about the wrong point. A heavy motor and battery did not make the nose lead.

## What changed

- **Inventory boxes.** [director.gd](../../../../app/render/crash/director.gd) `inventory_box()` turns each inventory item into a model-frame box (mass, centre, size), with the same datum conversion as the CG, and hands the list to the wreck.
- **Distribution.** [wreck.gd](../../../../app/render/crash/wreck.gd) `_inventory_masses()` spreads each item's mass over the sections by per-axis box overlap with each **member's** own mesh box.
  - A nose leg and a main leg are separate boxes, not one block that swallows the tank and battery.
  - Each box is thickened to at least 6 cm per axis, so thin skins (stab, fin, wing) catch items placed to within the data's centimetre precision.
  - What no section holds stays with the core.
  - Every section keeps at least 15 g, taken from the core, so the total is conserved exactly.
- **Centre of mass.** Every body gets a custom centre of mass at its own mass moment. Without inventory data the fixed shares remain.
- **Stated property.** The data's virtual balancing masses (Stik 0.284 kg in the aft fuselage, Timber 0.25 kg at the nose) go where the data places them.

| Stik section (C4) | Wreck mass | Inventory items |
| --- | ---: | --- |
| engine | 0.71 kg | engine + muffler + mount 0.745 kg |
| propeller | 0.08 kg | propeller + spinner 0.071 kg |
| each wing half | 0.30 kg | wing + aileron servo 0.565 kg, split by overlap |
| gear | 0.15 kg | nose and main gear 0.195 kg |
| tails | 0.21 / 0.21 kg | stab 0.10, fin 0.055, plus part of the aft balancing mass |

## Evidence

- [test_crash_masses.gd](../../../../app/tests/test_crash_masses.gd): **27 checks**.
  - **Unit checks:** box overlap (half / full / point inside / outside), thin-skin regions, and the floor taken from the core.
  - **Stik and Timber:** the intact wreck weighs the aircraft, and its centre of mass is the aircraft CG to **0.0 mm** (fixed shares: 231.5 mm). A destroyed wreck conserves mass to 1e-6 kg. Wing halves are symmetric and carry real wing mass, the engine section carries the engine, the gear does not swallow the tank and battery, and reset restores automatic centres of mass. Without inventory, the fixed shares remain.
  - **Production:** a real crash through `main.tscn` hands all 20 Stik items to the wreck.
- [Mutations](../../../../research/crash-damage/cr-09d/mutations.log): **7/7 killed**. The first run left three survivors (overlap ignoring box size, floor creating mass, union box); the unit and gear checks were added for them.
- **Unchanged suites:** `test_crash_wreck` (163), breakup (27), sections (33), integration (95), prop-strike feedback (12), energy (33), effects (59), cause (29).

## Limits

- Overlap is between axis-aligned boxes, so swept or tapered parts are approximated.
- Item positions are the data's estimates.
- A C3 contact release moves the section's mass out of the core without moving the core's centre of mass.
- Collision is still one box per section (CR-09d3).
