# GDU-12: debug smoke and shadow registry

2026-11-01, Windows, headless, Godot `4.8.beta2.official.cafc17a19`.
The working tree was based on `46b004c7b469448c29ef96168da4f03cee2c6d23` with
the in-progress GDU-12 changes. The run used its own port and profile; the
Compatibility rendering method was selected. This is a software lifecycle check,
not a rendered, performance or physical-validation result.

Before the change, full smoke runs on beta1 and beta2 both completed their other
steps but failed the fly/Home soak: objects rose by 16 and then 32 relative to
the measured baseline, with 830 nodes and zero orphans throughout. Beta1 had
1,323 resources, beta2 1,327; both reported zero leaked objects at exit. The
shadow-lighting registry keeps weak references and normally removes dead entries
after 64 registrations. The smoke scenario now waits five frames after Home and
calls the existing prune before each census. Generic `soak` and its zero default
tolerance are unchanged; live objects remain counted. The existing 130-cycle
registry test checks the ordinary bound without this explicit smoke cleanup.

| Check | Result |
| --- | --- |
| Beta2 full `smoke --seed 20261024 --steps 150 --cycles 3` | Passed all 52 steps. After one warm-up, all three measured censuses had 830 nodes, 1,324 resources and zero orphans; no counters met soak's growth rule and there were no new soak errors. The exit report had zero leaked objects and no crash. |
| Live negative control | A separate bridge session retained one new `RefCounted` per fly/Home cycle before the same prune. The zero-tolerance soak failed with object differences `[1, 3]` and no errors. Five control objects were retained at inspection, including one created before the soak. Removing the control and stopping produced zero reported exit leaks. |
| `test_shadow_settings.gd` | Checked runner: 54 checks, zero failed, no engine errors or warnings, complete. |
| Python `test_debugctl.py` | 37 tests, one `/proc` test skipped on Windows. The smoke test checks settle-before-prune ordering, four sweeps and rejection of simulated live growth. |

Soak reports counters that increase in every compared cycle, excluding static
memory; passing a short soak is not proof that every leak is absent. The negative
control establishes that its growth check still detects retained objects after the
prune, not that the whole measured difference comes from the control.

Raw evidence is under `D:/OpenRCsimulator-experiments/gdu-beta2/`: pre-change
`smoke-beta1-control.log` and `smoke-beta2-repeat.log`,
`smoke-beta2-settled.log` and `smoke-beta2-settled-run/`,
`smoke-negative-control/`, `smoke-bound-check/`, and
`smoke-client-tests-final.log`. The smoke console executable SHA-256 was
`1a470886fc810b81a61e01bad7678e38989f1c94cf8e9733bfd1026224b3f42b`;
the run's `debugctl.py` SHA-256 was
`4d021b519be80f7ce72f776d71029dca0fcd8b3e8ff33eb54d28450401f25c45`.
