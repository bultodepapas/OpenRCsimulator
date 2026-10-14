# HELI ground-contact temporary A/B experiment

Candidate: reuse one `GroundContact.surface_at` result within a single skid RK-stage evaluation.
The copied Session and Skids sources were measured in a disposable project; production files were not edited.

Godot 4.7.2; 240 Hz; AB then BA, two pairs per scenario. Each timing surrounds the full `session.sim.step()` call.
State, aux, 14/6 continuous values, and shaft phase were byte-compared at every accepted tick; all paired hashes match.
Development run while parse_all.py had two other Godot processes active; host load was not isolated.

| Regime | A ticks | A p50 / p95 (µs) | B ticks | B p50 / p95 (µs) | Δ p50 / p95 (µs) |
|---|---:|---:|---:|---:|---:|
| stoppedground | 2400 | 2333 / 2816 | 2400 | 2391 / 3113 | +58 / +297 |
| 12ssoftspool | 5760 | 2555 / 3212 | 5760 | 2547 / 3195 | -8 / -17 |
| governedground | 2400 | 2608 / 3159 | 2400 | 2607 / 3076 | -1 / -83 |
| legacyairbornehover | 2400 | 1376 / 1677 | 2400 | 1405 / 1653 | +29 / -24 |

Source fingerprint: `8f4098aa6d8da256c59ba553f7a76d93a449389b48b774e8f3e1d516c59eadb9`.
See `performance.json` for per-file SHA-256, exact parity evidence, pair summaries, and disposable-versus-live source comparison.

This development run is not H15 qualification and is not evidence of a physical-model improvement.
