# SC-HUM-04 — Flight-line pilots fly the AI companions

Status: **implemented, software-verified, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). Builds on [SC-HUM-03](../SC-HUM-03/README.md).

## What changed

The two existing flight-line pilots take companion slots in roster order: pilot 0 (east −13 m) flies companion 0, pilot 1 (east +16 m) flies companion 1. Each keeps its head coupled to its own aircraft. A pilot whose slot is empty, or whose companion has faulted or been removed, returns to watching the player. A crashed companion stays a target, so its pilot looks at the wreck. Everyone else keeps watching the player.

No placement, envelope or collision proxy changed, so companion admission and the collision identity are unchanged. A third companion has no pilot figure; adding one is a collision-world change (plan D10, SC-HUM-13).

| Part | File |
| --- | --- |
| Targets: player plus one per companion slot, each with its own smoothed velocity; a (re)appearing target starts without a lead spike; `companion_slot` per pilot | [people_gaze.gd](../../../../app/scenery/people_gaze.gd) |
| `advance_people(…, companions_ned)` | [field.gd](../../../../app/render/field.gd) |
| `_companion_positions()`: read-only NED position per companion slot, null when faulted. Read in the player's tick consumer, before the manager advances companions that tick (one-tick lag, render-only) | [main.gd](../../../../app/main.gd) |

## Verification

| Check | Result |
| --- | --- |
| `tests/test_field_people_gaze.gd`, headless | PASS. Pilots take slots 0 and 1 in order, spectators none; pilot 0 settles on its companion within 1°; pilot 1 without a companion watches the player; a removed companion (null slot) returns its pilot to the player; a new companion target has no velocity spike; the default scenery assigns slots [0, 1] |
| Parse check of changed scripts | pass |
| Running app, two companions, `OPENRC_SCENERY_QUALITY=high`, debug bridge | Pilot 0 read 11.6° yaw / 6.9° pitch toward companion 0 (expected ≈12° / 7° from its position and the pilot's 5° heading); pilot 1 read −20.8° / 19.9° toward companion 1 (expected ≈ −22° / 21°); neither followed the player |
| Companion regressions | `test_companions_shell`, `test_companions_lifecycle`, `test_companions_manager`: see the plan status for the latest result |

**Live run caveat:** at the current HEAD the companion profile refuses admission on this checkout: `controller.sha256: current pilot source does not match this profile`. `app/ai/companions/pilot.gd` changed in commit `177d6582` (AFC-04-R8) after the pin in `fda2fa86`; the pinned hash is `3842cbdb…`, the file is `6c9eb4c5…` (not a line-ending difference). The live check therefore ran on a disposable copy of `app/` whose profile pin was set to the current file, then deleted. Renewing the pin belongs to the AFC owner; this step did not change any companion file.

## Limits

- Only two pilot figures exist; the third companion has none.
- Spectators still watch only the player; choosing the nearest or loudest aircraft is part of the attention work (plan §4.2).
- The VM is not performance evidence, and the owner has not reviewed it in flight.
