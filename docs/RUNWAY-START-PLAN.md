# Experimental runway start

2026-10-08 · Revision 4 · Step prefix: **UI-06a…c** (repairs use `-R` suffixes)

**Status: UI-06a…c complete (software delivery, 2026-10-08).** Owner flight and physical validation remain pending. This scoped part of [MENU-PLAN UI-06](MENU-PLAN.md) owns the steps below. Other UI-06 field/scenario work remains deferred. It enables a manual Stik pilot experiment toward [PT2](../ROADMAP.md), without closing Gate 2 or accepting takeoff/landing realism.

Ownership: UI owns `app/app_root.gd`, `app/ui/`, `app/app_state/`, `app/i18n/` and UI tests; coordinate `app/main.gd`, `app/sim/flight_session.gd`, trace metadata and simulation tests with the physics line. Reuse the current field and aircraft data. Evidence is retained in `docs/research/menu-investigations/UI-06a/`, `UI-06b/`, `UI-06c/` and `UI-06a-R1/`.

## Delivery rationale

This slice exposes a player-controlled runway launch using the existing [GroundStart](../app/physics/ground_start.gd) threshold and idle-equilibrium solver. [Runway tests](../app/tests/test_runway_start.gd), E3c2a/b circuit/review tools and E4a/b replay/sensitivity supplied the prior software evidence. Home now passes both aircraft and start choice; direct CLI routes keep the existing airborne behavior.

The integration fixes two gaps: the old one-shot runway helper did not persist through R, pause Restart or crash recovery, and trace headers described a trimmed airborne scenario after a runway start. The session now owns the selected restart recipe and records the actual launch independently of the recording-start snapshot. The legacy one-shot helper remains available to test/capture callers.

This plan narrows the legacy MENU-PLAN section 5 restriction: an **experimental runway start for a manual pilot trial** may precede PT2 acceptance. A validated takeoff/landing mode, training lesson or advertised v0.2 milestone still requires its existing physical gates. The old statement that a visual runway cannot support taxi/takeoff is a dated snapshot; current ground-contact code supersedes it.

## Small implementation steps

| Step | Change | Required proof |
| --- | --- | --- |
| UI-06a — complete (2026-10-08) | Define an explicit session start choice: existing airborne default or Stik runway threshold. Reconstruct equilibrium and wheel anchors on every chosen restart. Report the actual launch in trace metadata. | [UI-06a evidence](research/menu-investigations/UI-06a/README.md): 34 focused checks, runway and integrity regression tests, checkpoint and metadata tests, and four unchanged airborne golden flights pass. Invalid field, failed equilibrium and unsupported aircraft stay stopped; rejected hot reload preserves the active flight and Recorder. |
| UI-06b — complete (2026-10-08) | Home start selector in English/Spanish; runway only for the Stik on the existing field. Save the choice on successful Fly. | [UI-06b evidence](research/menu-investigations/UI-06b/README.md): real UI events, fake-radio input/isolation, old/invalid/future preferences, visible save failures, rejected launch/retry, aircraft restrictions and the Home round trip pass. Six guarded 1280×720 captures cover EN/ES runway Home/flight, default air and the unsupported-aircraft selector. |
| UI-06c — complete (2026-10-08) | Verify the integrated export and prepare the manual runway–circuit–landing trial. | [UI-06c evidence](research/menu-investigations/UI-06c/README.md): full `app/test.sh` (123 GDScript test processes), three-platform exports and package checks pass. The Linux release binary takes native keyboard input through Home → runway, records taxi and retains runway on R/Pause Restart. Source/export CSV parity and CLI preference isolation pass. Build/input hashes, trace snapshots, captures and the [pilot card](research/menu-investigations/UI-06c/FLIGHT-CARD.md) are retained. |

Reuse the current regression suite; do not multiply every restart case by every aircraft, language and controller. Cover each restart route and each unsupported aircraft once, plus the existing airborne fleet fixtures.

**UI-06a-R1 follow-up (2026-10-08):** [checkpoint trace-origin repair](research/menu-investigations/UI-06a-R1/README.md) clears inherited launch claims after physics-only checkpoint restoration. Four reproduced attribution failures now pass in a 14-check regression; full `app/test.sh` passes (125 GDScript test processes and frame-rate checks). Original UI-06c package evidence remains tied to its recorded binary.

**UI-06c-R1 package refresh (2026-10-08):** [new export evidence](research/menu-investigations/UI-06c-R1/README.md) verifies the repair in all three compiled packs and repeats the native Linux Home/runway/restart smoke. Full frozen-source `app/test.sh` passes (125 GDScript test processes); the verified bytes are installed in `dist/` with checked hashes.

Do UI-06a before UI-06b; combine neither with force-law tuning. UI-06c completes software delivery, not the owner session or PT2. Preserve the existing low-throttle arming, disconnect/focus pause and named pause holds. Do not copy the offline scenery scenario's manual stepping or autopilot into the player loop.

For UI-06a, keep `reset_on_runway()` usable by existing test/capture callers and define the error path before changing `reset()`: the present helper falls back to air on failure, which is unsuitable for an explicitly selected player runway start. An invalid reload must preserve the active valid flight. Recompute ground support after a valid reload; never reuse stale wheel anchors. Trace headers must distinguish the selected launch from the state at which recording actually began; retain the existing recording-start snapshot contract.

## Ready-to-paste commit messages

- `UI-06a: persist runway launch and trace identity; proof: 34 start checks and unchanged airborne goldens`
- `UI-06b: expose experimental Stik runway start; proof: real UI/radio tests and six EN/ES captures`
- `UI-06c: verify packaged runway route; proof: full app suite, three exports and native keyboard/CLI smoke`
- `UI-06c-R1: refresh packages after checkpoint-origin repair; proof: frozen-source suite, three compiled-pack probes and native Linux smoke`

## Pilot evidence after delivery

Use the existing [pilot feedback form](../.github/ISSUE_TEMPLATE/pilot_feedback.md), [tool workflows](TOOLS.md) and E3c2b review kit. Record the exact build, Stik input hash, radio/profile, OS/display and camera mode. Attempt idle hold, straight taxi, takeoff, circuit, approach and wheel landing; retain unsuccessful attempts and restart behavior. Rate trim, throttle/steering response and attitude/height readability separately. Save the trace and screen/radio evidence; collect target frame times.

Run the existing G1b1 offline range audit on the recorded trace and state its K1/previous-state reconstruction limit. Independent mass/CG/inertia, matched propeller/RPM and surveyed flight-video evidence still belong to VAL-5…8. Synthetic tool fixtures and automated circuits do not close those measurements. If radio trim blocks the flight, resolve the bounded F2 linkage-trim decision first. Gate 2, Gate L, F4/F6 and PT2 are accepted only from their own evidence.

## What follows, and what waits

1. Fix the largest reproducible pilot blocker from that session. Select a bounded input, readability, ground/contact or handling repair; compare before/after evidence before changing coefficients.
2. Add G1b runtime range counters if the recorded flight exposes a question the offline audit cannot answer (such as internal RK-stage coverage). This observability work is not a prerequisite for exposing the already-tested runway start.
3. Continue E0b6p prepared-path attribution and E0b7 calibration as research. Native adoption, platform qualification and enabling Stik wash each need separate evidence; none blocks this production GDScript route.
4. Reconsider wind, broader aircraft/scenarios, electric propulsion, training and damage presentation after the pilot findings. The Timber source/asset track can continue independently; its shared electric/flap dependencies do not expand this slice.

No new field, generic scenario framework, autopilot, scoring, wind, production wash, contact model, aircraft tuning, installer or engine upgrade is part of UI-06a…c. The next release number follows the shipped scope and gate decisions, not completion of a menu control alone.
