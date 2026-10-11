# Crash implementation ownership

2026-10-11 · **Status: implementation and qualification in progress.** CR-02a, CR-03a, CR-08a, CR-09a, CR-19a, CR-22a.

The owner's current request explicitly prioritizes crash presentation beyond the older CR-A schedule. Existing plan dependencies remain relevant to claims of validated material failure and damaged flight. Presentation thresholds are provisional estimates, never measured material strengths.

## Boundaries

- Lead: `app/render/crash/director.gd`, `effects.gd`, `app/assets/crash/`, CR integration/effects tests, `research/crash-damage/cr-22a/`, evidence and plan updates. Additive integration only in `main.gd` and a crash-restart policy in `sim/flight_session.gd`.
- Luna/max severity agent: `render/crash/severity.gd`, `test_crash_severity.gd`, CR-08a evidence.
- Luna/max wreck agent: `render/crash/wreck.gd`, `test_crash_wreck.gd`, CR-09a evidence (excluding this record).
- Luna/max audio agent: `render/crash/crash_audio.gd`, `assets/audio/crash/`, `test_crash_audio.gd`, CR-02a generator and evidence.

The active tree already contained AUD audio, UI-21, EL2a-P3, L4c/L9e and VQ-04a edits. Their files and generated models are excluded. The lead re-reads `main.gd` before changing it; no revert, staging or commit of another track. The source airplane and its hinge/node names remain intact. Shared flight dynamics, coefficients, generated model data and landscape shaders remain unchanged.

Only this task's three agents are reachable through the collaboration service. Other developers' work is identified through the dirty-tree audit and ownership registry; direct acknowledgement from those developers is unavailable. This record makes the proposed seam reviewable without claiming such acknowledgement.

## Budgets to verify

At most 24 CCD bodies, 160 lightweight fragments, 700 particles, 16 marks, one unshadowed light and eight crash voices. Crash effects CPU p95 target <=1.5 ms/frame on this Windows host; impact setup <=16.7 ms; warmed full-scene p95 <=33.3 ms at 1280x720. Report cold first-crash separately. Preserve ordinary flight state exactly, test reset/pause/teardown, and bound mixer peaks <=-1 dBFS. Hardware and real-time versus fixed-FPS timing must be stated with results.
