# VQ-01c — all-airplane runtime screen, 2026-10-24

All nine fixed-wing catalog configurations were launched through the native Home
UI and exercised separately through the normal engine input path. The X-Cell
helicopter is a separate experimental vehicle and was not included. This screen
finds uneven performance; it does not qualify all aircraft as smooth or physically
validated. No new production, physics, model or shader changes were made.

## Native frame screen

[Machine-readable results](all-planes.json) retain configurations, source/artifact
hashes, validity, diagnostics and local raw-evidence paths. Windows, Godot 4.7.2,
Ryzen 9 5900X, RTX 3090, Compatibility, 1920×1080, 4× MSAA, VSync 60 Hz;
Electrical Storm, airborne start, keyboard selected, Dummy audio driver. Each
primary sample has 10 s warmup and 60 s collection with frame diagnostics enabled.

| Airplane | Mean FPS | p95 frame ms | p99 frame ms |
| --- | ---: | ---: | ---: |
| Ugly Stick | 59.98 | 17.82 | 18.67 |
| Ugly Stick · MAX-61FX | 56.31 | 24.28 | 30.70 |
| Ugly Stick · MAX-55AX | 45.26 | 40.60 | 59.44 |
| Ugly Stick · FS-64V | 49.89 | 29.47 | 43.95 |
| Extra 300S | 56.81 | 23.32 | 51.77 |
| P-51D Mustang | 28.92 | 67.14 | 75.71 |
| F4U Corsair **(Green Paradise)** | 60.00 | 17.78 | 19.22 |
| Ventage Jet | 60.00 | 17.65 | 18.46 |
| Turbo Lumber, finite battery pack | 60.00 | 17.66 | 18.55 |

Other rows use Club field. The Corsair alternative cannot be pooled into a
matched Club-field comparison. One primary sample per plane is screening, not
the required three-repeat performance qualification. P-51 advanced only 55.89
simulation seconds in 60.02 wall seconds (~93.1%); it had no solver fault or
crash. A final unchanged Stik reference gave p95 17.58 / p99 18.17 ms, similar
to the initial run; this is a limited order check, not statistical repeatability.

Short `--debug --profiling` captures for 55AX and P-51 showed simulation work
dominating reported inclusive script time. The hot paths include glow
`point/evaluate` and liquid-fuel `evaluate/_coupled_response`. Their nested
totals must not be summed. These early 2 s + 8 s instrumented trajectories do
not explain the later native worst frames quantitatively. No safe high-impact
optimization was established; the solver and visual quality were preserved.

## Verification and findings

- **913 assertions passed:** catalog 107, render contract 373, propulsion 230,
  powertrain audio 45, runway fleet 132, engine sound 26; parser check passed.
  The engine-sound test now explicitly covers all nine catalog IDs, correcting
  an obsolete Stik ID and covering the P-51/Corsair special blade counts.
- **90 native engine-input assertions passed:** each plane checked its actual
  ID, active 1080p flight, pilot/chase/orbit mode, roll/pitch/throttle event
  receipt, simulation advancement and neutral release. These use injected
  `InputEventKey` events, not OS/HID delivery or input-to-photon measurements.
- Actual UI flight samples covered every plane for 6–54 simulation seconds,
  with sampled empty crash/fault states and normal focus-loss pauses. Preview
  inspection and clear-sky checks found the Jet's unusual paint consistent
  with the accepted [AV-31 model](../../../avanti-blender/AV-31/README.md).
- Two Corsair Club captures were excluded: one froze at tick 336 with
  insufficient pause history; the focus-watch repeat reported a pylon impact
  at 16.39 simulation seconds. No obstacle, pause protection or aircraft
  behavior was disabled to obtain the Green Paradise sample.
- The first completed Turbo capture logged a GLES3 shader-cache short-read
  error. An unchanged fresh retry was clean. The pinned engine's
  [cache loader and fallback](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/gles3/shader_gles3.cpp#L506-L547)
  recompile after load failure; the exact corrupt entry and its cause are
  unknown. No cache was cleared and no rendering feature was disabled.
- Powertrain-audio testing reported two ObjectDB objects at shutdown; the
  valid Corsair alternate reported 17. These are retained warnings, not proof
  of an accumulating leak or a clean-shutdown result.

C: reached zero free space during UI work; artifacts were redirected to D:.
Native samples retained only about 0.18 GiB free on C:, an environment limit,
not a proven cause of the shader error or slow frames. Full raw receipts,
profiles and the one retained screenshot are local at
`D:/OpenRCsimulator-evidence/all-planes-20261024-4049e4da/`; images were not added
to the repository. These are not a portable release qualification bundle.
Takeoff/landing pilot acceptance, long sessions, other hardware/platforms and
full visual regression coverage remain unqualified. Unrelated edits and the
existing `docs/DECISIONS.md` conflict were preserved.

Final Evidence Auditor and Good Enemy reviews found no material objection to the
changes or bounded claims. Good Enemy emphasized repeating matched slow cases
and capturing their slow frames before choosing an optimization. The P-51 and
glow-aircraft performance findings remain unresolved, not fixed by this test pass.
