# AFC-02-R4: re-bind tapes on Godot 4.8-beta1

2026-10-27. GDU-03 moved the project to Godot `4.8.beta1.official.4d10419ca`.
The nine re-bind tapes in [`qualification.json`](../../../../tools/companions/qualification.json)
were the AFC-04-R1/R2 recordings from Godot 4.7.2. Replay refuses another engine
(`prepare_replay` in `app/tools/flight_log_cli.gd`), so `rebind.py` stopped with
exit 2 and the solver pin could not be renewed after physics or sim edits.
`test_companions_profiles.gd` stayed red on every such edit.

The same nine scenarios were re-recorded on Linux at `399d00c6f` with the pinned
engine, using the original probe and arguments:

```sh
G="$(app/get-godot.sh)"; P="$PWD/research/ai-companions/encounter_probe.gd"
"$G" --headless --path app --audio-driver Dummy --script "$P" -- --record-crossings --out=<dir>  # six crossing tapes
"$G" --headless --path app --audio-driver Dummy --script "$P" -- --out=<dir>                     # three parallel-two-threats tapes
```

Each [tape](tapes/) has 2881 rows. The probe verified every written log and a
deterministic repeat ([crossings](survey-crossings.json), [parallel](survey-parallel.json)).
As with the 4.7.2 recordings, the survey's 30 m separation gate fails for some
cases: these are survey fixtures, not a qualification. `rebind.py` uses them only
as recorded command input for candidate replay.

With these tapes, the accepted solver `b7173d8a` (`577c803`) and the current
solver `590372ba` (`399d00c6f`) produce byte-identical CSVs on all nine tapes. The
tool re-pinned the profile; [receipt](../AFC-02/rebinds/2026-10-27-b7173d8a-to-590372ba.json).
`test_companions_profiles.gd` passes 43 checks and `test_rebind.py` 9 tests.

The 4.7.2 tapes remain the dated AFC-04-R1/R2 evidence. Re-record again only when
the engine pin changes ([procedure](../../../../tools/companions/README.md#when-the-engine-pin-changes)).
Parity on these tapes is not exact replay, a new qualification or physical
validation.
