# Verification Record — OpenRC Afterburner Starter

*Archived 14 November record. Relative document links are adjusted for this archive location; technical results and commands retain their original meaning. Follow the current top-level guide for new test routing. Original engine reports and logs are unchanged.*

**Date:** 14 November 2026
**Reviewed source:** `f41d0fd2eb5483c609bcd858bcf22776eb311e14`
**Executed engine:** `4.8.beta2.official.cafc17a19` on Linux x86_64

## Result and scope

The standalone core passed **97 checks, 0 failed**. The independent visual-state suite passed **14 checks, 0 failed**. Import and a short headless fixture runtime completed without reported engine/script diagnostics. An independent reviewer repeated the final core suite on a disposable copy and found no remaining blocker in its stated standalone scope.

This evidence supports the tested software contracts only. It does not establish an installed OpenRC afterburner, a rendered flame, GPU shader compilation, sound quality, target-hardware performance or physically calibrated flight behavior.

## Retained evidence

The original checked-run JSON and log files are preserved unchanged under the following package paths. Their embedded absolute paths identify the original execution environment; they need not exist on the reader's machine.

| Evidence directory | Actual command behavior | Result |
|---|---|---|
| `evidence/core-final/` | Execute `res://tests/test_afterburner_core.gd`, headless, Dummy audio | 97 checks, 0 failed; error/warning counts 0/0 |
| `evidence/visual-import/` | Headless editor import and quit | Complete; error/warning counts 0/0 |
| `evidence/visual-state/` | Execute `res://visual/verify_visual.gd`, headless | 14 checks, 0 failed; error/warning counts 0/0 |
| `evidence/visual-runtime/` | Run `res://visual/visual_fixture.tscn` for eight headless iterations | Complete; error/warning counts 0/0 |

Each `report.json` records the command, start time, completion status, process exit, parsed diagnostics and log SHA-256. These are functional-check receipts, not repeatable performance measurements. Their elapsed times must not be used as a target-host CPU/GPU budget.

The source-pinned downloader verified the engine's official archive/executable hashes. The executed Linux binary SHA-512 is:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The [source manifest](source_manifest_2026-11-14.json) binds that identity to the inspected source and its referenced file hashes. The full application was not imported or flown; the inspected checkout was sparse.

## Core checks and independent review

The test harness uses a test-only scalar RK4 integrator and independent closed-form exponential response/fuel expectations. It exercises numeric input rejection, configuration gates, read-only sampling, repeatable stage evaluation, boundary-proposal purity, ignition timing, hysteresis, rearming, high-RPM source cutoff, soft-tail fuel consistency, off-axis moments, disabled/cosmetic zero increments, checkpoint repeatability and separate engine state.

The independent review produced useful counterexamples before handoff:

- Unsupported `%g` formatting in a test failure label could cause script errors despite a zero process exit. The test labels were corrected, and clean diagnostics became part of the completion check.
- Finite but extreme force/arm inputs could overflow into a nonfinite load. The core now rejects that output rather than returning success.
- Re-requesting during a soft extinction tail could introduce a cold-ignition discontinuity. It now resumes the existing burn continuously. At illustrative intensity 0.8, the 30 N / 0.005 kg/s profile preserves 24 N / 0.004 kg/s on resumption.
- Deliberately corrupting an analytical expectation caused the harness to fail. That mutation was confined to a disposable copy and is not in this package.

The final 97-check revision was independently rerun. The clean final run receipts are bundled; earlier development failures and temporary counterexample copies are not part of the deliverable. No physical aircraft claim follows from these checks.

## Visual checks and display limitation

The 14 visual-state checks cover material isolation, timestamp pause/restore behavior, continuity at the 1024-second phase boundary, very large finite timestamps, invalid input, clamping/reset, finite bounds and shadow settings. They establish script/resource behavior under the headless renderer.

A local graphical-launch attempt could not open a display because this execution environment denied display-server socket creation. No rendered screenshot was produced. No GPU shader compile or visual judgement is claimed. The attempted display-server tooling is not bundled, and no access controls were altered.

The following remain open for the reusable visual component and the real aircraft:

- Successful GPU compilation on Compatibility, Mobile and Forward+ as applicable.
- Correct tailpipe placement and +Z/−Z conversion under actual parent transforms.
- Day/night appearance; aft, side and flight-line readability; occlusion and transparent sorting.
- Pause/reset/seek, fast translation and rotation, and any optional particle history.
- Cost and frame pacing on named target hardware at 1920×1080.
- The fixture's proposed fixed-time capture command.

## Reproduce with the project's checked runner

Substitute the three absolute paths below. Use the inspected checkout's `tools/godot/run_checked.py`; the package does not vendor a competing runner.

```sh
export AFTERBURNER_REPO="/absolute/path/to/OpenRCsimulator"
export AFTERBURNER_GODOT="/absolute/path/to/Godot_v4.8-beta2_linux.x86_64"
export AFTERBURNER_PROJECT="/absolute/path/to/extracted-package/prototype"

python3 "$AFTERBURNER_REPO/tools/godot/run_checked.py" \
  --label afterburner-core --timeout 30 \
  --out-dir /absolute/path/to/new-evidence \
  --require-text 'AFTERBURNER_CORE: 97 checks, 0 failed' -- \
  "$AFTERBURNER_GODOT" --headless --path "$AFTERBURNER_PROJECT" \
  --audio-driver Dummy --script res://tests/test_afterburner_core.gd

python3 "$AFTERBURNER_REPO/tools/godot/run_checked.py" \
  --label afterburner-visual-state --timeout 30 \
  --out-dir /absolute/path/to/new-evidence \
  --require-text 'AFTERBURNER_VISUAL_CHECKS 14 checks, 0 failed' -- \
  "$AFTERBURNER_GODOT" --headless --path "$AFTERBURNER_PROJECT" \
  --audio-driver Dummy --script res://visual/verify_visual.gd
```

For a fresh extraction, first run the headless import command in the [package guide](../README.md). Inspect the checked-run result and logs, not only a shell success code. Repeating a headless run cannot close the graphical or listening gaps.

## Production acceptance still required

The full test matrix is in Sections 12–13 of the [implementation plan](../2026-11-15/handoff.md). The next implementation must supply evidence for:

| Boundary | Required evidence before claiming it complete |
|---|---|
| Original dry behavior | Exact accepted trajectory/replay for disabled and cosmetic modes; retain original arithmetic path |
| Complete physical integration | Gross thrust and moment, preserved inlet momentum, shared fuel derivative, mass/CG/inertia, source cutoff and fuel-exhaustion event remainder |
| State/input contract | Versioned initialization, validation, input indices, logging, checkpoint restore, rollback and exact replay |
| Native backend | Explicit pre-install refusal/reference selection until a supported native port passes parity requirements |
| Controls | Actual keyboard/gamepad/radio routing, mapping conflicts, profile migration and release-to-rearm after focus/device recovery |
| Presentation | Actual jet attachment, accepted/interpolated clock, renderer/quality tests, lifecycle and culling |
| Audio | Licensed asset selection, auditioning, installed-bank mix, causal delayed one-shots, travel time, Doppler once, directivity and headroom |
| Aircraft/Workshop | Authored schema/generator changes, separate configuration identity, save/load/trials and second-aircraft binding |
| Realism | Matched engine/installation measurements, stated uncertainty, operating domain and held-out comparison |

The zero increments in the standalone disabled/cosmetic tests are not a full production no-op proof. Adding `+0.0` can change a `-0.0` representation. Bypass the augmentation accumulation when absent, and demonstrate exact baseline replay in the integrated simulator.

No sound samples were auditioned or imported, no production settings were changed, and no release was published. The package is ready to serve as the researched implementation starting point; the production acceptance work above remains explicit.
