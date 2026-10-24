# SC-HUM-05 — Crash glance

Status: **implemented, software-verified, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). The step-and-hold head behaviour of SC-HUM-05 shipped with [SC-HUM-03](../SC-HUM-03/README.md); this adds the crash reaction.

## What changed

When the player's aircraft crashes, every spectator, veranda visitor and pits member reacts after a seeded startle delay (0.2–0.8 s). For 8 s their usual range limit is lifted and their dead zone shrinks to a quarter, so they look at the wreck. Afterwards the normal rules resume. Flight-line pilots stay coupled to their own aircraft. People facing away keep their rear gate, because the plan does not turn bodies.

A crash pauses the simulation, so no tick reaches the head state. While the player is crashed, [main.gd](../../../../app/main.gd) advances the head state on the crash director's presentation clock: crash time plus the frame time accumulated since (`dt` capped at 0.1 s, as the director uses). Like the director's aftermath, this clock stops while a menu or other hold is open (repair after the [independent review](../SC-HUM-03/README.md#independent-review-2026-10-24)). A restart sends time backwards, which resets every head. Scripted routes are unchanged.

| Part | File |
| --- | --- |
| `alert` input on `reset`/`update_to`, alert window per person (`reaction_s`, `ALERT_DURATION_S`, `ALERT_DEAD_ZONE_SCALE`) | [people_gaze.gd](../../../../app/scenery/people_gaze.gd) |
| `player_crashed` argument | [field.gd](../../../../app/render/field.gd) |
| Tick call passes `not session.crash.is_empty()`; `_advance_people_after_crash(dt)` in `_process` | [main.gd](../../../../app/main.gd) |

## Verification

| Check | Result |
| --- | --- |
| `tests/test_field_people_gaze.gd`, headless | PASS. A pits member ignores a distant aircraft; after a crash it reacts within its startle delay (+0.3 s), settles on the wreck within 2°, returns to rest after the window, and a restart clears the alert |
| Running app via the debug bridge (`OPENRC_SCENERY_QUALITY=high`, airborne Ugly Stik dived into the ground) | Crash at simulation time 2.11 s; the simulation stayed at 2.1125 s while the head clock advanced 2.86 → 4.06 s on presentation time. North-facing pits members turned 21° and 17° to the wreck (−1° pitch); a seated spectator and the flight-line pilot looked at it; a pits member facing 160° stayed at rest (wreck behind). Session ended with no crash and 0 leaked objects |
| Companion regressions with SC-HUM-03/04/05 present | On a disposable full copy of `app/` whose companion controller pin was renewed (the current pin refuses admission; see [SC-HUM-04](../SC-HUM-04/README.md)): `test_companions_manager` 53/0, `test_companions_lifecycle` 653/0 (taken before this step's edit), `test_companions_shell` 0 failed. The copy was deleted afterwards |

## Limits

- Only the player's crash is an event. Companion crashes keep their pilot looking at the wreck (SC-HUM-04) but do not alert the field.
- The shared field-event signal for the birds plan is not built yet; the crash flag is passed directly.
- No body turn: people facing away do not look.
- 8 s and the startle range are estimates, to be judged by the owner.
