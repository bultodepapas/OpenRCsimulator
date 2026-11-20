# Legacy modes audit: native physics and the Compatibility renderer (2026-11-20)

The owner asked two questions:

1. How much of the native physics kernel is already on by default?
2. Can development stop spending effort on the Compatibility (OpenGL) renderer as a legacy mode?

This report answers both from three sources: the code, today's CI, and runs on DEVIL (Windows, RTX 3090) and ANGEL (M1).
Code was read at `48580b75a`. Traces ran on the working tree of that day. CI evidence comes from run 44693516940
(`a70d2a8f7`). The owner accepted §3 on 2026-11-20. It is recorded in [DECISIONS](../../DECISIONS.md#compatibility-is-a-frozen-legacy-renderer).

## Verdict

| Question | Answer |
| --- | --- |
| Is native physics the default? | **Yes, for every stock fixed-wing aircraft on Windows and Linux x86_64**, in source runs and in release packages. On Windows, 11 of 11 were verified today. **The helicopter's default flight is not native.** Club field publishes a lake, the native helicopter refuses lakes, and the flight runs GDScript; it runs native only on Green paradise. On Apple Silicon, native is the default only in source/editor runs, and the public macOS package ships GDScript physics. The airship and the multirotor have no native path. |
| Can the GDScript physics be retired? | **No.** The C++ mirrors it bit for bit, so it is the specification. It is also the qualification oracle, and the only path for imported (Creator) aircraft. Stop using it as a *runtime* mode; keep it as code. |
| Can Compatibility be retired? | **Freeze it now; do not delete it yet.** Stop new look calibration and new Compatibility-only features. Today Compatibility is still the *Standard* renderer for integrated and weak GPUs, Intel Macs, Linux laptops and the Steam Deck: about 18% of the Steam top-45 share at 1080p, and most players at 4K. Those players keep a supported path until the four gates in §2 close. |

## 1. Native physics kernel

### Status by platform and vehicle

| Route | Default backend | Evidence |
| --- | --- | --- |
| Fixed-wing, Windows x86_64, source and release | native | All 11 fixed-wing catalog aircraft logged `"backend":"native"` in today's headless traces on DEVIL (see Method). All 138 mirrored sources match `build-receipt-windows.json`. The CI job "NK-4 native kernel qualification (Windows)" passed. The Windows package carries the DLL, following the owner decision of 2026-11-18 ("native kernel always"; `export.sh` runs `package.py prepare-windows`). |
| Fixed-wing, Linux x86_64, release | native | CI builds, qualifies and packages the `.so` on every run ("NK-3 … (Linux)", passed). `export.sh` runs `package.py prepare`. |
| Fixed-wing, Linux, DEVIL's WSL install | **reference (stale)** | The ignored local `.so`, dated 2026-11-12, differs from 10 of its 135 mirrored sources (`flight_session.gd`, `simulation.gd`, `native_stage.gd` and others). Local Linux runs on this host fall back silently. Development only. |
| Helicopter (X-Cell), Windows/Linux, Club field (default landscape) | **reference** | Today's trace logged `"reason":"native helicopter terrain does not support lakes; using gdscript_reference"`. Club field publishes a `lake_context` (`helicopter_main.gd:156`), and `native_configuration.gd` refuses any lake for the helicopter. |
| Helicopter, Green paradise | native | Native in today's trace. Spatial, thermal and turbulence weather also fall back to the reference. |
| Fixed-wing, macOS arm64, source/editor | native inside the screened stock domain | The CI Apple Silicon job (`installed-default-route.log`) shows: the default route runs native; a custom spawn falls back to the reference and logs the reason; an explicit reference request is respected. Result `MACOS_DEFAULT_ROUTE verdict=pass checks=74`. Decision DT-MAC-11a. |
| Fixed-wing, macOS public package | **reference** | `export.sh` builds the Mac zip through `macos_reference_receipt.py`. Native Mac packaging (`package.py prepare-macos`) is still experimental. |
| RC ground vehicles | native (separate `openrc_ground_vehicle` module) | Selected automatically when its receipt loads. CI builds and checks it ("RC native … build/production checks", passed), and `export.sh` verifies it before shipping. |
| Airship, multirotor | GDScript only | No native code path exists. |
| Creator-imported aircraft, servo law, RC-track circuit | reference by design | `main.gd:_requested_stage_backend` pins the reference for Creator trials. `flight_session.gd:_prepare_stage_backend` refuses servo law and the RC circuit terrain. |
| Low-level tools, replay, historical `.orfl` baselines | reference by design | `FlightSession` defaults to `gdscript_reference`. Replay must reproduce the recorded backend ([flight logging](../../FLIGHT-LOGGING.md)). |

### What native buys

Measured on the live flight route, RTX 3090 host, 2026-11-17
([matrix](../visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17/README.md#native-physics-results)):

| Measure, reference → native | Result |
| --- | --- |
| Median physics step | 742 → 384 µs (1.9×), inside the 500 µs Gate P budget |
| Wall frame time, p50 | −25–40% |
| Wall frame time, p99 | −30–60% |

The Standard/OpenGL row at 1080p went from 4.47 to 3.44 ms at p50 and from 10.26 to 5.82 ms at p99. Stage-level
figures in [NK-4](../native-kernel/NK-4/README.md#measured-cost) are higher (2.3–2.8×). They come from a debug editor
binary on a loaded shared host and exclude the session observers. Use the live-route numbers for product claims.

### Why the GDScript reference stays

- The native build is a **mirror**. `research/native-kernel/build.py` pins 138 GDScript sources by hash, and the C++ is
  qualified as bit-identical to them. Physics is still authored in GDScript and then mirrored.
- It is the only physics for imported aircraft, servo law, the airship and the multirotor.
- It is the guaranteed fallback when an artifact or a configuration is refused.

Making the C++ the source of truth would remove the mirror cost. That is a separate architecture decision, and this
audit does not recommend it.

### The real risk: silent fallback

A refusal roughly doubles the physics step and prints a single log line. Any edit to a pinned source disables native
until it is rebuilt and requalified. This has already happened:

- 2026-11-12, Linux.
- 2026-11-17, Windows. The matrix's first live rows ran on the reference.
- 2026-11-19, Windows (audit F11).
- Today, on DEVIL's WSL install.

Telemetry records the renderer but not the physics backend (`telemetry_contract.gd`). A fallback in a player's build
would therefore be invisible.

## 2. Compatibility renderer

### Current roles

| Profile | Renderer | Who gets it |
| --- | --- | --- |
| High | Forward+ | Windows and Linux x86_64 dedicated GPUs with at least 4 GB whose predicted High time is at most 4.3 ms. That covers about 82% of the Steam top-45 share at 1080p and 26% at 4K ([DECISIONS](../../DECISIONS.md#compatibility-baseline-and-a-windows-nvidia-package)). |
| Standard, Apple Silicon | Mobile (Metal) | Every Apple Silicon Mac (`rendering_method.arm64`, DT-MAC-05b). |
| Standard, all other hosts | **Compatibility** | Integrated GPUs, unknown GPUs and weaker cards (GTX 1060/1650 class). Also Linux laptops and the Steam Deck, Intel Macs, and players who chose Standard. |
| Project setting | **Compatibility** | Every editor-binary test, capture and research launch. CI captures run `--rendering-driver opengl3` on Xvfb/llvmpipe at 1280×720. |

### Evidence

- **On the measured RTX 3090, Compatibility is never the cheapest renderer.**
  - GPU time: it costs more than Forward+ below about 1440p.
  - Render CPU: 3.5–5× that of the RenderingDevice renderers.
  - High was about 35% faster at 1080p.
  - On the live route, measured rather than interpolated, Mobile was fastest and OpenGL slowest (p50 2.52 / 2.72 / 3.44 ms for Mobile / Forward+ / OpenGL).
  - That host is CPU-bound in flight, and the plan's Mobile GPU row is an interpolation kept out of decisions ([automatic-graphics §2](../../plans/automatic-graphics.md#2-evidence-and-extrapolation)).
- **On the M1, Mobile is about 1.33–1.4× Compatibility, and Forward+ is 21–27% slower than Mobile** (DT-MAC-03b,
  2026-11-18). Forward+ is therefore the wrong default for weak or tile-based GPUs.
- **No weak GPU has been measured.** The rows for Iris Xe, UHD, 780M, Steam Deck and GTX 10xx are extrapolated from the
  3090, and the plan marks them unvalidated. That Mobile beats Compatibility on those machines is a prediction, not evidence.

### What keeping Compatibility costs

Counts come from `rg` on `CURRENT_RENDERER` in shaders and on `get_current_rendering_method|"gl_compatibility"|"forward_plus"` in non-test GDScript.

- **Shader branches.** There are 7 renderer branches in 5 shader files: water, sun glare, ridge haze, sky and
  `engine_srgb`.
- **GDScript checks.** There are 62 renderer checks across 29 files.
- **Compatibility-only workarounds.** These include:
  - the shadow-energy compensation in `atmosphere.gd`;
  - the projected aircraft-shadow proxy;
  - crash-shader warm-up;
  - sky retention for a GL cubemap bug;
  - the lake ambient probe.
- **Tests.** About ten tests assert Compatibility behaviour. Two of them require the project renderer to stay
  `gl_compatibility`.
- **Captures and look.** Every capture and the calibrated Standard look are on GL.

### Gates before Compatibility can become fallback-only

1. **The weak-GPU default.** Mobile must be measured against Compatibility on one Intel and one AMD integrated GPU at 1080p. First result (2026-11-20, UHD 630, Linux/Mesa): Compatibility is the fastest, Mobile +21% GPU time ([evidence](../visual-quality-implementation/VQ-07/igpu-uhd630-2026-11-20/README.md)), so Compatibility stays Standard for that class. Mobile's forced `use_hdr_2d` buffer must be costed, and the Windows driver (D3D12 or Vulkan) chosen per vendor. The owner must also accept Mobile's Windows look. All of this is [VQ-07h A5 → A2](../../plans/automatic-graphics.md#a2-renderer-strategy-efficient--mobile-behind-measurement). Mobile lacks SSAO, PCSS and the High cascades, so for those players it is a Standard look on a faster renderer, not High.
2. **Recovery.** `RendererGuard` restarts an unconfirmed RenderingDevice launch into Compatibility. Recovery must be generalized per renderer, and must cover hybrid laptops, which may be classified from the wrong adapter.
3. **CI captures.** They run on software OpenGL. A Vulkan software path is now proven feasible (§4) and wired as an
   opt-in CI job; it still has to run on CI and gain its own image contracts before it can replace the GL captures.
4. **Hardware with OpenGL only.** GPUs without Vulkan, D3D12 or Metal (Intel HD 4000–4600, Fermi, pre-GCN AMD) can run only OpenGL; Godot falls back to it automatically. Intel and Rosetta Macs are in the same position. Keeping them supported or dropping them is an owner decision.

The Web export is **not** a reason to keep Compatibility. There is no Web preset, and `advanced-graphics.md` rules out a web build. The `project.godot` comment calling Compatibility "the only one Godot can export to the web" is stale. Windows arm64 is not shipped; if it ships, `rendering_method.arm64` selects Mobile there.

## 3. Development policy (accepted 2026-11-20)

**Stop doing:**

- New look calibration on Compatibility. New visual features target Forward+ (High) and Mobile. On Compatibility they may be disabled or reduced, as long as the frame stays correct.
- New features or effects built only for Compatibility.
- Using Compatibility results as evidence for High, Mac or 4K performance.
- Running flights on the GDScript physics for performance or feel tuning. Confirm the `physics backend: … native` log line first. Historical `.orfl` baselines and replay keep their recorded backend.
- Citing the Web export as a constraint.

**Keep, because weak-GPU players depend on it until the gates close:**

- Compatibility as the Standard renderer: it must start, fly, stay readable and pace well.
- Fixes for crashes, hitches, compile stalls and frame pacing on Compatibility (for example the grass compile stall). Compatibility measurements remain the performance acceptance for weak GPUs until A2 passes.
- CI captures on Compatibility. They are 720p image contracts, not 1080p or High evidence.
- The GDScript physics reference, as specification, oracle and fallback.

**Next steps, in order:**

1. **Make physics fallback loud.** Done 2026-11-20 for flights and the debug bridge (§4). Remaining: add the physics
   backend to the telemetry contract (TELEM, needs a receiver deployment) and rebuild DEVIL's WSL Linux install.
2. **Native helicopter on lakes.** The default helicopter flight runs on GDScript today. Either add lake terrain to the
   native helicopter, or record the fallback as a known limit. The HELI track owns the water policy
   ([HELI-33](../helicopter/HELI-33/README.md)).
3. **Close VQ-07h A5 → A2** (gates 1 and 2). If they pass, Automatic selects Mobile for weak GPUs and Compatibility
   becomes fallback only.
4. **Run the Vulkan capture shadow on CI** (gate 3; §4). Dispatch `ci.yml` with `vulkan_captures`, then decide per
   group which image contracts can move to Mobile/Forward+.
5. **Ship native physics in the macOS package**, completing the existing DT-MAC promotion path.
6. **Owner decision, optional.** Drop Intel Macs and pre-Vulkan GPUs from the supported list (gate 4). Together with steps 3
   and 4, this would let Compatibility be removed entirely.
7. **Documentation.** Done 2026-11-20: DECISIONS, STACK, the automatic-graphics plan and the `project.godot` comment.

## 4. Changes made on 2026-11-20

The owner accepted §3 and asked for the three highest-return changes.

1. **The policy is recorded.** It is in [DECISIONS](../../DECISIONS.md#compatibility-is-a-frozen-legacy-renderer), with
   updates to STACK, the automatic-graphics plan and the stale `project.godot` web comment. No renderer key changed.
2. **Native fallback is visible.**
   - [`native_fallback.gd`](../../../app/app_state/native_fallback.gd) classifies `stage_backend_status()` as `native`,
     `selected`, `domain`, `stale` or `missing`.
   - A normal flight now raises an engine warning in two cases: a stale build or package on any host except the macOS
     release, and a missing library on Windows or Linux x86_64. Trace and capture runs keep the existing log line only.
   - The debug bridge `state` reports `flight.physics_backend`.
   - [`test_native_fallback.gd`](../../../app/tests/test_native_fallback.gd) has 71 checks. It derives every installation
     refusal from `native_stage.gd` and `native_package.gd`, so a new or reworded reason cannot silently classify as an
     expected domain fallback.
   - The edits stay out of `app/physics`, `app/sim` and `app/failures`. The Windows native install still matches all 138
     mirrored sources. Re-traced flights stayed native (Stik electric) or quietly reference on the lake (X-Cell).
3. **CI captures can run on Vulkan.**
   - `app/capture.sh` accepts `OPENRC_CAPTURE_RENDERER=mobile|forward_plus`. The default stays `--rendering-driver opengl3`.
   - `tools/ci/capture_groups.py` admits the variable and records `driver: vulkan` and `rendering_method`. The default
     receipt is unchanged (3 new tests, 23/23 pass).
   - `ci.yml` gains the manual, non-required job `vulkan-captures` (core group, Mobile and Forward+).

### Vulkan capture feasibility (WSL Ubuntu 24.04, Mesa 25.2.8, pinned Godot 4.8-beta2)

These are the same Ubuntu and Mesa versions as the CI runner. Every run used Xvfb, `LP_NUM_THREADS=1` and no GPU.

| Case | Compatibility, llvmpipe GL | Mobile, lavapipe | Forward+, lavapipe |
| --- | --- | --- | --- |
| Minimal probe (sky, PBR, shadows) | 4.5 s | 7.4 s | 8.1 s |
| Real core shot (`--scripted`), first / second run | 12.6 / 9.9 s | 54.5 / 18.8 s | 51.0 / 14.8 s |
| Real field shot (production Club field), first / second run | 46.3 / 22.2 s | 247.4 / 64.9 s | 201.9 / 37.4 s |
| Errors, fallbacks | 0, 0 | 0, 0 | 0, 0 |
| Same image on both runs | yes | yes | yes |

Each renderer produced byte-identical images on repeated runs. Forward+ was also identical at 1 and 4 lavapipe threads.
The adapter reported `llvmpipe` on the `vulkan` driver, so no OpenGL fallback occurred.

The first run is dominated by shader compilation. Within one capture run all shots share a profile, so only the first
shot pays that cost. Warm Forward+ costs about 1.5–1.7× Compatibility, and Mobile about 2–3×.

The renders were reviewed visually. Forward+ matches the GL field closely. On Mobile the HUD panel blends lighter,
which is an A2 look item (2D under `use_hdr_2d`). The images are not retained in the repository.

## 5. Follow-up work, 2026-11-20 (second request)

| Item | Result |
| --- | --- |
| Vulkan captures in CI | The `vulkan-captures` job runs on lavapipe. The first dispatch exposed two problems: cold pipeline compilation needs more than the 60 s first-shot limit, and the Vulkan process hangs at quit after saving its capture. `capture.sh` now gives Vulkan +540 s and an `--exit-grace` of 20 s, so the runner stops a process that has already saved its evidence. Compatibility keeps the strict path. A clean CI pass is still pending (run 44783172957). |
| Physics backend in telemetry | Done. Schema v2 adds `activity_summary.physics_backend`, under notice 2026-11-20 in 9 languages. The receiver on PRIMIS CT 404 runs release `0c6579085`: 133 tests pass, `check-release v0.3.0` returns ok, and v1 is still accepted. See [DECISIONS](../../DECISIONS.md#telemetry-schema-v2-reports-the-physics-backend). |
| Native helicopter over lakes | Done on branch `heli-native-lake`, draft [PR #16](https://github.com/bultodepapas/OpenRCsimulator/pull/16). On Windows, all 18 gates and the negative control pass, the build installs, and the lake oracle and an end-to-end Club flight are identical to the reference. A 120 s Club flight takes 31.8 s of wall time native and 52.1 s on the reference. The merge waits for CI on Linux and macOS. |
| Mobile on an integrated GPU | Measured on an Intel UHD 630 under Linux/Mesa: Compatibility is fastest, Mobile costs +21% GPU time and Forward+ +60%. [Evidence](../visual-quality-implementation/VQ-07/igpu-uhd630-2026-11-20/README.md). Windows Intel and an AMD iGPU remain open. |

Side fix: commit 6a536bcb0 had changed `main.gd` without renewing the AI-companion behavior manifest, which failed
every Godot unit shard. It was renewed in d0a5c65bd.

## Method

- **Code read:** `app/project.godot`, `app/app_state/renderer_preference.gd`, `app/sim/native_stage.gd`,
  `app/sim/native/native_configuration.gd`, `app/sim/flight_session.gd`, `app/main.gd`, `app/helicopter_main.gd`,
  `app/physics/ground_vehicle/vehicle_dynamics.gd`, `app/export.sh` and `.github/workflows/ci.yml`.
- **Receipt check:** the SHA-256 of every mirrored source's raw bytes against both receipts, as `native_stage.gd` does.
  Windows matched 138/138; Linux matched 125/135.
- **DEVIL runs:** `Godot_v4.8-beta2_win64_console.exe --headless --path app -- --aircraft=<id> --trace=… --t=2` for all
  12 catalog aircraft on Club field. The 11 fixed-wing aircraft ran native; the helicopter ran the reference (lake). The
  helicopter was rerun with `--landscape=green_paradise` and ran native. Logs are retained outside the repository at
  `U:\OpenRC\tmp\native-eval\`.
- **CI:** run 44693516940 passed all native jobs. I read `domain-guard.log` and `installed-default-route.log` from its
  macOS ARM64 artifact `native-macos-correctness-44693516940-1`.
- **ANGEL (M1):** reachable over SSH (macOS 27.0, Apple M1), but it has no current native-kernel workspace. Building one
  would add nothing over today's CI Apple Silicon run. The Mac renderer figures come from DT-MAC-03b (ANGEL, 2026-11-18).
- **Not measured today:** the interactive launch (`sim_launch`) was not admitted by the shared-host queue within
  30 minutes, so no rendered session was measured, and no renderer figure was re-measured. I could not read live
  telemetry.
- **Review:** an independent review checked the claims against the sources. It corrected the physics speed-up, the
  Mobile evidence and the scope of the stop-doing list.
