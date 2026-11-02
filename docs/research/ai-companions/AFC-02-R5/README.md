# AFC-02-R5: companion qualification on Godot 4.8 beta2

2026-11-01. The existing airborne Ugly Stik circuit scope was checked on official
Windows Godot `4.8.beta2.official.cafc17a19`; no activity, aircraft, weather or
roster scope was expanded. The beta1 evidence remains at [GDU-03](../../engine-upgrade/GDU-03/companions/README.md)
and [AFC-02-R4](../AFC-02-R4/README.md).

The [current-source admission test](admission/checked.json) passed 44 checks,
including explicit refusal of a beta1 profile. The companion rebind tool also
inspects the current engine and every tape even when the solver hash is unchanged;
its focused Python tests and a beta1-tape refusal check passed.

The [checked matrix](matrix/checked.json) passed 148 checks with no engine errors
or warnings. All six calm and gentle-practice scenarios completed 28,800 ticks
at 240 Hz, with one to three companions; both seeded three-aircraft repeats
completed with bit-identical sampled state and commands. The [scenario metrics](matrix/scenario_metrics.csv)
and [one-second samples](matrix/flight_samples_1hz.csv) retain the actual outputs.
Minimum terrain clearance was 34.310643 m, maximum radial error was 4.047822 m,
and minimum player and fleet separations were 122.307210 m and 121.744242 m.
These match the values already recorded in the Club field profile.

The [paired beta1 matrix](beta1-matrix/checked.json) also passed 148 checks.
Its scenario metrics and one-second samples match the beta2 CSVs byte for byte
(SHA-256 `29cab4ba7a47da1afd10e39249b7080eb5537d5004c558995e9e0c301a6e2d56`
and `cdabecb58ad7ecb98762ba6de6d4f7ece6b7f3c71abfef1476f93c5c2aaba5fb`,
respectively). These rounded samples do not establish equality at every tick.

The pilot, circuit controller, physics, simulation, failures, aircraft and field
inputs matched tracked source at `46b004c7b469448c29ef96168da4f03cee2c6d23`.
The normalized solver identity was
`90fb5ae1a2cde743730ca2cd9f97fcdf0c56f096622de72f8c664e0bd8459724`;
the raw flight-log source identity was
`6c9768d9884097cde84f48c4563d8554ecb596a32b81a3e5b8b0449e4184bae7`.
The pilot script SHA-256 was
`6c9eb4c53f4f80c284249fc143f976b2e5becc555a50ee415afe92bb8129b151`.
The beta2 Windows editor and console SHA-256 values were
`9d735a72c1a06bf42379829257b0bf966a6cf0ea507c6d8efa051bcfc8faccf2` and
`1a470886fc810b81a61e01bad7678e38989f1c94cf8e9733bfd1026224b3f42b`.

Nine [new tapes](tapes/) were recorded using the unchanged encounter probe and
the commands in the [companion tooling guide](../../../../tools/companions/README.md).
Both [crossings](surveys/crossings.json) and [parallel](surveys/parallel.json)
surveys completed with a deterministic repeat and verified recording writes.
The parallel survey missed its separation gate; it is a survey input, not a
qualification. Each tape then completed exact beta2 replay with 2,881 rows and
`solver_changed=false`; the individual [replay reports](replays/) retain source
hashes and results. Original raw checked-run outputs and replay CSVs are under
`D:/OpenRCsimulator-experiments/gdu-beta2-identities/`.

The matrix exercises a stationary player and the circuit fleet. It does not prove
general encounter safety, physical accuracy, full fleet replay, rendered platform
behavior or target-hardware frame cost. The [existing companion limitations](../../engine-upgrade/GDU-03/companions/README.md#reproduction-and-limits)
remain open.
