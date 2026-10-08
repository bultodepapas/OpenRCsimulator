# DATA-3 — exact aircraft input identity

**Status:** complete; verified · 2026-10-07 · owner: Codex.

## Contract

`AircraftData.load_file()` reads one byte buffer, decodes/parses that buffer and,
only after successful validation, attaches `input_identity = {format, sha256}`
to its result. The digest identifies exactly the aircraft JSON bytes that were
loaded, including whitespace and line endings. Recording never rereads the path.
Failed reloads retain the previous flight's identity. Direct
`validate_and_derive()` callers have no file identity.

The derived model retains its existing `data_sha256` field solely for compatibility:
it hashes Godot's sorted-key, **rounded** JSON serialization. Keeping new source
identity outside that model preserves the existing checkpoint fingerprint.
The old hash is not a canonical full-precision semantic digest.

CSV columns remain `openrc-trace v3`. Comment metadata advances independently to
`openrc-flight-meta v2`:

| Header | Meaning |
| --- | --- |
| `aircraft_input_format` | `openrc-aircraft v1` data format |
| `aircraft_input_sha256` | Lowercase SHA-256 of exact source-file bytes; explicitly unavailable for in-memory inputs |
| `aircraft_input_hash_convention` | `sha256 of exact aircraft input file bytes` |
| `aircraft_semantic_sha256` | Existing rounded serialization digest, separately named |
| `aircraft_semantic_hash_convention` | Exact Godot serialization settings, explicitly not file bytes |

The default trimmed-flight checker requires metadata v2, valid digest syntax and
known conventions. It rejects missing/unavailable identity. Supplying
`--aircraft-input` also verifies a saved input artifact's bytes against the trace.
Without that option, success explicitly says source bytes were not checked.

C7-R2 metadata v1 requires `--allow-legacy-metadata`; its success is labelled
semantic-only, with exact identity unavailable. It cannot verify an input file.
Unversioned pre-C7-R2 headers, unknown versions and mixed v1/v2 hash fields are
explicitly rejected. An archival opt-in never relaxes v2 checks.

## Reproduce

```bash
app/test.sh
python3 app/tests/test_trace_acceptance.py
$(app/get-godot.sh) --headless --path app --script res://tests/test_trace_metadata.gd
$(app/get-godot.sh) --headless --path app -- --trace=/tmp/data3.csv --t=3
python3 app/tests/check_trimmed_flight.py /tmp/data3.csv --duration=3 \
  --aircraft-input app/data/aircraft/jensen_ugly_stik_60.json
```

## Proof and limits

| Check | Result |
| --- | --- |
| Loader/metadata regression | [171 checks, zero failures](final-metadata.log) |
| Real-process trace acceptance | 13 tests pass both in an isolated app copy and the full working-tree suite, including all four aircraft and source-file verification |
| Controlled defects | [Both rejected](mutations.json): hashing rounded serialization; rereading the path when recording |
| Before/after flights | [All four aircraft](fleet-comparison.json): 241 samples each (initial + 240 flown ticks), byte-identical numeric CSV rows; exact input files verified; actual pre-change v1 traces accepted only with the archival option |
| Engine/static validation | [Zero errors](skill-summary.json); the 12 physics and 15 simulation warnings are identical to the unmodified baseline, ignoring shifted line numbers |
| Full `app/test.sh` | Baseline and post-change runs both exit 0; goldens, live trimmed flights and 30/60/144 fps comparisons pass |

[Verification manifest](verification.json) identifies the baseline commit and changed-code hashes.
The fleet comparison preserves CSV-row identity on this host; it does not claim
cross-platform bitwise determinism or new independent flight validation.

The regression changes Stik CL0 from `0.1068` to `0.1068000000000001` in a
**temporary copy**: the parsed aerodynamic value changes, the old rounded hash
collides, and the exact-byte hash changes. CRLF/trailing-whitespace changes also
produce a distinct byte hash with the same semantic digest. Tests cover all four
catalog aircraft, saved traces and input copies, failed reload retention,
post-load file replacement, malformed headers and legacy compatibility.

This identifies aircraft source bytes, not every input to a flight: ground data,
runtime model mutations, engine/code versions and full simulation state are
separate concerns. In-memory experiments must preserve their own source artifact;
no file hash is invented for them. Hashing runs only at load time and changes no
force calculation, integrator or per-tick work. No flight-fidelity or performance
gate is closed by this provenance change.

## References

Repository-owned sources (MIT): [loader](../../../../app/physics/aircraft_data.gd),
[session metadata](../../../../app/sim/flight_session.gd),
[checker](../../../../app/tests/check_trimmed_flight.py),
[C7-R2 contract](../../trace-integrity/C7-R2/README.md), and
[aircraft-data knowledge base](../../roadmap-investigations/09-aircraft-data-pipeline.md).
No new dependency or external dataset.

Ready-to-paste commit message:

```text
DATA-3: identify exact aircraft input bytes in flight traces

Proof: metadata/input regressions, trace process tests and app/test.sh;
four aircraft retain byte-identical numeric flight rows.
```
