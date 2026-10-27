# EM-29/30 — Per-type failure selection, severity, onset window and seven new mechanisms

**Date:** 2026-10-27. **Scope:** software implementation and verification. The [plan checkpoint](../../../plans/failure-mode.md#implementation-checkpoint--current-scope) owns the current behavior. Severity bands and onset windows are **training-policy estimates**, not measured RC failure statistics. Nothing here is physical or pilot validation.

## What changed

**EM-29 — request and plan contracts**

- **Failure request v2** (`app/failures/config.gd`) adds three keys to the original three:
  - `severity`: `mild`, `standard` or `severe`.
  - `onset`: `early` (20–60 s), `standard` (20–120 s) or `late` (60–240 s) of qualified airborne time.
  - `excluded_ids`: unique known failure IDs, returned sorted.
- The original three-key dictionary is the only accepted upgrade; it becomes the defaults. Partial new shapes, unknown keys, unknown or duplicate IDs and non-string entries are refused.
- **Plan v3** (`app/failures/runtime.gd`, catalog version 3):
  - New profile-bound flights write `openrc-failure-plan v3`, and the resolved request is part of the physical identity. Notices still are not.
  - v1 and v2 builders are unchanged. They refuse requests they cannot express, and they store the legacy three-key projection, so saved v1/v2 plans re-validate byte-identically. `begin(..., plan_format)` recreates a historical v2 plan explicitly.
  - An empty eligible pool with probability above 0 is refused **before** any draw, so the same request never launches only on lucky seeds. The reason reaches the session as `No enabled failure type is available for this aircraft…`.
- **Severity bands** (hundredths; standard reproduces the v1/v2 ranges and draw counts exactly):

  | Band | Mild | Standard | Severe |
  |---|---|---|---|
  | Trim bias | 4–8 | 8–18 | 18–30 |
  | Servo rate factor | 50–75 | 25–50 | 10–25 |
  | Throttle ceiling | 70–85 | 45–70 | 25–45 |
  | Stuck-high demand | 55–70 | 70–90 | 90–100 |
  | Stuck-low demand | 20–30 | 8–20 | 0–8 |
  | Travel limit | 60–75 | 40–60 | 20–40 |

  Jams, engine stops, motor loss and radio loss are the same at every severity.

**EM-30 — mechanisms, elevon exclusion and interfaces**

- **Seven v3 mechanisms** reuse the existing staged actuator and throttle seams (prepare/commit/rollback, checkpoint, replay), with no new state layout:
  - `pitch_slow` and `yaw_slow`: reduced servo rate on that axis only.
  - `yaw_bias`: rudder command offset; trim can cancel it.
  - `throttle_stuck_low`: holds min(activation demand, resolved low demand).
  - `roll_travel_limit`, `pitch_travel_limit` and `yaw_travel_limit`: command clamp at ±limit on that axis.

  The frozen v1/v2 lists keep their order and seed mapping. v3 appends.
- **Healthy-draw debrief:** a configured flight with no selected event now reports itself, so End shows "No failure was assigned to the last flight."
- **Elevon honesty fix:** the X8's elevon mix fixes the rudder at 0, so every rudder-axis failure was a null event there. `yaw_jam` already was one before EM-29.
  - `Catalog.unsupported_ids(model)` returns the four yaw types for `controls.layout == "elevon"`.
  - Availability lists them as unavailable, with a reason.
  - The session merges them into the resolved request (`request_for_model`), so the v3 plan records them and replays without the model.
- **Menu** (Home → Practice → Failures, and Pause):
  - Onset-window and severity dropdowns.
  - One checkbox per failure type, grouped by axis and system, with Select all / Clear all.
  - Per-type "Not available on this aircraft" and "Requires catastrophic failures" tags.
  - A live count of the checked types that can occur on this aircraft.
  - Apply is refused when probability is above 0 and that count is 0.
  - Home and Pause summaries say "Custom" when the selection differs from the defaults.
- **CLI:** `--failure-severity=mild|standard|severe`, `--failure-onset=early|standard|late` and `--failure-exclude=id1,id2`. They are refused on rotorcraft like the other failure flags.
- **Translations:** 59 new messages in all eight catalogs.
- **Reproduction seed:** v3 changes the seed mapping. `--failures=100 --failure-seed=2063` on the default logical-profile Stik gives a roll jam at 20 s, which is what seed 1751 gave under v2.

## Verification

All runs used `tools/godot/run_checked.py` with Godot 4.8-beta1: first in a disposable app copy, then on the live tree, which contained other tracks' uncommitted edits.

| Script | Result |
|---|---|
| `test_failures.gd` (legacy v1, untouched) | 5150 checks, 0 failed: the v1 path is unchanged |
| `test_failure_profiles.gd` | 168 / 0 (v2 recreated explicitly, v3 default, relabel/downgrade/future refusals, fleet elevon exclusion) |
| `test_failure_selection.gd` (new) | 252 / 0 |
| `test_failure_ui.gd` | 45 checks pass (27 before) |
| `test_failure_availability_ui.gd` | 70 / 0 |
| `test_failure_launch.gd` | 24 / 0 |
| `test_failure_session.gd`, `test_companions_session_failures.gd` | 111 / 0 and 24 / 0, with seed 2063 |
| `test_failure_power.gd`, `test_failure_shutdown.gd` | 111 / 0 and 206 / 0 |
| `test_failure_routes.gd` (Home/Pause flows, card fits 1280×720) | pass |
| `test_ui_language.gd` (8 catalogs, placeholders, CJK glyphs) | pass |
| `test_ui_pause.gd` | pass |
| `test_ui_home.gd` | fails 51 layout-fit checks (Spanish 1024×768, 200 % text). A pristine `git archive HEAD` export fails identically, so this is pre-existing and unrelated. |

**What `test_failure_selection.gd` covers:**

- Request validation and upgrade.
- Group/catalog closure.
- Uniform selection across 6000 seeds per profile (each type within ±35 % of the mean).
- Exclusions never drawn.
- A single remaining type always drawn.
- Empty-pool refusal.
- Catastrophic gating.
- Every severity band, plus an exact v2/v3 standard-parameter match.
- Both edges of every onset window.
- Historical formats refusing new settings.
- The axis isolation of each new mechanism.
- Snapshot round trips and tamper refusal.

The warning scan (`tools/debug/gdscript_warnings.py`) reports 0 errors. Its two `SHADOWED_GLOBAL_IDENTIFIER` warnings (`seed`, `floor` in `runtime.gd`) predate this work.

**Mutations,** each run against that test on a disposable copy; all were detected:

| Mutation | Failed checks |
|---|---|
| Exclusions ignored | 10 |
| No travel clamp | 6 |
| Stuck-low uses max | 3 |
| Severity ignored | 5955 of 6202 |
| Onset window ignored | 4 |

**1080p check:** a debug-bridge session on a private Xvfb display, 1920×1080, Home → Failures on the base Stik.

- The dropdowns, the two-column checklist, unavailable tags and Cancel/Apply all render readably inside the scrolling card.
- The Chinese locale renders the new text with the bundled CJK font.
- Both sessions stopped cleanly with 0 leaked objects.
- Screenshots stayed in the ignored `tmp/debug-bridge/` run folders and are not committed.

## Limits and follow-ups

- **Labels on the X8.** Roll and pitch faults act on the elevon mix's logical axes, so "Aileron jam" there is a mixed-axis surrogate, not one servo. The roll-jam hint mentions the rudder. Independent elevon actuators are EM-13.
- **Travel-limit semantics.** The limit clamps the command, so at onset the servo retreats to the limit at its normal rate. A mechanical obstruction would hold the surface wherever it was. The label says "restricted travel", not "jammed".
- **Stuck-low throttle** holds the demand only. A glow engine keeps idling and an electric motor follows its ESC mapping. It is not a source cut.
- **Numbers are policy.** Uniform selection and the severity bands are training choices. [EM-00-R1](../EM-00-R1/README.md) proposes realism-weighted defaults.
- **Healthy-draw debrief (fixed in EM-30).** `runtime.status()` never set `enabled`, so `No failure was assigned to the last flight.` could not appear (plan §4.3). Status now reports `enabled: true` for any configured episode, and `test_failure_selection.gd` checks it.
