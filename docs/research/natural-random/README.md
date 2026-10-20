# Natural Random: initial implementation evidence

Date: 2026-10-13. Scope: NR-01/02/04/05 and the NR-06 lifecycle. This is development-source software evidence, not pilot, physical or release acceptance. The [active plan](../../plans/natural-random-flight.md) retains NR-03 qualification and NR-07…09 extensions. [Menu behavior](../../MENU-PLAN.md) is the operating guide.

## Implemented boundary

Home opens a read-only briefing using the existing screen stack. The generator resolves one of five stock airplanes, one of four bounded wind recipes, atmosphere and a fixed astronomical daylight snapshot. Workshop variants, helicopters and ground vehicles cannot enter the pool. A new catalog entry does not become eligible automatically.

Preparation loads the actual stock data and configures weather before trim, with input and physics stepping disabled. Launch rechecks source identities and binds the scenario only after the production flight accepts it. A failed launch after world creation rebuilds the saved Home world, including shared atmosphere/clock state. Another flight draws once; Restart and Repeat preserve the accepted conditions. Normal aircraft/weather/lighting preferences are isolated from random flights and their pause-lighting edits.

The implementation adds no wind equations, simulation state, aircraft tuning, assets or dependencies. Current source separately includes other vehicle and night-lighting integrations; their presence is not Natural Random admission or acceptance.

## Scenario identity and recording

`openrc-flight-scenario v1` is separate from the sealed aircraft, weather, lighting and checkpoint formats. It carries the resolved settings, seed, generator/recipe versions, required capabilities, build identity and exact SHA-256 hashes of source aircraft, field and model manifest. Source checks bypass the generation cache at launch.

The scenario digest sorts keys and canonicalizes numeric values to **12 significant decimal digits**. Godot's JSON parser can change a serialized float64 by one ULP; the canonical decimal representation avoids rejecting that diagnostic transport. Scenario values and trace JSON retain full precision. This digest is a content check at the stated precision, not a bit-exact physical checkpoint or a security signature. Uint32 seeds remain exactly representable. Exact solver replay uses native state and the existing input/trace mechanisms.

Trace metadata stores the initial scenario and appends lighting edits at their simulation tick. Such an edit changes provenance to `customized`, retaining the parent identity. Restoring a paired checkpoint that has no scenario envelope clears stale scenario provenance; the flight's origin still prevents writes to normal lighting defaults.

## Verification

The pinned engine is Godot `4.7.2.stable.official.ed1daf0bf`. New tests use isolated preferences and never rewrite golden flights. Earlier exploratory failures are not passing evidence.

| Check | Purpose |
| --- | --- |
| `test_natural_random_config.gd` | Strict fields/capabilities/eligibility, immutable policy copies, source identities, JSON round trip, tampering and customized-lighting lineage. |
| `test_natural_random_generator.gd` | Uint32 boundaries, reproducibility, detached outputs and a deterministic 10,000-seed distribution sweep. |
| `test_natural_random_screen.gd` | EN/ES text, focus/error recovery, duplicate activation, details/repeat controls and 1024×576 / 1280×720 layout. |
| `test_natural_random_flight.gd` | Actual aircraft×recipe session starts, finite 240 Hz integration and deterministic reset/replay; `--gust-period` covers an entire gust period. [Flight evidence](flight-checks.md). |
| `test_ui_natural_random.gd` | Real menu input, cancel/reroll, late world-build failure, preference isolation, accepted launch, recording edits, restart, repeat and checkpoint context clearing. |

Headless checks do not establish airplane attitude recognition, human workload or radio hardware acceptance. Native captures show representative initial views only. The full five-aircraft/background/distance readability matrix, flown windy circuits, atmosphere corners with a pilot, 20-cycle lifetime measurements and target-hardware performance remain open. No platform release is claimed by this report.

### Current working-tree result

2026-10-19 release-candidate follow-up: deterministic seed 4 exposed a source-identity mismatch. Home loaded Turbo Lumber's default finite-pack data, while scenario identity had hashed its base prescribed-voltage data. Preparation and identity resolution now share the runtime default source; changing that default also invalidates a previously resolved identity. Native checked Windows Godot 4.7.2 passed 34 checks in `test_natural_random_config.gd` and 27 in `test_ui_natural_random.gd`. The source candidate also passed the [Linux capture job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39370568586/job/118457277015) and [three-platform export job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39370568586/job/118457913934). These checks do not close the pilot/readability gates above. [Configuration test](../../../app/tests/test_natural_random_config.gd) · [UI lifecycle test](../../../app/tests/test_ui_natural_random.gd).

After the concurrent modules became available, import and all six integration parse checks passed. The config, 10,000-seed generator, screen and 576-check flight matrix passed against the current `app/`. The lifecycle's 27 assertions passed too, but that first run read the Jensen aircraft JSON while another task regenerated it and logged a presentation error. The runner correctly marked the invocation failed. [Complete first report](current-verification.json).

Once that source was valid, a fresh import/parse and lifecycle rerun passed **without engine errors**: [verification report](current-lifecycle-verification.json), [27-check output](current-lifecycle.log). Together these runs provide passing current-tree evidence for all five Natural Random tests. They do not make the broader suite green: the existing `test_ui_time_of_day_pause` still expects the older menu label/focus order and fails in the concurrent sky/menu integration.

A clean native current-tree capture also completed Home → briefing → flight → pause: [capture log](current-capture.log), [Spanish briefing](current-es-briefing.png), [Spanish flight](current-es-flight.png). The current-tree full-gust check then passed **60 checks, zero failures**, through 7,428 ticks / 30.950 simulated seconds, without engine errors: [full output](current-gust.log). The following isolated results retain the broader regression evidence collected while the shared tree was changing.

### Isolated integration result

Concurrent sky, failure and rotorcraft integrations temporarily made the shared application unparseable. To check Natural Random independently, [snapshot.py](../../../research/natural-random/snapshot.py) reconstructs commit `7562dba6`, including the authoring inputs named by its model manifests, and overlays the current scenario implementation and its five tests. It also matches the launch factory's optional argument, shortens the Workshop label and bounds diagnostic worker threads to two. This is a diagnostic application, not a replacement for the working tree or a performance fixture. [Source inventory](snapshot-sources.json).

The [focused run](snapshot-verification.json) passed all five Natural Random tests and 11 existing regressions: screen stack, pause, weather, field lighting, start choice, wind flight, turbulence, atmosphere, lighting checkpoints, checkpoint integrity and replay integrity. The older `test_ui_time_of_day_pause` did **not** pass: its hard-coded Down-key sequence reached Workshop instead of Time of day and then dereferenced a null editor. The report retains that failure; this is not an all-green application suite.

The final briefing style was then corrected to read the explicit Sidebar theme while detached, preserving its gutters while making the background opaque. Its EN/ES layout test was rerun successfully with 40 assertions, including the new gutter checks. [Screen result](screen-final.log).

- The deterministic sweep generated **10,000 valid scenarios, zero invalid**, exercising every airplane/recipe cell. Aircraft counts were 1,981–2,018 each; recipe counts were 1,961 calm, 3,989 gentle, 2,456 lively and 1,594 windy. [Generator output](generator.log).
- The flight matrix passed **576 checks** across all 20 airplane/recipe combinations. The separate full-period gust check passed **60 checks** through 7,428 ticks / 30.950 simulated seconds. [Flight evidence](flight-checks.md).
- The real menu lifecycle passed **27 checks**, including late startup rollback, restart/repeat, trace edits and normal-preference isolation. [Lifecycle output](lifecycle.log).

Native OpenGL captures from that diagnostic snapshot use seed 4 (Spanish, 1280×720) and seed 0 (English, 1024×576). They were generated by the capture script below and visually inspected: [Spanish briefing](es-720-briefing.png), [Spanish flight](es-720-flight.png), [English Home](en-576-home.png), [English briefing](en-576-briefing.png). The briefing deliberately retains the ordinary Home backdrop; its aircraft name identifies the drawn airplane. These images do not qualify distance/attitude recognition in flight.

## Reproduce

From the repository root, with the pinned native executable:

```powershell
python research/natural-random/verify.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out .tools/nr-check
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --log-file C:/temp/nr-gust.log --script res://tests/test_natural_random_flight.gd -- --gust-period
```

The runner requires a fresh output directory, writes per-check logs and fails on engine/script errors even when Godot returns exit code zero. Use `--tests` to select listed focused checks. [TOOLS](../../TOOLS.md) remains authoritative for the complete application suite and platform release workflow.

To reproduce the isolated diagnostic route:

```powershell
python research/natural-random/snapshot.py --out .tools/nr-snapshot
python research/natural-random/verify.py --godot .tools/Godot_v4.7.2-stable_win64.exe --app .tools/nr-snapshot/app --out .tools/nr-snapshot-check --tests test_natural_random_config test_natural_random_generator test_natural_random_screen test_natural_random_flight test_ui_natural_random
```

Give simultaneous Godot processes distinct absolute `--log-file` paths. On this shared workstation, isolating internal logs removed lengthy startup contention. The runner already does so. This is an observed tooling workaround, not a simulator performance result; the flag is documented in the [Godot command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

For native rendering, use [capture.gd](../../../research/natural-random/capture.gd) with a fresh absolute output directory. It drives Home → briefing → flight → pause using isolated preferences and writes the accepted scenario beside the images:

```powershell
Start-Process -WindowStyle Hidden -Wait -FilePath .tools/Godot_v4.7.2-stable_win64_console.exe -ArgumentList '--path app --audio-driver Dummy --log-file C:/temp/nr-capture-engine.log --rendering-method gl_compatibility --script ../research/natural-random/capture.gd -- --out=C:/temp/nr-capture --lang=es --seed=4 --width=1280 --height=720'
```

For package integration, export the Windows pack and run [pack_smoke.gd](../../../research/natural-random/pack_smoke.gd) against it:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --export-pack Windows ../.tools/nr.pck
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --main-pack ../.tools/nr.pck --script ../research/natural-random/pack_smoke.gd
```

Inspect export errors as well as the exit code. The smoke checks all five stock sources and an interactive random launch from the exported resources; it does not qualify platform packaging, signing or native display behavior.

The attempted pack export reported a missing model manifest for the concurrently added research helicopter and did not produce a passing package proof. Export acceptance remains open; the five-airplane scenario tests do not waive the complete catalog's packaging contract.
