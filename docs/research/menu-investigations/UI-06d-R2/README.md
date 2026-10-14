# UI-06d-R2 — bounded launch captions and live language refresh

2026-10-14. Follow-up to [UI-06d-R1](../UI-06d-R1/README.md) and the baseline failures found during [UI-05-R1](../UI-05-R1/README.md). Production changes are confined to `app/ui/home.gd`; regression coverage is in `app/tests/test_ui_home_start_layout.gd` and the existing Home layout matrix.

## Cause and change

The Spanish helicopter-pad caption imposed a 328 px button minimum inside a card with 324 px available. Card and sidebar margins propagated that requirement, widening the 440 px sidebar to 444 px. The Spanish half-power airplane launch caption also exceeded the width contract, outside the earlier matrix's default-start cases.

The launch button now wraps long captions at word boundaries. It keeps the existing font and complete text. In the native Spanish helicopter capture it is 324×71 px instead of 328×44 px; the sidebar is 440 px. At 720p Fly remains visible and initially focused, and the keyboard legend remains reachable at the bottom of the existing vertical scroll. The English helicopter button remains 324×44 px.

The helicopter caption, instructions and tooltip were translated when assigned. Changing locale on an already-open Home left them in the previous language. Home now refreshes the currently selected start choice on the translation notification. This does not emit a launch request or alter the chosen pad/hover/half-power mode.

No per-frame callback, layout polling, dependency, asset, physics change or global style change is added. This slice repairs layout and state consistency; it makes no FPS or loading-speed claim.

## Verification

- Existing full catalog × EN/ES × calm/default conditions × 720p/1080p layout matrix: reference **358 passes / 4 failures**, candidate and integrated implementation **362 passes / 0 failures**.
- New regression uses real Enter key events, EN→ES→EN changes on the same Home, helicopter pad/hover toggles, focus preservation and both languages' explicit half-power airplane start. Reference **35/44 pass**; candidate **44/44 headless and native**, integrated **44/44 headless**. The reference failures establish that the checks detect both defects.
- Existing unchanged-legend regression: **23/23**, preserving the UI-05-R1 behavior.
- Native Godot 4.7.2, Compatibility, RTX 3090 / NVIDIA 610.88: eight measured Home cases (reference/candidate × EN/ES × 720p/1080p). Six Spanish captures retain the top and scrolled 720p states and the 1080p state. The corrected 720p top and scrolled images were visually inspected. This captures the Home UI on a plain viewport, without the 3D backdrop.

Broader integrated language (**25 checks**), input isolation (**17 checks**) and controller menu (**29 checks**) pass cleanly. The Home route has **57 passing checks and three failing helicopter startup/hint/restart assertions**. Its attempted reference comparison then encountered an unresolved `skid_contact.gd` dependency while the shared helicopter sources were changing, so that broad comparison is inconclusive; it does not establish parity or attribute those failures to this repair. The UI-only reference/candidate comparisons above completed cleanly and establish both repaired defects independently of flight startup.

Commands and logs live in `integrated-checks.json` and the corresponding files. These checks use the current shared tree, not an immutable release or a full `app/test.sh` run. The earlier field-data rejection no longer blocks these route runs; this slice did not modify field data. Exported builds, hardware controllers, other operating systems and display scaling remain separate acceptance gates.

The attempted broad reference run hit its 180-second timeout after the dependency error and a null-session script error; its log is retained as failed evidence, not counted as a completed comparison.

## Evidence and reproduction

`sources.json` identifies the starting source/dependency hashes; `manifest.json` identifies the retained artifacts and source identity at completion. The compressed reference/candidate Home scripts include pre-existing parallel changes; `home.patch` contains only this repair. `layout-comparison.json`, `launch-comparison.json` and `capture-metrics.json` contain commands/results or measured geometry.

Run these with the pinned engine and `--path app --audio-driver Dummy --script`:

```text
res://tests/test_ui_home_start_layout.gd
res://tests/test_ui_home_layout.gd
res://tests/test_ui_home_legend.gd
```

Use `--headless` for the layout/logic checks and repeat the launch check with a native display. To compare against the retained reference, decompress the `.gd.gz` files outside `app/` and pass `-- --home=<reference.gd>` to the launch regression. For native captures, run the decompressed `capture.gd` and pass `-- <directory-containing-reference.gd-and-candidate.gd>`.

## Next

The specific width/language defects are closed. Recheck the helicopter route assertions on a stable source snapshot before claiming complete menu acceptance. Continue UI-22 theme before UI-23 scaling/display; preserve the bounded sidebar, complete launch captions, keyboard focus and live-language regressions when changing either. Qualification of the full Home backdrop/load remains with the separate loading campaign.
