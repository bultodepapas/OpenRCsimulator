# DT-10a / H / VQ — native release pacing and capture configuration

2026-10-21. Three active controls with the shipped FPS/VSync settings pass the
existing software pacing gates. Three active controls with an additional 60 FPS
cap fail. This is a host-specific benchmark-condition finding, **not a new product
speedup**: the project already defaults to `max_fps=0`, VSync enabled.

The implemented repair records effective cap/mode settings and prevents the
offline reducer from approving mixed configurations. No physics, graphics setting,
asset, focus-safety rule or golden flight changed. Physical-display qualification
and ordinary-release shutdown remain open; this does not close VQ-01c/d.

## Workload and identity

Baseline ordinary Windows release: clean `ffc2974db625756bc19b2913ef0dd1c77c2d540c`,
including the accepted windsock and batched-shadow construction optimizations.
Godot 4.7.2-stable `ed1daf0bf`, Compatibility, NVIDIA RTX 3090, driver 617.42,
1280×720, 4× MSAA, Dummy audio. No custom MainLoop, forced resume or scripted pose
in the sustained controls. Each process requested 10 seconds warmup and 60 seconds
collection. Tests, exports and screenshot readback did not run concurrently with
the measurements. Other host activity was not controlled.

Execution order: capped 01/02/03, capped diagnostic 01, default 01, capped 04,
default 02/03. This is not a randomized or balanced A/B campaign. Default commands
explicitly use `--max-fps 0`; capped commands use `--max-fps 60`. Both retain VSync.
The baseline reports predate the new cap/mode fields. Their settings are evidenced
by checked commands and source configuration, not retroactively inserted into raw
reports. Reducer output therefore correctly says configuration completeness is false.

## Results

All values are milliseconds; percentiles use the retained reducer. Active flight
also requires complete duration, advancing healthy simulation and a valid log.
Gates remain p95 ≤18 ms, p99 ≤25 ms and simulation/wall ratio 0.99–1.01.

| Condition/run | Active | p95 | p99 | Maximum | Software gates |
| --- | --- | ---: | ---: | ---: | --- |
| Additional cap 01 | No, paused at tick 0 | 27.587 | 30.344 | 33.500 | Ineligible; retained |
| Additional cap 02 | Yes | 25.819 | 31.479 | 34.110 | Fail |
| Additional cap 03 | Yes | 22.703 | 30.431 | 34.640 | Fail |
| Additional cap 04 | Yes | 26.197 | 31.329 | 35.764 | Fail |
| Default 01 | Yes | 17.586 | 18.178 | 35.959 | Pass |
| Default 02 | Yes | 17.378 | 17.782 | 35.256 | Pass |
| Default 03 | Yes | 17.400 | 17.787 | 33.665 | Pass |

All active controls advance simulation at approximately real time. Default runs
still contain isolated long frames; passing percentiles does not mean hitch-free
motion. See [default reduction](runs/default-verified-summary.json) and
[capped reduction](runs/capped-verified-summary.json). The paused control is never
averaged into an active-flight result.

The separate capped diagnostic has p95 29.723 ms and p99 31.313 ms. Root-viewport
render CPU p95 is 1.695 ms; GPU p95 is 5.423 ms. Its longest 35.8 ms frame has an
associated GPU sample of 2.85 ms. These observations do not identify a GPU-saturated
tail. Timer results can lag, exclude other work and add instrumentation overhead;
no matched observer-overhead qualification was performed. See [diagnosis](runs/diagnosis.json).
Do not infer a specific driver/OS defect or a generally harmful double limiter.

## Implementation and verification

- `app/main.gd` adds end-of-collection `max_fps`, `vsync_mode`, display server,
  screen index and reported refresh rate. No per-frame observer or setting write
  was added. Values do not prove that settings stayed constant during a run.
- `native_summary.py` validates optional cap/mode values and VSync consistency,
  exposes each run's configuration, and refuses mixed or partially known campaigns.
  All-null historical campaigns retain their previous numeric result with explicit
  incomplete configuration; unknown is never interpreted as uncapped.
- Independent Luna Max review found a partial-metadata campaign loophole; the
  final gate rejects it. The complete Python performance suite passes **95 tests**;
  the frame collector passes **86 checks**. Both ordinary release exports succeed.
- Three short packaged probes verify cap 37/VSync 1, cap 0/VSync 0 and headless
  metadata. They are scripted startup probes, not performance controls. Windows
  reports screen 0 at 60 Hz. Headless reports screen/refresh -1 and VSync enum 1;
  that enum is a setting and does not imply physical presentation. The initial
  probe harness incorrectly expected headless enum 0; its expectation was corrected
  against the retained output without changing runtime code or rerunning capture.
- [Checked invocation audit](provenance/checked-summary.log) validates 14 process
  captures: 14 passed, zero engine errors. Warning policy was not warnings-as-errors.
  Capped 03 reports **19 ObjectDB instances retained at exit**; the short no-VSync
  probe reports four. These are open shutdown findings, not clean-exit evidence.

The updated ordinary executable is retained locally at
`D:/OpenRCsimulator-scratch/pacing-20261021-ffc2974d/updated/OpenRC Simulator.exe`,
with its required sibling `openrc_ground_vehicle.dll`. The sustained timings use
the baseline executable; the updated executable was checked only for export and
metadata behavior. [Source verification](provenance/source-verification.json)
records both binary hashes and confirms that only `app/main.gd` differs among
the 3,842 frozen tracked source files. The runtime/reducer/test patch is retained
in [report-metadata.patch](provenance/report-metadata.patch).

## Reproduction and next work

Use the [performance tool commands](../../../../../research/performance/README.md#capture-without-the-additional-observer)
with a new output directory. Retained checked reports contain exact commands,
exit statuses and log hashes. `provenance/pacing_*.py` records this campaign's
local recipes; adapt scratch paths and source identity rather than overwriting
existing evidence. The `.gz` files are lossless; decompress them to a new scratch
directory, preserving paths, to rerun the reductions or checked-log audit.
[manifest.json](manifest.json) records original and stored hashes for 64 files.

Proceed to VQ-01d/CAM motion-reference refresh and select a demonstrated visual
defect in the existing Compatibility sequence. Keep physical display, pilot
readability, input latency, initial-loading targets, capped pacing and shutdown
qualification separate. These measurements do not authorize disabling VSync or
changing the shipped FPS setting.

Primary API reference: [Godot 4.7 Engine.max_fps](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine-property-max-fps)
defines the cap; [application/run/max_fps](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-application-run-max-fps)
documents its default. Historical [Godot issue 99728](https://github.com/godotengine/godot/issues/99728)
is context only, not evidence that this release has that older defect.
