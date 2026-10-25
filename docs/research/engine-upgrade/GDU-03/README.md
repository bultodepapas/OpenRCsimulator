# GDU-03: Godot 4.8 standard-engine adoption

2026-10-25. The owner authorized official **4.8-beta1** as the standard development
engine after the [parallel trial](../GDU-02/README.md). This is the latest official
4.8 build in the [download archive](https://godotengine.org/download/archive/),
not a stable release. Build: `4d10419cacd6d3009976e8f9fd3abd970fd58018`.
The [upgrade plan](../../../plans/godot-4.8-upgrade.md) retains remaining gates.

## Implemented

The application, verified editor/template downloads, CI pins and active launchers
use 4.8-beta1. Focus, unfocused joypad input and fullscreen-shortcut defaults are
explicit to preserve existing application behavior. Presentation identities,
Workshop bindings and generated Timber/insulator provenance were regenerated
through their owners; accepted aircraft physics and golden records were not
retuned. godot-cpp remains 10.0.0 with the 4.7 extension API.

| Area | Evidence and limits |
| --- | --- |
| Numerical comparison | [18 frozen fixed-wing trajectories and PCG/OU streams](numerical/README.md) match byte-for-byte, including the [final-core rerun](numerical/final-core/README.md); bounded Windows comparison |
| Import provenance | [Root import and later input audit](imports/README.md) retain the version-only Timber/insulator deltas and unchanged numeric inputs |
| Native evaluator | [Windows/Linux rebuild receipts](native/) retain load, float64, evaluator and lake parity checks |
| Flight companions | [148-check paired matrices, 21 regression groups and a 120-second production session](companions/README.md), followed by [final-source rebind and fresh exact player/AI replay](companions/final-core/README.md); strict admission retained |
| Replay and tools | [Default launchers, 3,247 FL-04 checks and exact same-build replay](tooling/README.md); wrong-engine/source rejection retained |
| Native audio | [Menu, 125-second worker stress and paired wind captures](audio/README.md); no audio-guard removal or performance claim |
| Native UI | [Eight scenarios at 1080p and clean shutdown](ui/README.md); two automation readiness defects corrected |
| Production rendering | [Fourteen 1080p day/sunset/night captures and Standard/High restart](rendering/native/README.md), plus the [cloud shader contract](rendering/cloud/README.md); no full-image or performance equivalence claim |
| Moon radiance | [Existing amplified cubemap probe on both engines at 1080p](rendering/moon/README.md); the COLOR/DISABLED invariant holds |
| GPU correctness | [Existing color/shadow oracles pass](rendering/gpu-correctness/README.md); the separate ReflectionProbe lifetime controls still fail with leaked Texture RIDs on beta1 |
| Integration corrections | [Shadow-world test scoping](integration/field-shadow-world/README.md), [bounded Settings layout](integration/settings-layout/README.md), [interactive loading fixture](integration/loading-route/README.md), [population fixture](integration/vegetation-fixture/README.md) and [math boundary](integration/math-boundary/README.md) retain their focused checks and limits |
| UI and fixture cleanup | [672 responsive cases and retained picker focus](integration/overlay-focus/README.md), [quit fixture](integration/quit-fixture/README.md), [gear teardown](tooling/gear-input/README.md) and [tree-node cleanup](integration/tree-detail-cleanup/README.md); original failures retained |
| Unit and offline coverage | [All 709 unit scripts and 559 offline unittest cases](suite/README.md), with selected receipts and warnings; named physical gates remain pending |
| Integration | [Complete logical coverage through retained prefix and exact continuations](integration/final/README.md), including H6/H7, model contracts, CLI rejection controls and 30/60/144 FPS checks; no uninterrupted-run claim |
| Generated lake | [Owner regeneration](lake/README.md) preserves every geometry/input buffer; metadata binds the final source and engine |
| macOS templates | [Scoped universal-export correction](macos/README.md) fixes beta1's debug/release inversion; native macOS execution remains untested |
| Desktop packages | [Three release archives and existing package gates](exports/README.md) pass; Windows release runs at actual 1080p, with compiled UI/livery checks. No native macOS or Linux desktop qualification |

## Local verification complete

The full application suite uses a frozen copy at
`D:/OpenRCsimulator-experiments/gdu03-suite`, with separate profiles and retained
checked-runner collections. All 709 unit scripts, the complete logical
integration partition and the frozen desktop package checks have passing
coverage within the scope above. Original failed invocations remain explicit.
Neither remote CI nor release qualification is claimed here.

Four parallel UI edits arrived after the frozen runs. Their
[current-source continuation](suite/late-ui/README.md) passes 285 livery checks,
672 responsive cases, aircraft flow and screen-stack lifecycle with unchanged
sources throughout. The [final source audit](suite/final-source-audit.json)
accounts for these four differences; exported artifacts retain their earlier
bound snapshot. No later UI bytes were silently attributed to those packages.

The first passes exposed stale woodland provenance hashes and Windows-specific
outfit-test path/line-ending assumptions. The owning woodland generator changed
only two source hashes; placement and geometry stayed identical. Outfit checks
now use POSIX manifest keys, and an explicit LF checkout rule preserves the six
original recorded source hashes. No asset or hash gate was weakened. The bounded
companion lifecycle test required 67.719 seconds in one complete run, so its
supervision deadline is now 180 seconds; the subsequent 653-check run passed.
This deadline is not a performance budget.

The final integration also exposed an LF/CRLF-only Extra fit check and an
obsolete fixed-FPS fixture assumption. The unchanged fit generator produces
identical values on both engines; a specific Git attribute preserves its bytes.
Measured startup alignment supports ticks 120/240/360 on Windows and Linux;
exact rejection and complete-state checks remain intact. The existing Timber
shell hash parser passed unchanged.

## Remaining platform scope

Beta1 predates the upstream [Compatibility texture-slot fix](https://github.com/godotengine/godot/pull/124750).
The exercised RTX 3090 path does not qualify GPUs with the reported binding
collision. Linux desktop [X11-to-Wayland fallback](https://github.com/godotengine/godot/issues/124731)
also remains affected; an explicit Wayland driver bypasses that path only in a
valid Wayland session. Headless Linux success is separate from desktop coverage.
Real radio/gamepad identities, macOS execution, other GPUs, quiet-host performance
and full paired visual/audio baselines remain open.
One Linux 144-FPS fixture run reported 23 ObjectDB instances at exit; a bounded
verbose repeat preserved the numerical hashes but did not reproduce that
warning. Its cause remains unclassified in the integration evidence, and clean
Linux lifecycle qualification is not claimed.

Official Godot does not gain NVIDIA DLSS from this version switch. The
[native DLSS experiment](../../../../tools/graphics/native/README.md) remains a
separate engine build; unavailable providers continue to fall back to Native.
No release was published by this adoption work.
