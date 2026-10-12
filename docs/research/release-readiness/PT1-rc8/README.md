# PT1 — rc8 release verification

2026-10-12 · Status: candidate qualification in progress. Native GUI, physical-radio, target-GPU and pilot acceptance remain open.

## Candidate scope

The release integrates current main-line work since rc7, including aircraft v2, wheel/terrain integration, landscape/population and soundscape, persistent crash presentation, updated Home defaults, update notices and the Turbo Lumber Evolution PREVIEW. [Release notes](../../../releases/v0.1.0-rc8.md) define the download's scope and limits.

Preflight found existing Linux blockers. The schema controls removed the Stik's gear while retaining its catalog ID, which attaches a real wheel profile at the file boundary. The three controls now use a synthetic profile-free ID. The full pinned-Linux contract test passes **1,873 cases / four tests**, retaining strict runtime validation.

The extreme-atmosphere reset control attempted a 15 m/s Stik trim at 4,000 m, 45 °C, 870 hPa QNH and 100% RH (density 0.5400099459 kg/m³). Pinned Linux Godot reproduces the previously documented nonconvergence, residual 0.16638981173064932. Nearby atmosphere configurations at 15 m/s and the same extreme configuration at 16 m/s converge. This release uses 16 m/s for the reset/recovery control, verifies that speed is retained and checks checkpoint availability before reading its fields. Runtime trim equations, acceptance tolerances and golden flights are unchanged. The exact 15 m/s convergence limitation remains open; [original Linux/Windows evidence](../../landscape-upgrade/LU-06/atmosphere-baseline.md) records its scope.

Focused pinned-Linux checks pass: atmosphere flight **142/142**, trim **14/14** (including 5 m/s refusal), trim density **35/35**, trim integrity **700/700**.

The v2 agreement runner also retained a scratch-directory default absent in fresh CI checkouts. Its default now resolves the checked-out `app/`; the CI command passes **62 cases**.

Local offline-tool regressions and all eleven CI geometry/physics/Timber generator commands pass. Full app/capture/export qualification is required before publication; no test skips or golden-flight replacements are authorized by this release.
