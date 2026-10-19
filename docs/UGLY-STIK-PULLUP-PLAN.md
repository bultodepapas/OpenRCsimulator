# Ugly Stik high-speed pull-up: experimental polar path

2026-10-12 · Revision 4 · **Status: diagnosis, opt-in polar plumbing and software checks are complete. No production polar is selected; aircraft-specific and owner acceptance remain open.** Roadmap step: `D8b-R2`. Owner: main physics; evidence path: `docs/research/flight-robustness/D8b-R2/`.

The current simulator can turn a high-speed full-elevator pull into a severe lateral departure as the wing crosses the estimated post-stall branch. The [original diagnosis](research/flight-robustness/D8b-R2/README.md) traces the mechanism through the live session and separates it from the owner's unrecorded event. It establishes a simulator cause, not that the same severity is realistic for a physical Jensen Ugly Stik.

An optional, provenance-checked wing-polar path and restricted research launch are implemented. Three synthetic polar families exercise it; they are sensitivity fixtures, not candidates calibrated to the airplane. Normal aircraft JSON does not enable the branch, so ordinary launches retain the previous behavior. The [implementation report](research/flight-robustness/D8b-R2/implementation/README.md) contains the pipeline, verification, candidate matrix and reproduction command.

## Current step status

| ID | Result | Status and remaining evidence checked 2026-10-12 |
| --- | --- | --- |
| D8b-R2a | Reproduce the maneuver and locate the force-law feedback | Diagnosis complete; [report](research/flight-robustness/D8b-R2/README.md) |
| D8b-R2i | Research polar shape, spanwise separation and related models | Complete; [research index](research/flight-robustness/D8b-R2/research-index.md) and [synthetic experiments](research/flight-robustness/D8b-R2/research-experiments.md) |
| D8b-R2b | Per-tick command, load and strip telemetry; scenario matrix | Implemented; owner-event capture, physical key-event delivery and dive-entry comparison remain open. [Matrix](research/flight-robustness/D8b-R2/implementation/matrix/README.md) |
| D8b-R2c | Mass/control contracts and symmetry checks | Software contracts complete; physical mass tensor, CG and installed servo measurements remain open. [Contracts](research/flight-robustness/D8b-R2/implementation/mass-controls.md) |
| D8b-R2d | Test a justified post-stall wing model | Optional polar implementation and synthetic candidates complete; matched polar data or defensible uncertainty bounds and production selection remain open. [Method review](research/flight-robustness/D8b-R2/implementation/polar-method.md). Analog bound (2026-10-19): the measured Ultra Stick 120 whole-aircraft polar keeps 89–94 % of CLmax from 18° to 30°, against 45–56 % for the legacy blend; only `retained` stays within 0.1 to 28° ([D10-R4](research/flight-dynamics/spin-post-stall-2026-10-19/README.md#2-post-stall-lift-retention-the-production-law-against-a-measured-rc-airframe)). |
| D8b-R2e | Verify nonlinear coupling and numerical behavior | Software checks complete; fixed-input mesh convergence, target performance and physical transient identification remain open. |
| D8b-R2f | Qualify complete maneuvers and mirrored cases | Automated coverage complete; owner loop/pull review and measured handling bands remain open. |
| D8b-R2g | Integrate the smallest justified correction | Integrated as opt-in research; production coefficient replacement awaits physical evidence and Gate 2. |
| D8b-R2h | Owner keyboard and radio acceptance | Open; requires a selected experimental path and controlled before/after builds. |

## Promotion limits

The synthetic tables have no measured uncertainty interval. The [candidate-screen data](research/flight-robustness/D8b-R2/implementation/candidate-screen.json) and [full matrix](research/flight-robustness/D8b-R2/implementation/matrix/README.md) show simulator sensitivity only. No matched Jensen post-stall polar, measured mass/inertia inventory, recorded high-load physical flight or structural limit is available.

Do not ship an arbitrary transition width, rate clamp, extra damping, automatic rudder, throw reduction or removal of physical propeller effects to make the maneuver look better. First reconcile aircraft input and mass provenance; compare the full lift, drag and separation shape; then use held-out maneuvers and owner review. Keep any pilot-comfort option separate from aircraft physics. Until those gates close, the new path remains experimental and disabled for normal flights.
