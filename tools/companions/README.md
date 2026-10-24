# Companion solver re-bind (AFC-02-R3)

The AI companion profile ([jensen-das-ugly-stik-60.json](../../app/data/ai/companions/aircraft/jensen-das-ugly-stik-60.json)) pins a normalized identity of `app/physics`, `app/sim` and `app/failures`. Any edit there changes it, and an exported game refuses companions until the pin is renewed. This tool renews it only when the qualified aircraft's behaviour is unchanged.

## When a physics edit lands

`tests/test_companions_profiles.gd` is the only gate. It fails with:

```text
FAIL companion qualification pins the current physics/sim/failures identity  pinned 69bf5c78, current 3a8ebbc5: … run python3 tools/companions/rebind.py
```

The other companion suites call `accept_current_solver_for_tests()` and keep testing companion logic. The override works only in editor builds; exports always enforce the pin.

```sh
python3 tools/companions/rebind.py            # report: identical or changed, per tape
git commit ...                                # commit the physics edit first
python3 tools/companions/rebind.py --accept   # re-pin and write a receipt
```

The tool replays the [retained tapes](qualification.json) in candidate mode on two disposable copies under `tmp/`. The copies differ only in the solver directories: the accepted revision and the current tree. Byte-identical CSVs re-pin the profile, update `qualification.json` and write a receipt under [AFC-02/rebinds](../../docs/research/ai-companions/AFC-02/rebinds/). Commit all three together. A run takes about a minute.

Use `--workspace-root D:/OpenRCsimulator-evidence/rebind` when the repository drive lacks space for the project copy. Each run creates its own directory there; `--keep` retains it for inspection.

| Exit | Meaning |
| --- | --- |
| 0 | Already current, or every tape identical (re-pinned with `--accept`) |
| 1 | Behaviour changed: the report lists the first differing row and the largest column differences. Requalify the companion; do not re-pin. |
| 2 | Setup or replay failure, uncommitted solver directories with `--accept`, or inconsistent records. Nothing was changed. |

## Limits

The tool reports parity on these tapes only. It is not exact replay, a new qualification or physical validation. The tapes are airborne circuits, so ground-handling edits rarely show here. Changes to the pilot controller, aircraft data or field are separate profile pins and are not re-bound by this tool. Candidate replays adopt the current `wheel_profiles.json` file identity, but still refuse a change to this aircraft's own wheel profile.

`test_rebind.py` (run by `app/test.sh`) covers the CSV comparison, the safe re-pin and the agreement between the profile and `qualification.json`.
