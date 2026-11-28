# Native fixed-wing stage and bridge

Audited production source `8d4169f8febfd7d78a028eaa817414217a54f24b`. The two opportunities below concern separate operations. One is at the GDScript-to-C++ tick-context boundary. The other is inside a single C++ force evaluation. Both experiments used GCC 14.2.0 on Linux x86-64, C++17, `-O2 -fno-fast-math -ffp-contract=off`. Neither exercised an installed GDExtension, a full flight, a recorded replay, or rendered frames. The qualified Linux compiler is GCC 13.3.

## Retractable aircraft copy the static field and lake at each tick context

**P3 performance opportunity, reproduced at the C++ context-copy boundary.** Static ground data can be initialized once per successful stage preparation. Every qualifying context currently copies the surface table, shoreline, bank, and bed-profile arrays; it also copies the base wheel-contact array twice. The repeated copies occur even with the gear held fully down.

The fixed-wing session primes the native context at installation (`app/sim/flight_session.gd:825–835`). At each ordinary pre-step it checks the configuration guard, obtains the next aux, and sets one context when the aux has the expected size (`app/sim/flight_session.gd:6365–6391`, `app/sim/native_stage.gd:529–545`). Liquid and prescribed adapters forward to the common setter (`app/sim/native/liquid_stage_adapter.gd:68`, `app/sim/native/prescribed_stage_adapter.gd:46`). This is one potential copy per tick context, independent of the number of RK4 stage evaluations. A later tick refusal can still occur after the context was set.

The setter validates retraction inputs, assigns the entire prepared ground context, then calls `retractable_pose` (`research/native-kernel/src/nk_kernel.cpp:2933–2951`). That function independently copies the base gear for both full-down and valid partial positions (`research/native-kernel/src/nk_retractable.hpp:48–65`). `GroundContext` owns the gear, surface table, and lake by value (`nk_wheels.hpp:43–48`). Its terrain data contains five independent vectors (`nk_terrain.hpp:35–47`). Successful stage preparation already has an ownership boundary that resets the previous tick context and installs a newly decoded model (`nk_kernel.cpp:2903–2915`).

The probe used production ground, wheel and retraction types, the stock **dimensions**, and synthetic coefficient, polygon, and pose values. The Corsair, P-51, and Avanti records each have three contacts and retractable gear. The default field produces 24 binary64 values (three six-word rectangles plus the catch-all; `app/physics/ground_surfaces.gd:76–95`). The stock lake contributes another 86 binary64 values (40 shoreline, 40 bank, three inset and three depth; `app/data/fields/lake.json`, `research/native-kernel/src/nk_kernel.cpp:537–562`). The control initialized the static parts once per preparation and retained the existing pose function at every context. The wrappers counted calls to the emitted `memcpy` and `memmove` symbols only when both source pointer and size identified one of these six vectors.

| Warm accepted retractable context | Current copied vector bytes | Candidate copied vector bytes | Difference |
| --- | ---: | ---: | ---: |
| Default-sized field, no lake | 864 | 336 | 528 |
| Default-sized field and lake | 1,552 | 336 | 1,216 |

Across 1,440 paired calls in three prepared configurations, the experiment compared refusal status, contact bytes, static vectors, sampled lake metadata, and a downstream wheel-compression query. There were 600 accepted retractable calls, 120 invalid-fraction refusals, and 720 fixed-gear control calls. The control and refusal groups generated no counted copies. In each retractable configuration, 200 accepted calls copied 134,400 contact bytes in the original and 67,200 in the candidate. The terrain contribution fell from 38,400 bytes to zero without the lake and from 176,000 to zero with the lake. These are copied payload bytes, independent of allocator capacity and cache behavior. They do not measure service time or memory usage.

**Proposed repair and acceptance.** Initialize the posed context's immutable surface/lake data and validity flag after successful preparation for a retractable model. Leave location, stiffness, steering, and travel updates in the existing per-tick pose function. Keep the current input validation and ready-state transitions. Qualify the actual GDExtension binding with exact force, compression, wheel-audio, contact and accepted-state parity for all three stock aircraft. Exercise full, partial, and fully retracted travel, bad extension/target, native configuration change, stage replacement with a different field/lake, restore and rollback. Compare warm tick time on qualified hardware if prioritizing this by cost.

## The spatial propeller stage repeats the same hub lookup for thrust, wake and transport

**P3 performance opportunity, measured native extension of earlier research.** A successfully evaluated, spatial, non-glow Ct/Cp propeller with wake enabled produces its thrust/torque pair at the propeller hub. The propulsion loads consume the pair. The native wake then asks for the same pair again, with identical hub velocity, model, RPM and density (`research/native-kernel/src/nk_stage.hpp:316–319,329–348`). If transported wash is active, its target can ask a third time (`nk_stage.hpp:394–408`). For a turning propeller the helper looks up both coefficient tables and takes two powers of diameter (`nk_prop.hpp:105–117`).

The historical E0b6p decoder report proposed sharing a stage-local result in Dynamics (`docs/research/propwash/E0b6p/decoder/README.md:38–40`; see also `docs/research/simulation-state/H14/README.md:36`). The current GDScript load path already supplies explicit-hub thrust and torque to the wake (`app/physics/dynamics.gd:109–133`). This experiment establishes a remaining difference in the C++ port and quantifies its additional transported-wash call.

A disposable header edit carries the existing value across these exact branches. All 480 pairs passed through the full `stage_evaluate` numerical header. The fixture has six wing stations, a synthetic Ct/Cp propeller and a horizontal wake piece. It varies spatial versus uniform weather, no/quasistatic/transported wake, untilted versus tilted shaft, reversed through positive body speed, nonzero body rates, five RPM values including 0, 0.5 and the 1 RPM cutoff, plus an out-of-domain spatial position.

| Group | Stage calls | Emitted pow calls, original | Emitted pow calls, candidate |
| --- | ---: | ---: | ---: |
| Eligible quasistatic wake | 24 | 348 | 300 |
| Eligible transported wake | 24 | 396 | 300 |
| Other combinations, including spatial refusals and stopped propeller | 432 | 5,220 | 5,220 |

All 4,480 binary64 output words for loads, rotor momentum and any wash derivatives matched. Shaped/finite results, returned dimensions, preview/body-derivative flags, errno and sampled floating-point exception masks matched row for row. All 48 eligible stages returned finite outputs. A mutation that supplies a zero pair only to wake and transport, while preserving the correct propulsion loads, changed output words in 16 of 24 quasistatic cases and 22 of 24 transported cases. The 432 controls retained their output words. These tests use a directly constructed numerical model rather than an aircraft admitted through the decoder. The saving is two emitted power calls per eligible turning stage for quasistatic wash and four for transported wash on this compiler.

**Proposed repair and acceptance.** Carry the previously computed pair only after the evaluated Ct/Cp branch has produced it. For transport, require successful explicit spatial sampling as well. Keep uniform datum inflow, invalid spatial flow, glow blade-element output, turbine dispatch and the separate shaft derivative's `prop_torque` arithmetic (`nk_prop.hpp:120–130`). The storage lifetime should end with the current RK stage. Exercise wake-on and wake-off admitted propellers with both source conventions, actual nonuniform wind, stalled/stopped motion, invalid samples and a large transported state. Run the pinned platform's component oracles, exact stage and replay comparisons, native selection and packaging gates, then measure tick and frame distributions on target hardware.

## Prior-art and exclusion notes

- The first round's discarded analytic wing-polar work, disposable derivative-vector copy, diagnostic strip norm, and late-refusal freezing concern belong to that round. Neither candidate above uses those sites.
- A33 already identified the overwritten uniform-air evaluation before the spatial branch (`external Audits/cpu-mathematical-optimization-2026-11-09.md:270–276`). It was excluded.
- The stock retractable context duplication did not surface in the consolidated or completed audit ledger, the preceding native audit, or the NK-5e documentation. NK-5e describes the lifetime of the posed ground used by observers (`docs/research/native-kernel/NK-5e/README.md:17`).
- NK-5h-R1 already introduced a per-root path budget and a full-watch fallback (`nk_guard_plan.hpp:84–111`, `nk_configuration_guard.hpp:345–351`, `nk_weather_guard.hpp:258–272`). The previous deeply shared-configuration finding was excluded. This review found no demonstrated new admission regression from that fix. Its runtime behavior on this SHA was outside this component run.

The two reproduction drivers take a checkout path and build only in a temporary directory. The accompanying JSON records the compiler, flags, comparison counts, and component counters.
