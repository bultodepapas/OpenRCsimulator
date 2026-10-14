# VQ-01c — measurement foundation and first Windows evidence

2026-10-14. **Implemented measurement tools; baseline qualification remains open.**
Runtime source: `72403977`. Godot 4.7.2-stable, native Windows x86_64. No runtime,
physics data, shader, asset, preference or golden-flight change was made by this slice.
The [tool contract and commands](../../../../research/performance/README.md) own reproduction.
The [implementation sequence](../../../plans/global-performance-visual-quality.md) still owns adoption order.

Follow-up: [actual Home/Fly loading and the DT-11a lake geometry reuse repair](loading/README.md). The original baseline below remains a dated pre-repair record; its manifest is unchanged.

## Delivered and verified

- Complete session/input callback followed by the guarded simulation callback, with
  production field, lake and 4,980 scenery proxies; bounded per-tick raw measurements.
- Alternating observer-on/off processes, numeric trajectory fingerprints, strict report
  validation and retained failures. Direct reducer calls also reject missing identities.
- Native frame reduction that separates collection integrity, active flight, duration
  eligibility and pacing gates. Paused flights, zero-progress samples and short smoke
  runs cannot qualify performance. Logs are inspected even when process exit is zero.
- Read-only [texture inventory foundation](../VQ-02a/README.md), independently useful
  while native/pilot acceptance remains open.

Verification: **44 Python tests pass**, GDScript probe parses, **8/8 real probe guard
checks pass**, existing frame collector **43/43** and simulation **11/11** checks pass.
The guard run uses disposable external scripts to prove rejection of pause, missing
input sampling, an exact stop boundary and an observer that changes controls.
[Guard results](probe-guards/verification.json) and [check logs](checks/) retain proof.
The [final runner smoke](runner-smoke/session_baseline.json) also passes both observer
modes after metadata/reducer hardening, including hashes of the console launcher and
the actual engine executable. Its eight sample ticks are a software check only.
No full `app/test.sh`, capture suite, package/export or physical validation is claimed:
the production tree was unchanged, and the new tools live outside `app/`.

## CPU attribution

[Campaign](cpu-trim/session_baseline.json), [per-run reduction](cpu-summary.json).
Three aircraft × three alternating pairs × two observer modes = **18 complete runs**.
Each used 2,400 warmup + 14,400 measured ticks. All **nine pairs** matched fingerprints,
world identities and tick/input counts. These durations are simulated time, not a
wall-clock render qualification protocol. The fixed input is trimmed straight flight,
not an owner-flown circuit, takeoff, landing or high-load P-51 acceptance.

| Aircraft | Complete callback p50 across three runs, µs | Complete callback p95, µs |
| --- | --- | --- |
| Stik | 1107 / 890 / 741 | 1568 / 1366 / 1390 |
| P-51 | 1048 / 912 / 1031 | 1790 / 1277 / 1550 |
| Timber electric | 1231 / 1351 / 1446 | 1973 / 1865 / 2104 |

These are development-host observations, **not Gate P acceptance or a speedup**. The
wide run variation exceeds small optimization effects. Observer-on minus observer-off
total-loop differences include negative values; incremental observer cost is not yet
resolved above host variation. Do not subtract these differences from individual ticks.
Numeric agreement establishes that the observer preserved the recorded simulation
sequence, not that timing was stable or all session/contact histories were identical.

The separate [case smoke campaign](case-smoke/session_baseline.json) ran 24 warmup +
240 sample ticks for maneuver, runway and lake cases. **16/18 processes succeeded**;
the two P-51 runway requests were correctly refused because that product start is not
supported. The campaign remains failed, with those refusals retained. This is a coverage
limitation, not evidence that the P-51 suffered a simulated crash. Supported smoke cases
are not substitutes for long-flight qualification.

## Native frame observations

[Native reduction](native-summary.json), [raw reports and logs](native/).
Three fresh processes, 10 seconds warmup + 60 seconds sample, current default Stik,
1280×720, Compatibility, 4× MSAA, VSync enabled, explicit `--max-fps 60`, Dummy audio.
The app logger excluded startup. No screenshot/readback or CPU benchmark ran alongside
these samples; the desktop was not reserved from user/background activity.

| Run | p95 / p99, ms | Simulation/wall ratio | Result |
| --- | --- | --- | --- |
| 1 | 29.704 / 31.289 | 1.00029 | Active flight; misses 18/25 ms pacing limits |
| 2 | 26.191 / 30.831 | 0.71260 | Paused during the run; ineligible |
| 3 | 29.824 / 30.761 | 0 | Paused at tick zero; ineligible |

All three collections completed; **none qualifies performance**. The collector's
`complete=true` is not a flight pass. Pause cause was not instrumented; focus loss is
a possible explanation, not an established diagnosis. Keep the product's focus safety.
Runs 1/3 logged 24 ObjectDB instances retained at exit; run 2 did not. The preceding
5-second [smoke log](checks/native-smoke.log) additionally reported one resource still
in use and 26 instances despite exit zero. Do not generalize that smoke error to all
three long logs or attribute the leak to frame collection without a verbose comparison.

Host: AMD Ryzen 9 5900X, 24 logical processors; RTX 3090; NVIDIA OpenGL 610.88 / Windows
driver 32.0.16.1088; Windows 11 Pro build 26100, Balanced power plan. Windows reported a
3840×2160/120 Hz NVIDIA display and a 1920×1080/60 Hz virtual display. The actual output
display was not frozen, so DT-01 display qualification remains open. Native source/editor
execution is not acceptance of an exported package or a minimum-GPU profile.

## Remaining acceptance and next implementation action

| Finding / gap | Required next action and owner |
| --- | --- |
| Native pacing miss; two paused samples | VQ-01c / DT-01/10a: reserve a foreground host/display, retain focus/pause cause and repeat valid runs; separate VSync/cap diagnosis from scene changes |
| CPU variation larger than the effect | VQ-01c / H: isolate background load/power behavior, then attribute session/collision versus integration cost; retain Gate P's existing regime/statistic |
| Exit retention warnings/error | VQ-01c / runtime owner: verbose matched normal-exit/logger comparison before changing ownership/lifecycle |
| Setup timings omit scene/render/Home/Fly | Follow-up [actual UI loading evidence](loading/README.md) now covers three before/after cycles; cold Home and first Fly targets and package acceptance remain open |
| Incomplete flight/camera/weather matrix | VQ-01c/d / CAM/L/FW: complete long workloads and prepare matched visibility motion evidence; owner flight remains independent |
| Packages and other OS/hardware | DT: qualify exact exports on named hosts; Mac/Linux are not inferred from Windows |

No candidate was adopted from this initial campaign. The subsequent
[DT-11a loading investigation](loading/README.md) independently attributed and implemented
a bounded render-geometry cache; no LU-10-R1, shader or appearance change is adopted. VQ-01c stays open until its missing coverage, observer-cost
uncertainty and native/loading evidence are resolved. VQ-01d remains the next dependent
package; the import inventory alone does not authorize material edits.

## Artifact identity

[Evidence manifest](evidence-manifest.json) records source commit, runtime diff, both
the Windows console launcher and actual engine binary hashes, tool hashes and raw-file
hashes. A concurrent commit incorporated part of the tooling during this work; the
measurement commit is retained separately from the later retention HEAD, and `app/`
has no intervening changes. Raw reports were not rewritten when reducers were hardened;
the CPU summary revalidates all complete pairs with the final validator.

Raw JSON samples use deterministic gzip (`mtime=0`); decompressing a `.json.gz` restores
the exact original bytes recorded in the manifest. Summary JSON and logs remain plain
text. Canonical runners regenerate uncompressed reports; gzip is storage only. No
timing sample, fault, unsupported case or failed native qualification was discarded.
