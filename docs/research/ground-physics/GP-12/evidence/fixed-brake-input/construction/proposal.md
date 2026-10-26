# Fixed-gear shared brake input — bounded candidate

Runtime drafts: FlightSession, Main and legacy Trace only. No Simulation,
aircraft loader, wheel law, global profile or stock JSON changes.

Session exposes `wheel_brake_available()` from admitted wheel-profile contacts
whose explicit availability is `available`, provenance is present and torque is
positive. `wheel_brake_input_index()` is 5 for historical retractable layouts,
4 for fixed braked layouts, otherwise -1. Retractable layouts remain 6/7 even
if no usable brake hardware is installed. Fixed unbraked layouts remain 4/5.
Only the new fixed braked branch appends wheel_brake before optional flaps.
Hardware availability governs positive commands; zero releases always clear.

The fixed branch uses the already installed reader identity
`fixed-gear-shared-wheel-brake-input-v1`, index 4, explicit input_layout, and
flap index 5 when present. It adds that identity/index to configuration and
checkpoint only in this branch. Restore validates both and restores demand
inside the existing accepted restore hook. Reset clears demand through the
existing initial-gear staging. Pre-step, checkpoint and external input reject
invalid brake values atomically. Main B eligibility uses hardware availability;
focus/pause/menu releases remain unconditional.

Trace adds one cmd_wheel_brake column only for the explicit new law, validates
the exact named layout and index, rejects mixed gear claims, and adjusts flap
index/count without inventing gear columns or gear aux. Legacy metadata and
columns are unchanged when the new identity is absent.

Fixtures use Data.validate_and_derive on the existing authored Stik source,
plus WheelProfiles.apply_to_model with a detached provenance-bearing synthetic
profile file. Session.setup's existing frozen_data argument installs that
validated result. The synthetic brake torque is explicitly fixture-only;
no stock hardware claim. A second fixture adds a valid authored flap module.
Controls with none/unspecified hardware retain old widths. Existing retractable
fixtures retain their exact state/layout/metadata behavior.

Checks: public/live and external commands, pause/focus release, exact accepted
checkpoint/replay and rollback, reset/reload demand clearing, invalid hardware,
new metadata/CSV/Trace roles and hostile mixed layouts. Preserve the six current
canonical ORFL baselines; explicit candidate comparisons report solver_changed,
and use exact candidate checkpoint replay rather than pretending cross-source
solver identity. No differential braking or airborne mechanics claim.
