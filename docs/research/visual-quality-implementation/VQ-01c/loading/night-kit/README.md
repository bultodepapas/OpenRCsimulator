# DT-11a — remove duplicate night-kit geometry extraction

Follow-up: [audio retirement attribution and corrected probe teardown](../audio/README.md).
The measurements and warnings below retain their original scope.

2026-10-14. Continued from the [grain bake](../grain/README.md). `AircraftLights.attach`
now extracts the posed aircraft triangles once and uses the same array for both wing
skins. The prior implementation extracted them twice before attaching any kit nodes.
No cache, persistent memory, asynchronous state, physics or visual change is introduced.

## Measurement and parity

The previous Home attribution measured approximately 202–219 ms in aircraft lighting.
The retained [probe](lights_probe.gd.gz) compares original and candidate constructors
on the same aircraft, removing/freeing each kit before the next. Five alternating
reference/candidate pairs per visual family compare serialized child names, transforms,
visibility, mesh arrays, shader source/uniforms, light properties and crash attachment
metadata. All 25 pairs are byte-identical. Geometry extraction is outside physics.

| Visual family | Original median (ms) | Candidate median (ms) |
| --- | ---: | ---: |
| Stik | 284.915 | 262.783 |
| Extra | 130.855 | 128.695 |
| P-51 | 304.963 | 292.956 |
| Avanti | 39.976 | 37.523 |
| Timber | 215.690 | 202.936 |

[Raw measurements](lights-bench.json) are phase attribution on Windows, pinned Godot
4.7.2, Dummy audio and headless rendering. First pairs include cold resource work;
models are reused within each family. This small removal of redundant work is retained
with exact output parity. It does **not** establish a 5% full-loading gain or close
Home/first-Fly budgets. Do not compare these absolute phase timings to earlier runs
on a different source snapshot or under different host load.

The existing night-kit suite passes 30 checks, including all catalog models, mode
switching, landing-light placement and crash attachment. The native Compatibility
capture suite passes **123 GPU checks** on RTX 3090 / driver 610.88: dusk dark blocks,
upper/lower strip visibility, distance/FOV/aspect sizing and opaque occlusion.
[Capture summary](captures/summary.json), images and logs are retained. These tests
and a spot inspection do not replace a pilot's night-flight readability acceptance.

## Merge integration and package checks

This turn began with an unfinished merge of `ac5f2b0e` and `a3a350ed`. Two conflicted
files prevented parsing. Resolutions preserve both branches' intent:

- Export uses the new `Catalog.airplane_visual_families()` helper, retains the verified
  HX-700 authoring bytes required by rotor profiles, and preserves fixed-wing proofs.
- Field-pack verification retains lake-bake validation and both scenery branches,
  while adding the incoming three-source/150-clump imported-grass limits and texture
  checks to the existing source-mesh/material and triangle-budget checks.

Only those two files were staged to mark their conflicts resolved; the merge was not
committed. Other staged changes and concurrent controller work were preserved.

| Check | Result |
| --- | --- |
| Editor import after resolution | Pass, no engine errors |
| Catalog / model manifests / package proofs | 98 / 75 / 29 passing checks |
| Grain / world field lighting | 7 / 64 passing checks |
| Model manifest generator freshness | Five families current |
| Final Windows release export | Pass, no engine errors |
| Empty-project field pack, scenery on/off | Both pass, imported/procedural grass plus lake/cues/trees |
| Exported rotorcraft / night-kit checks | 8 / 30 passing checks |
| Actual release executable | 1 s / 240-tick finite trimmed-flight trace passes |

[Package commands and results](package-checks.json) pin the empty-project checks.
The pinned editor engine copied beside the exporter's DLL runs external test scripts
against the actual embedded pack; the executable itself runs the application's trace
entry point. The probe engine is a test harness, not a shipped file. This was a manual
Windows export, not the full multiplatform `app/export.sh` or qualified release provenance.

## Lifecycle finding and exclusions

The verbose source run in `before.log.gz` reproduced the two exit warnings and identified
the retained objects as **AudioStreamMP3 and AudioStreamPlaybackMP3**, one reference each.
The only production MP3 source is the lake ambience in `water_effects.gd`. This narrows
investigation to audio shutdown; it does not prove a production leak or its cause.
No audio lifecycle fix is claimed in this slice.

`after.log.gz` failed before Home because concurrent controller edits temporarily
caused a parse error in the shared app. It is excluded from timing. Lifecycle verification
therefore uses the already exported artifact. The initial `pack-lifecycle.json` completed
20 cycles, but PowerShell's GUI launch did not retain stdout/exit status reliably; it is
an observation only. The subsequent subprocess run records complete output and exit status.

The [verified 20-cycle report](pack-lifecycle-verified.json) completed with exit zero
and no engine errors. Every cycle returned to 550 Home nodes, reached 880 flight nodes,
reported zero orphan nodes and drew unpaused at tick 12. The [command ledger](lifecycle-command.json)
pins the exact embedded package run. Both MP3 objects were again retained at exit;
stable node counts do not establish stable resource/RSS memory. These Home/Fly cycles
do not cover Workshop, reset, 50-cycle acceptance or the 30-minute soak. The single
4.939 s Home observation is not a five-run cold-loading qualification.

## Reproduction and remaining gates

[Manifest](manifest.json) pins owned source changes, original/candidate probe scripts,
engine and exported executable/DLL hashes, raw logs, captures and reports. The source
tree was being edited concurrently: this is not a complete frozen export-source manifest.
Reproduce the constructor probe with the three retained `.gd.gz` files extracted beside
one another outside `app/`, using `--headless --path app --script <lights_probe.gd> -- <new.json>`.
The existing capture and loading commands are in their scripts and retained package ledger.
Do not use the before/after observations as a paired full-workload comparison.

Home ≤5 s, Fly ≤2 s, controlled native performance, audio shutdown, Workshop/reset
lifecycle coverage, 50 cycles and a 30-minute soak remain open. No golden flights were
re-recorded and no generated aircraft data was hand-edited.
