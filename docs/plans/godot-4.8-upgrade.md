# Godot 4.8 upgrade plan

**Status:** GDU-03 local development adoption verified on 2026-10-25: the owner explicitly requested 4.8 as the standard engine after the [GDU-02 parallel trial](../research/engine-upgrade/GDU-02/README.md), accepting beta risk. Current pin: official 4.8-beta1 (2026-10-15). [GDU-03](../research/engine-upgrade/GDU-03/README.md) retains complete logical Windows suite coverage, bounded numerical/native checks, frozen package checks and a separate late UI continuation. This supersedes the stable-only entry requirement; broader platform, performance and release gates below remain open. **Owner:** export/CI maintainer (DT/PT). The tracks listed per phase own their own acceptance. **Prefix:** `GDU-`. **Evidence:** `docs/research/engine-upgrade/`; audit in [GDU-00](../research/engine-upgrade/GDU-00/README.md).

## Goal and rules

Use the owner-authorized official 4.8-beta1 as the development engine, preserving physics, replay, identities and packages through explicit checks. Platform and release acceptance still require the remaining gates below; development adoption does not close them.

- **Upgrade one dependency at a time.** godot-cpp stays at 10.0.0-stable with `api_version=4.7`, and Python/Node pins stay unchanged.
- **Owner-authorized beta adoption (2026-10-25).** Official 4.8-beta1 is the standard development engine. This replaces the earlier beta-only-in-disposable-worktrees restriction. Adopting the engine does not claim completed platform qualification or authorize publishing a release.
- **Simulation must be byte-identical.** Golden flights, traces and fleet fingerprints are not re-recorded for the engine change. Any difference stops the upgrade until it is explained.
- **Visual and audio baselines change only with a paired, explained diff.** Each owning track accepts its own diff.
- **Upstream defects go upstream.** Report a regression with a minimal reproduction project. Use a local workaround only when it is scoped, tested and can be removed.
- **Keep commits small and separate.** The switch lands as reviewable commits: pin, settings, reimport, identities, then docs.

## Qualification criteria retained after the authorized switch (GDU-03)

1. The exact adopted build has verified official SHA-512 archives. Stable/RC availability is no longer an entry requirement following the owner's explicit beta adoption.
2. [#124742](https://github.com/godotengine/godot/issues/124742) (Compatibility globals) and [#124744](https://github.com/godotengine/godot/issues/124744) (macOS universal template swap) are fixed in that build, or have an accepted local workaround with a test.
3. The GDU-02 triage has no unexplained failure.

Rollback must restore the matching engine, generated identities and resources together. Once the migration is committed, revert its scoped GDU-03 commits; CI cache keys follow `get-godot.sh` and `get-templates.sh`. The current root has an unrelated pending merge, which this work preserves. The local companion qualification branch contains only its core/admission commits, not the complete migration, so reverting that branch alone is not an engine rollback.

## Phases

### Phase 0: Audit (done)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-00 | Audit the 4.8 changelog (1,523 PRs), breaking changes and open regressions; scan `app/` exposure; register the track | Done 2026-10-21: [GDU-00](../research/engine-upgrade/GDU-00/README.md), [scanner](../../research/engine-upgrade/gdu00_exposure.py) |

### Phase 1: Upstream watch and early reports

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-01 | At each beta/RC, re-run the regression query and the scanner, and update the GDU-00 tables in a dated addendum | Rechecked beta1 on 2026-10-25: [addendum](../research/engine-upgrade/GDU-02/README.md#gdu-01-update-upstream-state). Three blockers fixed on master, still present in official beta1; watch remains active |
| GDU-01a | Reduce any project failure found in GDU-02 to a minimal reproduction project and report it upstream with a link back here | Open; issue links |

### Phase 2: Disposable trial on the current candidate

All work runs in a worktree or tree copy with the candidate editor in `.tools/`. Nothing is committed to `app/`. Only evidence is kept.

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-02a | Run `--import` and record the `.import`, `.tscn` and `.tres` churn by file type | Done for Windows beta1, 2026-10-25: 307 `.import` files, 767 additions; no scene/resource churn; [evidence](../research/engine-upgrade/GDU-02/README.md) |
| GDU-02b | Run `app/test.sh` (all parts) and classify every failure as engine regression, required adaptation or intended behavior change | Trial superseded by [GDU-03 application coverage](../research/engine-upgrade/GDU-03/suite/README.md): all 709 unit scripts and complete logical Windows integration coverage, retaining explained failures and exact continuations. No single uninterrupted run or full remote CI claim |
| GDU-02c | Run `app/capture.sh` and the field, landscape, sky, moon, lake, smoke and Workshop captures against the 4.7.2 set on the same host | Open; paired image report |
| GDU-02d | Linux export plus `export.sh` package checks; size comparison against 4.7.2 | Superseded by [GDU-03 final exports](../research/engine-upgrade/GDU-03/exports/README.md): Linux release startup/package gates pass; paired package-size comparison remains open |

### Phase 3: Owner-authorized development switch

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-03a | Pin the editor (`get-godot.sh`), templates (`get-templates.sh` version, SHA-512, `TEMPLATE_DIR_NAME`) and the CI Windows editor URL and path; set `config/features` to `"4.8"` | Implemented with verified official archives; native Windows/Git Bash and Linux CLI checks pass. Full CI remains open; [adoption evidence](../research/engine-upgrade/GDU-03/README.md) |
| GDU-03b | Write the new defaults explicitly in `project.godot` so 4.7 behavior is kept on purpose: `gui/common/auto_focus_strategy=0`, `input_devices/joypads/ignore_joypad_on_unfocused_application=false` and `display/window/size/enable_toggle_fullscreen_shortcut` per decision D1 | Implemented; [native UI scenarios](../research/engine-upgrade/GDU-03/ui/README.md) pass. Physical-device focus behavior remains unqualified |
| GDU-03c | One mechanical commit with the regenerated `.import` metadata, and no hand edits | [Official import audit](../research/engine-upgrade/GDU-03/imports/README.md) and [final 422-sidecar export audit](../research/engine-upgrade/GDU-03/exports/source-receipt.json) retained; separate migration commits remain pending while the existing root merge is preserved |
| GDU-03d | Rebuild the native ground-vehicle evaluator receipts against the new editor (godot-cpp unchanged); run 10,000-state parity and load checks | Windows/Linux rebuild, load/float64, 733 evaluator checks and 2,676 exact lake scalars pass; [receipts](../research/engine-upgrade/GDU-03/native/). The broader 10,000-state gate remains open |

### Phase 4: Simulation and replay equivalence (physics/SF/FL owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-04a | Golden flights, SF fleet fingerprints and kernel trajectories: exact match with no re-record | [18 final-core trajectories](../research/engine-upgrade/GDU-03/numerical/final-core/README.md) match byte-for-byte across both engines and original/final core; [H6/H7 and existing integration contracts](../research/engine-upgrade/GDU-03/integration/final/README.md) pass. Bounded Windows comparison; no golden re-record |
| GDU-04b | Wind PCG32: `tests/check_wind_trace.py` and a raw-word comparison with 4.7.2 | [Five PCG and five OU streams](../research/engine-upgrade/GDU-03/numerical/final-core/README.md) match byte-for-byte; PCG matches the independent Python recurrence. [Turbulence CLI and exact FPS checks](../research/engine-upgrade/GDU-03/integration/final/README.md) pass; Linux P-51 checks retain their explicit lifecycle-warning limit |
| GDU-04c | Preserve strict `.orfl` engine/source identities; verify exact 4.8 replay and compare frozen numeric states across engines (see [FLIGHT-LOGGING](../FLIGHT-LOGGING.md)) | [Same-build replay passes; wrong-engine/source replay is rejected](../research/engine-upgrade/GDU-03/tooling/README.md). The original cross-engine `.orfl` acceptance criterion conflicts with the existing exact-engine contract and is not claimed. GDU-04a/b provide a separate bounded comparison without relabeling recordings |
| GDU-04d | Physics tick cost p50/p95 against the 500 µs budget on the H4/H5 host, paired with 4.7.2 | Open; distributions |

### Phase 5: Rendering (VQ/FW/LU/SC/SM owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-05a | Shader globals now in a texture: correctness in all 29 global-uniform shaders (ground and trees first), plus frame-time cost | [Bounded GPU oracles](../research/engine-upgrade/GDU-03/rendering/gpu-correctness/README.md) and production captures pass on RTX 3090. Full shader/cost qualification and affected 16-slot GPUs remain open |
| GDU-05b | Sky/fog/brightness changes: paired day, dusk, night and fog captures; retune `sky_state.gd` only with an explained difference | [Fourteen native 1080p captures](../research/engine-upgrade/GDU-03/rendering/native/README.md) pass; full paired visual acceptance remains open. No sky retune |
| GDU-05c | Re-verify the FW-MOON-01 radiance invariant behind `world.gd` with the cubemap cost-amplifier probe | Passed on both official engines at native 1080p, RTX 3090; [28 checked invocations and frozen sources](../research/engine-upgrade/GDU-03/rendering/moon/README.md). This is a path detector, not a performance qualification |
| GDU-05d | Tangents and normal maps: repeat the US-V09b dP/du test and run glTF/GLB model captures | Open; test and captures |
| GDU-05e | Lake probe ambient, MultiMesh scenery, flowers' per-instance colours, particle smoke and dust | Open; captures |

### Phase 6: Audio (AUD owner)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-06a | `tools/audio/bench.sh` mixed-output comparison of engines, soundscape, crash and menu audio against 4.7.2 | [Native cues/worker stress and bounded paired wind checks](../research/engine-upgrade/GDU-03/audio/README.md) pass. Full mixed-output bench remains open |
| GDU-06b | Check whether each 4.7.2 audio quirk still exists: the WAV loop padding (`Soundscape.seamless_loop`), the high-shelf squared gain, the limiter and hard-limiter release, and the 3D start-at-listener level; keep or remove each workaround with a test | Open; probe table |

### Phase 7: Input, UI and shell (UI/controller owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-07a | SDL 3.4.16: compare GUID, VID:PID and name strings for EdgeTX, JETI, Xbox and DualSense on Windows and Linux; check that existing calibrations still match | Open; device report |
| GDU-07b | Alt+Enter and display mode per D1; keyboard bindings using Alt or Enter; Windows Shift raw-input change | Open; UI tests |
| GDU-07c | Dialog titles and `es.po` coverage; focus navigation; the embedded-popup and focus-out workarounds (UI-31, TOD-08b) in editor and release builds | [Eight native editor scenarios and both menu crawls](../research/engine-upgrade/GDU-03/ui/README.md), [responsive geometry/focus](../research/engine-upgrade/GDU-03/integration/overlay-focus/README.md), and [compiled Windows UI/livery checks](../research/engine-upgrade/GDU-03/exports/README.md) pass; full packaged interaction and physical-input coverage remain open |

### Phase 8: Export and delivery (DT/PT owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-08a | All three presets: the macOS release ZIP contains the release template (#124744), the embedded PCK loads, scripts never pass `-d` to release builds, and the Mach-O minimums are read back | [All three final release archives and canonical package gates pass](../research/engine-upgrade/GDU-03/exports/README.md); verified project-local macOS correction, CRC/SHA256, resource/native/identity checks. [Final Mach-O readback](../research/engine-upgrade/GDU-03/exports/macos-minimum-os.json): arm64 macOS 13.0, x86_64 11.0 (declared minimums, not native compatibility acceptance). Nonfatal UID fallbacks retained; no publication |
| GDU-08b | Native launch on Windows and Linux (X11 and Wayland, #124731); macOS launch when DT-01a hardware is available | [Actual Windows release at 1080p and Windows/Linux headless trimmed flight pass](../research/engine-upgrade/GDU-03/exports/README.md). Linux X11/Wayland desktop and macOS execution remain open |

### Phase 9: Identities and documentation

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-09a | Bump the presentation identity (AE-24), the presentation source pin, the companion qualification (AFC owner) and version-stamped tests; regenerate Timber geometry provenance through its generator | Implemented; [final companion qualification/replay](../research/engine-upgrade/GDU-03/companions/final-core/README.md), generator checks and Timber physical-data checks pass. Timber/insulator geometry is unchanged; [application coverage](../research/engine-upgrade/GDU-03/suite/README.md) complete within its stated scope. Delivery must retain the qualification branch's source ancestry |
| GDU-09b | Update STACK, TOOLS and the [desktop delivery plan](../DESKTOP-DELIVERY-PLAN.md); mark each version-scoped LEARNINGS or DECISIONS claim as re-verified or scoped to 4.7.2; add a DECISIONS entry for the switch | Active engine/setup/tool instructions and DECISIONS updated. Historical measurements retain their original engine scope; [GDU-03](../research/engine-upgrade/GDU-03/README.md) identifies the rechecked behavior and remaining gates |

### Phase 10: Acceptance

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-10 | Full CI, capture set and release gates on the merged switch; owner accepts the visual, audio and packaging diffs; release notes name the engine change | Open; CI run and owner sign-off |

### Phase 11: Owner-authorized 4.8 improvements

On 2026-10-25 the owner requested exploiting 4.8's improvements after development adoption. This authorizes bounded feature work before GDU-10; it does not close the broader release gates. Each change retains its owning track's limits and paired evidence.

| ID | Owner and work | Evidence / boundary |
| --- | --- | --- |
| GDU-11a | L6/VQ: alpha-test coverage import ([#104289](https://github.com/godotengine/godot/pull/104289)) for the existing maple leaf atlas | [Native comparison and adoption](../research/engine-upgrade/GDU-11/README.md). One texture, unchanged source pixels/material cutoff/geometry, primary 1080p and secondary 1440p. Other vegetation requires its own evidence |
| GDU-11b | CR: Compatibility decals ([#118070](https://github.com/godotengine/godot/pull/118070)) for terrain-following marks | Candidate only. Beta1 permits eight decals per receiving geometry instance; current crash marks allow sixteen. Require bounded use/fallback and 9/16-mark tests before replacement |
| GDU-11c | SM: native `Trail3D` ([#117107](https://github.com/godotengine/godot/pull/117107)) | Deferred: ribbons do not supply existing smoke advection, buoyancy, residual or presentation-clock contracts. No demonstrated smoke replacement benefit |
| GDU-11d | DT/VQ: texture streaming ([#113429](https://github.com/godotengine/godot/pull/113429)) | Deferred for Compatibility: unsupported by the pinned implementation. Evaluate only within a separately qualified Forward+/Mobile profile and measured memory need |

## Owner decisions

| ID | Question | Proposal |
| --- | --- | --- |
| D1 | Keep Godot's Alt+Enter (Ctrl+Cmd+F on macOS) fullscreen toggle? | Disable it. Display mode stays in Settings and stays in sync with preferences |
| D2 | Adopt 4.8.0 directly or wait for 4.8.1? | Owner chose official 4.8-beta1 on 2026-10-25 after the parallel trial. Development adoption precedes full platform/release qualification |
| D3 | Accept per-track visual and audio re-baselines inside the switch, or in follow-up commits? | Follow-ups, each with its paired evidence |
