# TOD-08b paused editor screenshots

2026-10-10 · Status: captured layout evidence.

These screenshots render the production pause editor at 800×600 and 1280×720 in English and Spanish. Each JSON manifest records the requested and actual image size, panel bounds, renderer, translation and `fits_viewport=true`. The advanced section is open; fields below the visible area remain reachable through the editor scroll container. The captures use Godot 4.7.2 Compatibility rendering on llvmpipe and make no target-GPU performance claim.

| Viewport | English | Spanish |
| --- | --- | --- |
| 800×600 | [PNG](time-of-day-en-800x600.png) · [manifest](time-of-day-en-800x600.json) | [PNG](time-of-day-es-800x600.png) · [manifest](time-of-day-es-800x600.json) |
| 1280×720 | [PNG](time-of-day-en-1280x720.png) · [manifest](time-of-day-en-1280x720.json) | [PNG](time-of-day-es-1280x720.png) · [manifest](time-of-day-es-1280x720.json) |

Reproduce one capture from the repository root:

```bash
xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script res://tests/capture_time_of_day_dialog.gd -- \
  --out="$PWD/docs/research/time-of-day-investigations/TOD-08b/ui/time-of-day-en-800x600.png" \
  --lang=en --size=800x600
```
