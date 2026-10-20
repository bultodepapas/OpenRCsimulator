# DT-11a / L6b — avoid temporary treeline-validation allocations

2026-10-19. Official Godot 4.7.2-stable (`ed1daf0bf`), Windows x86_64 headless,
Ryzen 9 5900X. Shared-host load, power and OS caches were uncontrolled. These
measurements cover complete field validation and file loading; full startup,
Home/Fly loading, rendering throughput and FPS were not measured.

## Change and equivalence

`FieldLoader._validate_tree_positions()` now prepares its three axis labels once
per call and uses a `Vector2i` duplicate key instead of formatting a three-number
string for every position. The existing guard requires finite horizontal offsets
within ±1,500 m and down exactly zero before keying. At the 0.25 m grid spacing,
the rounded key components fit within ±6,000, safely inside
[Vector2i's 32-bit range](https://docs.godotengine.org/en/4.7/classes/class_vector2i.html).
The omitted down component was always zero. The key retains the same `roundi`
operations and earliest-index insertion policy, including off-grid rows that
already have a quantization error.

Normalized coordinates remain float64 values in ordinary arrays. Validation
order, error text/order, acceptance, source data and placement policy are unchanged.
All temporary data remains local; no persistent cache or physics change is added.

The [runtime/test patch](runtime.patch) and [original source](reference.gd.txt)
retain the comparison. The reference matches `app/data/field_loader.gd` at
`a3df9bc0555664776d8b30e5f0a9ed402361c1b7` after line-ending normalization.
[Manifest](manifest.json) pins runtime, tests, engine, probe and fixtures.
Luna Max helpers reviewed key equivalence, edge cases and measurement guards;
the lead implemented and ran the serial campaign.

## Complete-workload measurements

Five fresh processes alternate initial variant order. Each workload has 40
alternating warmup pairs followed by 12 alternating timed batches. Batches have
eight calls for the default 1,680-tree field and 32 for the no-tree control.
`validate()` receives the same parsed dictionary; `load_from()` includes opening,
reading, JSON parsing and complete validation. Script dispatch and result
assignment are inside both timers; comparisons and hashing are outside.

| Complete workload | Reference, ms | Candidate, ms | Reduction | Process reduction range |
| --- | ---: | ---: | ---: | ---: |
| Default `validate()` | 11.032 | 9.013 | **18.3%** | 17.6–20.1% |
| Default `load_from()` | 12.163 | 10.235 | **15.9%** | 14.3–18.8% |
| No-tree validation control | 0.330 | 0.333 | -0.8% | -1.1–4.6% |
| No-tree loading control | 0.708 | 0.710 | -0.3% | -0.7–2.7% |

Values are medians of five process medians of batch means, not individual-call
latency percentiles. Each variant has 960 measured default calls and 3,840
control calls. Every default workload improves in every process, exceeding the
5% component adoption gate. The unchanged no-tree route has small mixed changes,
including unfavorable pooled medians; no control benefit is established.
This is warm CPU/file-cache evidence, not an import-cold or process-startup claim.

The probe runs copied source/data in a minimal headless project. Its default
fixture is byte-identical to the committed data; the control removes `objects`.
It verifies the 1,680-row default and empty-object control, rejects identical
variant sources, and checks source/probe/data hashes before and after execution.
The external runner independently checks the same hashes around every process.

All **55 fixture pairs** preserve complete result bytes, normalized values,
acceptance and ordered diagnostics, with unchanged inputs. Cases include mixed
numeric types/signs, tolerance collisions, positive/negative half-grid ties,
non-flat rows, huge finite coordinates, radius boundaries, malformed/non-finite
values and a duplicate at the final committed position. All **240 final-batch
output comparisons** also match the reference. Per-case result hashes remain
stable across processes. All five verified logs exit zero without engine warnings
or errors.

[Summary](summary.json), [verified commands and hashes](verified-commands.json)
and `verified-*.json`/`verified-*.log` retain the accepted campaign. Earlier
`run-*.json`/logs and [trial probe](trial-probe.gd.txt) use fixed reference-first
warmups and fewer input guards; they are retained separately and are not pooled.

## Regression checks

[Six focused invocations](tests.json) pass: field loader (178 checks), treeline
data (124), scenery loader (all checks), field surfaces (19), and treeline runtime
(28,631 headless / 31,991 native). The native checks include exact transforms and
packed instance coordinates. Four new assertions lock complete diagnostics for
tolerance collisions, signed half-grid ties, off-grid insertion and non-flat
rows. Existing admission and float64 normalization checks remain.

[Reference/mutation checks](reference-and-mutation.json) pass the updated data
test with the original loader. A [disposable first-index mutation](mutation.json)
is rejected by the new earliest-index assertion. It overwrites the stored index
after a duplicate; the old substring-only duplicate check alone accepts that defect.
[Probe guard checks](probe-guards.json) reject identical sources and a nonempty
control without creating a result file.

Field-surface and treeline integration checks emit the existing unsupported-maple
material wind warning. The original loader reproduces each warning and passes
the same checks. An initial disposable app copy lacked sibling authoring assets,
causing model-source errors in the Home/Fly part of the treeline test; that setup
run is retained as rejected. Restoring its repository asset context and rerunning
headless/native passes with only the reproduced wind warning. No such error occurs
in the shared-tree candidate checks. Full app tests and exports were not run.

## Reproduce

Use copies of the original loader, candidate, default JSON, an `objects=[]`
control and the supplied minimal [project settings](probe-project.godot). Create
a new output parent, then run the committed probe with the pinned engine:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --headless --path <minimal-project> `
  --script "$PWD/research/performance/field_validation_probe.gd" -- `
  --reference="$PWD/tmp/field_reference.gd" --candidate="$PWD/app/data/field_loader.gd" `
  --data="$PWD/tmp/default.json" --no-trees-data="$PWD/tmp/no-trees.json" `
  --output="$PWD/tmp/field-validation-new/run-0.json"
```

Repeat in five fresh processes with new output paths, adding `--candidate-first`
to odd-numbered runs. Retain stdout/stderr through exit and require exit zero,
`complete=true`, `inputs_unchanged=true`, exact comparisons and matching identities.
Run timing alone and do not import or mutate the source/data snapshot.
