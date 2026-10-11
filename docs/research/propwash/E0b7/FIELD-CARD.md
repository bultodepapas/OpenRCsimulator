# E0b7 — observation card

2026-10-09 · **Status: blank collection protocol; no physical observations supplied.** Owning step: [ROADMAP E0b7](../../../../ROADMAP.md). [Reducer contract](../../../../research/propwash/e0b7/README.md).

Use a copy for each aircraft/configuration/day. This card defines observations; the operator chooses suitable field procedures. A restrained test and a free taxi run are different boundary conditions and must remain separately identified.

## Freeze before collecting or fitting

| Item | Record |
| --- | --- |
| Campaign/date/operator | Unfilled |
| Aircraft and hardware revision | Unfilled |
| Mass, fuel/battery state, CG and measurement references | Unfilled |
| Motor, propeller make/diameter/pitch, installed rotation viewed from a stated direction | Unfilled |
| Gear/wheel sizes, nose steering alignment, spring/preload and tire condition | Unfilled |
| Actual elevator/rudder/aileron trim, rates, expo, control deflections and steering coupling | Unfilled |
| Surface, slope, runway axis, position/heading datums and wind with uncertainty | Unfilled |
| Restraint, attachments and force directions, if any | Unfilled |
| Video geometry/cadence, surveyed markers and observed aircraft reference point | Unfilled |
| RPM and throttle recording/calibration, filtering and common-clock alignment | Unfilled |
| Absolute error bounds and their derivation; unknown contributors | Unfilled |
| Independent trial IDs reserved for calibration and held-out comparison | Unfilled |
| Planned windows/end events and comparison tolerances | Unfilled before inspecting validation responses |

Keep original video/log bytes and their SHA-256 hashes. Record annotation frame/timestamps and calibration references so another reader can reproduce readings. Preserve failed, interrupted and inconclusive attempts with reasons; do not retain only clean responses. A separately recorded trial under the same configuration provides a better reserved case than a later excerpt from the calibration trial. Shared-day/environment/instrument errors still need consideration.

## Three observations

1. **Nose-wheel unloading.** Record initial rest/idle condition, throttle/RPM history, elevator position, restraint and whether the aircraft translated. Use nose-wheel load only when a suitable measurement exists; otherwise annotate tire clearance and the limits of visibility. Record contact/lift/bounce/return frames. A load decrease and visible separation are different observations. Do not interpret restraint-induced pitch as free-aircraft wash response.
2. **Taxi blip.** Record a baseline, the applied throttle pulse and recovery. Preserve the actual command history, RPM lag, steering/rudder/elevator corrections, signed ground heading and lateral path of the same reference point. Mark uneven surface, wind changes, brake/restraint use or uncertain frames. Do not infer a wash lag from engine lag alone.
3. **Takeoff swing.** Record from the declared initial event through a declared endpoint, including throttle application, corrections, first motion and wheel-contact changes. Annotate signed heading and lateral position against the surveyed runway frame. Preserve uncertain event intervals. The existing [VAL-8a tool](../../../../research/validation/ground-video/README.md) can separately reduce along-runway event displacement/time; it does not supply lateral geometry or yaw observations.

Use multiple annotated samples through transitions; the reducer has no assumed sample rate or automatic peak finder. Record timing bounds broad enough to cover channel alignment. Unwrap heading using observed motion before reduction. Ground-plane mapping is appropriate only for points on that plane; a raised nose tire needs geometry that supports vertical clearance. Occlusion is missing evidence, not zero clearance.

## Reduce and compare later

Create a campaign using the [documented JSON contract](../../../../research/propwash/e0b7/README.md), with `evidence: measured`, actual original files and measurement-derived readings. The synthetic example only demonstrates structure. Reduction preserves all annotations and separates the reserved trials; it cannot certify the field setup.

Before a simulator comparison, reproduce configuration, commands, initial state and boundary conditions. Compare the same reference points, heading convention and time windows. Godot CG height is not tire clearance; body yaw rate is not ground heading change. Current production Stik wash is disabled. A future candidate needs an explicit input snapshot and wash configuration, plus enabled-path cost evidence from E0b6p.

If fitting becomes justified, label inferred coefficients **fitted/derived**, describe identifiability and competing explanations, freeze them, then assess the reserved independent cases against the recorded uncertainty/tolerances. State any inspected held-out cases that became development data. Enablement and golden changes require their own deliberate, documented step. This preparation closes neither physical E0b7 nor PT2.
