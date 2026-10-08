# Experimental runway start

2026-10-08 · Revision 1 · Step prefix: **UI-06a…c**

**Status: planned; implementation has not started. Next development slice after rc6.** This scoped part of [MENU-PLAN UI-06](MENU-PLAN.md) owns the steps below. Other UI-06 field/scenario work remains deferred. It enables a manual Stik pilot experiment toward [PT2](../ROADMAP.md), without closing Gate 2 or accepting takeoff/landing realism.

Ownership: UI owns `app/app_root.gd`, `app/ui/`, `app/app_state/`, `app/i18n/` and UI tests; coordinate `app/main.gd`, `app/sim/flight_session.gd`, trace metadata and simulation tests with the physics line. Reuse the current field and aircraft data. Evidence belongs in `docs/research/menu-investigations/UI-06a/`, `UI-06b/` and `UI-06c/` when those steps run.

## Why this is next

The missing product capability is a player-controlled runway launch. [GroundStart](../app/physics/ground_start.gd) already finds a threshold and solves idle equilibrium; [FlightSession.reset_on_runway](../app/sim/flight_session.gd) applies it. [Runway tests](../app/tests/test_runway_start.gd), E3c2a/b circuit/review tools and E4a/b replay/sensitivity already provide software evidence. Home currently passes only the aircraft choice, and the ordinary flight route resets into trimmed airborne flight.

Two integration gaps need explicit treatment. `reset_on_runway()` changes live state, but `reset()` restores the airborne start: R, pause Restart and crash recovery would lose the runway choice. `trace_meta()` currently describes a trimmed airborne scenario even after a runway reset. A new menu button alone would therefore produce inconsistent restarts and evidence.

This plan narrows the legacy MENU-PLAN section 5 restriction: an **experimental runway start for a manual pilot trial** may precede PT2 acceptance. A validated takeoff/landing mode, training lesson or advertised v0.2 milestone still requires its existing physical gates. The old statement that a visual runway cannot support taxi/takeoff is a dated snapshot; current ground-contact code supersedes it.

## Small implementation steps

| Step | Change | Required proof |
| --- | --- | --- |
| UI-06a — planned | Define an explicit session start choice: existing airborne default or Stik runway threshold. Reconstruct equilibrium and wheel anchors on every chosen restart. Report the actual launch in trace metadata. | Focused tests exercise first start, R, pause Restart, crash recovery and valid/invalid hot reload. Runway starts at idle in solved support, remains stationary within the existing ground-test tolerances and accepts manual inputs. Invalid field, failed equilibrium or unsupported aircraft returns an explicit error and remains stopped; never silently launch airborne. Airborne fleet numeric traces/goldens remain unchanged. |
| UI-06b — planned | Add a small Home start selector using the existing UI, with English/Spanish labels: air / runway (experimental). Offer runway only for the Stik on the existing supported field. Save this start choice on Fly. | Real UI events plus keyboard/fake-radio flight; radio axes cannot navigate menus. A rejected start displays its reason and keeps Home available; it must not leave an active flight behind. Changing aircraft cannot retain an unsupported runway request. Old preferences default to air, invalid values are handled, future schemas are preserved and save errors remain visible. Home → flight → Home → flight and reset retain coherent choices. EN/ES captures fit at sizes already covered by the capture harness. |
| UI-06c — planned | Verify the integrated route in an identified export and prepare the existing pilot/review tools for a manual runway–circuit–landing attempt. | Full `app/test.sh`, relevant captures and export checks pass. Direct CLI `--trace`, `--quick-flight`, `--aircraft` and scripted/capture routes retain their current behavior and preference isolation. Record an exported manual-launch smoke; retain build/data hashes, selected start and trace metadata. A flight card names the observations below and distinguishes pending physical trials from software proof. |

Reuse the current regression suite; do not multiply every restart case by every aircraft, language and controller. Cover each restart route and each unsupported aircraft once, plus the existing airborne fleet fixtures.

Do UI-06a before UI-06b; combine neither with force-law tuning. UI-06c completes software delivery, not the owner session or PT2. Preserve the existing low-throttle arming, disconnect/focus pause and named pause holds. Do not copy the offline scenery scenario's manual stepping or autopilot into the player loop.

For UI-06a, keep `reset_on_runway()` usable by existing test/capture callers and define the error path before changing `reset()`: the present helper falls back to air on failure, which is unsuitable for an explicitly selected player runway start. An invalid reload must preserve the active valid flight. Recompute ground support after a valid reload; never reuse stale wheel anchors. Trace headers must distinguish the selected launch from the state at which recording actually began; retain the existing recording-start snapshot contract.

## Pilot evidence after delivery

Use the existing [pilot feedback form](../.github/ISSUE_TEMPLATE/pilot_feedback.md), [tool workflows](TOOLS.md) and E3c2b review kit. Record the exact build, Stik input hash, radio/profile, OS/display and camera mode. Attempt idle hold, straight taxi, takeoff, circuit, approach and wheel landing; retain unsuccessful attempts and restart behavior. Rate trim, throttle/steering response and attitude/height readability separately. Save the trace and screen/radio evidence; collect target frame times.

Run the existing G1b1 offline range audit on the recorded trace and state its K1/previous-state reconstruction limit. Independent mass/CG/inertia, matched propeller/RPM and surveyed flight-video evidence still belong to VAL-5…8. Synthetic tool fixtures and automated circuits do not close those measurements. If radio trim blocks the flight, resolve the bounded F2 linkage-trim decision first. Gate 2, Gate L, F4/F6 and PT2 are accepted only from their own evidence.

## What follows, and what waits

1. Fix the largest reproducible pilot blocker from that session. Select a bounded input, readability, ground/contact or handling repair; compare before/after evidence before changing coefficients.
2. Add G1b runtime range counters if the recorded flight exposes a question the offline audit cannot answer (such as internal RK-stage coverage). This observability work is not a prerequisite for exposing the already-tested runway start.
3. Continue E0b6p prepared-path attribution and E0b7 calibration as research. Native adoption, platform qualification and enabling Stik wash each need separate evidence; none blocks this production GDScript route.
4. Reconsider wind, broader aircraft/scenarios, electric propulsion, training and damage presentation after the pilot findings. The Timber source/asset track can continue independently; its shared electric/flap dependencies do not expand this slice.

No new field, generic scenario framework, autopilot, scoring, wind, production wash, contact model, aircraft tuning, installer or engine upgrade is part of UI-06a…c. The next release number follows the shipped scope and gate decisions, not completion of a menu control alone.
