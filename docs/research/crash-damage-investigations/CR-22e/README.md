# CR-22e — Crash-frame and ground-contact hitches

2026-11-12. Windows 11, Godot 4.8-beta2 `cafc17a19`, Compatibility/OpenGL, RTX 3090 /
driver 617.42, **1920 × 1080**, uncapped. Follows [CR-22c-R1…R3](../CR-22c-R1/README.md).
Presentation and economics only: no solver, aircraft data, crash threshold or golden flight changed.

## Root cause

Reproduced in the running app (debug bridge) and in a rendered `main.tscn` bench that splits every
frame into physics callbacks, `_process` callbacks and the remainder (render/engine).

1. **Accident economics ran whole inside one frame.** On the frame after a crash,
   `economy/incident.gd` recalculated the report (25–35 ms) and then encoded, re-parsed, strictly
   validated and wrote the 36 KB archive (13–23 ms) on the main thread. This was 86 % of the
   crash-frame script time. `_purchase_options()` alone took ~18 ms, partly because it prepared the
   same "Automatic" plan that `_recalculate()` had just prepared. The economics plan's own budget is
   under 10 ms.
2. **The same work repeated during ground contact.** Each accepted revision during a scrape or slide
   triggered a recalculation, and evidence-only archive rewrites ran every 60 ticks. Ugly Stik slides
   had 45–106 frames with more than 8 ms of `_process`.
3. **Scenery crashes deep-copied the whole collision world.** The director called
   `session.collision_world(true)`, which runs `duplicate(true)` over about 5,000 proxies and bins.
   The director's `_start` took 70–105 ms for a P-51 hitting a bench.
4. **Ground contact itself is expensive (open).** The reference GDScript solver costs about 1.1 ms
   per tick in flight and 2.4–2.6 ms per tick in contact (Ugly Stik). Near the ground it costs
   4.5 ms per tick on the Extra and 6–10 ms per tick on a P-51 slide. Native stages are Linux-only.
   At 240 Hz, any slow frame catches up with up to 12 ticks, which keeps frames slow. Ablations put
   the per-tick economics observers at 0.15–0.25 ms and audio at about 0.4 ms. The rest is pinned
   `app/physics`/`app/sim` code.

## Changes

- **Archive off the frame.** In the runtime (`async_archive`), `flush()` encodes and writes a deep
  copy on `WorkerThreadPool`. The bytes are identical. A failure stays reported and is not retried
  every frame. `archive()`, a new incident and a restore all wait for the write.
- **Valuation off the frame (clone-and-compute).** `evaluate_in_background()` runs the unchanged
  `_recalculate()` on a private copy of the ledger. The frame commits only its outputs. Revisions
  that arrive meanwhile coalesce into the next pass (CR-39h: publication cadence cannot change the
  result). Every synchronous entry point waits for an in-flight pass. The pass publishes its own
  `terminal` state.
- **One prepared plan per pass.** `_prepare_purchase` results are memoized within a single
  `_recalculate()`; the memo key includes the revision.
- **Crash-frame deferral.** The live frame that first sees a crash leaves valuation to the next
  frame, so the wreck setup and the economics never stack.
- **Presentation beat.** A live terminal card is held for 0.6 s while the camera shows the wreck,
  then the headline counts up over 0.9 s to the exact text. The count uses the same formatter, and
  non-zero amounts never scale to zero. Direct and test callers stay immediate. Pause freezes the
  beat; restart or another presentation cancels it.
- **Scenery contacts without the copy.** Main shares the collision world it installed in the
  session (read-only) through `PresentationContext.collision_world`. `SceneryBodies.build_near` skips
  broken proxies using the same `SceneryDamage.id_is_broken` check.
- **Final pass on scenery contacts.** Micro costs after a crash, best of N:

  | Cost | Before | After |
  | --- | ---: | ---: |
  | Full plan | 15.3 ms | 1.1 ms |
  | First 16 bodies in the crash frame | — | 1.3 ms |
  | Each later frame (24 bodies) | — | 0.2–0.4 ms |
  | Valuation clone (property names cached) | 0.67 ms | 0.44 ms |

  Measurement located the cost. It was not body creation (about 17 µs per body). It came from:
  - visiting all 6,092 proxies, now replaced by the world's existing 32 m bins;
  - a GDScript sort comparator, now a native lexicographic sort with the same order;
  - a per-crash `push_warning` for the designed 160-body cap, which cost 6–28 ms with its
    backtrace. The omitted count is now exposed as `scenery_contacts_omitted` in director stats.

  The bin query covers `RANGE_M` plus the world's largest filter margin (computed once at setup) at
  all heights. A proxy's centre lies inside the bounds it is binned by, so the candidate set is exact.
  A test compares the selection with the original comparator and full scan for five obstacle kinds.
  The director creates the 16 nearest bodies at impact and 24 per frame after that, so all 160 exist
  within about 7 frames; the struck obstacle is present in the crash frame.

## Evidence

Rendered bench: `research/crash-damage/cr-22e/` (`run.py`, `crash_bench.gd`). Each aircraft and
scenario ran in a fresh process with two crashes. The window covers one frame before impact to eight
after. `--reference` restores synchronous archive and valuation without the deferral. This is a shared
host: other Godot sessions ran during some trials, so single values are trials, not confidence
intervals.

| Measure | Reference | Final |
| --- | ---: | ---: |
| Ugly Stik, largest `_process` in the impact window | 38–65 ms | 8.3–8.9 ms |
| Ugly Stik, largest frame in the impact window | 46–94 ms | 19–35 ms |
| Ground/hull crashes, 7 other configurations (FS64V, Extra, P-51, F4U, Avanti, Lumber, MoonRunner), largest `_process` | 32.7–98.5 ms | 5.4–12.2 ms |
| P-51 slide into a bench (scenery crash), largest `_process` | 158–171 ms | 8.9–10.7 ms |
| P-51 scenery crash, director `_start` | 70–105 ms | 6.1–7.8 ms |
| Ugly Stik slide, frames with `_process` > 8 ms (600 frames) | 45–106 | 5–10 |

Final runs overlapped other Godot sessions; some individual impact frames there reached 186–868 ms of
physics callbacks, and reruns without that load did not reproduce them (P-51 slide: 110–119 ms).

The remaining impact-window wall time is physics catch-up of 6–12 ticks at the contact tick cost
(item 4). Moving valuation off the frame made no physics difference (Extra ablation: 37–70 ms with
synchronous or background valuation).

In the running app at 1080p, the card is absent 0.3 s after impact and shows the final US$138 1.5 s
after it. Repeated crashes in one session peaked at 17–42 ms with GPU readings of 8 ms or less. **The
first crash of a fresh session is still intermittent:** 53, 97, 697 and 1,048 ms in four fresh
launches, with GPU readings up to 350 ms and no consistent element in hide-wreck/hide-effects
ablations. This is consistent with driver-side first-use compilation or contention from other
instances; it is not attributed here.

Tests (headless, 0 failures): `test_accident_integration` 100, `test_accident_report` 164,
`test_economy_checkpoint` 65, `test_crash_cost_round2` 72, `test_crash_cost_incident` 59,
`test_economy_cr39` 52, `test_economy_inspection` 83, `test_accident_settlement` 46,
`test_crash_integration` 246, `test_landscape_runtime` 76, `test_heli_crash_presentation` 44, `test_crash_wreck` 361,
`test_hull_scrape_session` 56, `test_water_director` 22, `test_crash_cause` 29, `test_crash_pose` 343.
New checks cover:

- identical background and synchronous archive bytes;
- a failed write that is reported once and retried explicitly;
- a report changed during a write staying dirty;
- the background valuation equal to the synchronous report and receipt;
- coalesced revisions and synchronous entry points that wait;
- the held card, newest value, count-up landing on the exact headline, pause and restart;
- shared-world scenery contacts equal to the detached copy and the original comparator for five obstacle kinds, with staged creation reaching the full selection.

Two independent adversarial reviews were folded in: error stickiness, write starvation, memo
revision key, terminal pairing and count-up form.

## Open

- First-crash GPU stalls in a fresh session (above). Rerun on an idle host before changing the
  warmup.
- Contact-tick physics cost: [NK-4](../../native-kernel/NK-4/README.md) brings the bit-identical native stage to
  Windows (ground-slide tick 2.0–2.2 → 1.3 ms, same state hash). The 12-step catch-up limit (time dilation
  under load) remains an owner decision.
- Glow-voice synthesis runs in GDScript on its own producer thread (`glow_audio_pump.gd`), not on the frame;
  it costs CPU proportional to audio time (audio track).
- Per-tick accident observers during ground contact (`incident.observe` 60–190 µs, settlement 50–70
  µs) remain; they are defensive by design (bounded, digested evidence).
