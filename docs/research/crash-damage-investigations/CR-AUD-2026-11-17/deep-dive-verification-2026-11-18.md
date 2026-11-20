# Verification record for the second collision investigation

**Date:** 18 November 2026, America/Bogota. This is a separate campaign from the [17 November verification record](verification.md). Its counts must not be substituted for, or silently added to, the original suite totals.

## Source and runtime identity

The continuation started from the published audit commit `1effa267c519526156e9aefbef63d344102bc989` on `audit/collision-damage-2026-11-17`. A fresh isolated sparse checkout supplied the application, tools, audit documentation, and required asset metadata; the engine import hydrated the assets needed by these probes. The application code remained unchanged throughout execution.

| Scope | Tree SHA at both original application baseline and continuation start |
|---|---|
| `app` | `f72e113b9f0cc068579c6c5d7cf5a216a3e67fac` |
| `assets` | `3ed558d2a5f37ae24e784436c9def5841d7382ad` |
| `tools` | `95d35ed671a2a32919ffadc13036c66e240ab2ec` |

The original application baseline is `a7de9b35676d891bc2034cc344b910d9e1ef9c61`. The tree comparison proves that the first audit commit changed no code in these scopes. [Provenance](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/provenance.json) records both revisions, runtime identity, classified run summaries, and counts. [Setup](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/setup.json) records the verified binary's source and availability checks.

**Engine:** `4.8.beta2.official.cafc17a19`, pinned Linux x86_64 Godot binary. **SHA-512:**

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The executable was copied from an available local checkout and independently checked against that exact pinned digest before use. This does not claim a newly compiled engine or a different engine version. The shared test pool was unavailable because its local configuration was absent; the checked local runner was used with isolated XDG profiles and sequential engine jobs. No graph/simulation MCP capability was available. Helpers performed source review and authored narrowly scoped draft files; the lead inspected the drafts and owned all engine execution. The repository-prescribed helper model/reasoning settings were requested, not independently attested by a runtime metadata probe.

The fresh editor import completed successfully in **364.31 s**, with zero checked errors and **eight checked OBJ/material import warnings**. It is setup evidence, not a physics test. Its [raw log](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/setup/import/engine.log) and [report](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/setup/import/report.json) are retained. Runtime duration is not a performance benchmark: cache hydration, startup, and this host's characteristics differ from a player's steady-state scene.

## Final executed evidence

| Run | Checks | Passes | Desired-behavior failures | Checked engine errors / warnings | Finding |
|---|---:|---:|---:|---:|---|
| [Delayed helicopter frames](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/probes/heli-delayed-frames/report.json) | 90 | 74 | 16 | 0 / 0 | CR-AUD-16 |
| [Quad crash checkpoint](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/probes/quad-crash-checkpoint/report.json) | 15 | 13 | 2 | 0 / 0 | CR-AUD-17 |
| [Ground/scenery ordering](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/probes/contact-order/report.json) | 11 | 10 | 1 | 0 / 0 | CR-AUD-18 |
| [Crash pause log, corrected fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/probes/crash-pause-log/report.json) | 15 | 12 | 3 | 0 / 0 | CR-AUD-19 |
| [Quad obstacle aftermath](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/probes/quad-obstacle-aftermath/report.json) | 32 | 31 | 1 | 0 / 0 | CR-AUD-20 |
| **New product-probe total** | **163** | **140** | **23** | **0 / 0** | **Five records** |
| [Existing helicopter visual control](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/controls/existing-heli-crash-visual/report.json) | **33** | **33** | **0** | **0 / 0** | Surrounding regression control |

Each final product probe reaches its completion marker and deliberately exits 1 because it asserts desired behavior that the baseline violates. `run_checked.py` therefore reports `ok: false` for those runs. That is preserved accurately; it is not relabeled as a green test. The existing control exits 0.

The 23 failed checks are correlated assertions within five scoped counterexamples. For example, the helicopter test checks both the raw spin vector and the released velocity for each moved blade. A control, setup assertion, and physical invariant are not independent bugs merely because they are separate checks. Counts communicate what ran, not severity or statistical confidence.

Some final logs print existing aircraft-data notices, including an inertia comparison. The table counts the checked runner's engine diagnostics, not every string containing the English word “warning.” The original text is retained so this distinction is reviewable. No claim of completely notice-free output is made.

## Test construction and independent controls

### Delayed helicopter release

The oracle is geometric covariance, not a second copy of the implementation's stale-world-frame expression. Translating the whole attached assembly must not change spin-relative velocity; rotating it must rotate the vector. Stock authored blades are used, but severity, shaft speeds, transform changes, zero core velocity, and zero scatter are supplied isolation conditions. The scheduler and declared energy caps are included. No Godot physics frame is used to generate the prescribed trajectory. Thus the result qualifies a release-function reference-frame defect, not general simulated crash dynamics.

Unchanged-pose and transported-zero-spin controls pass. All four delayed blade groups activate in each case. The existing `test_heli_crash_visual.gd` suite passes 33/33, showing that this missing transported-release invariant is not already established by its existing checks.

### Quad checkpoint

A real strict-mode 3 m disarmed drop generates the terminal event. The early checkpoint is read inside the actual kernel event callback and restored without modification. Its kernel is byte-identical to the post-tick kernel. Healthy restore and completed-crash restore controls isolate the incomplete enclosing session metadata. Resume becomes allowed, but the motor-cut latch stays set. No existing UI save behavior or restored powered flight is claimed.

### Mixed ground/scenery incident

The fixture uses real production hull loads at the accepted reference RK stages. A matched ground-only run supplies the same pre-filter candidate and byte-identical stage captures as the combined run. Independent terminal and crossing helpers evaluate that candidate, and a separate ground-clear wall case establishes valid scenery detection. A 960 Hz run is an additional numerical control. The prescribed single-point geometry, no aero/prop/gear/gravity, no continuous block, and no finite fuel are explicit simplifications.

Crossing fractions are interpolation estimates. The current ground terminal predicate is a tick-boundary rule; the test exposes a missing mixed-candidate policy, not a measured exact ground time of impact. The 960 Hz run is not the 240 Hz trajectory's dense output. Any fix must preserve harmless soft contacts and state its chosen arbitration contract.

### Fixed-wing pause and actual recording

The corrected fixture preserves the ordinary coupled-stage state layout and real logger/reader. Gravity is disabled, the hull is a synthetic point, and the starting speed is 100 m/s. An ordinary staged-reason pause verifies the recording path before the accepted wire strike. The complete readable `.orfl` contains a pause at the crash tick whose reason is empty. The callback separately observes zero contact/damage count before they become one each.

The [recording](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/recordings/fixedwing-crash-pause.orfl) is retained. Read it with the repository's `app/tools/flight_log_cli.gd`; it is an OpenRC binary recording, not a JSON document. The completion/readability assertion is part of the executed probe. No corrupted fixed-wing checkpoint is alleged.

### Continuing quad motion

The graded quad retains ordinary gravity and aerodynamics. Its accepted initial state is disarmed with stopped shafts, isolating frame contact from prop-disc effects. Four 120-tick cases compare a synthetic wall at 3 and 9 m/s with matched no-wall controls. The 3 m/s contact bounces. The terminal 9 m/s frame crosses the entire box, and its final recorded position/velocity match the clear control. The probe distinguishes CG velocity from contact-point velocity and projects the rotated frame extents independently.

Solid containment after a terminal strike is a proposed product invariant. The current law does not promise calibrated terminal restitution. No actual scene render is claimed; source inspection connects the accepted motion to the activity's continued posing of the original quad.

## Unsuccessful attempts retained separately

| Attempt | Outcome | Treatment |
|---|---|---|
| [Helicopter draft parse](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/earlier-attempts/heli-parse/report.json) | The authoring draft used an unquoted reserved `class` dictionary key; two checked errors, no completed probe | Audit authoring error. Exact prior script retained; excluded from product counts. |
| [First pause-log fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/earlier-attempts/pause-no-contact/report.json) | Five accepted ticks but no collision; 15 reported checks, five failures, zero checked engine diagnostics | Inconclusive fixture, not five product failures. Exact prior script and recording retained. |
| [CSV diagnostic of first recording](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/runs/diagnostics/pause-v0-csv/report.json) | Real reader export succeeded with zero checked diagnostics; trace showed small negative-East motion | Fixture diagnosis, not a product test or additional finding. |

The first pause fixture indexed its wire only in East cell 0. Ordinary coupled stage forces moved the synthetic hull point slightly into negative East, where the broadphase queried East cell -1. The box bounds span both cells. Replacing the handmade bins with `CollisionWorld._build_bins` corrected the setup. The attempted `model.loads` override also did not override the active joint `model.stage`; the final fixture removes that misleading stub and explicitly retains ordinary coupled loads.

The prior [helicopter parse script](evidence/round2/earlier-attempts/heli-delayed-frames-v0-parse-failure.gd), [pause script](evidence/round2/earlier-attempts/crash-pause-log-v0-no-contact.gd), [first recording](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/earlier-attempts/pause-recording-v0/fixedwing-crash-pause.orfl), and [CSV trace](evidence/round2/earlier-attempts/pause-recording-v0/trace.csv) make those corrections inspectable. The fixture bug is not attributed to production world construction.

## Reproduce

Use the audit branch with repository dependencies/assets available, and follow the repository's Godot import and checked-execution instructions. Import first if the checkout is fresh; a missing imported asset is not a meaningful collision result. Supply the exact pinned Linux x86_64 engine or obtain it with the repository downloader. The convenience launcher rejects a different SHA-512 and an existing output directory.

From the repository root:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/run_probes.py --list
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/run_probes.py --out "$PWD/tmp/collision-audit-round2-review"
```

To reproduce just the recording case in another fresh directory:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/run_probes.py crash-pause-log --out "$PWD/tmp/collision-audit-round2-log-review"
```

The launcher runs sequentially, isolates each profile, passes the required completion marker, creates a fresh recording directory for the pause probe, and writes a reproduction summary. On this baseline, expect nonzero status from all five probes and the aggregate launcher. Inspect each checked report and assertions: a new parse error or timeout is not equivalent to reproducing a known behavior failure.

The launcher was syntax-checked and its listing/path resolution checked after packaging. The raw evidence was produced with the equivalent explicit checked-runner commands recorded in each `report.json`; the packaging step did not rerun the entire campaign through the new convenience wrapper. It does not include the old inconclusive drafts in its default run list.

To inspect the saved recording independently, use a fresh checked-runner output path and the repository reader:

```bash
python3 tools/godot/run_checked.py --label round2-recording-reader --timeout 120 --out-dir tmp/round2-recording-reader -- .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app --audio-driver Dummy --script res://tools/flight_log_cli.gd -- --log="$PWD/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/recordings/fixedwing-crash-pause.orfl" --csv="$PWD/tmp/round2-recording.csv" --report="$PWD/tmp/round2-recording-report.json"
```

That last command is a reviewer instruction, not a claim that an additional final-recording CLI run was executed in this campaign; the real reader already ran inside the final probe.

## Packaging, integrity, and limits

The five retained probe files are byte-for-byte copies of the final executed drafts. Comments describing them as drafts reflect their authoring stage and have deliberately not been rewritten after execution. Raw checked reports retain the original workspace paths and command arguments. Adjacent `observations.json` files are decoded copies of the machine-readable JSON emitted in the corresponding raw logs; they are convenience views, not replacement evidence.

The [manifest](evidence/round2/manifest.json) lists SHA-256 and byte length for every retained round-two artifact except itself, plus the three continuation documents. [Provenance](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round2/provenance.json) classifies setup, final probes, an existing control, authoring failure, inconclusive attempt, and diagnostic. The original evidence manifest remains the dated first-campaign record.

Only audit documents, probes, evidence, and an optional reproduction launcher belong in this change. No application source, asset, generated golden, or engine binary is published. Three UID files generated by import were removed from the working tree because they were created by this run and were not part of the task.

This continuation did not rerun the original 53-suite campaign, run full CI, build the native extension, measure graphics timing, observe a rendered impact, or validate material thresholds. It does not prove stock-flight frequency for the isolated cases, a universal 300 km/h crash envelope, or realistic explosion/fracture behavior. Those remain separate gates in the original plan and the [continuation plan](deep-dive-plan-2026-11-18.md).
