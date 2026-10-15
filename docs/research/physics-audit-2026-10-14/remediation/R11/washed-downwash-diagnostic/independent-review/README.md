# Independent review: washed-tail downwash candidate

2026-10-14 · Read-only review of P51-22's candidate. The candidate was applied only to a physical disposable copy of `tmp/physics-audit-r11-final-scenarios-04/verified-app`; no runtime, aircraft data, P51-owned documentation, or tests were changed.

## Finding

The proposed free-flow denominator has no continuous zero-speed extension under the current wing-wake proxy. `Aero.wing_wake_velocity()` is an equal-area mean of `V_plane * CL` (m/s), explicitly a proxy rather than measured circulation (`app/physics/aero.gd:649-653, 656-710`). For fixed nonzero approach angle, the proxy is proportional to freestream speed, so the candidate's `atan2(gain*U, |V_free|)` can approach a finite, approach-angle-dependent angle as `|V_free| -> 0`. At exactly zero, `Aero.downwash_angle()` returns zero when `U == 0` (`app/physics/aero.gd:257-260`). The nonzero-speed limit therefore disagrees with the exact-zero branch. Since the candidate's propwash still gives the tail finite dynamic pressure, that angle difference creates finite tail-force and moment jumps.

This counterexample is in the catalog P-51 path, not only a synthetic fixed-wash calculation. At catalog max RPM 4951.245226, sea-level density 1.225 kg/m³, and all three authored slipstream pieces immersed, the model computes static thrust 235.368855 N and tail wake increment 13.397674944 m/s. The candidate's `V=1e-8 m/s` loads differ from its exact `V=0` loads as follows:

| Flow approach angle | Baseline force delta | Candidate force delta | Baseline pitch delta | Candidate pitch delta |
| ---: | ---: | ---: | ---: | ---: |
| −5° | 1.51e−8 N | 0.332620 N | −1.35e−8 N·m | −0.300271 N·m |
| 0° | 1.58e−8 N | 0.241002 N | −1.46e−8 N·m | +0.275275 N·m |
| +5° | 1.64e−8 N | 1.516351 N | −1.56e−8 N·m | +1.817879 N·m |

The force delta is the Euclidean norm of the three force components relative to that case's exact-zero-flow load; pitch delta is the change in body pitch moment. In the candidate, `wing_wake_velocity` at +5° is only 4.5626e−9 m/s at `V=1e-8`, and changes to exactly zero at `V=0`; prop-wake increment remains 13.397674953 versus 13.397674944 m/s. Thus the jump is from the changed angle closure, not a comparable jump in propwash strength. The baseline implementation is itself an approximate downwash model; this finding rejects the proposed closure's zero-flow behavior, not the current law as validated truth.

The candidate also makes the production P-51 `Slipstream.loads()` path disagree with public `Aero.tail_surface_increment()` composition: the baseline maximum absolute component difference across the 45 actual piece/state samples is 0; candidate maximum is 2.463743 N·m (pitch moment, +5°, 1 m/s). `Slipstream.loads()` passes a free-speed override only to the washed private helper call (`app/physics/slipstream.gd:190-204` in the candidate), while `tail_surface_increment()` still calls the helper twice with its default denominator (`app/physics/aero.gd:496-514`). The candidate likewise does not add the denominator to the public `tail_surface_load()` interface (`app/physics/aero.gd:474-493`). If the law were reconsidered, its production and public helper/oracle semantics must be made coherent; the candidate README already acknowledges frozen reference tests need updates.

## Scope and reproduction

The independent probe loads `res://data/aircraft/p51d_mustang_120.json`, fixes RPM at the catalog maximum, computes wake and immersion through `Propulsion` and `Slipstream`, then independently sums the three immersed-piece increments through `Aero.tail_surface_increment()`. It sweeps α = −5°, 0°, +5° and speed = 0, 1, 0.01, 1e−6, 1e−8 m/s. The fixed body attitude and shrinking velocity isolate the approach-direction limit; this is a model-law diagnostic, not a claim that a real P-51 can fly steadily at 1e−8 m/s. Both runs exited 0 with no Godot script errors.

Run from repository root (Windows PowerShell):

```powershell
.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-p51-downwash-review-20261014/baseline-app --audio-driver Dummy --script docs/research/physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/independent-review/p51_actual_slipstream_limit.gd
.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-p51-downwash-review-20261014/candidate-app --audio-driver Dummy --script docs/research/physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/independent-review/p51_actual_slipstream_limit.gd
```

Raw complete outputs are retained in [`baseline-p51-actual-slipstream.txt`](baseline-p51-actual-slipstream.txt) and [`candidate-p51-actual-slipstream.txt`](candidate-p51-actual-slipstream.txt); the probe is [`p51_actual_slipstream_limit.gd`](p51_actual_slipstream_limit.gd). The disposable baseline was copied from the exact R11 `verified-app`. The candidate copy differs by the exact P51-22 patch only. Hashes:

| Input | SHA-256 |
| --- | --- |
| Godot 4.7.2 stable console binary | `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643` |
| P51-22 candidate patch | `E6A6B0E7E53F032182461D107FD56B2D28B7116356E806649467A5451D7CE2B6` |
| Probe script | `047B7BE43C85C6234ECBDA0C444DC6A7514C63EA4EF454A41D9E4BCB7302464F` |
| P-51 catalog JSON (both copies) | `21D5F6DD1951AFD91DA407289B4A69530B62795AF08F60D71C183CDB8B76A008` |
| Baseline `app/physics/aero.gd` | `7AC94F6003F2CB7660A56DD94755C6A7D6143D90CC446C6B6C20433038CE38E3` |
| Candidate `app/physics/aero.gd` | `495EEB819DD45CB6AD8787F4CCEF129C4230A21B33B06B5494849B125A0F6289` |
| Candidate `app/physics/slipstream.gd` | `732692F008CE04E93668F32FA17668DDE2B9A2183DC226F65D2CCD5B2C4E6837` |
| Candidate `app/physics/swirl_loads.gd` | `0D9E57034F7856F21630C03D352178011D3AC083513F0F1E152B8746B0EF52FD` |
| Baseline `app/physics/slipstream.gd` | `BB810E8E9E93B1B89AD1750CD4DB507EB7FE66FAD070A5CCE51DFD0DCE58AB06` |
| Baseline `app/physics/swirl_loads.gd` | `2303BFCB6BDD33810B6DB052ED581111BC7B3DDA6FB69BB8B6CB0B32AFB83DCF` |

The P-51 catalog uses the direct piece-integration path (`edge_fraction` absent; three authored pieces), so the candidate changes in `SwirlLoads._integrate_interval()` are not exercised by these P-51 values. Graph call tracing confirms `Slipstream.loads()` calls `SwirlLoads.correction()` only in its smooth-profile branch, and that `correction()` is also called by the E0b6 quadrature research probe and tests. The two candidate denominator edits in the swirl integrator need a separate smooth-profile test; this P-51 result neither validates nor quantifies that branch.

## Physical support and limits

NACA Report 690 is primary evidence that propeller operation can increase effective tail downwash for tested aircraft and configurations. Its summary covers eight airplanes; for the YO-31A, the report says propeller operation increases effective tail pressure and downwash with angle of attack. Its flow surveys were made at selected locations and specified operating conditions, with interpolation where readings were unavailable ([NASA NTRS Report 690 PDF](<https://ntrs.nasa.gov/api/citations/19930091767/downloads/19930091767.pdf>)). Those data do not establish a universal inequality that downwash inside any propeller jet is at least the free-stream downwash, nor that equal-to-free-stream is a conservative lower bound for this P-51 model. That sentence in P51-22 is an inference, not a finding from the report. The report's measured result is a reason to model wing/propeller interaction better, not enough calibration to choose this replacement denominator.

A defensible integrated extension needs a dimensional local-flow/downwash source whose behavior is defined when freestream vanishes, including whether propwash impinges on and loads the wing, how that changes circulation/downwash, and how the resulting field reaches the tail pieces. This may require a coupled wing-plus-propeller local-flow model and evidence for the interaction/geometry. It cannot be repaired by a small angle clamp or epsilon because that would merely select a path-dependent limit. Until then, retain this as an open physical-model decision; the candidate's improved flight regressions are simulator outcomes, not physical validation.
