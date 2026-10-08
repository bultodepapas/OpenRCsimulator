# G1b1 — Propeller range audit

**Status:** implemented and verified; offline Ct/Cp diagnostics. [Evidence and limits](../../../docs/research/propulsion/G1b1/README.md). Standard-library Python; no app, aircraft-data or force changes.

```sh
python3 research/propulsion/range-audit/audit.py /tmp/flight.csv \
  --aircraft app/data/aircraft/jensen_ugly_stik_60.json \
  --ticks 720 --assume-still-air \
  --coverage research/propulsion/range-audit/stik-coverage.json \
  --output /tmp/propeller-range.json

python3 research/propulsion/range-audit/verify.py --output /tmp/new-range-evidence
```

`--ticks` is the externally requested number of steps, excluding the initial sample. `--hz` defaults to 240. Mid-flight recordings may start at a nonzero tick. The verifier requires an empty output directory; it uses the pinned Godot, with an optional `--godot` override.

The auditor requires trace v3 metadata v2, matching exact aircraft-file bytes, finite continuous rows, known frames/timing, and an explicit still-air assumption. Trace v3 does not carry wind. It reads each input once and hashes those bytes; it refuses to overwrite an input. This is a diagnostic reader of relevant aircraft fields, not a substitute for the complete Godot aircraft loader. It assumes the loaded diameter, shaft axis and Ct/Cp tables have not been overridden in memory.

For each recorded load query after the initial sample, use the previous row's body velocity and current row's RPM. Project velocity onto the down/right-tilted shaft, then compute `J = max(u_axial, 0) / ((RPM/60)*D)`. Below 1 RPM, the propeller is stopped and J is reported as null. Negative axial flow is flagged separately from the clamped J=0 lookup. Table endpoints are inclusive; a J gap has open endpoints. Counts exclude the initial state, which is reported separately and is not a reconstructible load query for mid-flight starts.

Output includes per-table counts and first occurrences, active J range, initial operating point, source provenance and byte hashes. Reverse flow never inherits static J=0 source coverage: its clamped lookup remains visible while source support stays unknown. These are nominal queries reconstructed from rounded CSV values, not all internal RK-stage queries or exact crossing times. Counts can be rounding-sensitive at boundaries. Ct/Cp coefficient values, force floors, engine torque-curve coverage and propeller crossflow tables are outside this step.

## Source coverage

Coverage is optional; omitted information stays **unknown**. `openrc-propeller-coverage v1` binds to an exact aircraft input hash and declares `relationship` as `matched-propeller`, `borrowed-propeller` or `synthetic`. Each table entry has a source, optional `j_gaps` (null = unknown; empty = no declared gaps), and optional `source_regions`. A region carries `j_range`, `rpm_range` (null when unavailable), and source. Only regions containing the current J participate in RPM checks. Split a region around declared gaps; contradictory overlaps are rejected. These envelopes describe exclusions; their interiors are not a validated polar or uncertainty band.

[Stik coverage](stik-coverage.json) records the borrowed APC Sport 11×6 sources applied to a 12×6 Sport. The static campaign's RPM extent applies only at J=0; the runtime static coefficient was selected from the 5,954 RPM row and does not vary with RPM. The tunnel file gives a nominal 6,000 RPM in its filename but no actual RPM column/range, so its numeric RPM coverage remains null. The explicit unmeasured interval is `0 < J < 0.373`. No band is invented from nominal RPM, and the source propeller mismatch remains visible in every Stik report. A changed aircraft file requires a reviewed coverage update, not automatic rebinding.

Verification runs 20 unit/CLI tests, three mutations on disposable copies, six actual-session flights, 1,680 comparisons with direct `Propulsion.thrust_torque` queries, and the existing propulsion/trace-metadata tests. It checks recorded throttle and RPM so synchronous fixtures cannot silently fly with stale sampled inputs. All source hashes must remain unchanged throughout the run.
