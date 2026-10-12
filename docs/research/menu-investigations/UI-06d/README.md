# UI-06d: active interactive flight defaults

**Status (2026-10-11): implemented; native Windows and focused runtime/UI checks pass. The full suite stops at the separately reproduced baseline atmosphere failure.**

The owner requested gameplay options and diagnostics on, with a little wind, gusts and turbulence. New interactive preferences select the Ugly Stik on the runway, the existing flowing `evening` choice, a gentle weather preset and the latency marker. Existing explicit saved choices retain priority; the owner's current settings were updated through the validated preferences API after preserving a backup.

## Active profile

| Setting | Value |
| --- | --- |
| Scenery, ambience, decorative birds | On; existing high-quality scenery |
| Engine shadow maps | On for interactive worlds; explicit CLI/env off remains supported |
| Weather | `gentle-practice` (`openrc-weather v2`) |
| Mean wind | 1.5 m/s (5.4 km/h), from 090° |
| Horizontal gust increment | 0.6 m/s; 4 s raised-cosine pulse every 14 s, after an initial 3 s delay |
| Upward gust increment | 0.15 m/s |
| Turbulence N/E/D RMS | 0.15 / 0.15 / 0.08 m/s; 3 s correlation time, seed 20261011 |
| Sky | Golden-hour start, time advancing at ×20 (`evening`) |
| Launch | Existing experimental Stik/default-field runway start |
| Diagnostics | Existing input panel and HUD plus live latency marker; marker hides with paused overlays |

Weather numbers are **estimated authored practice settings**, source: this owner-requested bounded profile. They are not measured site weather or validated RC operating limits. Turbulence RMS is not a maximum: the existing OU process is Gaussian. Wind from the east is westward; the eastbound lineup therefore receives a headwind. The sign was checked against `GroundStart.threshold()` and `WindField._direction_ned()`.

Canonical `WindConfig.defaults()` remains calm. Technical/direct launches retain explicit aircraft/start/weather/diagnostic selection and do not read player preferences. They clear any previous in-process Home sky choice. The standalone radio report and trace/frame-time capture routes remain separate tools: they replace or constrain a flight and cannot all run as simultaneous startup modes.

The bundled scenery layout is used automatically only on its matching default field. Another valid field receives no mismatched default props; explicitly selected scenery files still undergo full field-ID validation. The paused TOD editor retains its separate fixed-day/astronomical path; flowing field-world time is selected through Home. Aircraft-specific physics modules received no invented parameters.

## Verification

The native Windows UI Home test passed the real Home → Fly transition with runway start, exact gentle weather, passing evening and a latency marker. The renderer probe used the same transition on Godot 4.7.2/Compatibility, RTX 3090, then advanced 1,200 simulation ticks. It confirmed scenery/birds, sun shadow maps, panel/HUD/marker visibility, moving sun, changing wind, no fault/crash, and marker hiding with overlays. [Native report](native-report.json), [log](native.log), [Home](native-home.png), [flight](native-flight.png).

Captures were visually inspected. Build/frame timings are diagnostic samples, not frame-time acceptance or hardware latency measurements. The marker reported `waiting for radio`; no connected-radio timing was claimed.

All 26 focused UI, wind, turbulence, scenery, latency and atmosphere test processes passed after updating their reference fixtures: [consolidated summary](focused-summary.tsv), [logs](tests/). The existing legacy weather and paused-editor tests select calm/fixed-day cases explicitly; default behavior is exercised separately through Home. A changed default exposed two integration gaps that were repaired: a Home sky preset leaking into a later technical route, and the default scenery layout being applied to an unrelated valid field.

`app/test.sh` passed resource import, data/generator guards, float64/transcendental checks, shader-clock checks and parsing of every script in the frozen source overlay. It stops at the known `test_atmosphere_flight.gd` extreme-density reset failure and Dictionary `format` access, reproduced before this change in [SC-02a](../../scenery-implementation/SC-02a/README.md). [Full log](full-suite.log). No full-suite pass is claimed.

`app/capture.sh`, world parity and the UI flight-capture fixture pin their previous reference selections rather than inheriting new gameplay defaults. Gate W/L/SC and physical aircraft acceptance remain separate.

The live Windows tree was also checked while the parallel landscape/collision track was editing it: 408 scripts were checked, with four dependent test parses temporarily failing on its missing `CELL_SIZE_M`. All four passed after that track's update ([initial summary](live-parse-initial.json), [recheck](live-parse-recheck.json)). A repeated native probe on the current tree completed without script/engine errors; the retained native images/report are from that final pass. These concurrent integration results do not expand the frozen focused-test claim to every new landscape feature.

Sources: [preferences](../../../../app/app_state/preferences.gd), [weather](../../../../app/physics/wind_config.gd), [sky conditions](../../../../app/render/world/conditions.gd), [flight shell](../../../../app/main.gd), [entry](../../../../app/app_root.gd), [scenery](../../../../app/scenery/scenery.gd), [shadow resolver](../../../../app/render/atmosphere.gd).
