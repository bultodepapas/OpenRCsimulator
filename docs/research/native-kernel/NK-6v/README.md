# NK-6v — a clear contact step proved in one native call

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick main-thread cost](../../../plans/optimization-priorities.md).

## Why

Live flights cost far more per tick than bare headless benches. In the running app, with the Corsair airborne, a tick
took 280–380 µs; with the published observers disconnected, about 155–200 µs. A headless bench with the production
field closes the gap: the field's surfaces, its 6,139-proxy scenery world and the lake, with soft hull contacts and
cost observations on, as in the app. There the Corsair's tick was 150 µs against 116 µs bare.

The largest piece was the contact step the native integrator calls after each tick's integration:
`_resolve_mass_contact_step` for an aircraft whose fuel mass changes, `_resolve_collision_step` otherwise. Probes put
it at 47–51 µs per tick, high in the air included. On almost every tick it resolves nothing. Its native proofs
already decide that: the store checks (NK-6e, NK-6t), the scenery and lake reach (NK-5d), the state checks (NK-6q)
and the quiet hull terminal (NK-6h, NK-6i). GDScript only routes between them: it builds the mass sampler's closure,
reads the lake and probe reach, validates the sweep inputs, and allocates the sweep results.

## Change

- The kernel's `stage_contact_clear` composes those proofs in the reference's order. It answers 1, or 2 when the
  hull terminal was answered quiet. 0 means not proven.
- `NativeStage.clear_contact_step` binds it. As `contact_reach` does, it first follows the session's collision world
  by identity.
- `FlightSession._clear_contact_step` runs at the top of both contact steps.
  - Its conditions: inside the guarded tick, for this class, with soft hull contacts, no RC track, and every native
    check it composes enabled.
  - It decides each input as the reference does: which stores, a scenery world and its validity, a lake and the
    lake sweep's own inputs, and whether the terminal check applies.
  - On a proof it leaves exactly the bookkeeping of the reference's clear path:
    - pending contacts and scenery damage are cleared for the tick;
    - the accepted scenery and lake events are kept;
    - the pending ones are left null; without a lake, the lake event passes through.
  - It counts a quiet terminal as `_native_terminal_quiet` does, then returns the candidate.
  - Anything unproven runs the unchanged reference step.
- Hook: `FlightSession.native_clear_contact_enabled`. Diagnostic: `native_clear_contact_answers`.
- `_native_contact_reach` now reads its lake threshold from `_contact_lake_threshold()`, the same expression moved
  so both callers share it.

## Evidence

- `app/tests/test_native_clear_contact.gd` covers the production field, lake and scenery world with soft hull
  contacts, for the Corsair, the P-51, the glow Stik 61FX and FS64V, and the electric Stik 6S. The electric Stik
  takes the sampler-free `post_tick`. 31 checks pass:
  - **Random steps.** Each aircraft takes 3,000 random contact steps: airborne, low over the field, low over the
    lake bank, rolling, and tilted into the ground, with valid and broken fuel stores. One step in five carries in
    accepted scenery and lake events from an earlier tick. With the proof on and off, every field the step leaves
    is equal: the returned state, every pending and accepted event, the scenery damage, the contact flags, the
    quiet-terminal count and the crash record. Between 1,331 and 2,573 of each 3,000 were proved clear.
  - **Other configurations.** The Corsair, the glow Stik 61FX and the electric Stik repeat this without the lake,
    and again without lake or world; there 2,151–3,000 of 3,000 were proved clear.
  - **Flights.** A takeoff roll, a hard landing and a nose-over fly byte-identical with the proof on and off,
    contact events included, with the same count of quiet hull terminals.
- 93 suites pass on the installed binary: every `test_native_*` script and every suite that installs a scenery
  world or lake, flies soft hull contacts, or calls the contact steps or their reach proofs.
- Independent review found no exactness bug. It traced every branch of the clear path (lake or not, world or not,
  sampled or not, the terminal gate) and its bookkeeping. Its one test gap, no run without lake or world and no
  carried-in events, is closed above.
- All nineteen installer gates pass for binary `c9c6991e365fab5c1747afde91c55577c8179f8a6b0185211defad22e4d928de`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T073053399194Z.json` `137a660767f801210bbc92843025cd83aae0feccd9e9623d222dde7d92511f7d`
  - `stage_mutant-20261128T073119191934Z.json` `8b3e373596d39bc96dcc43945436a2f07c860801f0f5ec1a0fcc0d899ce8834d`
  - `trajectory-20261128T073144851755Z.json` `2eecf4bf2963410e4d84e0de46b325ba74a8c3216f84b83f5795f1eea8918e1a`
  - `legacy-ground-20261128T073525244562Z.json` `ce50bbedd7f9d9c59a8c12c3f5601f802e9ffec85b950a0316de4886139f0d17`

## Gain

Headless, native backend, on the production field with its surfaces, scenery world and lake, soft hull contacts and
cost observations. Paired sessions run with the hook on and off, in 8 interleaved blocks of 60 ticks, over two runs.
Median per-tick `Simulation.step`, with the hook off, then on:

| Aircraft | Airborne climb | Runway roll |
| --- | ---: | ---: |
| Corsair | 231 → 198 µs, 149 → 138 µs | 225–243 → 238–247 µs |
| Glow Stik 61FX | 242 → 219 µs, 165 → 152 µs | 314–317 → 287–303 µs |
| Electric Stik 6S | 101–102 → 99 µs | 162–249 → 156–244 µs |

The two runs differ by up to 80 µs on this workstation, so only the paired differences count: 11–33 µs per
airborne tick for the fuel aircraft. On a rolling warbird about half the ticks are not proven: its reach box meets
runway-side scenery, or a hull point is not quiet. Those ticks pay the proof and then the reference, so the roll
breaks even.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- No live-app A/B yet.
