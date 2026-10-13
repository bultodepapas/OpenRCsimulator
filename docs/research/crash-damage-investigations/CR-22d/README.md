# CR-22d — Ignition flash

2026-10-13 · **Status:** implemented; presentation estimate. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §8 rank 3. Gated by the [CR-22b](../CR-22b/README.md) fire outcomes.

## Behaviour

When a fuel fire starts (CR-22b), a short fireball comes first, before the sustained flames:
- kerosene, with a hot turbine and a ruptured tank;
- gasoline, in a destroyed airframe with a central hit and the engine running.

Glow fuel, LiPo flares and untagged aircraft never flash. This is the only "explosion" the simulator shows, and only where a fuel source, a rupture and an ignition source coincide.

**Size and duration.** They follow the Roberts (1981) fireball correlations, D = 5.8·M^(1/3) m and t = 0.45·M^(1/3) s, applied to an estimated 1 % of the declared fuel that is atomised. The duration is at least 0.35 s so the eye can see it, and the radius is at most 1.2 m.

| Aircraft | Atomised fuel | Radius |
| --- | ---: | ---: |
| Avanti / Ventage Jet (1.28 kg kerosene) | 12.8 g | 0.68 m |
| P-51 (0.37 kg gasoline) | 3.7 g | 0.45 m |

**How it looks.** [effects.gd](../../../../app/render/crash/effects.gd) uses a 12-particle additive fireball. It is drawn after the dust thrown at the same instant, with a white-yellow core fading to orange, plus an 8× light flash that decays over the flash duration. The vent emitter went from 108 to 96 particles, so the total stays 700.

**Ejecta.** The renders also exposed slow-falling ejecta: turf, soil and bark ejecta fell at only 0.6 m/s² and hung like green smoke. They now fall at 4 m/s²; leaves drift at 0.8 m/s².

## Evidence

- [test_crash_energy.gd](../../../../app/tests/test_crash_energy.gd): **42 checks** (9 new).
  - The flash happens for kerosene and gasoline only, at the Roberts radius, with the perceptible minimum duration.
  - It is never for glow fuel, a LiPo flare or cold kerosene.
  - On a real effects instance: a fireball at ignition, a light at least 6× brighter, then the flash ends while the fire burns on; reset clears it.
- **Renders** (xvfb + llvmpipe, [capture_flash.gd](../../../../research/crash-damage/cr-22d/capture_flash.gd)): [ignition](flash_ignition.png), [0.4 s](flash_0.4s.png), [2 s](flash_2s.png). The first renders showed the fireball covered by the turf dust and the turf hanging like smoke; both were fixed (draw order, colour, ejecta fall).
- **Unchanged suites:** effects (60), ladder (39), soft-contact feedback (10), integration (95), wreck (163).

## Limits

- The 1 % atomised share is an estimate.
- There is no ignition sound yet: the fire loop starts with the flames.
- The fireball is camera-facing sprites, not a volume.
