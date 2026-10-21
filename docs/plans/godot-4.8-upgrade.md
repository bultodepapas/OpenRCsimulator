# Godot 4.8 upgrade plan

**Status:** GDU-00 done on 2026-10-21; GDU-01 onward open. Pinned engine: 4.7.2-stable. The latest 4.8 build is beta1 (2026-10-15), and stable is expected in Q4 2026. **Owner:** export/CI maintainer (DT/PT). The tracks listed per phase own their own acceptance. **Prefix:** `GDU-`. **Evidence:** `docs/research/engine-upgrade/`; audit in [GDU-00](../research/engine-upgrade/GDU-00/README.md).

## Goal and rules

Move the pinned engine from 4.7.2 to the first 4.8 build that passes every gate below, without silently changing physics, replay, identities or packages.

- **Upgrade one dependency at a time.** godot-cpp stays at 10.0.0-stable with `api_version=4.7`, and Python/Node pins stay unchanged.
- **Never ship a beta or RC.** Betas and RCs are only used in disposable worktrees (GDU-02).
- **Simulation must be byte-identical.** Golden flights, traces and fleet fingerprints are not re-recorded for the engine change. Any difference stops the upgrade until it is explained.
- **Visual and audio baselines change only with a paired, explained diff.** Each owning track accepts its own diff.
- **Upstream defects go upstream.** Report a regression with a minimal reproduction project. Use a local workaround only when it is scoped, tested and can be removed.
- **Keep commits small and separate.** The switch lands as reviewable commits: pin, settings, reimport, identities, then docs.

## Entry criteria for the switch (GDU-03)

1. A 4.8 stable build, or an RC that is expected to become stable unchanged, exists with an official SHA-512.
2. [#124742](https://github.com/godotengine/godot/issues/124742) (Compatibility globals) and [#124744](https://github.com/godotengine/godot/issues/124744) (macOS universal template swap) are fixed in that build, or have an accepted local workaround with a test.
3. The GDU-02 triage has no unexplained failure.

Rollback: revert the GDU-03 commits. The 4.7.2 pins, hashes and CI cache keys come back with them, because the cache keys hash `get-godot.sh` and `get-templates.sh`.

## Phases

### Phase 0: Audit (done)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-00 | Audit the 4.8 changelog (1,523 PRs), breaking changes and open regressions; scan `app/` exposure; register the track | Done 2026-10-21: [GDU-00](../research/engine-upgrade/GDU-00/README.md), [scanner](../../research/engine-upgrade/gdu00_exposure.py) |

### Phase 1: Upstream watch and early reports

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-01 | At each beta/RC, re-run the regression query and the scanner, and update the GDU-00 tables in a dated addendum | Open; addendum per build |
| GDU-01a | Reduce any project failure found in GDU-02 to a minimal reproduction project and report it upstream with a link back here | Open; issue links |

### Phase 2: Disposable trial on the current candidate

All work runs in a worktree or tree copy with the candidate editor in `.tools/`. Nothing is committed to `app/`. Only evidence is kept.

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-02a | Run `--import` and record the `.import`, `.tscn` and `.tres` churn by file type | Open; diff stat |
| GDU-02b | Run `app/test.sh` (all parts) and classify every failure as engine regression, required adaptation or intended behavior change | Open; triage table |
| GDU-02c | Run `app/capture.sh` and the field, landscape, sky, moon, lake, smoke and Workshop captures against the 4.7.2 set on the same host | Open; paired image report |
| GDU-02d | Linux export plus `export.sh` package checks; size comparison against 4.7.2 | Open; manifest and size table |

### Phase 3: Switch (after the entry criteria)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-03a | Pin the editor (`get-godot.sh`), templates (`get-templates.sh` version, SHA-512, `TEMPLATE_DIR_NAME`) and the CI Windows editor URL and path; set `config/features` to `"4.8"` | Open; hash check, CI green |
| GDU-03b | Write the new defaults explicitly in `project.godot` so 4.7 behavior is kept on purpose: `gui/common/auto_focus_strategy=0`, `input_devices/joypads/ignore_joypad_on_unfocused_application=false` and `display/window/size/enable_toggle_fullscreen_shortcut` per decision D1 | Open; settings test |
| GDU-03c | One mechanical commit with the regenerated `.import` metadata, and no hand edits | Open; diff limited to importer keys |
| GDU-03d | Rebuild the native ground-vehicle evaluator receipts against the new editor (godot-cpp unchanged); run 10,000-state parity and load checks | Open; receipts and parity report |

### Phase 4: Simulation and replay equivalence (physics/SF/FL owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-04a | Golden flights, SF fleet fingerprints and kernel trajectories: exact match with no re-record | Open; `test.sh` output |
| GDU-04b | Wind PCG32: `tests/check_wind_trace.py` and a raw-word comparison with 4.7.2 | Open; trace check |
| GDU-04c | Replay a 4.7.2 `.orfl` baseline on 4.8 with the same tape; require `complete` and no `solver_changed` (see [FLIGHT-LOGGING](../FLIGHT-LOGGING.md)) | Open; reports and CSV |
| GDU-04d | Physics tick cost p50/p95 against the 500 µs budget on the H4/H5 host, paired with 4.7.2 | Open; distributions |

### Phase 5: Rendering (VQ/FW/LU/SC/SM owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-05a | Shader globals now in a texture: correctness in all 29 global-uniform shaders (ground and trees first), plus frame-time cost | Open; captures and frame times |
| GDU-05b | Sky/fog/brightness changes: paired day, dusk, night and fog captures; retune `sky_state.gd` only with an explained difference | Open; image report |
| GDU-05c | Re-verify the FW-MOON-01 radiance invariant behind `world.gd` with the cubemap cost-amplifier probe | Open; probe output |
| GDU-05d | Tangents and normal maps: repeat the US-V09b dP/du test and run glTF/GLB model captures | Open; test and captures |
| GDU-05e | Lake probe ambient, MultiMesh scenery, flowers' per-instance colours, particle smoke and dust | Open; captures |

### Phase 6: Audio (AUD owner)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-06a | `tools/audio/bench.sh` mixed-output comparison of engines, soundscape, crash and menu audio against 4.7.2 | Open; bench report |
| GDU-06b | Check whether each 4.7.2 audio quirk still exists: the WAV loop padding (`Soundscape.seamless_loop`), the high-shelf squared gain, the limiter and hard-limiter release, and the 3D start-at-listener level; keep or remove each workaround with a test | Open; probe table |

### Phase 7: Input, UI and shell (UI/controller owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-07a | SDL 3.4.16: compare GUID, VID:PID and name strings for EdgeTX, JETI, Xbox and DualSense on Windows and Linux; check that existing calibrations still match | Open; device report |
| GDU-07b | Alt+Enter and display mode per D1; keyboard bindings using Alt or Enter; Windows Shift raw-input change | Open; UI tests |
| GDU-07c | Dialog titles and `es.po` coverage; focus navigation; the embedded-popup and focus-out workarounds (UI-31, TOD-08b) in editor and release builds | Open; UI tests and native smoke |

### Phase 8: Export and delivery (DT/PT owners)

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-08a | All three presets: the macOS release ZIP contains the release template (#124744), the embedded PCK loads, scripts never pass `-d` to release builds, and the Mach-O minimums are read back | Open; package checks |
| GDU-08b | Native launch on Windows and Linux (X11 and Wayland, #124731); macOS launch when DT-01a hardware is available | Open; native smoke logs |

### Phase 9: Identities and documentation

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-09a | Bump the presentation identity (AE-24), the presentation source pin, the companion qualification (AFC owner) and version-stamped tests; regenerate Timber geometry provenance through its generator | Open; tests |
| GDU-09b | Update STACK, TOOLS and DESKTOP-DELIVERY; mark each version-scoped LEARNINGS or DECISIONS claim as re-verified or scoped to 4.7.2; add a DECISIONS entry for the switch | Open; doc diff |

### Phase 10: Acceptance

| ID | Work | Proof/status |
| --- | --- | --- |
| GDU-10 | Full CI, capture set and release gates on the merged switch; owner accepts the visual, audio and packaging diffs; release notes name the engine change | Open; CI run and owner sign-off |

### Phase 11: Opt-in 4.8 features (after GDU-10, each a proposal to its owner)

These are not part of the migration. Each one needs its own plan step, budget and evidence:

- Alpha-test coverage import ([#104289](https://github.com/godotengine/godot/pull/104289)) for alpha-scissor trees and grass (L6/L11 owners).
- Compatibility decals ([#118070](https://github.com/godotengine/godot/pull/118070)) for crash and tyre marks (CR).
- Native `Trail3D` ([#117107](https://github.com/godotengine/godot/pull/117107)) as a smoke or trail candidate (SM).
- Texture streaming ([#113429](https://github.com/godotengine/godot/pull/113429)) for VRAM limits (DT/VQ).

## Owner decisions

| ID | Question | Proposal |
| --- | --- | --- |
| D1 | Keep Godot's Alt+Enter (Ctrl+Cmd+F on macOS) fullscreen toggle? | Disable it. Display mode stays in Settings and stays in sync with preferences |
| D2 | Adopt 4.8.0 directly or wait for 4.8.1? | Adopt 4.8.0 once the entry criteria and GDU-10 pass. Wait only if a blocker stays open |
| D3 | Accept per-track visual and audio re-baselines inside the switch, or in follow-up commits? | Follow-ups, each with its paired evidence |
