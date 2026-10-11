# Crash implementation ownership

2026-10-11 · **Status: implementation reviewed; native qualification passed.** CR-02a, CR-03a, CR-08a, CR-09a, CR-19a, CR-22a. Broader regression status is recorded in [CR-22a](../CR-22a/README.md).

The owner's current request explicitly prioritizes crash presentation beyond the older CR-A schedule. Existing plan dependencies remain relevant to claims of validated material failure and damaged flight. Presentation thresholds are provisional estimates, never measured material strengths.

## Boundaries

- Lead: `app/render/crash/director.gd`, `effects.gd`, `app/assets/crash/`, CR integration/effects tests, `research/crash-damage/cr-22a/`, evidence and plan updates. Additive integration only in `main.gd` and a crash-restart policy in `sim/flight_session.gd`.
- Required product seam: the persistent-wreck policy updates the pause-menu explanation (and Spanish string), plus the two UI tests that explicitly expected automatic crash restart. Other UI navigation, aircraft selection and display work remain unchanged.
- The keyboard end-to-end test now expects the same persistent wreck and explicit R restart. Export preset include filters append only crash manifests/notices, preserving the audio track's additions; a clean-clone PCK check validates the packaged resources.
- Luna/max severity agent: `render/crash/severity.gd`, `test_crash_severity.gd`, CR-08a evidence.
- Luna/max wreck agent: `render/crash/wreck.gd`, `test_crash_wreck.gd`, CR-09a evidence (excluding this record).
- Luna/max audio agent: `render/crash/crash_audio.gd`, `assets/audio/crash/`, `test_crash_audio.gd`, CR-02a generator and evidence.

The active tree already contained AUD audio, UI-21, EL2a-P3, L4c/L9e and VQ-04a edits. Their files and generated models are excluded. The lead re-reads `main.gd` before changing it; no revert, staging or commit of another track. The source airplane and its hinge/node names remain intact. Shared flight dynamics, coefficients, generated model data and landscape shaders remain unchanged.

Only this task's three agents are reachable through the collaboration service. Other developers' work is identified through the dirty-tree audit and ownership registry; direct acknowledgement from those developers is unavailable. This record makes the proposed seam reviewable without claiming such acknowledgement.

## Qualified budgets

At most 24 CCD bodies, 160 lightweight fragments, 700 particles, 16 marks, one unshadowed light and eight crash voices. Director/effects CPU p95 <=1.5 ms/frame; final impact-setup limit tightened from 16.7 to 10 ms; full-scene p95 <=33.3 ms at 1280x720; first impact frame <=50 ms. The first impact is measured per process with the existing driver cache, not a cleared-cache claim. Ordinary flight parity, reset/pause/teardown and Master peaks <=-1 dBFS (float32 tolerance stated) passed. [CR-22a](../CR-22a/README.md) records hardware, timing method, captures and exact measurements.
