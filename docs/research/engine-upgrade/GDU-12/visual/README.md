# GDU-12: visual capture recovery

2026-11-01. The visual capture uses Godot `4.8.beta2.official.cafc17a19`
on Linux/Xvfb with Mesa 25.2.8 llvmpipe and the Compatibility renderer. Its
historical 1280×720 reference captures do not qualify 1080p performance or
physical realism. The source snapshot is `46b004c7b469448c29ef96168da4f03cee2c6d23`
plus the in-progress changes, including the population test correction below.
The copied runtime, checker and asset trees were fingerprinted; documentation
is a shared, frozen link. The visual engine SHA-256 is
`34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.
Against the later commit `4358b7134369b3d4232b4efc07c310e9303919bc`, the
tracked application, tool, research and asset paths matched except for the
population test's CRLF/LF encoding. Three Python files newly tracked by that
commit were present in the snapshot and byte-matched the working tree. This
comparison does not change the recorded dirty-snapshot identity.

## Population asset guard

The former production batch guard looked for the retired `standing.glb`,
`sitting.glb` and `pilot.glb` files. The shipped people are outfit variants;
the corrected guard uses `Population.human_assets()` and `asset_path()`, along
with the three car assets. A missing required asset now fails the test.

Windows beta2 checked runs passed headless and with the NVIDIA RTX 3090
Compatibility renderer. Both executed all 14 required asset checks and the
24-person-and-car batch assertions; the native run also checked the human and
car fit bounds. The test file SHA-256 was
`bf6cf997471cdc86467df89da59ae1854510a117b4ad9ee652a4f45c8e91cc92`.
A separate Linux headless control removed one outfit GLB and its import sidecar
from a disposable copy: the checked runner exited 1 and recorded the required
missing-production-asset failure. Raw reports and logs are in
`D:/OpenRCsimulator-experiments/gdu-beta2/population-guard-recovery/` and
`population-guard-missing-control/`.

## Full capture

The first long run was interrupted by a WSL restart and has no complete-set
manifest. Its 38 core and eight UI image/sidecar hashes and scene labels
matched the verifier's fixed inventories; its VQ manifest and 66
image/sidecar hashes passed the existing matrix verifier. Persisted repeat
images match byte for byte for trees (13), horizon (42) and atmosphere (32).
Tree, horizon, atmosphere, cloud, ground, stripe and cue summaries were
persisted, but grass, seam, tree-wind, treeline and
scenario completion reports were not. The surface checker labels its
no-filter stripe comparison observational; that mutation was not rejected.

Comparison with the new snapshot matched all 29 root flight images and nine
field images byte for byte, but the same-renderer comparison failed on all
eight UI images. These snapshots had different inputs: the old flight-backed
UI used the GDScript reference backend and the new one used the native backend;
the sidecars also recorded changed source hashes. Three hint/pause pairs froze
at different simulation ticks (240 versus 252) after a live one-second timer.
Home differed by at most one RGB level and Help by two; the flight-backed
views had larger localized changes. Inspection of the largest Hint and Pause
pairs found no concrete new visual defect. These uncontrolled comparisons do
not establish UI equivalence. The failed comparison and pixel audit remain at
`D:/OpenRCsimulator-experiments/gdu-beta2/inspect-ui-difference-20261101.log`.

A subsequent attempt rendered its first image but failed the capture runner's
exact saved-path guard: `app/captures` was a symlink, so its resolved path
differed from the path printed by Godot. The failed output was retained. An
unchanged full-script retry used a bind mount to preserve the canonical path,
but was interrupted during its VQ matrix. A third fresh full-script run passed
setup, core rendering, UI, core checks, quality and terrain-atmosphere before
WSL stopped during the ground mutation import. It has neither a terminal exit
record nor the complete-set manifest. Windows recorded a `wsl.exe` stack
overflow; this does not identify a Godot defect.

Before that interruption the fixed inventories and image/sidecar hashes were
independently verified for 38 core, eight UI and 66 VQ captures. The tree
review passed 13 repeated images, the horizon review passed 42 views in each
of two byte-identical repeats, the atmosphere review passed 32 captures in
each of two byte-identical repeats, and the cloud projection controls passed.
The third run's initial runtime and tool fingerprints matched the second
run's snapshot. Its post-run fingerprints were never written.

Raw outputs and controls remain outside Git in the preallocated
`D:/OpenRCsimulator-experiments/gdu-beta2/export-stage.ext4` image, under
`visual-full-recovery-20261101-r2/`, `visual-full-recovery-control-20261101-r2/`,
`visual-full-recovery-20261101-r3/` and
`visual-full-recovery-control-20261101-r3/`. Ground, vegetation and scenario
remain to be completed. Partial group runs can cover those checks but do not
replace the uninterrupted full capture or produce its complete-set manifest.

The Linux VQ unit checks skip the Windows-only junction control. That one
control passed separately on Windows; its log is
`D:/OpenRCsimulator-experiments/gdu-beta2/visual-windows-junction-control.log`.
