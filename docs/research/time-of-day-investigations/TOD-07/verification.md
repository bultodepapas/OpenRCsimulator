# TOD-07 — Integration verification

Status: all app-check blocks pass across split execution; focused checks and Linux export pass, 2026-10-10. See [rendered evidence](README.md) and the [owning plan](../../../TIME-OF-DAY-PLAN.md).

The delivery selects a fixed local civil time before flight. Legacy daylight remains the default. No physics, aircraft data or simulation module changed. Lighting owns separate configuration and scene resources; Home, direct flight, traces and captures use that selection.

## Checks

| Check | Result |
| --- | --- |
| Pre-change `app/test.sh` at `7fe3d84` | Exit 0; 143 GDScript test files plus all integration/golden/frame-rate checks |
| Post-change `app/test.sh` | First run exited 143 (SIGTERM) during the atmosphere CLI block, after all 148 GDScript programs and preceding integration blocks passed; all remaining blocks rerun successfully, exit 0 |
| Configuration / independent solar / actual-Main lifecycle | 75 / 42 / 9 checks, zero failures; [TOD-02](../TOD-02/README.md) |
| Shared rendering parameters | 203 checks, zero failures across 24 hours, duplicated ground/grass materials, contact cues, finite zenith/horizon handling and resource isolation |
| Real-entry-point CLI tests | 5 tests pass: valid/invalid selection, full JSON input, four-aircraft physics equality, reference/custom atmosphere and seeded turbulence, 30/60/144 fps parity |
| UI / persistence | New time-of-day test and existing weather, slider and atmosphere suites pass; [keyboard/radio/mouse and EN/ES 800×600 evidence](../TOD-06/README.md) |
| Static Godot skill linter | Before and after: zero errors, the same 12 warnings from existing test fixtures |
| Scene smoke with deterministic input fuzzing | All three `.tscn` scenes pass, zero errors; engine warning diagnostics remain, so this is not a warning-free claim |
| Native Linux export | Release export succeeds; embedded pack runs in an empty working directory, without a source-project `--path`; [result](export-check.json) |

The CLI comparison removes only the new `visual_context` header and existing wall-clock `created_utc` header. Every other metadata field and every physics CSV row must agree. The exported binary repeats legacy/noon/night with identical physics, records the complete astronomical context, and rejects an invalid hour before writing a trace. It does not require network access or a runtime astronomy service.

The first post-change process was terminated by SIGTERM; the cause was not established. Verification resumed from the beginning of the interrupted atmosphere CLI block and included every remaining command from `app/test.sh`, with its original `set -euo pipefail` and engine-error checks. This is split execution, not a claim that one uninterrupted post-change invocation exited zero.

Archived logs: [pre-change baseline](baseline-test.log.gz), [interrupted post-change run](post-change-partial.log.gz), and [successful remainder](post-change-remainder.log.gz). [Machine-readable results and checksums](check-summary.json) record the split. The remainder passed atmosphere, TOD CLI, coupled shaft, four trimmed flights, logging, frame-rate independence, wash/swirl and both ground-contact verification blocks (E5a: 21 + 63 checks; E5b: 125 checks).

## Reproduction

```sh
bash app/test.sh
python3 app/tests/test_time_of_day_cli.py
python3 /home/bulto/.codex/skills/godot/scripts/debug/lint_project.py app --pretty
```

Use the repository's existing Linux export preset and pinned templates. The smoke accepts the resulting binary at any path:

```sh
python3 research/time-of-day/tod-07/check_export.py \
  --binary /absolute/path/openrc-simulator.x86_64 --out /tmp/tod-export-check.json
```

The integration run exported to a temporary directory, preserving the existing `dist/` artifacts. The build identity is the current dirty `git describe`, populated through the same `OPENRC_BUILD_*` environment variables as `app/export.sh`. This is a Linux pack/runtime check, not native Windows/macOS acceptance or a release publication.

## Remaining acceptance

Rendered evidence uses pinned Compatibility on llvmpipe. Target-GPU cost, absolute sky brightness, pilot attitude recognition and night appearance on the owner's display remain unvalidated. Authored sky/energy curves are labelled estimates. Moon/stars, aircraft/field lamps, paused time editing, progression and visual checkpoint playback are later plan steps; none are claimed by this fixed-time delivery.
