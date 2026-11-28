# NK-6u — the tick's substep count in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick main-thread cost](../../../plans/optimization-priorities.md).

## Why

After [NK-6t](../NK-6t/README.md), the native tick integrator still called one GDScript callback every tick before
its RK4 pieces: `FlightSession._substeps_joint` (or `_substeps`), which decides how many pieces the tick takes. For
it, the kernel built the stage dictionary, and GDScript then:
- validated the stage context;
- posed the landing gear for `Ground.substeps`;
- read half a dozen capability getters for the shaft refinement near the engine's stop.

Probes on `Simulation.step` put the callback at 17–19 µs per tick on the Corsair and P-51 and 10–12 µs on the glow
Stik 61FX, out of 138–143 µs.

## Change

- `FlightSession.native_substep_plan()` sits next to `_substeps_with_context`, which stays the specification. It
  returns the inputs only the guarded configuration decides:
  - the battery and step-policy short-circuit;
  - the gear's substeps and reach, and the retractable gear's aux slot;
  - the terrain's maximum relief;
  - the shaft refinement's base conditions and rotor index;
  - the constants.

  The per-tick configuration guard refuses a tick after any change to them, and `native_stage.gd` hands the plan to
  the kernel at every installation. Hook: `FlightSession.native_substeps_enabled`, read at installation: set it
  before `setup`.
- `nk_substeps.hpp` computes the count from the plan, the tick's body, continuous values and aux, and the joint
  stage's preview, in GDScript's operation order. `integrate_tick` uses it when the model's callback is the
  installed session's own `_substeps_joint` or `_substeps` and no RC-track overlay is set. Each tick the kernel
  checks both and reads the overlay itself.
- The callback still decides two kinds of tick: a shaft refinement that needs the power latch (a coupled engine
  without liquid fuel), and one without a finite preview rate, where GDScript evaluates the coupled response.
- `tick_stats` reports `substep_answers` and `substep_refined`. The test probe is `stage_substep_probe`.

## Evidence

- `app/tests/test_native_substeps.gd` covers the Corsair, the P-51, the glow Stik 61FX and the electric Ugly
  Stik 60, 20 checks in all:
  - **Random states.** 4,000 random bodies, near and above the ground, take random speeds and attitudes. Rotor
    speeds run from zero through the stop to full power, and the gear aux is valid or invalid. Half carry the
    joint stage's preview. Wherever the kernel answers, its count equals the callback given the same stage
    dictionary. That is 2,500 of 4,000 on the warbirds, including 336–391 refined counts of 2 and 3, and all
    4,000 on the Stiks.
  - **Ground branch.** No stock gear declares more than one contact substep. A synthetic 4-substep plan matches
    `Ground.substeps` on 3,000 bodies under each aircraft's own retractable-aux rule.
  - **Flights.** Two native sessions per aircraft, one leaving every count to the callbacks, keep identical
    checkpoints for 2,400 ticks: default start, power off and nose down, engine stopped halfway. The kernel
    answered every tick.
- 57 suites pass on the installed binary: every `test_native_*` script and the ground, contact, event, interval,
  shaft, electric and glow lifecycle, checkpoint and session suites that exercise substeps.
- All nineteen installer gates pass for binary `c57f77f50eefeaa1f13543ae4a10aad193d5329dfbcce108a4b832c1b42b30df`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T065727105198Z.json` `c307b30c57ad14699aaecfb3463a417ddab7f170b99825eae1da94ba31385bec`
  - `stage_mutant-20261128T065753632251Z.json` `1cb3f979b136afe9de4e2662cc8a6ad7eca7025a88015de374f549724368060b`
  - `trajectory-20261128T065819567903Z.json` `8dd48b8965af85ed5d46289e19355a110aa7188bcb5d6955b3bf1fd6d3c6974c`
  - `legacy-ground-20261128T070156233453Z.json` `351032d2ae4d13351d566945e77b447bcf83f0552608b918a3e2cbe2d04bf733`

## Gain

Headless, native backend, paired sessions with the hook on and off, 12 interleaved blocks of 150 ticks, two runs.
Median per-tick `Simulation.step`:

| Aircraft | Before | After |
| --- | ---: | ---: |
| Corsair | 135 µs | 116 µs |
| P-51 | 135–136 µs | 116–117 µs |
| Glow Stik 61FX | 134–136 µs | 126–130 µs |
| Ugly Stik 60 (electric) | 67 µs | 59 µs |

Live app, 1920×1080, Corsair airborne on the club field, native backend. Two flights, with the kernel's plan cleared
and rebound in interleaved blocks of 60 ticks: median `Simulation.step` 273–274 → 250–255 µs.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- Malformed retractable gear: if the gear lacked its retraction path or contacts, the callback would raise a script
  error, while the kernel still answers a count. The `openrc-aircraft v2` validator refuses such gear before flight.
- Independent review: no exactness bug found. The plan's inputs are guarded, the branches and operation order match,
  the skipped callback has no observable side effects, and no plan can outlive its installation or reach another
  session.
