# GDU-03: final companion source qualification

2026-10-25. Final admission pins canonical solver
`5df257b35154f1f2908431acfbc0dd60d837c083dddd55026a1627fab646aaae`
at source commit `be068e5a3a25bab03e8954fbed57eb1489b37df6`, on the local
`gdu03-core-qualification-20261025` branch. The isolated commit contains exactly
`math3d.gd`, `mass_inventory.gd` and `flight_session.gd`; root's unrelated index
and merge state were preserved. Admission follow-up commit `280b3548c…` retains
that source commit as its ancestor and contains only the generated profile,
qualification record and rebind receipt. Full migration/presentation/lake/platform
delivery remains separate from this bounded local branch. Engine, pilot, data, field and 240 Hz guards
remain strict. [Source identities and results](verification.json).

When assembling the delivery history after the existing root merge, retain the
qualification commits in its ancestry. Copying the generated admission JSON
alone does not deliver the source commit that its provenance references.

## Corrected invalid initialization

The existing staged-session fixture exposed a pre-existing bug on **both 4.7.2
and 4.8 beta1**. After rejecting the same invalid input, synchronous setup kept
throttle demand 0.5 while staged setup used zero. Every other compared field and
message matched. Both sessions were detached at tick zero: no post-await physics
could account for the difference. [Diagnosis](diagnosis.json) and original
failed checks under `checks/pre-fix-*` retain the exact field/byte differences.

The synchronous invalid-start branch now sets throttle to zero before building
inputs. The equivalence assertion is unchanged. The original fixture passes
all **12 checks on both engines** with final source. The other two source edits
move the unchanged minimum-normal float constant to the shared math module and
alias it from mass inventory; the [separate numerical audit](../../numerical/README.md) owns their boundary
and trajectory evidence. No valid-flight command or physics law was retuned.

## Requalification evidence

- The normal [solver rebind pipeline receipt](../../../../ai-companions/AFC-02/rebinds/2026-10-25-1f7daf66-to-5df257b3.json)
  records the committed source and all nine historical tapes with byte-identical
  pre/post CSVs. These tapes were replayed with **4.7.2**, their recorded engine;
  their headers and replay guards were not changed. Raw replay reports/logs are
  retained under `legacy-rebind/`.
- Two preserved **4.8** player/AI recordings replay exactly on original source:
  `complete=true`, `solver_changed=false`. Final-source candidate replays report
  `complete=true`, `solver_changed=true`; all 261 CSV rows per stream remain
  byte-identical. [Comparison](pre-post-comparison.json), reports/CSVs under `replays/`.
- The final-source circuit matrix passes **148 checks**, including six 120-second
  calm/gentle 1–3-aircraft cases and both deterministic repeats. Both generated
  CSVs are byte-identical to the original 4.8 qualification.
  [Matrix comparison](matrix-comparison.json), [checked matrix](checks/matrix/report.json).
- Strict final source/build admission passes **43 checks**. The final-source
  recorder fixture passes **157 checks**. New player/AI recordings each contain
  260 intervals, then both normal CLI exact replays report `complete=true` and
  `solver_changed=false`, with 261 rows. [Fresh verification](fresh-exact-verification.json).

The `.orfl` raw identity changes from `d8d056aa…` to `08d8086f…`; it remains
separate from the LF-normalized admission identity above. Full identities,
three core hashes and the accepted revision are in [verification.json](verification.json).
No source identities or old file headers were relabeled.

Recordings and working copies remain under
`D:/OpenRCsimulator-experiments/gdu03-final-core/` and the original companion
fixture directory. The rebind receipt records its exact method and scope;
historical tapes require their 4.7 engine rather than the new default binary.
These are bounded software gates, not fleet restoration, AI decision replay,
physical validation, new activities, a higher population ceiling or frame-cost
qualification. The [original limits](../README.md#reproduction-and-limits) remain open.
