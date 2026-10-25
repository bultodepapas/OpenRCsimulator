# GDU-03: launcher defaults and strict flight-log replay

2026-10-25, Windows x86-64. The existing debug bridge, flight-log CLI and
flight-test launcher all resolve their default to official
`4.8.beta1.official.4d10419ca`. Explicit engine overrides still select the requested
executable. The non-Windows paths were inspected, not qualified on another host.

The [final-core follow-up](final-core/README.md) repeats FL-04 and the actual
default-CLI exact roundtrip after the later source corrections; both pass.

| Focused check | Result |
| --- | --- |
| Existing debugctl offline tests | 22 passed, one Linux `/proc` check skipped |
| Existing flight-log Python tests | 16 passed |
| Existing FL-04 recording/replay suite, six aircraft | 3,247 checks, zero failures, both frozen and current-root source copies |
| Actual flight-log CLI with no engine override | Export and exact replay complete, 261 rows, `solver_changed=false`; CSVs byte-identical |
| Actual flight-test launcher with no engine override | Existing `modes` case valid 1/1; run receipt identifies official 4.8-beta1 |
| Unchanged 4.8 log replayed explicitly with 4.7.2 | Rejected: engine version differs |
| Frozen-copy log replayed against different raw source bytes | Rejected: solver sources differ |

The `.orfl` reader still checks the exact engine string before preparing either
exact or candidate replay. It also retains its exact source fingerprint gate.
The earlier frozen worktree has semantically identical core source after LF
normalization, but different checkout line endings; `.orfl` hashes those source
bytes exactly and correctly refused that replay. Recording against the current
root's actual bytes then passed the normal default-CLI roundtrip. No file headers,
source identities or replay checks were relabeled or loosened. This remains
separate from the [GDU-04 frozen-checkpoint experiment](../numerical/README.md).

The only additional code change is in `tools/debug/test_debugctl.py`: the fake
bridge now accepts a connection that intentionally sends no request during a
port-availability probe, and the CSV assertion closes its read handle. These
correct the observed background JSON exception and ResourceWarning in the test
fixture. Product launcher code needed no further fix.

[Verification](verification.json) records engine selections, overrides, source
hashes, checked invocations, exact/negative replay results and offline log hashes.
Recordings, CSVs and full logs remain on D under
`D:/OpenRCsimulator-experiments/gdu03-tooling/`. All process profiles and temporary
directories used isolated D locations. No renderer or additional full app suite
was launched; observer/elapsed timings in raw outputs are not performance evidence.

The existing test entrypoints remain:

```powershell
python -B -m unittest discover -s tools/debug -p test_debugctl.py -v
python -B -m unittest discover -s tools/flight_log -p 'test_*.py' -v
```

The real recording/replay checks used the existing `app/tests/test_flight_log.gd`
through the [checked runner](../../../../../tools/godot/README.md), followed by
the normal commands in [Flight logging](../../../../FLIGHT-LOGGING.md).
