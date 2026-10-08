# E4a — Frozen-control full-circuit regression

2026-10-07 · **Status: COMPLETED — bounded experimental replay verified; E4/PT2 physical and release acceptance remain open.** Owner: Codex circuit-replay agent. Scope: `research/landing/e4a/`; no app, physics, aircraft-data, circuit-controller or active H9-reader edits.

## Result

The [offline tool](../../../../research/landing/e4a/README.md) records the completed E3c2a pilot once, then replays a saved control tape in a fresh session. The replay never calls the feedback controller. The checked fixture covers runway idle, takeoff, the complete circuit, approach, touchdown, rollout and five seconds of anchored stop/hold: **28,861 physics ticks, 120.25417 s, 483 sampled boundaries**.

All sampled state, previous pose, auxiliary state, engine modes, inputs and loads match **bit for bit** on the identified Linux/Godot baseline. Body and auxiliary acceptance uses existing H9 component tolerances; discrete engine/anchor modes and clock are exact. No tolerance was widened. Force-byte equality is a same-platform diagnostic, not a new cross-platform tolerance policy.

| Probe | First sampled rejection | Evidence |
| --- | --- | --- |
| Rolling resistance ×1.1 | tick 300 (1.25 s), east-position error 2.19184e-6 m > 1e-6 m | [rolling.json](rolling.json) |
| Each wheel anchor stiffness ×2 | tick 60 (0.25 s), north-position error 1.04904e-5 m > 1e-6 m | [anchor.json](anchor.json) |

The probes modify only disposable sessions **after** authentic baseline restoration. Neither the model fingerprint nor initial state is rewritten to admit a different configuration. Changing rolling resistance also changes the model's static breakaway threshold; the result establishes regression sensitivity, not separate parameter identification. Both probes stop at the first sampled failure, so no mutated whole-flight behavior is claimed.

## Proof and reproducibility

- [Recording](record.json), [record log](record.log): completes with wheel-reference touchdown sink 0.393875 m/s, landing runway margin 1.33278 m and 5.0 s anchored dwell. These are code verification of the experimental model, not measured aircraft performance.
- [Baseline replay](none.json), [log](none.log): all 28,861 ticks complete, all 483 sampled boundaries match exactly, no crash/fault/pause.
- [Verification summary](verification.json): one successful replay, the two physics probes above, and ten rejected tape corruptions. Missing/nonfinite input, missing final sample, altered checkpoint tick, fractional anchor flag and malformed policy/stamp fail before flight. Altered initial state fails at tick zero; changed expected position and servo fail at tick 60 under H9. Engine errors do not count as intended detection.
- [Independent rerecord](rerecord.json): a deliberate second recording reproduces the saved gzip bytes exactly. Ordinary verification always reads the checked baseline; it never regenerates expected states from current physics.
- Existing [H8 checkpoint checks](test_checkpoint.log): 90 pass; [H9 policy checks](test_replay_policy.log): 50 pass; [four existing airborne goldens](test_golden.log): pass.
- [Static lint](lint.json): both new GDScripts have zero errors/warnings. Both are parsed by the pinned engine before replay. The known aircraft-data inertia warning is retained in logs; it is an existing physical-evidence warning, not an engine error.
- [Source identity](source-identity.json): tracked baseline commit, exact app/circuit/replay source hashes, engine and native-tape hashes. Verification ran in a fresh local clone with completed E3c2a and E4a files overlaid; user settings were isolated. The wrapper checks unchanged source hashes through the run. Other developers' active edits are excluded.

An independent Luna Max review checked tick/input alignment, reset observer behavior, sampled-state comparisons and after-restore mutation placement. Its metadata-consistency finding led to the policy/platform rejection cases. The stored flight report is informational beyond completion/count; replay proves state reproduction, while E3c2a owns full route acceptance.

```sh
python3 research/landing/e4a/verify.py --out /tmp/e4a-proof
```

Use a new output directory. [The tool contract](../../../../research/landing/e4a/README.md) documents deliberate candidate recording, the reference field, native serialization and unsupported configurations. The checked tape is a Godot-native, object-disabled, float64 fixture; JSON is used for human-readable proof only. The field fixture freezes the ground environment independently of later presentation edits.

## Limits and next step

This is one eastbound, calm-air, wash-off Stik circuit at 240 Hz on Linux. It verifies a frozen input sequence at 0.25 s state checkpoints plus the exact endpoint, with completeness and crash guards on every tick. It does not compare every intervening state, establish cross-platform long-flight tolerances, or replace the active H9 golden reader. It remains an explicit offline command rather than a new default CI gate.

No runtime or source aircraft parameters changed, so the full app suite and aero timing were not rerun; focused H8/H9/golden integration and actual complete session flights are the proof for this change. E4 production adoption, rendered circuit acceptance, calibrated propwash, physical field comparisons and PT2 owner handling remain open. Choose CI/platform coverage after those gate decisions; preserve the frozen tape to detect unintended physics changes now.

Ready-to-paste commit message:

```text
E4a: add frozen-control full-circuit replay regression

Proof: 28,861 ticks and 483 checkpoints replay bit exactly; C_rr +10%
and anchor stiffness x2 exceed H9 limits; ten tape corruptions rejected.
Independent recording is byte-identical; H8 90/H9 50 checks and four
existing goldens pass in an isolated clone. No runtime/data changes;
physical and release acceptance remain open.
```
