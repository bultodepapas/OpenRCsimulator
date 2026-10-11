# TOD-05 — Direct flight and visual provenance

Status: implemented; focused and rendered checks pass, 2026-10-10. Parent: [time-of-day plan](../../../TIME-OF-DAY-PLAN.md).

Direct launch accepts `--time-of-day=HH:MM[:SS]`, optional `--date=YYYY-MM-DD`, or a complete `--lighting-config=/absolute/path.json`. The complete format is the same validated `openrc-lighting v1` dictionary used by Home. File input cannot be combined with individual lighting overrides. `--lighting=legacy` selects the existing appearance; no lighting flags preserve the old default. Technical routes never load the player's preferences. Malformed explicit input fails before a flight or trace starts.

Examples (after the engine's `--` separator):

```sh
$(app/get-godot.sh) --path app -- --time-of-day=05:45
$(app/get-godot.sh) --path app -- --time-of-day=12:00 --date=2026-06-21
$(app/get-godot.sh) --headless --path app -- --time-of-day=00:00 --trace=/tmp/night.csv --t=3
```

The default geographical reference is explicitly synthetic: 0° latitude, 0° longitude, UTC+00:00, 2026-03-20. A real club needs its own coordinate/date/offset configuration. Civil offset is explicit, with no operating-system timezone or implicit daylight-saving conversion.

## Recording boundary

Code inspection found that existing trace writers already support arbitrary frozen metadata headers. For this fixed-time slice, use an optional JSON `visual_context` header instead of creating a second sidecar file. It contains the full configuration, its SHA-256, geometric Sun sample, lighting-profile revision, exposure and explicit `moon: not-modelled`. The recorder copies the context when recording starts. Default legacy traces retain their existing headers/bytes; CSV format and columns do not change. Capture manifests always include the lighting context.

This self-contained header cannot be separated from the trace accidentally. It does **not** turn the physics checkpoint/replay machinery into a visual playback implementation. Checkpoint restore, edit logs and changing time during flight remain TOD-08/09 work.

`test_time_of_day_cli.py` runs the real entry point to compare all existing metadata/physics rows for daylight, twilight and night with both reference and custom physical atmosphere. It also checks 30/60/144 fps parity, complete-file input and invalid-input refusal. Results: [TOD-07](../TOD-07/README.md).
