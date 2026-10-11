# PT1 — rc7 release verification

2026-10-11 · **Status: rc7 published; pre-tag and tagged CI, three downloaded release checksums and Windows headless flight smoke passed. Native GUI, target-GPU, physical-radio and pilot acceptance remain open.**

## Frozen candidate

The pre-tag candidate is `d9d9a3bfb6f49ed0f07f318bb8894b35292c4c3b`. [CI run 38163959531](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38163959531) completed successfully, including:

- aircraft schema/loader contracts and generated geometry/physics checks;
- offline measurement/validation regressions and the complete `app/test.sh` suite;
- `app/capture.sh` rendered evidence;
- Windows, Linux and universal macOS exports through `app/export.sh`, including Linux flight execution, resource-pack/build-identity checks, platform versions and macOS ad-hoc-signature inspection;
- the archived three.js checks.

All three `release-builds` artifacts were downloaded and independently hashed in Windows PowerShell with `Get-FileHash -Algorithm SHA256`. Every digest matched [preflight-SHA256SUMS](preflight-SHA256SUMS). Their build identity is `v0.1.0-rc6-40-gd9d9a3b`; they are pre-tag verification artifacts, not the rc7 downloads. Tagged packages have their own build identity and checksums.

The release adds only README/first-launch documentation, source-authored SVG download buttons and this evidence to the frozen candidate. The app, workflow, data, assets, generators and test tools remain unchanged from the validated commit. Concurrent later work on `main` is outside this frozen release.

## README verification

The pilot-first README was rendered through GitHub's Markdown API and then inspected on the public repository page with Chrome DevTools. At 1360×1000 the three direct-download buttons appear together before the flight image. At 390×844 they wrap into a vertical stack; document width equals viewport width and all images load. Relative links/images, the four published release-asset targets and SVG XML were checked. Direct links are version-specific because GitHub's latest-release route excludes prereleases.

The initial public README linked to rc6 until rc7 was published. The tag's README names rc7; `main` now points to the verified rc7 assets.

## Tagged publication

Tag `v0.1.0-rc7` identifies commit `eb0a92d8797ad10bbcf3ba247f3b8f7e842ca665`. [Tagged CI 38168590489](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38168590489) passed all four jobs, including app/captures, exports and publication. The prerelease was published at **2026-10-11 20:14 UTC** with exactly three ZIPs and `SHA256SUMS`. Every published ZIP was downloaded with `gh release download` and hashed with PowerShell; all three match the attached [SHA256SUMS](SHA256SUMS) and GitHub asset digests. [Release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7) · [Release notes](../../../releases/v0.1.0-rc7.md).

## Downloaded Windows executable

The Windows ZIP was extracted into an isolated directory and its embedded-pack executable ran headless on Windows with Dummy audio for a three-second default Stik flight. `Start-Process -WindowStyle Hidden -Wait -PassThru` reported exit **0**; the trace identifies build `v0.1.0-rc7`. The pinned candidate's `check_trimmed_flight.py --duration=3` passed: **721 rows / 720 ticks**, all samples finite, altitude **30.000 → 30.000 m**, airspeed **15.0000 m/s**. [Engine log](windows-engine.log) contains no engine errors; it retains the existing aircraft-data warning about estimated pitch inertia.

This checks native Windows headless execution of the downloaded pack, not GUI rendering, installation/trust prompts or radio behavior. The initial PowerShell direct invocation of the GUI-subsystem executable produced a valid trace but did not provide a reliable synchronous exit code; the verified run uses an explicit waited process.

Cross-exporting, Linux execution and Windows headless execution do not establish native GUI launch, trust prompts, real-radio compatibility, sustained GPU performance or realistic handling. No physical acceptance gate is closed by this release.
