# Shadow settings and bounded Native comparison

2026-10-31 · VQ-04b-S01/S02, candidate S03 allocations, DT-11a bounds work.

This implements the first settings/ownership slice of the [shadow plan](../../../../plans/shadows.md).
It does not complete the coverage, motion, performance or package qualification of that plan.
Current quality and Automatic technique preserve the existing renderer defaults. Native remains an
explicit experimental comparison, with incomplete object coverage.

## Implemented behavior

- One presentation owner resolves requested and effective configuration and commits changed global
  directional-atlas/filter settings. World construction cannot reset saved quality. Existing and newly
  built suns receive the policy; the ground activity retains its 35 m cap. No simulation state changes.
- Settings adds quality, technique, aircraft cue, distance, softness and shadow-only defaults. Schema-1
  files migrate additively; invalid individual values recover independently. Live previews, Keep,
  Revert/Close, eight translations and renderer-restart persistence use the existing preference flow.
- Native suppresses field, population-contact, aircraft and wreck planes and promotes eligible opaque
  meshes from the existing nearby projection sources. Off suppresses both direct-shadow routes.
  Original visibility/casting flags return on Revert. Source destruction, detachment/reattachment,
  static Home previews, paused wrecks and replacement field managers have explicit regression checks.
- The default field inventory admits **8 source meshes in 3 selected scenery cells**, skips 8 material
  candidates and admits no current population batches. The existing 100 m scenery budget bounds the
  source selection. Alpha-cut people, separate shelters, distant trees and uncaptured objects remain
  limitations; this is not a claim of complete Native coverage. Whole native meshes also include low
  triangles excluded from the projected mask's 0.04 m cutoff.
- Hard sets angular size to zero as well as selecting hard filtering; it does not leave High PCSS
  accidentally active. Native presets expose 2048/4096/8192 atlases, two/four cascades and 100/300/600 m
  limits. Bias is unchanged. AO, cloud shade and the rejected contact-shadow experiment remain separate.
- Compatibility's existing light compensation follows effective native enablement. Weakly registered
  lights, environments and haze/sky/ground/water materials retain their own raw lighting inputs, so
  Apply does not use another retained world's time, reset exposure or accumulate round-trip drift.
- Saved cue changes seed the flight-local cue; **V** continues cycling the actual flight mode. Explicit
  launch controls retain precedence. Detached aircraft cannot reactivate a rendered projector through
  a later settings change.

The [player guide](../../../../FIRST-LAUNCH.md) owns the controls. [Graphics tools](../../../../../tools/graphics/README.md)
owns capture arguments. The new capture switches use the production resolver and report actual sun
enablement plus the bounded field-caster inventory.

## Source and environment

Work began at `4b89082c1eabf1e84766de827ec5992daeb61dfc`. Other sessions committed intermediate
shared-tree changes during implementation; those commit messages do not reliably describe this slice.
The verification snapshots use base `88cd28c1be72c2a6fed2db7e0f04eb73076dc4b1` plus
15 recorded overlays and six generated UID sidecars. They isolate suite source and user profiles from
concurrent edits. The Windows retry is `D:/OpenRC-shadow-verification2-20261031`, with
`tmp/shadow-verification2-inputs.json` and `tmp/shadow-verification2-toolchain.json` receipts.
The Linux visual snapshot is `/home/bulto/OpenRC-shadow-visual-20261031`, with
`tmp/shadow-visual-snapshot.json`. Generated UID sidecars come from the first snapshot's pinned-engine import.
At source review, the 21 overlay/UID hashes matched the working tree. A comparison of 1,823 tracked application source/text
files and 421 import sidecars matched after line-ending normalization; this is not a raw-byte identity
claim for every checkout file. Current tracked runtime content is also represented by
`d5ad6f8131cd80335bb044d6189034d9e0d4f5c2`, with the six UID sidecars still separate at verification time.

Native captures use official Godot **4.8-beta1 / 4d10419ca**, Windows, NVIDIA GeForce RTX 3090,
driver 617.42, Compatibility OpenGL 3.3 and Forward+ Vulkan 1.4.351, actual **1920×1080** offscreen
targets with 4× MSAA and fixed scene time. The live Settings inspection used the debug bridge and
confirmed a 1920×1080 fullscreen root viewport. This is a fixture/developer GPU observation, not minimum
hardware, active-flight or package qualification.

## Checks

Focused checks passed through the repository's checked runner:

| Contract | Result |
| --- | --- |
| Shadow resolver, light policy, compensation, exact restore, weak registry and retained lighting | 54 checks |
| Main's V input, saved/CLI cue precedence, presentation adapter and source reattachment | 35 checks |
| Field/native ownership, bounded selection, restoration and manager replacement | 40 checks |
| Shadow preferences, malformed input, migration, preview/save/Revert and receipt | 99 checks |
| Existing display preferences / advanced graphics UI | 160 / 146 checks |
| Existing projected aircraft / field / windsock / blur / wreck cache | 43 / 59 / 22 / 50 / 11 checks |
| Home preview / staged field / atmosphere / time-of-day update | 118 / 43 / 149 / 94 checks |
| Eight catalogs, ordered placeholders and required glyphs | Pass; 2,599 source messages |
| Existing real Settings integration, including paused-flight tick preservation | Pass |
| Documentation local targets/anchors / retained capture SHA-256 values | 106 destinations checked, no local errors / all 48 images match |

These are headless software results unless explicitly identified as native below. Additional atmosphere,
moon, lake, field-surface and ground-cache checks passed; their detailed logs remain in the temporary
checked-runner collections. Both full suites were attempted but remain incomplete as described below;
focused results do not substitute for them.

### Full-suite attempts

The first Windows snapshot (`D:/OpenRC-shadow-verification-20261031`) stopped in an aircraft-standardization
path-containment test because its `.tools` directory was a junction into the original checkout. No application
parse/unit roster ran. Its `tmp/shadow-full-suite` evidence is retained. A second snapshot uses a real local
`.tools` directory. Its first checked import emitted four `get_multiple_md5` / `f.is_null()` errors despite
engine exit 0, correctly failing `tmp/shadow-full-suite-r2`. A subsequent checked import passed without those
errors; the cause is not established. Neither failed attempt is a full-suite pass.

The unpartitioned third Windows attempt (`tmp/shadow-full-suite-r3`) passed the checked import and the
previously failing model-clone fixture. It continued through diagnostic, reference and generated-data
checks, including RCV-14a intake verification, with no test failure observed before interruption. It was
stopped when C: free space reached 8.49 GiB, preserving the 8 GiB minimum guardrail. The remaining source
checks and complete application parse/unit rosters did not run. The [stop receipt](suite-stopped.json)
records the exact last stage and termination. This is an incomplete run, not a pass.

Git Bash could not start `app/capture.sh` because `flock` was unavailable. The Linux snapshot has the pinned
engine and visual dependencies, and its checked import passed with zero errors and eight OBJ material
warnings. The full visual suite uses that isolated environment; native Windows 1080p observations remain
separate from the Linux reference-capture checks. Core Linux sidecars report Compatibility,
`llvmpipe (LLVM 20.1.2, 256 bits)`, Mesa 25.2.8 and 1280×720. These are regression fixtures, not the
primary-resolution acceptance evidence and not GPU performance measurements.

Linux setup passed 18 checks and the core-render phase completed: 29 atmosphere and nine field captures,
plus a separate sun-alignment capture. One Home UI capture also verified. The run was stopped during
English Pause UI capture at 9.51 GiB free on C:, before its later core image-check phase and remaining
suite. No complete-set manifest was produced. The timings file's `ui fail (0)` row is the manual-stop
trap artifact, not an observed assertion failure. The compact [partial visual receipt](visual-partial.json)
retains completed producer/image hashes. It does not establish a full visual regression pass.

### Native observations

Six views cover flightline, windsock, aircraft near the ground, pilot view, pavilion and lake.
The six **High current-default images are byte-identical** to the pre-implementation captures.
Standard aircraft-ground, pavilion and pilot images are byte-identical. The initial Standard comparison
differs at 26 flightline pixels (maximum 4/255), 4 windsock pixels (1/255), and 570 lake pixels (1/255).
These are recorded differences, not a blanket parity pass or an assumed noise tolerance.

A second current Standard run reproduces the 26-pixel flightline difference exactly. Its lake image differs
from the first current run at 823 pixels by 1/255; pilot differs at 3 pixels and windsock at 4, also by 1/255.
Thus this producer has a repeatability envelope, but that does not explain away the stable flightline
difference. No tolerance was widened and no Standard exact-default parity gate was closed.

Native High property checks pass 96 assertions, the shadow resolver/lighting test passes 54 on native
High, and the existing unoccluded-light GPU oracle passes with **zero sampled RGB difference** between
engine shadows off/on. Its controlled 512×256 panels are a color oracle, not a 1080p quality/performance test.
The 4096 atlas comparison changes only High's directional atlas allocation relative to Current 8192:
four cascades, depth precision, medium filtering and solar angular size remain fixed. The static comparison
shows fence-edge noise and incomplete population/shelter coverage; no allocation is promoted as a new default.

Native reveals building self-shadows and fence/bench cast shadows in the inspected stills. Missing
people shadows and other excluded sources remain visible limitations. Neither these stills nor a
larger atlas closes the landing-contact, thin-feature, camera-motion or temporal-stability gates.
High baseline and candidate producers both emit the existing seven Texture-RID shutdown warning.
The final native Settings inspection (`tmp/debug-bridge/20261031-092441-47870`) confirms the configured-cue,
distance-limit and experimental-coverage wording at 1920×1080. Revert succeeds; normal exit has no
observed crash or shutdown leak warnings.

Captures and receipts are retained outside Git under `tmp/shadow-implementation-{baseline,current,native}-{standard,high}`,
with the 4096 High comparison in `tmp/shadow-implementation-native-high-4096`. Checked logs are under
`tmp/shadow-implementation-render-checks`; native UI images/logs are in the dated `tmp/debug-bridge/` session.
No new screenshots or downloaded assets are committed.
The compact [capture inventory](captures.json) retains renderer, size, configuration, caster counts and image hashes.

## CPU work and C++ decision

Field population collection now resumes its already-completed static bounds scan at the first appended
population vertex. It retains the original ordered expansion; it does not substitute `Mesh.get_aabb()`.
The existing comparator passes **60 exact workload pairs** across three cells, checking faces/arrays,
serialized bounds, triangle counts and population counts against the preserved original. Additional
large/asymmetric transformed-population fixtures pass. Evidence is in
`tmp/shadow-implementation-cpu-bounds-20261031`.

All timing output from that comparator is excluded: concurrent rendered workloads prevented an
established exclusive measurement window. There is **no new speedup or FPS claim**. Godot already
performs the packed transforms and run appends in native code. A separate C++ helper, worker scheduler,
new library or engine fork was not justified by this pass and has not been added. The plan's current-engine
attribution and end-to-end native-helper gates remain open.

## Remaining work

Complete the required suites after adequate disk headroom is available, and resolve the Standard repeatability
investigation; retain the failed and interrupted tool evidence.
Then qualify actual moving flight/landing, low sun, fences and animated surfaces before selecting a new
default. Extend caster coverage through each asset owner, and separately evaluate local lights, nonplanar
receivers, foliage, cloud/moon coherence and the larger-resolution matrix. These remain S04–S11 work;
this record does not mark the entire plan complete.
