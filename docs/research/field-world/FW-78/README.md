# FW-77/78/81/82 — sky selection and lifecycle

2026-10-13. Pinned native Godot `4.7.2.stable.official.ed1daf0bf`, Windows, Compatibility. This record covers the implemented appearance contract and its integration. The [world guide](../../../FIELD-WORLD-PLAN.md#sky-and-cloud-controls) owns player controls; the [active plan](../../../plans/sky-clouds-weather.md) owns remaining acceptance gates. Other tracks modified this working tree concurrently; this is not a clean-commit release qualification.

## Implemented boundary

- `environment/sky_appearance_config.gd` validates the exact `openrc-sky-appearance v1` schema and resolves the nine-profile JSON catalog into detached values. Explicit invalid CLI input refuses startup; unrelated flight CLI options still reach their owners. Old/corrupt preferences fall back to classic with a notice. A newer read-only preferences schema stays read-only.
- Home Weather gains a **Sky & clouds** tab and a compact selected-sky summary. Paused airplane flights use **Sky and lighting**, with the same controls. Selection, cloud motion, wind aloft and storm preferences remain a draft until Apply. Choosing another cloud shape preserves an explicit motion/aloft selection and flash/audio settings. The night action modifies the time draft explicitly; ordinary sky selection leaves physical weather and time alone.
- `render/weather/cloud_transport.gd` evaluates wrapped analytic offsets from a float64 anchor. Still is zero velocity; Follow wind maps configured mean NED wind to the renderer; Wind aloft supplies independent meteorological FROM direction. Classic defaults preserve the old seed and drift; its other motion modes use the actual legacy deck cell size. CPU state remains float64 until conversion to shader vectors. No physical RNG or frame-delta integration is used.
- Sky, solar-disc transmission, stars, ground and near grass receive the resolved cloud state. Star masks are associated with their own Environment resource, including retained Workshop worlds. A failed candidate launch rebuilds the accepted Home appearance; returning from a Workshop trial restores the retained flight's transport, night helpers, flowing-world references, shader clock and adapted exposure. These scene references are weak and are not serialized into save files. The helicopter route explicitly resets classic instead of inheriting Home's shader state.
- `app_state/sky_checkpoint.gd` adds a hashed native envelope around the accepted visual/physical checkpoint. It stores selection, resolved catalog profile, transport and ordered edits. Validation precedes mutation and binds transport to accepted physical weather/time. Catalog retunes are refused rather than silently replayed. Historical envelopes still select classic; untouched classic checkpoints keep the old format. Trace and capture metadata include the resolved appearance without changing physics identity.
- Electrical storm is presentation-only. Its event, local-light and audio contracts, licensed intake and limits are recorded separately in [FW-84](../FW-84/README.md).

## Software verification

Canonical logs are in [checks](checks/). Native headless tests use the exact project and Dummy audio; both exit status and engine error output were checked. Runtime errors can otherwise exit Godot with status zero.

| Test | Scope |
| --- | --- |
| `test_sky_appearance_config.gd` | Catalog schema, invalid inputs, detached resolution, defaults, CLI parsing/identity and cardinal mean wind. |
| `test_sky_preferences.gd` | Old/corrupt settings, save/load, detached values and future-schema read-only protection. |
| `test_ui_sky.gd` | Shared draft controls, explicit aloft persistence across cards, apply/cancel, weather/time independence and Home affordance at 720p. |
| `test_sky_routes.gd` | Actual AppRoot Home → Apply/Cancel → flight → paused sky edit; persisted state and unchanged physics/time. 10 checks passed. |
| `test_sky_checkpoint.gd` | Every profile preserves complete physics bytes, including noncalm weather and turbulence RNG; exact restore, old envelope, tampered profile/wind/history rejection and running-flight refusal. 45 checks passed. |
| `test_cloud_transport.gd` | Sign, units, periods, still/calm, classic mode semantics, strict checkpoint shape and float64 phase rebasing. |
| `test_sky_render.gd` | Resolved renderer parameters, layered ordering, clear path, classic seed/motion, ground composition and cloud occlusion. |
| `test_world_stars.gd` | Existing star geometry plus layered masking and retained-Environment refresh. |
| `test_world_presentation_context.gd` | A temporary world can be freed before restoring the retained world's flow, night helpers, exposure and shader clock. The retained flow continues updating its own scene. 17 checks passed. |
| `test_workshop_integration.gd` | Real Home/paused-flight trial routes, candidate failure and return preserve the previous flight, selected sky and adapted exposure. |
| Existing Home/weather/time/checkpoint/world tests | `test_ui_home`, `test_ui_weather`, `test_ui_time_of_day_pause`, `test_ui_field_world_time_of_day`, `test_time_of_day_checkpoint`, `test_world_flow`, `test_world_sky`. |

Example standalone command from the repository root, after resource import:

```powershell
& ./.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --log-file C:/absolute/check.log --script res://tests/test_sky_checkpoint.gd
```

`app/test.sh` discovers the added tests automatically. The complete repository suite was not run for this slice; the checks above are the affected contracts and regressions. No aircraft data or golden flight was changed by the sky work. Concurrent aircraft/failure/vehicle/night-light edits remain separate.

## Visual evidence and package inventory

[EN/ES 1280×720 captures](captures/) use the actual AppRoot, Home and conditions dialog with an isolated temporary preference file. They cover the entry point, two-column image cards and the electrical controls. The capture producer is [sky_ui_capture.gd](../../../../tools/atmosphere/sky_ui_capture.gd). Programmatic focus checks and captures do not establish physical-controller acceptance.

[FW-79](../FW-79/README.md) records nine native daytime profiles and quiet/peak moonlit/moonless electrical scenes. [Classic comparison](../FW-79/classic-parity/comparison.json) found zero changed channels in 12 directional field/sky views at two simulation times. The fixture reused `l4c_capture.gd` with the aircraft builder replaced by an empty Node3D: the frozen pre-sky working tree could not import the entire application because of unrelated in-progress aircraft/UI interfaces. Thus this establishes field/sky pixel preservation, not whole-app or aircraft parity. The baseline is the locally frozen `.tools/fw76-baseline-20261013/app` snapshot; it is not a clean historical Git checkout.

The Windows pack inventory probe passed 23 checks for all profiles and imported thumbnails, the OGG, both license notices, cloud-flash shader and visual checkpoint script. The producer is [sky_pack_probe.gd](../../../../tools/atmosphere/sky_pack_probe.gd), run with `--main-pack` from an empty directory. All three export include filters explicitly include the catalog and notices.

**Full export qualification failed:** the independent aircraft export plugin reported `Cannot export an invalid aircraft model: ["no checked-in model manifest exists for this visual family"]`. Godot still wrote a pack; the successful sky-asset probe does not make that pack a valid release. [Export log](checks/package-export.log), [inventory result](checks/package-probe.log). No published build was produced. Linux/macOS export checks remain open.

## Remaining limits

The renderer uses projected procedural layers and a one-second transport quantum. Dense-cloud art, low-angle/moving-camera behavior, fast-wind stepping, aircraft tracking through flashes, minimum-GPU cost and full circuit review remain acceptance work. The RTX 3090 captures are visual evidence, not minimum-hardware performance measurements; concurrent engine work makes this session unsuitable for isolated timing claims.

Natural Random still selects classic. The rotorcraft route has no sky editor/storm consumer. Progressing FW checkpoints keep their prior unsupported-path refusal. There is no rain curtain, volumetric traversal, tropical-band scene, spatial storm force or tornado challenge in this implementation. Their requirements remain active in FW-83 and FW-85–90.
