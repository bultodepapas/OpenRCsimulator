# Fixed-wing audit corrections, 2026-11-08

Owners: shared aerodynamics/propulsion, EX-05/14 and F4U-07. Baseline: `8ebb252acc341a5a1fc047e6bb931fabdb17b148`, Godot `4.8.beta2.official.cafc17a19`, Windows x86-64. The unrelated concurrent UI/localization work is excluded from these findings. The [audit queue](../../../external%20Audits/CONSOLIDATED-AUDITS.md) retains unrelated implementation, research and qualification work.

## Corrections and contracts

- **E300-01 / CF-01:** generators separate reference-CG rotational-inflow arms from ARP moment arms. The runtime transfers each force to the current CG once. Fin-only static roll and complete signed rate-force/moment pairs have independent wrench invariants; changing every CG arm to an ARP arm is not the repair.
- **E300-02:** one installation-to-section adapter supplies the installed optional zero-lift angle to the Extra crossflow derivation and the calibration helper. Independent recomputation checks every generated row, including omitted/zero camber controls. This is consistency with the existing surrogate, not independent propeller calibration.
- **CF-02:** extrapolation starts at the final coefficient actually stored. A floor cannot raise a below-floor final knot discontinuously. Other interpolation knots and existing force/refusal paths retain their contracts.
- **CF-06:** the incremental flap-lift couple uses each station's actual chordwise flow projection in its section plane. Section and drag couples remain separate. Reverse, rotating, spatial and shifted-CG controls compare against independently reconstructed force cross products.
- **E300-08:** startup and F5 synchronize propeller scale from the accepted installation. Repeated/rejected reloads retain camera zoom/interpolation. Diameter changes refresh dependent extents/shadow geometry; a failed display synchronization owns a named session hold until recovery. Physical commit is not rolled back or mislabeled because presentation failed.

Original reports: [Extra](../../../external%20Audits/extra-300-physics-optimization-audit-2026-11-06.md), [Corsair](../../../external%20Audits/f4u-corsair-physics-optimization-audit-84f4657.md), [flap geometry](../../../external%20Audits/f4u-corsair-collision-flaps-presentation-audit-3751e35.md), [F5](../../../external%20Audits/extra-300-round2-trim-reload-audit-8e5f2f0.md).

## Reproduction and numerical evidence

Fresh checked-runner artifacts are retained locally under `tmp/audit-generators-20261108`, `tmp/audit-corsair-runtime-20261108` and `tmp/audit-reload-20261108`. These ignored paths are regeneration/evidence locations, not committed artifact links. The source tests and owning generators are the reproducible checks.

| Check | Observed scope |
| --- | --- |
| `test_generator_rate_datums.gd` | 218 checks pass: both aircraft, signed/mixed rates, nonzero angles, fuel-derived reference/live CG and both empirical/local branch joins. |
| `test_reload_geometry.gd` | 97 checks pass: real Main/F5 key dispatch, accepted frozen candidates, no-op/repeat, both diameter directions, rejected installation mismatch, physical disc/solid/blur, CG, camera and display-failure recovery. The frozen candidates are prevalidated; this alone does not establish on-disk reload-validator wiring. |
| D11g derivation and leaf-only updater | Stik `CLq=2.357`, `Cmq=-8.082`, `Cnr=-0.136` remain exactly unchanged. Only the three generated provenance law names change from v2 to v3; historical reports remain unchanged. |

The thrust witness reproduced an approximately **1.018890630 N** endpoint jump before the fix and no displayed jump after it. Component numerical consistency does not establish encounter frequency or physical aircraft accuracy.

## Identity and remaining gates

`Aero.LOADS_LAW` advances to `section-plane-source-weighted-wake-velocity-v3`; coefficient lookup has its own `piecewise-linear-table-aware-floor-v1` identity. Checkpoint admission must reject incompatible old configurations. Trace inspection retains historical v2 support, while new D11g reports name the actual current law. Native mirrors and admission identities must describe the same equations; stale binaries/receipts cannot establish candidate-native qualification.

Both aircraft have retained baseline ORFLs with successful exact replay. Aircraft-data-only candidate replays use the same baseline tapes. The solver-law candidate intentionally refuses the incompatible historical checkpoint; that refusal is retained and is not a successful same-tape solver comparison. Original goldens are not rewritten.

Source-bound native/companion qualification, complete required CI, real-aircraft measurements and rendered/device acceptance remain separate gates. Headless transform checks do not qualify native 1080p appearance, motion/strikes or pilot handling. Private disk-fixture import attempts and any timed-out/incomplete checks are setup failures, not passes.
