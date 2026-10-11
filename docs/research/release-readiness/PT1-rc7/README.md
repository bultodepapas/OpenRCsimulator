# PT1 — rc7 release verification

2026-10-11 · **Status: candidate software checks, exports and downloaded CI-artifact checksums passed. Native-platform, target-GPU, physical-radio and pilot acceptance remain open.**

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

The initial public README links to rc6 until rc7 is published. The tag's README names rc7; `main` is updated after publication and downloaded-package verification.

## Tagged publication

The `v*` workflow repeats the software gates and publishes the three ZIPs plus `SHA256SUMS`. Its result and the downloaded rc7 asset verification are retained in a follow-up to this report on `main`. [Release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7) · [Release notes](../../../releases/v0.1.0-rc7.md).

Cross-exporting and Linux execution do not establish native Windows/macOS launch, trust prompts, real-radio compatibility, sustained GPU performance or realistic handling. No physical acceptance gate is closed by this release.
