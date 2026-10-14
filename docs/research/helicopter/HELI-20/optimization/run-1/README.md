# HELI ground-contact temporary A/B experiment

Candidate: reuse one `GroundContact.surface_at` result within a single skid RK-stage evaluation.
The copied Session and Skids sources were measured in a disposable project; production files were not edited.

Godot 4.7.2; 240 Hz; AB then BA, two pairs per scenario. Each timing surrounds the full `session.sim.step()` call.
State, aux, 14/6 continuous values, and shaft phase were byte-compared at every accepted tick; all paired hashes match.
Development run concurrent with root cycle evidence; host load was not isolated.

| Regime | A ticks | A p50 / p95 (µs) | B ticks | B p50 / p95 (µs) | Δ p50 / p95 (µs) |
|---|---:|---:|---:|---:|---:|
| stoppedground | 2400 | 1604 / 2626 | 2400 | 1577 / 2577 | -27 / -49 |
| 12ssoftspool | 5760 | 2521 / 3809 | 5760 | 2045 / 3526 | -476 / -283 |
| governedground | 2400 | 2574 / 3218 | 2400 | 1967 / 3172 | -607 / -46 |
| legacyairbornehover | 2400 | 1116 / 1658 | 2400 | 1396 / 1854 | +280 / +196 |

Source fingerprint: `c4f72c5c6852cd87c04a46784c67e6967314f23a08a0abde19f235834cba42d2`.
See `performance.json` for per-file SHA-256, exact parity evidence, pair summaries, and disposable-versus-live source comparison.

This development run is not H15 qualification and is not evidence of a physical-model improvement.
