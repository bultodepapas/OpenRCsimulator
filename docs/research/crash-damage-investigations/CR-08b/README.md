# CR-08b — Proportional, size-consistent crash grading

2026-10-13 · **Status:** implemented; uncalibrated. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.1. **Replaces** the CR-08a class bins and tangential term; the rest of [CR-08a](../CR-08a/severity.md) (validation, snapshot adapter, accumulation) still applies.

## What changed

[severity.gd](../../../../app/render/crash/severity.gd) now grades three channels. All of them are presentation estimates.

| Channel | Quantity | Grade |
| --- | --- | --- |
| Normal (breakage) | E = transfer × ½ m_eff v_n² at the struck point | ε = E / (m × durability); cuts **0.5 / 2.5 / 25 / 150 J/kg** for C0…C4 |
| Slapdown | (½ m v_cg,n² − ½ m_eff v_n²) × transfer, ≥ 0 | same cuts. This is what the CG still carries into the surface after a plastic first contact (the nose stops, the belly slams). It is an upper bound with body rates ignored. |
| Abrasion (sliding) | friction work μ (m_eff v_n) v_t, at most ½ m_eff v_t², per kg | ≥ 1 J/kg gives **C1** at most. Sliding never breaks sections. |

The class is the worst of the three. `severity` (used for dust, audio gain and component exposure) is the worse of ε and slapdown divided by 150 J/kg. Durability is an argument, default 1.0. The data field arrives with CR-01d (decision D1).

[effective_mass.gd](../../../../app/physics/effective_mass.gd) is the shared helper: m_eff = 1 / (1/m + (r×n)ᵀ I⁻¹ (r×n)). It uses the same formula as `SceneryCollision._event_at`, and a test asserts the two agree to 1e-12. [director.gd](../../../../app/render/crash/director.gd) passes the following:

- **Ground hull contacts:** effective mass at the struck hull point, and the CG's down velocity for the slapdown.
- **Scenery contacts:** the whole mass plus their swept effective mass. Before, the effective mass was passed in place of the whole mass.
- **Gear-limit contacts:** no point is known, so they keep the whole mass, and `mass_basis` says so.

The C0 card now reads "Touch, no damage" (decision D2).

Side effect, intended: the report now carries `normal_energy_j`. The wreck already preferred that key for its C3/C4 scatter budget ([wreck.gd](../../../../app/render/crash/wreck.gd) `_scatter_energy_budget`). Breakup scatter now follows the struck point's energy instead of whole-mass CG energy. The 12 % / 600 J caps are unchanged.

## Evidence

**Fleet grades.** [grade_fleet.gd](../../../../research/crash-damage/cr-08b/grade_fleet.gd) loads every flyable aircraft and picks the first-contact hull point in five standard attitudes. It grades each case with the CR-08a estimator and the CR-08b estimator. Results are in [fleet-grades.md](../../../../research/crash-damage/cr-08b/fleet-grades.md). Summary:

| Scenario | CR-08a (Stik / Extra / P-51 / Avanti) | CR-08b |
| --- | --- | --- |
| Banked 45° touch, sink 1 m/s | C2 / C2 / C3 / C3 | C0 for all |
| Belly slide, sink 0.5 m/s, 20 m/s | C3 / C3 / C3 / C3 | C1 / C0 / C1 / C1 |
| 45° dive, 20 m/s | C3 for all | C3 for all (Avanti through slapdown) |
| Vertical nose-in, 20 m/s | C3 / C3 / C4 / C3 | C4 for all |

The "flat hard landing" rows use hull points only. Wheels are not hull points, so on gear aircraft the first contact is a wingtip or the prop, not the gear.

**Tests.**

- [test_crash_proportional.gd](../../../../app/tests/test_crash_proportional.gd): **49 checks**. They cover the plan's eight example cases, size invariance (Stik and P-51 grade identically at the same nose-in speed), slapdown, the abrasion cap, durability, input guards, exact cut boundaries, analytic effective-mass cases and scenery parity.
- [test_crash_severity.gd](../../../../app/tests/test_crash_severity.gd): 44 checks. The joule-bin fixture became J/kg, and the alias check now compares friction work.

The existing crash, wreck, effects, audio, pose, snapshot, integration and landscape-collision suites pass unchanged.

**Mutations.** [mutations.log](../../../../research/crash-damage/cr-08b/mutations.log): nine deliberate mutations, applied to a disposable copy of `app/`, were all killed. They were: whole mass, absolute joules, sliding counted as normal energy, uncapped abrasion, no slapdown, a slapdown that ignores the first contact, durability ignored, a missing rotational term, and an unrotated normal.

Healthy flight is untouched. The estimator runs only after a crash, and `test_crash_integration` keeps its 100-tick identical-checkpoint check for all four aircraft.

## Limits

- The cuts, transfer factors and friction coefficients are not calibrated. They separate the plan's example cases. CR-07 evidence is still required before any of them counts as strength.
- Body rates are ignored by the slapdown bound. A spinning airplane can carry rotational energy into the second contact.
- The slapdown is charged to the struck component's `component_damage`, although a different part takes it. CR-09b should feed the wreck's real secondary contacts through `accumulate_damage` instead.
- Hull points are sparse (8–14 per aircraft). The struck "point" is the nearest hull point, not the true first contact.

## Merge verification (2026-10-13)

Integrated `487b513` (local smoke, scenery destruction and overlay fixes) with `9cc60a6` (CR-08b and the camera proposal). Both decision sets and the CR-17a evidence remain linked. On the fresh LF WSL checkout with pinned Godot 4.7.2, import and the five changed/new application scripts parse; the transcendental guard passes. All 13 focused tests pass: crash, crash audio/effects/integration/pose/proportional/severity/snapshot/wreck, scenery damage session/runtime, engine smoke and overlay manager. CR-08b reports 49 checks, severity 44, overlays 64, with no failures.

The unchanged CR-17a capture harness renders before/impact/after/reset under software OpenGL with successful exit and no script/shader errors; local impact/aftermath views were inspected. These checks verify integration, not physical strength, hardware timing or pilot acceptance. The five pre-existing full-suite failures documented in [HUD integration](../../flight-overlays/HUD-01-10/README.md#hud-030611-merge-integration-2026-10-13) remain outside this change.
