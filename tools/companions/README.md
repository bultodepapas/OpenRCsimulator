# Companion solver re-bind (AFC-02-R3)

The AI companion profile ([jensen-das-ugly-stik-60.json](../../app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json)) pins a normalized identity of `app/physics`, `app/sim` and `app/failures`. Any edit there changes it, and an exported game refuses companions until the pin is renewed. This tool renews it only when the qualified aircraft's behaviour is unchanged.

## When a physics edit lands

`tests/test_companions_profiles.gd` detects a stale solver pin, for example:

```text
FAIL companion qualification pins the current physics/sim/failures identity  pinned 69bf5c78, current 3a8ebbc5: … run python3 tools/companions/rebind.py
```

Some companion suites use `accept_current_solver_for_tests()` to exercise their
logic independently of the solver pin. The override works only in editor builds;
exports enforce the pin. The separately pinned behavior manifest and admission
checks still apply and are not renewed by the solver re-bind.

```sh
python3 tools/companions/rebind.py            # report: identical or changed, per tape
git commit ...                                # commit the physics edit first
python3 tools/companions/rebind.py --accept   # re-pin and write a receipt
```

The tool replays the [retained tapes](qualification.json) in candidate mode against the current tree and a disposable baseline under `tmp/`. By default the baseline takes the accepted solver directories and current non-solver files. Byte-identical CSVs permit `--accept` to re-pin the profile, update `qualification.json` and write a receipt under [AFC-02/rebinds](../../docs/research/ai-companions/AFC-02/rebinds/). Commit all three together.

If the base copy fails to compile (`replay of … in base failed: … Compilation failed`), current non-solver code may call a solver API newer than the accepted revision. Use `--baseline full`: the base is built from the accepted revision's tracked `app/` and replay tools. Only the current `.godot/imported` asset cache is retained; current extension lists, class caches, native libraries and added source files are excluded. The accepted solver identity is still checked before replay. Identical tapes are a stricter result; a difference may come from non-solver code and still needs requalification. The receipt records the `baseline` used.

On macOS with APFS, `--copy-mode clone` uses the exclusive `clonefile` operation for the
disposable copy, including the optional import cache. It requires a supported
same-volume filesystem; an unavailable clone fails without a normal-copy or
hardlink fallback. `--copy-mode copy` remains the default. The full baseline
streams the Git archive, avoiding a second full-sized temporary tar. Both modes
still need enough free space for extracted historical files, tapes and results.
The receipt records the copy mode; a clone or reused asset cache does not prove
source or import compatibility. Use a real checkout containing the accepted
revision and retained tapes, not an archive with a fabricated Git HEAD.

## When the engine pin changes

Replay refuses a tape recorded by another engine (`Engine version differs`), so an engine change stops this tool with exit 2. Re-record the nine scenarios with the new pinned engine, point `qualification.json` at them and run the tool again. The probe refuses an existing output directory:

```sh
G="$(app/get-godot.sh)"; P="$PWD/research/ai-companions/encounter_probe.gd"
"$G" --headless --path app --audio-driver Dummy --script "$P" -- --record-crossings --out="$PWD/<new dir>/crossings"
"$G" --headless --path app --audio-driver Dummy --script "$P" -- --out="$PWD/<new dir>/parallel"
```

The current tapes were recorded on Godot 4.8-beta2 ([AFC-02-R5](../../docs/research/ai-companions/AFC-02-R5/README.md)). The tool checks the selected editor against the profile's exact build and inspects every retained tape for completeness and the recorded engine before accepting an unchanged solver or attempting a re-bind.

## Compressed qualification tapes

The `tapes` list may contain raw `.orfl` paths or gzip-compressed `.orfl.gz` paths, relative to the repository root. Raw entries need no new metadata and continue to use the original files. Each compressed entry requires both exact SHA-256 identities in a top-level `tape_identities` object, keyed by the same path string:

```json
{
  "tapes": ["docs/research/ai-companions/example.orfl.gz"],
  "tape_identities": {
    "docs/research/ai-companions/example.orfl.gz": {
      "orfl_sha256": "<SHA-256 of the original uncompressed ORFL>",
      "stored_sha256": "<SHA-256 of the stored gzip file>"
    }
  }
}
```

Replace the placeholders with 64 hexadecimal characters. `tape_identities` names exactly the compressed entries; missing, malformed or unexpected entries are refused. For deterministic storage, `gzip -n -c original.orfl > original.orfl.gz` retains the original and omits variable filename/time metadata. Pin binary evidence bytes across checkouts, and retain the original ORFL hash from its recording and replay reports.

The tool streams each gzip into a fresh private temporary directory, checks the gzip trailer and CRC, verifies both hashes and the ORFL magic, then passes the exact uncompressed bytes to the existing engine inspection and replay paths. Its decompressed limit is **544 MiB per compressed tape**: the [flight-log reader](../../app/tools/flight_log_cli.gd) permits the recorder's 512 MiB plus two 16 MiB packets. This transport limit does not change raw-file admission or validate the flight itself. Suffix/content mismatches, compressed output names that collide with another tape, corruption and excess size stop the run. It rechecks both identities after inspection and replay. The extracted files remain available throughout both replays and are removed on completion or failure, including with `--keep`; only the disposable project copies are retained by that flag.

Comparison receipts keep `orfl_sha256` as the uncompressed ORFL hash. Compressed entries additionally report `tape_encoding: gzip`, `stored_sha256` and the source hash reported by each replay child. Both child hashes must match the declared original, even when the two CSVs match. No replay output is normalized. Compression does not replace the existing engine, complete-log, source, replay or qualification gates.

The identity inspector hashes each tape before and after inspection and reports its path and hash; gzip entries must match their declared original hash. Each replay child also reports a source hash during startup. These checks do not lock files or prove that a concurrently modified file stayed unchanged throughout a child process.

Use `--workspace-root D:/OpenRCsimulator-evidence/rebind` when the repository drive lacks space for the project copy. Each run creates its own directory there; `--keep` retains it for inspection.

| Exit | Meaning |
| --- | --- |
| 0 | Already current, or every tape identical (re-pinned with `--accept`) |
| 1 | Behaviour changed: the report lists the first differing row and the largest column differences. Requalify the companion; do not re-pin. |
| 2 | Setup or replay failure, uncommitted solver directories with `--accept`, or inconsistent records. Nothing was changed. |

## Limits

The tool reports parity on these tapes only. It is not exact replay, a new qualification or physical validation. The tapes are airborne circuits, so ground-handling edits rarely show here. Changes to the pilot controller, aircraft data or field are separate profile pins and are not re-bound by this tool. Candidate replays adopt the current `wheel_profiles.json` file identity, but still refuse a change to this aircraft's own wheel profile.

`test_rebind.py` (run by `app/test.sh`) covers the CSV comparison, the safe re-pin and the agreement between the profile and `qualification.json`.
