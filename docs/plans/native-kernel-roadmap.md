# Native kernel roadmap

Owner goal (2026-11-27/28): move the game's hot paths into the native kernel, robustly and as efficiently as
possible, batch by batch with measured returns. This plan records what remains, the lessons that shape the next
batches, and their order.

Ownership and evidence:
- The [native kernel README](../../research/native-kernel/README.md) owns the coverage list and each batch's evidence.
- [Optimization priorities](optimization-priorities.md) owns the measured frame costs (F1 per tick, F5b per frame).
- [STACK](../STACK.md#native-backend-policy) owns the backend policy.

## Ground rules that stay

- The GDScript reference remains the specification, the fallback and the replay backend. Each native answer has a
  hook to turn it off, and a parity test compares the whole consumer output with it on and off. Simulation keeps
  the commit, publication, checkpoint and rollback transaction ([AGENTS](../../AGENTS.md#native-development)).
- UI, orchestration and the simulation transaction stay in GDScript by design. "Everything native" means every hot
  path whose return justifies it. It does not mean every line.

## What remains

Costs were measured headless with the native backend and real timers on 2026-11-28 (Windows x86_64). A live
session costs more per tick, because observers, statistics and companions run there too.

### Per tick (four per frame at 60 FPS; about 140 µs per tick headless)

| Item | Cost per tick | Note |
| --- | --- | --- |
| Configuration and weather guards | 9 + 5 µs | Native, but bounded by engine property reads per root. Freezing more configuration roots would let identity checks replace watches. |
| Contact step preparation | 8.7 µs | GDScript mode bits recomputed from configuration that cannot change between installs. |
| Liquid tick context (P-51, Corsair) | 15.6 µs | Its argument building: deflections, the preview predicate and its tick fact. |
| Glow step plan (glow aircraft) | 16 µs | Recording events and finish terms rebuilt each tick. |
| Accepted-tick observers | 11–13 µs | Endpoint facts, compressions and cost support. |
| Simulation guards before the pre-step | 12 µs | Pinned kernel transaction: out of scope. |

### Per frame (flight audio after NK-7j–7m)

| Item | Cost per frame | Note |
| --- | --- | --- |
| `FlightAudio.snapshot()` | 36–65 µs | The glow keys wrapper costs about 14 µs on top of the kernel's 11; running state, atmosphere, result dictionary and listener 4–13 µs each. |
| Endpoint observations | 13–23 µs | The mechanical snapshot (11–15) and the airborne clear test (6–8). |
| Soundscape | 25–44 µs | Glow voice hand-over 21 µs (glow only), wildlife 6.5, fabric 4.5. |
| Glow voice worker | 119 µs per 256-frame block | NK-6m's per-sample engine trigonometry; byte-identical PCM keeps it. |

### Evidence gaps

- macOS has no parity run for any NK-6/7/8 batch.
- Linux: all nineteen gates passed locally at `d080ca630` (WSL, 2026-11-28); CI requalifies each push. The NK-7
  parity tests have not run on Linux locally.
- Live-app timings exist for NK-6u, NK-6v and NK-8b only.

## What we learned

- Presentation readers may use a native answer only for the endpoint they read, under the publication's own
  conditions; every refusal must reach the unchanged reference
  ([learning](../learnings/physics.md#native-answers-for-published-endpoints)).
- Receipts pin raw source bytes, and linkers stamp binaries: line endings and PE timestamps both mislead
  ([learning](../learnings/runtime-and-delivery.md#clean-builds-and-desktop-evidence)).
- A plan that walks containers once per path explodes on aliased configurations; budget it and keep the
  alias-aware fallback ([learning](../learnings/physics.md#native-answers-for-published-endpoints)).
- Exported builds can lack project shader globals that the editor registers
  ([learning](../learnings/models-and-rendering.md#rendering-and-visual-evidence)).
- Estimates from synthetic inputs can be wrong by 3×. NK-7l's measured gain was 15 µs per block, not the
  estimated 50. Time the real workload before choosing a batch
  ([measure the complete workload](../learnings/physics.md#measure-the-complete-workload)).

## Plan

Each step needs a parity test with a mutation control, the affected suites, the nineteen installer gates, an
install in both trees and live timings.

1. **NK-9c · Live verification.** Fly the Corsair, glow Stik and P-51 in the live app (muted). Read the native
   answer counters (`native_audio_row_answers`, `native_approach_answers`, the glow voice's `native_render_answers`)
   and per-frame timings. Confirm that no path silently falls back.
2. **NK-6x · Contact step preparation.** Answer the mode bits and lake threshold from the stage's prepared
   configuration (about 6 µs per tick).
3. **NK-6y · Liquid and glow plans.** Keep the frozen-aircraft parts of the glow finish terms and the substep
   preview base, and build the liquid tick context's arguments natively (about 10 µs per tick on those aircraft).
4. **NK-7n · Audio endpoint snapshot.** Answer the mechanical snapshot (surface angles, gear) and the airborne clear
   test with the endpoint air and torques in one call (about 20 µs per frame).
5. **NK-7o · Glow voice hand-over.** Build the pump's detached telemetry natively from the glow keys (about 15 µs
   per frame on glow aircraft).
6. **Guard roots.** With the configuration owners, freeze more guarded roots after native acceptance, so identity
   checks replace property watches (up to about 10 µs per tick).
7. **Platform evidence.** Run the NK-6/7/8 parity tests on Linux (WSL) and on Apple Silicon. Record live-app timings
   at 1920×1080 on the owner's workstation.
