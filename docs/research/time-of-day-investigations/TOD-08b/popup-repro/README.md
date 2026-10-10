# TOD-08b embedded popup release error

Status: reproduced on the pinned Linux release export; native-popup workaround verified. Evidence for TOD-08b.

Godot 4.7.2 source mode closes the built-in `OptionButton` popup without engine errors. The Linux release export from the same installation emits two errors on close, even though the item is selected: `Popup::_deinitialize_visible_parents()` attempts to disconnect `focus_entered` and `tree_exited` connections that are absent. The minimal project has no `popup_hide` listener. Setting `get_popup().force_native = true` when `DisplayServer.FEATURE_SUBWINDOWS` is available removes both errors in source and release mode while preserving selection.

The driver performs a real XTest key sequence (Enter, Down, Enter) against the window. On this run, Godot reported `4.7.2.stable.official.ed1daf0bf`; the pinned engine binary SHA-256 is `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`. The release export SHA-256 and full case results are in [`logs/report.json`](logs/report.json). Conditions: Linux x86_64, Xvfb at 1280x720x24, Mesa llvmpipe (OpenGL 4.5), `FEATURE_SUBWINDOWS=true`.

| Mode | Engine errors | Popup opened | Item 1 selected |
| --- | ---: | --- | --- |
| Source, embedded default | 0 | yes | yes |
| Release, embedded default | 2 | yes | yes |
| Source, `force_native` | 0 | yes | yes |
| Release, `force_native` | 0 | yes | yes |

Reproduce from the repository root (requires the pinned engine and `xvfb-run`):

```sh
xvfb-run -a -s '-screen 0 1280x720x24' python3 docs/research/time-of-day-investigations/TOD-08b/popup-repro/run.py \
  --engine .tools/Godot_v4.7.2-stable_linux.x86_64 \
  --work-dir /tmp/tod08b-popup-repro
```

The project sources are in [`project/`](project/), and the driver reuses the repository's UI-06c XTest helper (hash recorded in the report). [`popup.cpp`](popup.cpp) preserves the relevant Godot source excerpt and license header; its SHA-256 is also recorded in the report. Logs include the source and release runs, plus the export log. The exported executable was used for the run but is intentionally not stored here.
