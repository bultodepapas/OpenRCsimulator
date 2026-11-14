# DT-MAC-11a / 07a1: first MetalFX implementation evidence

Date: 2026-11-14. Implementation and native API intake are in progress. This
record does not qualify four production technologies or establish an FPS gain.
The [plan](../../../plans/apple-metalfx.md) retains integration, motion, lifecycle,
latency, package and promotion gates.

## Source and host

Work started at `5e52336bf5b41e532045c8c03726518568f688b0`. Another concurrent
session incorporated the prerequisite edits and planning documents into mixed
commit `3c0f4c07da68b383bc1cf9e0318bb7dab04e91d0`; this task did not create or reset
that commit. Later working files and frozen overlays have separate identities.
Vehicle-paint and rotor edits are outside this task.

Strict SSH using the existing identity/known-host entries reached ANGELA_AIR,
`MacBook-Air-de-Angela.local`, account `gius`, Apple M1, native ARM64. Observed OS:
macOS **27.0.1 / 26A434**; CLT clang **21.0.0 / clang-2100.3.34.2**; SDK **27.0 /
26A425**. The Mac was on AC. Initial inventory showed 661 MiB free; a later
inventory showed 35 GiB and the previous workspaces absent. This task did not
delete them or claim credit for that space change.

New workspace: `/Users/gius/OpenRC-m1-work/metalfx-20261114/`. Native venv uses
CPython **3.12.15 ARM64**, psutil **7.2.2**, SCons **4.10.1**, zstandard **0.25.0**.
Existing keys, authorizations and frozen campaigns were preserved. No newer Mac
was available; the second Mac's documented mDNS aliases did not resolve.

## Implemented prerequisite fixes

The resource sampler holds one supported psutil `Process` identity for the
whole interval, checks before and after reads, discards a partially read replaced
process, and uses `Popen` liveness only for owned children. The CPU wrapper keeps
one sampler across its interval. The checked runner supplies its actual owned
game/helper handles; self/attached sampling remains unowned. Public schema and
creation-time metadata remain unchanged.

Native M1 source tests passed: **27** sampler, **14** checked-runner and **22**
CPU-wrapper tests, with one Linux-only skip. The six source-file hashes are bound
in the transferred fixture manifest. A 5.5-second owned Python-child smoke
reported required resource coverage complete, helper host-state coverage complete
and runner/helper overhead separately sampled. This is apparatus evidence, not
a game workload or performance qualification.

DropPool's unchanged-output cache now includes gravity, rain, height, mesh
identity, capacity and explicit mesh generation. All current production pool
mutations invalidate it; the production writer creates a fresh mesh. The sun
glare producer reuses its already calculated daylight background and preserves
the original luminance denominator, without adding halo/aureole to it.

On the official signed ARM64 `4.8.beta2.official.cafc17a19` editor:

| Focused M1 check | Result | Scope |
| --- | --- | --- |
| `test_lens_effects.gd` | 77 checks, zero failures/errors/warnings | Reduced source fixture; includes cache invalidation controls |
| `test_sun_optics.gd` | 118 checks, zero failures/errors/warnings | Full source-packet comparisons; moon assets added after first missing-resource failure |
| `test_metalfx_policy.gd` | 120 checks, zero failures/errors/warnings | Final injected status/rollback fixture; no GPU claim |
| `test_reconstruction.gd` | 127 checks, zero failures/errors | Shared reconstruction boundary |
| `test_fsr_history.gd` | 16 checks, zero failures/errors | Existing provider reset compatibility |

These are checked-runner verdicts, not merely process exit codes. The reduced
fixture's broad editor import failed on unrelated glTF files whose external
binary payloads were omitted. It is not a full-project import pass. The focused
tests passed after supplying their actual moon/font dependencies. Initial policy
tests also intentionally attempted an unsupported mode under Compatibility;
the final fixture skips that real-viewport branch on an unsupported backend.

The Windows shared-host queue never launched Godot: its materialized-copy
verification found file attributes 8224 instead of 32. Its optics attempt ended
`INFRA_FAILED`; the lens request was canceled before dispatch; both confirmed
cleanup and no claims remained. No queue policy was bypassed.

## Native API observations

The [native fixture](../../../../research/engine-upgrade/metalfx/README.md) builds
against the installed Apple headers and uses Metal3 command buffers. The first
compile failed because clang did not find libc++ `<tuple>` by default. Adding
`-isystem <SDK>/usr/include/c++/v1` compiled successfully, matching the previously
recorded CLT header-layout workaround. Nothing was repaired globally.

Retained `probe-r2` source SHA-256:
`d58de090a8e7f5c05bc54f67aaaf21b0e6492f285b18c26f4d7f62872ec810c3`;
binary: `996c3e4be3c73161fe9d052c334ba177e4a5ab886aadaba89a3e0c4e638da154`.
This is a historical fixture revision; later checked-in source also validates
reciprocal integer range and matches the Godot factory's manual exposure mode.

| Effect | Actual M1 observation | Unproven |
| --- | --- | --- |
| Spatial | Supported, allocated, GPU encoded/completed, all 1920×1080 RGBA16F output components finite; uniform-color maximum absolute error 0.00390625 | Moving image, gradients/HDR range, production performance |
| Temporal | Supported and allocated; native ratio bounds 1…3, Godot encoded limits 333333…1000000 | Encode, history/reset and product output |
| Frame interpolation | Supported and allocated | Encode, midpoint quality, production presenter and refresh pacing |
| Temporal denoised | Supported and allocated | Real RT producer, denoising encode, quality and performance |

Input was 1280×720; output was the primary **1920×1080** target. Spatial used one
uniform linear frame; its isolated cold GPU duration is not an FPS benchmark.
No generated frame advanced simulation, controls or audio.

The M1 reported Apple7=true, Apple9=false and ray-tracing API support=true.
Apple's current [feature table](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
(October 23, 2026, page 4) still lists Apple9 for denoised upscaling. The actual
`supportsDevice`/allocation observation disagrees with that floor; it does not
prove denoising execution or hardware ray-intersection acceleration. Eligibility
must query actual OS/symbol/device/descriptor and preserve the engine-input gate.

## Engine and application adapter

The [intake helper](../../../../tools/graphics/metalfx/README.md) pins official
Godot commit `cafc17a192acf67903910a68aeb3c076c0907a4b`, source ZIP SHA-256
`83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e`, ordered
patches and complete expected source catalog. It freezes inputs, rejects drift,
keeps pristine source separate from target build trees and records actual
toolchain/environment/artifacts. Thirteen intake/verifier negative-control tests
passed on Windows and native M1. Pair tests use explicitly synthetic receipts;
a real matching editor/template pair is still pending.

Frozen first patch SHA-256:
`f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a`.
It guards Spatial/Temporal allocation, latches failure until reconfiguration,
fills valid targets with the existing bilinear copy on factory/enqueue failure,
handles callback ownership, and exposes viewport/generation allocation/submission
status. `enqueued` is CPU submission, not GPU execution/completion.
Six focused compiled fake-SDK/rendering checks passed; they are source controls.

The production adapter accepts only coherent current viewport, generation,
requested/configured mode and provider failures. It restores Native/AA, preserves
saved preferences and prevents Auto from immediately reselecting that failed
provider. The official engine lacks the new API and stays unknown. Final app
overlay SHA-256: `2b09286232ba478e1cb9cc8de5d3670b1684ec2b489639a7d1f0d0a957910697`.

The first full native editor build stopped before the changed rendering units:
Godot requires `zstandard` with Python below 3.14. The builder now checks and
records the pinned dependency. A fresh intake/build follows; no failed attempt
is reused or represented as successful. Native compile, fault injection and
lifecycle results will be recorded here when available.

## Evidence retention and open gates

Raw receipts/logs remain in the task workspace's `candidate/tmp/` and native
fixture directories, with retrieved copies under ignored local
`tmp/metalfx-20261114/`. Initial sparse source ZIP SHA-256:
`20f2e606cd46831467fb31d26e966f5d37ab0007bce63c64a9f9ad15930b0245`;
dependency overlay: `018729e2438716d56fbd5cb4d157c01c84f638e7e7ae7bc6ac06e54dd03204aa`.
The reduced lens fixture archive is
`492298d00c3fb5bb9c4fa4c5a5b92e659cd08ae29930b46410e79c5ce30eab81`.
Later overlays are recorded separately; these are not a full frozen product build.

Remaining: actual engine/templates and native failure/reset tests, complete
production import/required CI, independent Temporal histories, FG input/presenter
integration, real engine RT/denoised consumer, moving-image/1080p workload
comparisons, physical latency, lifecycle/endurance and local development package.
Newer hardware remains useful for independent qualification; M1 denoising is an
open runtime finding, not an automatic unsupported result. Public Developer ID
distribution remains deferred. Normal reconstruction defaults are unchanged.
