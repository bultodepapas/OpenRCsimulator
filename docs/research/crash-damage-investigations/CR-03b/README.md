# CR-03b / CR-02b — Surface- and material-aware crash effects and sound

2026-10-13 · **Status:** implemented; presentation only, values are authored estimates. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.3. Builds on [CR-03a/CR-22a effects](../CR-22a/README.md) and [CR-02a audio](../CR-02a/README.md).

## What changed

[effects.gd](../../../../app/render/crash/effects.gd) — the effect decisions are pure helpers:

- **Dust** (`dust_profile`). The colour comes from the material: cut turf on grass, soil on rough or dirt, bark from a trunk, leaves from foliage. Runway, asphalt, concrete and structures throw none. It is thrown forward along the slide in a 30° cone, where it was an 82° spherical burst. Its size and speed follow severity. Soft-contact touches ([E3d1](../E3d1/README.md)) use the same rule.
- **Sparks** (`sparks_for`) appear only on a hard surface, from C2 up, when metal is involved: an engine or propeller part sliding at ≥ 10 m/s, or a hot turbine casing at C3+. Before, every C3 on paving sparked, wood and foam included.
- **Chips** (`splinter_count`):
  - Counts: none below C2, 8–16 at C2 (the struck part), and a wreck's worth at C3/C4 scaled by severity, at most 160.
  - Motion: they carry a quarter of the slide forward with a narrow spread and low lift, where before they were a random 2–8 m/s fountain.
  - Colour (`chip_color`): taken from the airframe's own materials. [director.gd](../../../../app/render/crash/director.gd) `airframe_colors()` samples up to six albedo colours, most used first, skipping dark or transparent hardware below a luminance of 0.12. A hot turbine adds dark casing chips.

[crash_audio.gd](../../../../app/render/crash/crash_audio.gd) `layers_for()` is a pure ladder; existing gains and pitches are kept.

| Class | Layers |
| --- | --- |
| C0 | surface thud |
| C1 | thud and scrape tail (no crack, no engine cut) |
| C2 | light crack, thud, lighter debris, scrape; engine cut only for a propeller or engine hit |
| C3/C4 | heavy crack, thud, tear, debris, scrape, engine cut or turbine rundown |

[severity.gd](../../../../app/render/crash/severity.gd) reports `tangential_speed_mps` for the spark rule.

## Evidence

- [test_crash_presentation_ladder.gd](../../../../app/tests/test_crash_presentation_ladder.gd): **39 checks**.
  - The dust and spark rules per surface and part, and the chip counts.
  - A real `Effects` instance: grass dust leans along the slide. Each chip carries 4.90 m/s along a 20 m/s slide, with 0.76 m/s sideways and 1.83 m/s lift. A runway wing hit throws no dust or sparks, and C0 throws nothing.
  - The audio ladder per class and part, gain growth and bounds.
  - Chip colours for all five catalog aircraft.
- **Unchanged suites:** `test_crash_effects` (57), `test_crash_audio` (12), `test_crash_integration` (95), `test_soft_contact_feedback` (10).
- [Mutations](../../../../research/crash-damage/cr-03b/mutations.log): **9/9 killed** — spherical dust, dust on paving, the old spark rule, the old chip fountain, chips below C2, palette ignored, crack at every class, engine cut on any C2, dark hardware colours kept. The first run let the old fountain survive; the check now bounds per-chip spread and lift.

## Limits

- Construction-specific chip shapes (balsa sliver, fibreglass shard, foam crumb) need a construction field in the aircraft data; every chip is still one box mesh.
- Headless rendering does not store MultiMesh colours, so the test checks the colour `start()` assigns, not a rendered pixel.
- Shader-based finishes contribute no sampled colour.
- Native mixes and rendered captures on the owner's Windows host remain to be recorded (CR-22c budget pass).
