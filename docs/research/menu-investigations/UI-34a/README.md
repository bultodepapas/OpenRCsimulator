# UI-34a — switch aircraft from Pause

2026-10-20. This step repairs [UI-30](../UI-30/README.md) finding AS-1 and follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

## Behaviour

- **Identity line.** Pause shows "Aircraft · field" under its title. A Workshop trial starts with "Workshop trial".
- **Change aircraft.** This top-level Pause action sits directly above Exit options. It runs the End-flight transaction: an active trace is saved, and a failed save asks Stay / Retry / Discard. It then opens Home on the Aircraft page with the aircraft just flown focused (`Home.open_aircraft_catalog`).
- **Hidden where Home is not the destination.** It is hidden during Workshop trials, which return to the Workshop, and on direct technical routes.

Mid-flight switch, before and after:

| | Steps |
| --- | --- |
| Before | Esc → Exit options → End flight → Aircraft → entry → Fly (6) |
| After | Esc, then three activations: Change aircraft → entry → Fly |

**Placement.** The action sits beside the exit group rather than right after Restart. Several suites (Pause, failure routes, field-world time, aircraft) walk Pause by key presses, and that order keeps their walks to Session options unchanged.

## Proof

[`test_ui_change_aircraft.gd`](../../../../app/tests/test_ui_change_aircraft.gd) is new.
- Before the change it stopped at a script error: the identity line did not exist.
- After the change all 8 checks pass. They cover the identity line, placement and keyboard reach, ending the flight to the focused catalog entry, selection without launch, Fly with the new aircraft, and the trial's Return to Workshop instead of Change aircraft.

`test_ui_aircraft.gd` walks Pause key by key to Exit options and now passes Change aircraft (65 ok). The full Pause and controller regression set is listed in [UI-31](../UI-31/README.md).
